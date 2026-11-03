package com.manzilionellm.native_video_player.ai

import android.content.Context
import android.os.SystemClock
import androidx.media3.common.GlObjectsProvider
import androidx.media3.common.GlTextureInfo
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import com.manzilionellm.native_video_player.logic.AiBypassReason
import com.manzilionellm.native_video_player.logic.AiFrameGate
import java.util.concurrent.Executor

internal class AiPictureEffect(
    private val engine: AiPictureEngine,
    private val hdrOrDrm: () -> Boolean,
    private val framesPerSecond: () -> Double,
    private val allowUpscale: (Int, Int) -> Boolean,
    private val sessionId: () -> Int,
    private val sourceKnown: () -> Boolean,
    private val onStatus: (AiPictureStatus) -> Unit,
) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram =
        AiPictureShader(engine, useHdr, hdrOrDrm, framesPerSecond, allowUpscale, sessionId, sourceKnown, onStatus)
}

/**
 * En refus, transférer l'objet texture original, sa taille et son timestamp.
 * Une copie agrandie n'est pas un fallback natif. Aucun accès au lecteur ici :
 * cette classe ne peut ni prepare/reopen, ni changer de piste, ni afficher une UI.
 */
internal class AiPictureShader(
    private val engine: AiPictureEngine,
    private val useHdr: Boolean,
    private val hdrOrDrm: () -> Boolean,
    private val framesPerSecond: () -> Double,
    private val allowUpscale: (Int, Int) -> Boolean,
    private val sessionId: () -> Int,
    private val sourceKnown: () -> Boolean,
    private val onStatus: (AiPictureStatus) -> Unit,
    private val nanoTime: () -> Long = System::nanoTime,
    private val statusClockMs: () -> Long = SystemClock::elapsedRealtime,
) : GlShaderProgram {
    private var inputListener: GlShaderProgram.InputListener = object : GlShaderProgram.InputListener {}
    private var outputListener: GlShaderProgram.OutputListener = object : GlShaderProgram.OutputListener {}
    private var gate: AiFrameGate? = null
    private var pipeline: ArtCnnPipeline? = null
    private var programs: ArtCnnPrograms? = null
    private var preparationRefusal: AiBypassReason? = null
    private var caps: AiCapabilities? = null
    private var flight: Flight? = null
    private var sourceWidth = 0
    private var sourceHeight = 0
    private var currentSession: Int? = null
    private var lastStatus: AiPictureStatus? = null
    private var lastStatusMs = 0L
    private var released = false
    private data class Flight(val input: GlTextureInfo, val output: GlTextureInfo)

    init {
        // Media3 crée ce programme avant de lui livrer une image. Compiler ici
        // évite d'exclure frauduleusement la compilation du premier chronomètre.
        // Sans mesure préalable, aucune compilation ni allocation IA.
        if (engine.hasReports() && !useHdr) {
            try { engine.assets?.let { programs = ArtCnnPrograms(it) } }
            catch (_: OutOfMemoryError) { preparationRefusal = AiBypassReason.MEMORY_LOW }
            catch (_: Exception) { preparationRefusal = AiBypassReason.GL_FAILURE }
        }
    }

    override fun setInputListener(listener: GlShaderProgram.InputListener) {
        inputListener = listener
        if (!released && flight == null) listener.onReadyToAcceptInputFrame()
    }
    override fun setOutputListener(listener: GlShaderProgram.OutputListener) { outputListener = listener }
    override fun setErrorListener(executor: Executor, listener: GlShaderProgram.ErrorListener) {
        // Les erreurs IA sont récupérables : transmettre la texture native,
        // et non déclencher le mécanisme fatal/reopen de Media3.
    }

    override fun queueInputFrame(provider: GlObjectsProvider, input: GlTextureInfo, presentationTimeUs: Long) {
        check(!released && flight == null) { "Une seule image IA en vol." }
        val capturedSession = sessionId()
        if (currentSession != capturedSession) resetSession()
        currentSession = capturedSession
        if (gate == null) admit(input)
        val policy = requireNotNull(gate)
        var output = input
        try {
            if (policy.shouldProcess() && !sourceKnown()) policy.disable(AiBypassReason.SOURCE_UNKNOWN)
            if (input.width != sourceWidth || input.height != sourceHeight) policy.disable(AiBypassReason.GEOMETRY_CHANGED)
            policy.updateFramesPerSecond(framesPerSecond())
            // Ne pas rebaptiser SOURCE_UNKNOWN en HDR/DRM lorsque le provider
            // utilise provisoirement true pour refuser les sources non décrites.
            if (policy.shouldProcess() && sourceKnown() && (useHdr || hdrOrDrm())) policy.disable(AiBypassReason.HDR_OR_DRM)
            if (policy.shouldProcess() && !allowUpscale(input.width, input.height)) policy.disable(AiBypassReason.UPSCALE_NOT_USEFUL)
            if (policy.shouldProcess()) {
                AiGl.State().use {
                    // Inclure la toute première allocation, pas seulement les draws.
                    val start = nanoTime()
                    val renderer = pipeline ?: ArtCnnPipeline(requireNotNull(engine.assets), input.width, input.height,
                        requireNotNull(caps).es3, programs).also { pipeline = it }
                    val succeeded = renderer.render(input.texId)
                    policy.record(nanoTime() - start, succeeded)
                    // Si cette image vient de manquer sa marge, ne pas la livrer
                    // sous une étiquette « IA active ». Restituer l'original.
                    if (policy.shouldProcess()) output = renderer.output
                }
            }
        } catch (_: OutOfMemoryError) { policy.disable(AiBypassReason.MEMORY_LOW) }
        catch (_: Exception) { policy.disable(AiBypassReason.GL_FAILURE) }
        if (!policy.shouldProcess()) { pipeline?.close(); pipeline = null }
        val status = AiPictureStatus(capturedSession, output !== input, policy.decision.reason,
            input.width, input.height, output.width, output.height, policy.decision, caps)
        val statusNow = statusClockMs()
        // Le premier événement peut précéder firstFrame/hold côté Flutter.
        // Une preuve fraîche, après une vraie frame, est republée au plus1Hz.
        if (status != lastStatus || statusNow - lastStatusMs >= 1000) {
            lastStatus = status
            lastStatusMs = statusNow
            // Un callback UI défaillant ne doit pas interrompre les images.
            runCatching { onStatus(status) }
        }
        flight = Flight(input, output)
        outputListener.onOutputFrameAvailable(output, presentationTimeUs)
    }

    private fun admit(input: GlTextureInfo) {
        sourceWidth = input.width; sourceHeight = input.height
        val currentCaps = runCatching { engine.probeCurrentContext() }.getOrNull()
        caps = currentCaps
        val policy = AiFrameGate(ArtCnnAssets.PIPELINE_SHA, currentCaps?.driverId.orEmpty())
        gate = policy
        policy.configure(input.width, input.height, 2, currentCaps?.maxTextureSize ?: 0,
            ArtCnnPipeline.workingBytes(input.width, input.height), engine.availableMemory(),
            currentCaps != null && currentCaps.refusal == null, useHdr || hdrOrDrm(), framesPerSecond())
        policy.loadBenchmark(engine.report(input.width, input.height))
        when {
            !sourceKnown() -> policy.disable(AiBypassReason.SOURCE_UNKNOWN)
            preparationRefusal != null -> policy.disable(requireNotNull(preparationRefusal))
            useHdr || hdrOrDrm() -> policy.disable(AiBypassReason.HDR_OR_DRM)
            input.width >= 3840 || input.height >= 2160 -> policy.disable(AiBypassReason.NATIVE_4K)
            !allowUpscale(input.width, input.height) -> policy.disable(AiBypassReason.UPSCALE_NOT_USEFUL)
            currentCaps?.refusal != null -> policy.disable(currentCaps.refusal)
            engine.report(input.width, input.height) == null && engine.refusal(input.width, input.height) != null ->
                policy.disable(requireNotNull(engine.refusal(input.width, input.height)))
        }
        policy.beginPlayback()
        if (sourceKnown() && !useHdr && !hdrOrDrm() && allowUpscale(input.width, input.height) &&
            input.width < 3840 && input.height < 2160 && engine.report(input.width, input.height) == null) {
            engine.rememberGeometry(input.width, input.height)
        }
    }

    override fun releaseOutputFrame(output: GlTextureInfo) {
        val pending = flight ?: return
        if (pending.output !== output) return // ancien callback après flush/zap
        flight = null
        inputListener.onInputFrameProcessed(pending.input)
        if (!released) inputListener.onReadyToAcceptInputFrame()
    }
    override fun signalEndOfCurrentInputStream() { outputListener.onCurrentOutputStreamEnded() }
    override fun flush() {
        flight = null
        resetSession()
        inputListener.onFlush()
        if (!released) inputListener.onReadyToAcceptInputFrame()
    }
    private fun resetSession() {
        pipeline?.close(); pipeline = null
        gate = null; currentSession = null; lastStatus = null; lastStatusMs = 0L
        sourceWidth = 0; sourceHeight = 0
    }
    override fun release() {
        if (released) return
        released = true
        flight = null
        resetSession()
        programs?.close(); programs = null
    }
}
