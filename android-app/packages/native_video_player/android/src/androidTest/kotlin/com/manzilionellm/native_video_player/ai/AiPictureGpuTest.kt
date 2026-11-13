package com.manzilionellm.native_video_player.ai

import android.graphics.Bitmap
import android.opengl.GLES20
import androidx.media3.common.GlTextureInfo
import androidx.media3.effect.DefaultGlObjectsProvider
import androidx.media3.effect.GlShaderProgram
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.manzilionellm.native_video_player.logic.AiBenchmarkReport
import com.manzilionellm.native_video_player.logic.AiBypassReason
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import kotlin.math.abs

/** Les pixels du vrai pilote sont comparés aux sorties ONNX CPU, pas à un booléen. */
@RunWith(AndroidJUnit4::class)
class AiPictureGpuTest {
    @Test
    fun realModelAndNativeFallbacksAreVerified() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val evidence = File(context.getExternalFilesDir(null), "ai-picture").apply { mkdirs() }
        val proof = JSONObject().put("schemaVersion", 1).put("baselinePassed", false)
            .put("modelSha256", ArtCnnAssets.MODEL_SHA).put("pipelineSha256", ArtCnnAssets.PIPELINE_SHA)
            .put("performanceVerdict", "NOT_MEASURED_ON_CLIENT_BOX")
            .put("testClockAndAdmissionInjected", true)
        try {
            AiEglSession().use {
                val engine = AiPictureEngine(context)
                val caps = engine.probeCurrentContext()
                proof.put("gpuRenderer", caps.renderer).put("gpuVersion", caps.version)
                val assets = ArtCnnAssets.load(context)
                val input = AiGl.texture(16, 12, false, caps.es3)
                try {
                    AiGl.upload(input, assets.referenceInput)
                    writePng(evidence, "reference-input.png", assets.referenceInput, 16, 12)
                    writePng(evidence, "reference-output.png", assets.referenceOutput, 32, 24)
                    // Les refus natifs restent testés même si le GPU n'offre pas de floatRT.
                    val refusals = nativeRefusals(engine, input)
                    proof.put("nativeRefusalsVerified", refusals)
                    if (caps.refusal != null) {
                        proof.put("referenceExecuted", false).put("referenceUnavailableReason", caps.refusal.name)
                        fail("AI_REFERENCE_UNAVAILABLE:${caps.refusal}")
                    }
                    val actual = try {
                        ArtCnnPipeline(assets, 16, 12, caps.es3).use { pipeline ->
                            assertTrue(pipeline.render(input.texId))
                            AiGl.read(pipeline.output)
                        }
                    } catch (error: Exception) {
                        proof.put("referenceExecuted", false).put("referenceUnavailableReason", error.message)
                        throw AssertionError("AI_REFERENCE_UNAVAILABLE", error)
                    }
                    proof.put("referenceExecuted", true)
                    val errors = actual.indices.map { abs((actual[it].toInt() and 255) - (assets.referenceOutput[it].toInt() and 255)) }
                    proof.put("referenceMaximumByteError", errors.max())
                        .put("referenceMeanByteError", errors.average())
                    writePng(evidence, "model-output.png", actual, 32, 24)
                    assertTrue("AI_REFERENCE_NUMERICAL_MAX", errors.max() <= 4)
                    assertTrue("AI_REFERENCE_NUMERICAL_MEAN", errors.average() <= 0.85)

                    // Admission et horloge déterministes UNIQUEMENT dans ce test.
                    // Toutes les convolutions restent exécutées sur le GPU réel.
                    primeFixtureReport(engine, assets, caps)
                    var tick = 0L
                    var currentSession = 7
                    val statuses = ArrayList<AiPictureStatus>()
                    val shader = AiPictureShader(engine, false, { false }, { 60.0 }, { _, _ -> true },
                        { currentSession }, { true }, { statuses.add(it) }, { tick.also { tick += 1_000_000 } })
                    val sink = Sink(shader)
                    try {
                        val first = sink.frame(input, 123456L)
                        assertNotSame(input, first)
                        assertEquals(32, first.width); assertEquals(24, first.height)
                        assertTrue(statuses.last().active)
                        assertEquals(7, statuses.last().sessionId)
                        assertArrayEquals(actual, AiGl.read(first))
                        sink.done(first)

                        // Une vraie erreur GLES au milieu du flux coupe le moteur.
                        GLES20.glBindTexture(-1, 0)
                        val failed = sink.frame(input, 223456L)
                        assertSame(input, failed)
                        assertEquals(AiBypassReason.GL_FAILURE, statuses.last().reason)
                        sink.done(failed)
                        val sticky = sink.frame(input, 323456L)
                        assertSame(input, sticky); sink.done(sticky)

                        // Nouvelle URL/flush : nouvelle admission, mêmes programmes.
                        currentSession = 8
                        shader.flush()
                        val next = sink.frame(input, 423456L)
                        assertNotSame(input, next)
                        assertEquals(8, statuses.last().sessionId)
                        sink.done(next)
                        assertEquals(4, sink.processed)
                    } finally { shader.release() }
                    proof.put("activeFrameVerified", true).put("gpuErrorFallbackVerified", true)
                        .put("flushAndSessionVerified", true).put("timestampsPreserved", true)
                    verifyDeadline(engine, input)
                    proof.put("deadlineFallbackVerified", true)
                    verifyUnknownDoesNotActivateLate(engine, input)
                    proof.put("noLateActivationVerified", true)
                    verifyExactGeometry(engine, input)
                    proof.put("exactGeometryVerified", true)
                    verifyLostMetadataAndHeartbeat(engine, input)
                    proof.put("lostMetadataFallbackVerified", true).put("boundedStatusHeartbeatVerified", true)
                    proof.put("baselinePassed", true)
                } finally { input.release() }
            }
        } finally { File(evidence, "measurements.json").writeText(proof.toString(2)) }
    }

    private fun nativeRefusals(engine: AiPictureEngine, input: GlTextureInfo): Int {
        val cases = listOf(
            Triple(AiBypassReason.SOURCE_UNKNOWN, false, 16 to 12),
            Triple(AiBypassReason.HDR_OR_DRM, true, 16 to 12),
            Triple(AiBypassReason.NATIVE_4K, true, 3840 to 2160),
        )
        for ((reason, known, size) in cases) {
            val statuses = ArrayList<AiPictureStatus>()
            val effect = engine.newEffect(hdrOrDrm = { reason == AiBypassReason.HDR_OR_DRM || !known },
                framesPerSecond = { 60.0 }, allowUpscale = { _, _ -> true }, sourceKnown = { known }, onStatus = { statuses.add(it) })
            val shader = effect.toGlShaderProgram(InstrumentationRegistry.getInstrumentation().targetContext, false)
            val sink = Sink(shader)
            // Objet descriptif d'une source native4K : le bypass ne le lit/copie jamais.
            val original = if (size.first == 16) input else GlTextureInfo(input.texId, input.fboId, -1, size.first, size.second)
            try {
                val output = sink.frame(original, 9001L)
                assertSame(original, output)
                assertEquals(original.width, output.width); assertEquals(original.height, output.height)
                assertFalse(statuses.last().active)
                assertEquals(reason, statuses.last().reason)
                sink.done(output)
            } finally { shader.release() }
        }
        return cases.size
    }

    private fun verifyDeadline(engine: AiPictureEngine, input: GlTextureInfo) {
        val statuses = ArrayList<AiPictureStatus>()
        val times = longArrayOf(0, 1_000_000, 2_000_000, 30_000_000)
        var index = 0
        val shader = AiPictureShader(engine, false, { false }, { 60.0 }, { _, _ -> true }, { 1 }, { true },
            { statuses.add(it) }, { times[index++] })
        val sink = Sink(shader)
        try {
            val first = sink.frame(input, 1L); assertNotSame(input, first); sink.done(first)
            val late = sink.frame(input, 2L); assertSame(input, late); sink.done(late)
            assertEquals(AiBypassReason.FRAME_DEADLINE, statuses.last().reason)
            val third = sink.frame(input, 3L); assertSame(input, third); sink.done(third)
            assertEquals(4, index) // le bypass ne relance plus le GPU/chronomètre
        } finally { shader.release() }
    }

    private fun verifyUnknownDoesNotActivateLate(engine: AiPictureEngine, input: GlTextureInfo) {
        var known = false
        val statuses = ArrayList<AiPictureStatus>()
        val shader = AiPictureShader(engine, false, { !known }, { 60.0 }, { _, _ -> true }, { 2 }, { known }, { statuses.add(it) })
        val sink = Sink(shader)
        try {
            val first = sink.frame(input, 40L); assertSame(input, first); sink.done(first)
            assertEquals(AiBypassReason.SOURCE_UNKNOWN, statuses.last().reason)
            known = true
            val second = sink.frame(input, 50L); assertSame(input, second); sink.done(second)
            assertEquals(AiBypassReason.SOURCE_UNKNOWN, statuses.last().reason)
        } finally { shader.release() }
    }

    private fun verifyExactGeometry(engine: AiPictureEngine, input: GlTextureInfo) {
        val statuses = ArrayList<AiPictureStatus>()
        val shader = AiPictureShader(engine, false, { false }, { 60.0 }, { _, _ -> true }, { 3 }, { true }, { statuses.add(it) })
        val sink = Sink(shader)
        val unmatched = GlTextureInfo(input.texId, input.fboId, -1, 17, 12)
        try {
            val output = sink.frame(unmatched, 600L)
            assertSame(unmatched, output)
            assertEquals(AiBypassReason.BENCHMARK_MISSING, statuses.last().reason)
            sink.done(output)
        } finally { shader.release() }
    }

    private fun verifyLostMetadataAndHeartbeat(engine: AiPictureEngine, input: GlTextureInfo) {
        var known = true
        var statusTime = 0L
        var tick = 0L
        val statuses = ArrayList<AiPictureStatus>()
        val shader = AiPictureShader(engine, false, { !known }, { 60.0 }, { _, _ -> true }, { 4 }, { known },
            { statuses.add(it) }, { tick.also { tick += 1_000_000 } }, { statusTime })
        val sink = Sink(shader)
        try {
            val first = sink.frame(input, 700L); assertNotSame(input, first); sink.done(first)
            assertEquals(1, statuses.size)
            statusTime = 500
            val second = sink.frame(input, 800L); sink.done(second)
            assertEquals(1, statuses.size)
            statusTime = 1000
            val third = sink.frame(input, 900L); sink.done(third)
            assertEquals(2, statuses.size) // pas de replay : une nouvelle frame a été traitée
            known = false
            val unknown = sink.frame(input, 1000L); assertSame(input, unknown); sink.done(unknown)
            assertEquals(AiBypassReason.SOURCE_UNKNOWN, statuses.last().reason)
            known = true
            val late = sink.frame(input, 1100L); assertSame(input, late); sink.done(late)
        } finally { shader.release() }
    }

    /** Injection confinée au code d'instrumentation, aucune API production pour cela. */
    @Suppress("UNCHECKED_CAST")
    private fun primeFixtureReport(engine: AiPictureEngine, assets: ArtCnnAssets, caps: AiCapabilities) {
        AiPictureEngine::class.java.getDeclaredField("assets").apply { isAccessible = true }.set(engine, assets)
        val reports = AiPictureEngine::class.java.getDeclaredField("reports").apply { isAccessible = true }
            .get(engine) as MutableMap<String, AiBenchmarkReport>
        reports["16x12"] = AiBenchmarkReport(ArtCnnAssets.PIPELINE_SHA, caps.driverId,
            16, 12, 2, 5, List(20) { 1_000_000 }, true, true)
    }

    private class Sink(private val shader: GlShaderProgram) {
        private val provider = DefaultGlObjectsProvider()
        private var output: GlTextureInfo? = null
        private var timestamp = -1L
        var processed = 0
            private set
        init {
            shader.setInputListener(object : GlShaderProgram.InputListener {
                override fun onInputFrameProcessed(inputTexture: GlTextureInfo) { processed++ }
            })
            shader.setOutputListener(object : GlShaderProgram.OutputListener {
                override fun onOutputFrameAvailable(outputTexture: GlTextureInfo, presentationTimeUs: Long) {
                    output = outputTexture; timestamp = presentationTimeUs
                }
            })
        }
        fun frame(input: GlTextureInfo, time: Long): GlTextureInfo {
            output = null
            shader.queueInputFrame(provider, input, time)
            assertEquals(time, timestamp)
            return requireNotNull(output)
        }
        fun done(output: GlTextureInfo) { shader.releaseOutputFrame(output) }
    }

    private fun writePng(directory: File, name: String, rgba: ByteArray, width: Int, height: Int) {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        for (y in 0 until height) for (x in 0 until width) {
            val i = ((height - y - 1) * width + x) * 4
            val argb = ((rgba[i+3].toInt() and 255) shl 24) or ((rgba[i].toInt() and 255) shl 16) or
                ((rgba[i+1].toInt() and 255) shl 8) or (rgba[i+2].toInt() and 255)
            bitmap.setPixel(x, y, argb)
        }
        File(directory, name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
    }
}
