package com.manzilionellm.native_video_player.logic

import kotlin.math.ceil
import kotlin.math.floor

/** Une mesure GPU terminée, et non le temps d'envoi d'une commande asynchrone. */
data class AiBenchmarkReport(
    val modelSha256: String,
    val driverId: String,
    val width: Int,
    val height: Int,
    val scale: Int,
    val warmupFrames: Int,
    val completedFrameNs: List<Long>,
    val completionSynchronized: Boolean,
    val numericalCheckPassed: Boolean,
)

/** Chaque refus est explicite ; un « false » sans cause ne fait pas partie du contrat. */
enum class AiBypassReason {
    NOT_CONFIGURED, GPU_UNSUPPORTED, GEOMETRY_INVALID, OUTPUT_TOO_LARGE,
    MEMORY_UNKNOWN, MEMORY_LOW, HDR_OR_DRM, BENCHMARK_MISSING,
    BENCHMARK_OTHER_MODEL, BENCHMARK_OTHER_DRIVER, BENCHMARK_OTHER_SIZE,
    BENCHMARK_INCOMPLETE, NUMERICAL_CHECK_FAILED, TOO_SLOW,
    INFERENCE_FAILED, FRAME_DEADLINE, MARGIN_LOST, PLAYBACK_STARTED,
}

data class AiFrameDecision(
    val active: Boolean,
    val reason: AiBypassReason?,
    val score: Int?,
    val p95Ms: Double?,
) {
    init {
        require(active == (reason == null)) { "Un bypass doit toujours avoir une cause." }
    }
}

/**
 * Politique sans dépendance Android, partagée par le rendu réel et ses tests.
 *
 * Score = 100 × budget d'une image / p95 COMPLET du traitement IA.
 * Seuil 200 : au plus la moitié de ce budget est consommée par l'IA,
 * l'autre moitié reste au décodage, à la composition et aux variations de charge.
 * 30 i/s : p95 <= 16,67 ms ; 60 i/s : p95 <= 8,33 ms. Aucun pic du
 * benchmark ne doit dépasser le budget entier. Ce seuil est une marge
 * d'ingénierie, pas une promesse de performance d'une marque de box.
 *
 * Le benchmark se fait HORS lecture. Ni une tuile 128×128, ni une vitesse
 * annoncée du GPU, ni la RAM système renommée « VRAM » ne peuvent activer
 * un flux HD. Il faut le modèle, le pilote ET la géométrie exacts.
 */
