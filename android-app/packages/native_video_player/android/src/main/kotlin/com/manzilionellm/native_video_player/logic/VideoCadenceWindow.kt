package com.manzilionellm.native_video_player.logic

/** Deltas des buffers de sortie, et non cadence déclarée par le fichier. */
data class VideoCadence(
    val renderedFrames: Long,
    val droppedFrames: Long,
    val windowMs: Long,
)

/**
 * Fenêtre monotone de lecture continue. Une pause, un changement de décodeur,
 * une remise à zéro des compteurs ou un appel trop tardif invalident la mesure.
 * Aucun échantillon n'est extrapolé à partir du Format.frameRate.
 */
class VideoCadenceWindow {
    private data class Baseline(
        val counters: Any,
        val atMs: Long,
        val rendered: Long,
        val dropped: Long,
    )

    private var baseline: Baseline? = null

    fun reset() { baseline = null }

    fun sample(
        counters: Any,
        nowMs: Long,
        rendered: Long,
        dropped: Long,
        playing: Boolean,
    ): VideoCadence? {
        if (!playing || nowMs < 0L || rendered < 0L || dropped < 0L) {
            reset()
            return null
        }
        val previous = baseline
        val next = Baseline(counters, nowMs, rendered, dropped)
        if (previous == null || previous.counters !== counters) {
            baseline = next
            return null
        }
        val elapsed = nowMs - previous.atMs
        if (elapsed <= 0L || elapsed > MAX_WINDOW_MS ||
            rendered < previous.rendered || dropped < previous.dropped
        ) {
            baseline = next
            return null
        }
        if (elapsed < MIN_WINDOW_MS) return null
        baseline = next
        return VideoCadence(rendered - previous.rendered, dropped - previous.dropped, elapsed)
    }

    companion object {
        const val MIN_WINDOW_MS = 2_000L
        const val MAX_WINDOW_MS = 5_000L
    }
}
