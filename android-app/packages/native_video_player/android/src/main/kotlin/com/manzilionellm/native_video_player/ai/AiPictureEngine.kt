package com.manzilionellm.native_video_player.ai

import android.app.ActivityManager
import android.content.Context
import android.opengl.GLES20
import android.os.Process
import android.os.SystemClock
import android.util.Log
import androidx.media3.effect.GlEffect
import com.manzilionellm.native_video_player.logic.AiBenchmarkReport
import com.manzilionellm.native_video_player.logic.AiBypassReason
import com.manzilionellm.native_video_player.logic.AiFrameGate
import com.manzilionellm.native_video_player.logic.AiPreflightGate
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.abs

/**
 * Préflight opportuniste HORS lecture. Chaque rapport concerne la frame entière,
 * le modèle, le pilote et une taille exacte. Aucun score d'une autre box n'entre ici.
 */
class AiPictureEngine internal constructor(context: Context) {
    private val app = context.applicationContext
    private val executor = Executors.newSingleThreadExecutor { task -> Thread(task, "ZunoAI-idle").apply { isDaemon = true } }
    private val running = AtomicBoolean(false)
    private val attempts = AtomicInteger()
    @Volatile private var retryPending = true
    @Volatile private var permanentlyRefused = false
    private val admission = AiPreflightGate { if (retryPending) startPreflight() }
    private val wanted = LinkedHashMap<String, Pair<Int, Int>>()
    private val seenRequests = HashSet<String>()
    private val reports = ConcurrentHashMap<String, AiBenchmarkReport>()
    private val refusals = ConcurrentHashMap<String, AiBypassReason>()
    @Volatile internal var assets: ArtCnnAssets? = null
        private set
    @Volatile internal var capabilities: AiCapabilities? = null
        private set
    @Volatile internal var preflightRefusal: AiBypassReason? = null
        private set

    /** Une lease par décodeur : fermer l'aperçu A ne libère jamais la lecture B. */
    fun acquirePlayback(owner: Any): AutoCloseable = admission.acquirePlayback(owner)

    fun attachFlutterUi(): AiPreflightGate.UiRegistration = admission.attachUi()

    fun startPreflight() {
        if (permanentlyRefused || !retryPending || attempts.get() >= 2 || !admission.canRun) return
        if (!running.compareAndSet(false, true)) return
        attempts.incrementAndGet()
        val leaseGeneration = admission.playbackGeneration
        val uiGeneration = admission.uiGeneration
        executor.execute {
            Log.i("ZunoStartup", "ai.preflight.begin")
            Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
            val deadline = SystemClock.elapsedRealtime() + 2500
            val cancelled = { !admission.canRun || admission.playbackGeneration != leaseGeneration ||
                admission.uiGeneration != uiGeneration || SystemClock.elapsedRealtime() >= deadline }
            var retry = false
            try {
                if (cancelled()) throw AiWorkCancelled()
                val loaded = try { ArtCnnAssets.load(app) } catch (_: Exception) {
                    preflightRefusal = AiBypassReason.MODEL_INTEGRITY
                    permanentlyRefused = true
                    return@execute
                }
                assets = loaded
                if (cancelled()) throw AiWorkCancelled()
                AiEglSession().use egl@ {
                    val caps = probeCurrentContext()
                    capabilities = caps
                    if (caps.refusal != null) {
                        preflightRefusal = caps.refusal; permanentlyRefused = true; return@egl
                    }
                    ArtCnnPrograms(loaded, cancelled).use programs@ { programs ->
                        if (!referenceCheck(loaded, caps.es3, programs, cancelled)) {
                            if (cancelled()) throw AiWorkCancelled()
                            preflightRefusal = AiBypassReason.NUMERICAL_CHECK_FAILED
                            permanentlyRefused = true
                            return@programs
                        }
                        preflightRefusal = null
                        // Tailles réellement vues en priorité au prochain vrai idle.
                        val sizes = synchronized(wanted) { (wanted.values.toList() + BENCHMARK_SIZES).distinct() }
                        for ((width, height) in sizes) {
                            if (cancelled()) throw AiWorkCancelled()
                            val id = key(width, height)
                            if (reports.containsKey(id) || refusals.containsKey(id)) continue
                            val gate = AiFrameGate(ArtCnnAssets.PIPELINE_SHA, caps.driverId)
                            gate.configure(width, height, 2, caps.maxTextureSize,
                                ArtCnnPipeline.workingBytes(width, height), availableMemory(), true)
                            if (gate.decision.reason != AiBypassReason.BENCHMARK_MISSING) {
                                refusals[id] = gate.decision.reason ?: AiBypassReason.GEOMETRY_INVALID
                                continue
                            }
                            val accepted = benchmark(loaded, caps, width, height, programs, cancelled)
                            synchronized(wanted) { wanted.remove(id) }
                            // Aucune extrapolation : les autres tailles restent sans rapport.
                            if (!accepted) break
                        }
                    }
                }
            } catch (_: AiWorkCancelled) {
                retry = true
                preflightRefusal = AiBypassReason.PLAYBACK_STARTED.takeIf {
                    admission.hasPlayback || admission.playbackGeneration != leaseGeneration }
            } catch (_: OutOfMemoryError) { preflightRefusal = AiBypassReason.MEMORY_LOW }
            catch (error: Exception) {
                preflightRefusal = if (error.message?.contains("FLOAT_FRAMEBUFFER_UNSUPPORTED") == true)
                    AiBypassReason.FLOAT_TEXTURE_UNSUPPORTED else AiBypassReason.GL_FAILURE
                permanentlyRefused = true
            } finally {
                Log.i("ZunoStartup", "ai.preflight.end")
                synchronized(wanted) { retryPending = retry || wanted.isNotEmpty() }
                running.set(false)
                if (retryPending && admission.canRun) startPreflight()
            }
        }
    }

