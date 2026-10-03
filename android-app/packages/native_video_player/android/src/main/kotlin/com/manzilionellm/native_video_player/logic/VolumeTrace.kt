package com.manzilionellm.native_video_player.logic

import java.util.Locale

/**
 * TRACE DE VOLUME (02/10/2026).
 *
 * Le son « dans un trou » est une baisse (Media3 mettait 0,2 sur une
 * demande CAN_DUCK) que les sondes PCM ne voient pas : elle est appliquée
 * sur le lecteur, après la copie. Pendant les 10 premières secondes de
 * chaque ouverture, une ligne dit le volume réel, l'état du focus, et
 * combien de lectures audio sont à nous.
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
        /** Qui joue vraiment. Le compteur client Android 16 n'est plus cru tel quel. */
        val owner: AudioRouteState.Owner = AudioRouteState.Owner.unknown(),
        /** Mode, haut-parleur d'appel, Bluetooth, sortie, flux réel. */
        val path: AudioRouteState.Facts = AudioRouteState.Facts(),
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
            "focus $focus. ${AudioRouteState.playbackPhrase(s.owner)} " +
            AudioRouteState.pathLine(s.path)
    }

    /**
     * Ce que veut dire le compteur affiché sur la fiche.
     * 0 pendant que le son s'entend = la fiche est en avance sur Android,
     * pas la preuve qu'il n'y a pas de lecture.
     */
    fun playbackNote(owner: AudioRouteState.Owner, audible: Boolean): String =
        AudioRouteState.playbackNote(owner, audible)
}
