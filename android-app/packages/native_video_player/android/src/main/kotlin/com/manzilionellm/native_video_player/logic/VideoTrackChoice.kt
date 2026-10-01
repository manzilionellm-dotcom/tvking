package com.manzilionellm.native_video_player.logic

/**
 * Choix d'UNE piste vidéo quand le flux en propose plusieurs qui ne
 * sont PAS un ladder adaptatif (HLS). Le HLS, lui, reste géré par
 * Media3 : on n'écrase pas son choix, sinon la qualité ne pourrait
 * plus descendre quand le Wi-Fi faiblit.
 *
 * Règle, du plus important au moins important :
 *  1. une seule piste fixe, ou seulement des pistes adaptatives → null
 *     (on ne touche à rien) ;
 *  2. on garde celles qui tiennent sur l'écran (hauteur ≤ écran + 10 %),
 *     s'il en reste au moins une. Une 4K seule sur une TV 1080p est
 *     quand même jouée : une chaîne doit démarrer ;
 *  3. si on connaît le débit, on garde celles qui tiennent dans 70 %
 *     de ce débit. Si aucune ne tient, on prend la plus légère pour
 *     que l'image parte quand même ;
 *  4. sinon la plus haute, puis le débit le plus élevé ;
 *  5. si ce choix est déjà celui qui joue, null : pas de second
 *     basculement (ça couperait l'image pour rien).
 *
 * Débit 0 ou trop peu d'octets lus = débit inconnu. On ne prend pas
 * le 1 Mbit/s « par défaut » de Media3 pour un vrai débit mesuré.
 */
data class VideoCandidate(
    val group: Int,
    val index: Int,
    val width: Int,
    val height: Int,
    val bitrate: Int,
    val frameRate: Float,
    val mime: String?,
    val selected: Boolean,
    val adaptive: Boolean,
)

object VideoTrackChoice {
    /** En dessous de ça, l'estimation de débit n'est pas encore fiable. */
    const val MIN_BYTES_BEFORE_BANDWIDTH: Long = 64L * 1024L

    /** Part du débit qu'on accepte d'occuper avec la vidéo. */
    const val BANDWIDTH_FRACTION: Double = 0.7

    fun bandwidthForChoice(bitrateEstimateBps: Long, bytesLoaded: Long): Long {
        if (bytesLoaded < MIN_BYTES_BEFORE_BANDWIDTH) return 0L
        if (bitrateEstimateBps <= 0L) return 0L
        return bitrateEstimateBps
    }

    fun pick(
        tracks: List<VideoCandidate>,
        bandwidthBps: Long,
        screenHeightPx: Int,
    ): VideoCandidate? {
        val fixed = tracks.filter { !it.adaptive }
        if (fixed.size < 2) return null
        val onScreen = fixed.filter { fits(it.height, screenHeightPx) }
        val pool = if (onScreen.isNotEmpty()) onScreen else fixed
        val chosen = if (bandwidthBps > 0L) {
            val affordable = pool.filter { withinBudget(it, bandwidthBps) }
            if (affordable.isNotEmpty()) bestQuality(affordable) else lightest(pool)
        } else {
            bestQuality(pool)
        }
        if (chosen.selected) return null
        return chosen
    }

    private fun fits(height: Int, screenHeightPx: Int): Boolean {
        if (screenHeightPx <= 0 || height <= 0) return true
        return height <= screenHeightPx + screenHeightPx / 10
    }

    private fun withinBudget(track: VideoCandidate, bandwidthBps: Long): Boolean {
        if (track.bitrate <= 0) return true
        val ceiling = (bandwidthBps * BANDWIDTH_FRACTION).toLong()
        return track.bitrate.toLong() <= ceiling
    }

    private fun bestQuality(tracks: List<VideoCandidate>): VideoCandidate {
        return tracks.maxWith(compareBy<VideoCandidate> { it.height }.thenBy { it.bitrate })
    }

    /** La plus légère. Un débit inconnu passe après un débit connu. */
    private fun lightest(tracks: List<VideoCandidate>): VideoCandidate {
        return tracks.minWith(
            compareBy<VideoCandidate> { if (it.bitrate <= 0) Int.MAX_VALUE else it.bitrate }
                .thenBy { it.height },
        )
    }
}