    fun newEffect(
        hdrOrDrm: () -> Boolean,
        framesPerSecond: () -> Double,
        allowUpscale: (width: Int, height: Int) -> Boolean,
        sessionId: () -> Int = { 0 },
        sourceKnown: () -> Boolean = { true },
        onStatus: (AiPictureStatus) -> Unit,
    ): GlEffect = AiPictureEffect(this, hdrOrDrm, framesPerSecond, allowUpscale, sessionId, sourceKnown, onStatus)

    internal fun report(width: Int, height: Int): AiBenchmarkReport? = reports[key(width, height)]
    internal fun hasReports(): Boolean = reports.isNotEmpty()
    internal fun rememberGeometry(width: Int, height: Int) {
        if (permanentlyRefused || width !in 1..1920 || height !in 1..1080) return
        val id = key(width, height)
        if (reports.containsKey(id) || refusals.containsKey(id)) return
        synchronized(wanted) {
            // Au plus quatre nouvelles géométries par lancement : pas de file sans borne.
            if (id in seenRequests || seenRequests.size >= 4) return
            seenRequests.add(id)
            wanted[id] = width to height
            attempts.set(0)
            retryPending = true
        }
    }
    internal fun refusal(width: Int, height: Int): AiBypassReason? = refusals[key(width, height)] ?: preflightRefusal
    internal fun availableMemory(): Long? = runCatching {
        val info = ActivityManager.MemoryInfo()
        (app.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(info)
        info.availMem.takeIf { it > 0 }
    }.getOrNull()

    internal fun probeCurrentContext(): AiCapabilities {
        val version = GLES20.glGetString(GLES20.GL_VERSION).orEmpty()
        val renderer = GLES20.glGetString(GLES20.GL_RENDERER).orEmpty()
        val vendor = GLES20.glGetString(GLES20.GL_VENDOR).orEmpty()
        val extensions = GLES20.glGetString(GLES20.GL_EXTENSIONS).orEmpty().split(' ').toSet()
        val max = IntArray(1).also { GLES20.glGetIntegerv(GLES20.GL_MAX_TEXTURE_SIZE, it, 0) }[0]
        val range = IntArray(2)
        val precision = IntArray(1)
        GLES20.glGetShaderPrecisionFormat(GLES20.GL_FRAGMENT_SHADER, GLES20.GL_HIGH_FLOAT, range, 0, precision, 0)
        val es3 = Regex("OpenGL ES [3-9]\\.").containsMatchIn(version)
        val reason = when {
            renderer.isEmpty() || max <= 0 -> AiBypassReason.GPU_UNSUPPORTED
            precision[0] < 16 -> AiBypassReason.SHADER_PRECISION_UNSUPPORTED
            !es3 && "GL_OES_texture_half_float" !in extensions -> AiBypassReason.FLOAT_TEXTURE_UNSUPPORTED
            !es3 && "GL_EXT_color_buffer_half_float" !in extensions -> AiBypassReason.FLOAT_TEXTURE_UNSUPPORTED
            else -> null
        }
        return AiCapabilities(renderer, version, "$vendor|$renderer|$version", max, es3,
            availableMemory(), app.packageManager.hasSystemFeature("android.hardware.npu"), reason)
    }

    private fun benchmark(loaded: ArtCnnAssets, caps: AiCapabilities, width: Int, height: Int, programs: ArtCnnPrograms, cancelled: () -> Boolean): Boolean {
        if (cancelled()) throw AiWorkCancelled()
        val input = AiGl.texture(width, height, false, caps.es3)
        try {
            val pattern = ByteArray(width * height * 4) { i -> if (i % 4 == 3) 255.toByte() else ((i * 13 + i / width) and 255).toByte() }
            if (cancelled()) throw AiWorkCancelled()
            AiGl.upload(input, pattern)
            ArtCnnPipeline(loaded, width, height, caps.es3, programs, cancelled).use { pipeline ->
                val samples = ArrayList<Long>()
                for (i in 0 until AiFrameGate.MIN_WARMUP + AiFrameGate.MIN_SAMPLES) {
                    if (cancelled()) throw AiWorkCancelled()
                    val start = System.nanoTime()
                    if (!pipeline.render(input.texId, cancelled)) throw AiWorkCancelled()
                    val elapsed = System.nanoTime() - start
                    // Un seul draw terminé trop cher suffit pour refuser ; pas 25 freezes.
                    if (elapsed > 1_000_000_000L / 60) {
                        refusals[key(width, height)] = AiBypassReason.TOO_SLOW
                        return false
                    }
                    if (i >= AiFrameGate.MIN_WARMUP) samples.add(elapsed)
                }
                if (cancelled()) throw AiWorkCancelled()
                reports[key(width, height)] = AiBenchmarkReport(ArtCnnAssets.PIPELINE_SHA, caps.driverId,
                    width, height, 2, AiFrameGate.MIN_WARMUP, samples, true, true)
                return true
            }
        } finally { input.release() }
    }

    /** Test réel de tous les shaders, comparé à ONNX Runtime CPU indépendant. */
    internal fun referenceCheck(loaded: ArtCnnAssets, es3: Boolean, programs: ArtCnnPrograms? = null, cancelled: () -> Boolean = { admission.hasPlayback }): Boolean {
        if (cancelled()) return false
        val input = AiGl.texture(ArtCnnAssets.REFERENCE_WIDTH, ArtCnnAssets.REFERENCE_HEIGHT, false, es3)
        try {
            AiGl.upload(input, loaded.referenceInput)
            ArtCnnPipeline(loaded, input.width, input.height, es3, programs, cancelled).use { pipeline ->
                if (!pipeline.render(input.texId, cancelled)) return false
                val actual = AiGl.read(pipeline.output)
                var maximum = 0
                var sum = 0L
                actual.indices.forEach { i ->
                    val delta = abs((actual[i].toInt() and 255) - (loaded.referenceOutput[i].toInt() and 255))
                    maximum = maxOf(maximum, delta); sum += delta
                }
                return maximum <= 4 && sum.toDouble() / actual.size <= 0.85
            }
        } finally { input.release() }
    }

    companion object {
        @Volatile private var instance: AiPictureEngine? = null
        @JvmStatic fun get(context: Context): AiPictureEngine = instance ?: synchronized(this) {
            instance ?: AiPictureEngine(context).also { instance = it }
        }
        private fun key(width: Int, height: Int) = "${width}x$height"
        private val BENCHMARK_SIZES = listOf(640 to 360, 720 to 480, 720 to 576, 960 to 540, 1280 to 720, 1920 to 1080)
    }
}
