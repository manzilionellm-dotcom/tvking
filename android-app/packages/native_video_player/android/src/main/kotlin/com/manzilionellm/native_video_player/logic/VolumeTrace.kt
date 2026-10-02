package com.manzilionellm.native_video_player.logic

import java.util.Locale

/**
 * TRACE DE VOLUME (02/10/2026).
 *
 * Le son « dans un trou » est une baisse (Media3 mettait 0,2 sur une
 * demande CAN_DUCK) que les sondes PCM ne voient pas : elle est appliquée
 * sur le lecteur, après la copie. Pendant les 10 premières secondes de
 * chaque ouverture, une ligne dit le volume réel, l'état du focus, l'état
 * du SYSTÈME audio (mode appel ?, route de sortie, micro ouvert ? — H1) et
 * combien de lectures audio tournent, dont la nôtre.
 *
 * Android ne relit pas le volume d'un AudioTrack (pas de getVolume).
 * On écrit « non lisible » plutôt qu'un chiffre inventé. Le volume du
 * flux « musique » de la box, lui, se lit.
 *
 * Pur Kotlin.
 */
object VolumeTrace {

    const val SECONDS: Int = 10

    data class Sample(
        val second: Int,
        /** Volume du lecteur ExoPlayer, 0 à 1. -1 = illisible. */
        val playerVolume: Float,
        /** Volume relu sur l'AudioTrack. Null = Android ne le donne pas. */
        val trackVolume: Float?,
        /** Volume du flux musique de la box, et son maximum. -1 = inconnu. */
        val streamVolume: Int,
        val streamMax: Int,
        val focusHeld: Boolean,
        /** Vrai = réglage de repli, Media3 gère le focus (et peut baisser). */
        val media3Focus: Boolean,
        val pausedByFocus: Boolean,
        /** Lectures audio de l'appareil, attribuées. Null = pas encore comptées. */
        val playbacks: PlaybackCount.Count?,
        /** État du système audio au moment de la ligne ([AudioRoute.short]). Null = non relevé. */
        val route: String?,
    )

    fun line(s: Sample): String {
        val player = if (s.playerVolume < 0f) {
            "illisible"
        } else {
            String.format(Locale.FRANCE, "%.1f", s.playerVolume)
        }
        val track = if (s.trackVolume == null) {
            "non lisible"
        } else {
            String.format(Locale.FRANCE, "%.1f", s.trackVolume)
        }
        val stream = if (s.streamVolume < 0 || s.streamMax < 0) {
            "inconnu"
        } else {
            "${s.streamVolume}/${s.streamMax}"
        }
        val focus = when {
            s.media3Focus -> "géré par Media3 (repli)"
            s.pausedByFocus -> "perte : lecture en pause"
            s.focusHeld -> "tenu par Zuno"
            else -> "pas tenu"
        }
        return "Seconde ${s.second} : volume lecteur $player, " +
            "volume AudioTrack $track, volume musique de la box $stream, " +
            "focus $focus, ${PlaybackCount.short(s.playbacks)}, " +
            "système ${s.route ?: "non relevé"}."
    }
}