class AiFrameGate(
    private val modelSha256: String,
    private val driverId: String,
) {
    companion object {
        const val MIN_SCORE = 200
        const val MIN_WARMUP = 5
        const val MIN_SAMPLES = 20
        const val MEMORY_RESERVE_BYTES = 256L * 1024 * 1024
    }

    private var width = 0
    private var height = 0
    private var scale = 0
    private var frameBudgetNs = 1_000_000_000.0 / 60.0
    private var configurationRefusal: AiBypassReason? = AiBypassReason.NOT_CONFIGURED
    private var report: AiBenchmarkReport? = null
    private var runtimeRefusal: AiBypassReason? = null
    private val recentFrames = ArrayDeque<Long>()

    var decision = AiFrameDecision(false, AiBypassReason.NOT_CONFIGURED, null, null)
        private set

    /** La mémoire demandée inclut toutes les textures temporaires et de sortie. */
    fun configure(
        width: Int,
        height: Int,
        scale: Int,
        maxTextureSize: Int,
        workingBytes: Long,
        availableSystemBytes: Long?,
        gpuSupported: Boolean,
        hdrOrDrm: Boolean = false,
        framesPerSecond: Double = 60.0,
    ): Boolean {
        this.width = width
        this.height = height
        this.scale = scale
        // Une cadence inconnue n'est jamais remplacée par une cadence plus facile.
        val fps = framesPerSecond.takeIf { it.isFinite() && it in 1.0..240.0 } ?: 60.0
        frameBudgetNs = 1_000_000_000.0 / fps
        recentFrames.clear()
        configurationRefusal = when {
            hdrOrDrm -> AiBypassReason.HDR_OR_DRM
            !gpuSupported -> AiBypassReason.GPU_UNSUPPORTED
            width <= 0 || height <= 0 || scale !in 2..4 || workingBytes <= 0 -> AiBypassReason.GEOMETRY_INVALID
            maxTextureSize <= 0 || width.toLong() * scale > maxTextureSize ||
                height.toLong() * scale > maxTextureSize -> AiBypassReason.OUTPUT_TOO_LARGE
            availableSystemBytes == null -> AiBypassReason.MEMORY_UNKNOWN
            availableSystemBytes < workingBytes ||
                availableSystemBytes - workingBytes < MEMORY_RESERVE_BYTES -> AiBypassReason.MEMORY_LOW
            else -> null
        }
        evaluate()
        return configurationRefusal == null
    }

    fun loadBenchmark(value: AiBenchmarkReport?) {
        report = value
        evaluate()
    }

    fun shouldProcess(): Boolean = decision.active

    /** Appelé uniquement après achèvement GPU ; n'apprend pas sur des trames abandonnées. */
    fun record(elapsedNs: Long, success: Boolean) {
        if (!decision.active) return
        if (!success || elapsedNs <= 0) {
            disable(AiBypassReason.INFERENCE_FAILED)
            return
        }
        if (elapsedNs > frameBudgetNs) {
            disable(AiBypassReason.FRAME_DEADLINE)
            return
        }
        recentFrames.addLast(elapsedNs)
        while (recentFrames.size > MIN_SAMPLES) recentFrames.removeFirst()
        if (recentFrames.size == MIN_SAMPLES) {
            val p95 = percentile95(recentFrames.toList())
            if (p95 > frameBudgetNs / 2.0) {
                runtimeRefusal = AiBypassReason.MARGIN_LOST
                decision = AiFrameDecision(false, AiBypassReason.MARGIN_LOST, score(p95), p95 / 1_000_000.0)
            }
        }
    }

    /** Le shader copie alors l'entrée, sans reopen/prepare/commande réseau. */
    fun disable(reason: AiBypassReason) {
        // Une réponse de benchmark arrivée en retard ne doit pas rallumer un
        // processeur qui vient de tomber en panne. Une nouvelle instance,
        // créée avec un nouveau traitement, est nécessaire pour le réessayer.
        runtimeRefusal = reason
        decision = decision.copy(active = false, reason = reason)
    }

    private fun evaluate() {
        val fixedRefusal = configurationRefusal ?: runtimeRefusal
        if (fixedRefusal != null) {
            decision = AiFrameDecision(false, fixedRefusal, null, null)
            return
        }
        val r = report
        val refusal = when {
            r == null -> AiBypassReason.BENCHMARK_MISSING
            r.modelSha256 != modelSha256 -> AiBypassReason.BENCHMARK_OTHER_MODEL
            r.driverId != driverId -> AiBypassReason.BENCHMARK_OTHER_DRIVER
            r.width != width || r.height != height || r.scale != scale -> AiBypassReason.BENCHMARK_OTHER_SIZE
            !r.numericalCheckPassed -> AiBypassReason.NUMERICAL_CHECK_FAILED
            !r.completionSynchronized || r.warmupFrames < MIN_WARMUP ||
                r.completedFrameNs.size < MIN_SAMPLES || r.completedFrameNs.any { it <= 0 } -> AiBypassReason.BENCHMARK_INCOMPLETE
            else -> null
        }
        if (refusal != null) {
            decision = AiFrameDecision(false, refusal, null, null)
            return
        }
        val samples = requireNotNull(r).completedFrameNs
        val p95 = percentile95(samples)
        val tooSlow = p95 > frameBudgetNs / 2.0 || samples.max() > frameBudgetNs
        decision = AiFrameDecision(!tooSlow, if (tooSlow) AiBypassReason.TOO_SLOW else null,
            score(p95), p95 / 1_000_000.0)
    }

    private fun score(p95: Long): Int = floor(100.0 * frameBudgetNs / p95)
        .coerceIn(0.0, Int.MAX_VALUE.toDouble()).toInt()

    private fun percentile95(samples: List<Long>): Long = samples.sorted()[ceil(samples.size * 0.95).toInt() - 1]
}
