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
        /** Lectures de notre processus. -1 = pas séparable ou pas encore compté. */
        val zunoPlaybacks: Int,
        /** Lectures de toute la box. -1 = pas encore compté. */
        val boxPlaybacks: Int,
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
        val zuno = if (s.zunoPlaybacks < 0) "pas encore comptées" else s.zunoPlaybacks.toString()
        val box = if (s.boxPlaybacks < 0) "pas encore comptées" else s.boxPlaybacks.toString()
        return "Seconde ${s.second} : volume lecteur $player, " +
            "volume AudioTrack $track, volume musique de la box $stream, " +
            "focus $focus, lectures Zuno $zuno, lectures de la box $box."
    }

    /**
     * Ce que veut dire le compteur affiché sur la fiche.
     * 0 pendant que le son s'entend = la fiche est en avance sur Android,
     * pas la preuve qu'il n'y a pas de lecture.
     */
    fun playbackNote(zuno: Int, box: Int, audible: Boolean): String {
        if (zuno < 0 && box < 0) {
            return "Lectures audio de Zuno : pas encore comptées. " +
                "Android n'a pas encore rappelé, ou la fiche part avant le démarrage."
        }
        if (zuno < 0) {
            return "Lectures audio de Zuno : Android ne les sépare pas des autres apps " +
                "(compte de la box : $box). Un 0 ici veut dire qu'aucune lecture n'était " +
                "encore annoncée au moment de la fiche."
        }
        if (zuno == 0 && audible) {
            return "Lectures audio de Zuno : 0, alors que le lecteur joue. " +
                "La fiche a été écrite avant que Android compte cette lecture, " +
                "ou le rappel n'est pas encore arrivé. Ce n'est pas la preuve qu'il n'y a pas de son. " +
                "Les lignes « Seconde 1 » à « Seconde $SECONDS » de la boîte noire donnent le chiffre pendant que ça joue."
        }
        if (zuno == 0) {
            return "Lectures audio de Zuno : 0. Le lecteur ne joue pas encore, " +
                "ou la lecture est arrêtée (Home, pause, zap en cours). " +
                "Si le son s'entend quand même, la fiche a été prise avant le démarrage de l'AudioTrack."
        }
        val boxText = if (box < 0) "" else " Lectures de la box : $box."
        return "Lectures audio de Zuno : $zuno.$boxText"
    }
}
