package com.manzilionellm.native_video_player.logic

/**
 * CHEMIN DE SORTIE (02/10/2026) — hypothèse « comme quand on t'appelle ».
 *
 * Si Android est resté en mode communication (micro, reconnaissance
 * vocale, Bluetooth d'appel), TOUTE lecture média passe par le chemin
 * téléphone : bande étroite, traitement d'écho. Ça sonne « vieille radio »
 * / « dans un trou », ça survit au zap, et un autre lecteur (mpv) l'entend
 * pareil. Ce fichier ne change pas le mode : il met des mots sur les
 * chiffres que le lecteur Android a lus.
 *
 * Les numéros sont ceux d'Android (AudioManager, AudioDeviceInfo,
 * AudioAttributes), recopiés ici pour que le test n'ait pas besoin du SDK.
 *
 * Pur Kotlin.
 */
object AudioRouteState {

    const val MODE_NORMAL: Int = 0
    const val MODE_RINGTONE: Int = 1
    const val MODE_IN_CALL: Int = 2
    const val MODE_IN_COMMUNICATION: Int = 3
    const val MODE_CALL_SCREENING: Int = 4
    const val MODE_CALL_REDIRECT: Int = 5
    const val MODE_COMMUNICATION_REDIRECT: Int = 6

    const val USAGE_MEDIA: Int = 1
    const val USAGE_VOICE_COMMUNICATION: Int = 2
    const val USAGE_GAME: Int = 14

    const val CONTENT_UNKNOWN: Int = 0
    const val CONTENT_SPEECH: Int = 1
    const val CONTENT_MUSIC: Int = 2
    const val CONTENT_MOVIE: Int = 3
    const val CONTENT_SONIFICATION: Int = 4

    const val TYPE_BUILTIN_EARPIECE: Int = 1
    const val TYPE_BUILTIN_SPEAKER: Int = 2
    const val TYPE_WIRED_HEADSET: Int = 3
    const val TYPE_WIRED_HEADPHONES: Int = 4
    const val TYPE_BLUETOOTH_SCO: Int = 7
    const val TYPE_BLUETOOTH_A2DP: Int = 8
    const val TYPE_HDMI: Int = 9
    const val TYPE_HDMI_ARC: Int = 10
    const val TYPE_USB_DEVICE: Int = 11
    const val TYPE_USB_HEADSET: Int = 22
    const val TYPE_BUILTIN_SPEAKER_SAFE: Int = 24
    const val TYPE_BLE_HEADSET: Int = 26
    const val TYPE_BLE_SPEAKER: Int = 27
    const val TYPE_HDMI_EARC: Int = 29

    /**
     * Qui joue, sans le compteur client d'Android.
     *
     * [uidMatches] null = la réflexion getClientUid n'a rien donné
     * (Android 16 la bloque : on lisait « Zuno 0, box 1 » alors que
     * cette lecture naissait avec notre AudioTrack).
     * [ourTracks] = AudioTrack de cette app encore vivants, comptés
     * par nous, pas par Android.
     */
    data class Owner(
        val announced: Int,
        val ours: Int,
        val others: Int,
        val uidTrusted: Boolean,
        val ourTracks: Int,
    ) {
        companion object {
            fun unknown(ourTracks: Int = 0): Owner = Owner(
                announced = -1,
                ours = -1,
                others = -1,
                uidTrusted = false,
                ourTracks = ourTracks,
            )
        }
    }

    /**
     * Chiffres lus sur l'appareil. −1 = pas encore lu.
     * [routedType] / [routedName] = la sortie de la lecture annoncée
     * (même renseignement que AudioTrack.getRoutedDevice).
     * [plannedTypes] = appareils qu'Android choisirait pour un son
     * média « film » (getDevicesForAttributes).
     */
    data class Facts(
        val mode: Int = -1,
        val speakerphone: Boolean = false,
        val bluetoothSco: Boolean = false,
        val routedType: Int = -1,
        val routedName: String = "",
        val plannedTypes: List<Int> = emptyList(),
        val usage: Int = -1,
        val contentType: Int = -1,
    )

    fun modeLabel(mode: Int): String = when (mode) {
        MODE_NORMAL -> "normal"
        MODE_RINGTONE -> "sonnerie"
        MODE_IN_CALL -> "appel"
        MODE_IN_COMMUNICATION -> "communication"
        MODE_CALL_SCREENING -> "filtrage d'appel"
        MODE_CALL_REDIRECT -> "renvoi d'appel"
        MODE_COMMUNICATION_REDIRECT -> "renvoi communication"
        -1 -> "inconnu"
        else -> "mode $mode"
    }

    /** Vrai si Android fait passer le son par le chemin téléphone. */
    fun callPath(mode: Int): Boolean = mode == MODE_IN_CALL ||
        mode == MODE_IN_COMMUNICATION ||
        mode == MODE_CALL_SCREENING ||
        mode == MODE_CALL_REDIRECT ||
        mode == MODE_COMMUNICATION_REDIRECT

    fun deviceLabel(type: Int): String = when (type) {
        TYPE_BUILTIN_EARPIECE -> "écouteur d'appel"
        TYPE_BUILTIN_SPEAKER -> "haut-parleur interne"
        TYPE_BUILTIN_SPEAKER_SAFE -> "haut-parleur interne"
        TYPE_WIRED_HEADSET -> "casque filaire"
        TYPE_WIRED_HEADPHONES -> "casque filaire"
        TYPE_BLUETOOTH_SCO -> "Bluetooth appel"
        TYPE_BLUETOOTH_A2DP -> "Bluetooth musique"
        TYPE_BLE_HEADSET -> "Bluetooth appel"
        TYPE_BLE_SPEAKER -> "Bluetooth musique"
        TYPE_HDMI -> "HDMI"
        TYPE_HDMI_ARC -> "HDMI"
        TYPE_HDMI_EARC -> "HDMI"
        TYPE_USB_DEVICE -> "USB"
        TYPE_USB_HEADSET -> "casque USB"
        -1 -> "non lue"
        else -> "type $type"
    }

    fun streamLabel(usage: Int, contentType: Int): String {
        val content = when (contentType) {
            CONTENT_SPEECH -> "parole"
            CONTENT_MUSIC -> "musique"
            CONTENT_MOVIE -> "film"
            CONTENT_SONIFICATION -> "bip"
            CONTENT_UNKNOWN -> "inconnu"
            -1 -> "inconnu"
            else -> "type $contentType"
        }
        return when (usage) {
            USAGE_VOICE_COMMUNICATION -> "appel (contenu $content)"
            USAGE_MEDIA -> "musique (contenu $content)"
            USAGE_GAME -> "jeu (contenu $content)"
            -1 -> "inconnu"
            else -> "usage $usage (contenu $content)"
        }
    }

    /** Nom d'appareil collé dans la fiche : court, sans retour à la ligne. */
    fun safeName(raw: String?): String {
        if (raw.isNullOrBlank()) return ""
        val clean = raw.replace(Regex("[\\p{Cntrl}]"), " ").trim()
        if (clean.isEmpty()) return ""
        return if (clean.length <= 40) clean else clean.substring(0, 40)
    }

    /**
     * À qui appartient la lecture annoncée.
     *
     * On ne croit le compteur client que s'il a reconnu au moins une
     * lecture à nous, ou si notre AudioTrack est arrêté (une autre app
     * peut alors être la seule). Sinon c'est le cas Android 16 : le
     * compteur dit 0 alors que notre piste est vivante, et cette piste
     * EST la lecture « film ».
     */
    fun attribute(announced: Int, uidMatches: Int?, ourTracks: Int): Owner {
        val tracks = ourTracks.coerceAtLeast(0)
        if (announced < 0) return Owner.unknown(tracks)
        val trustUid = uidMatches != null && (uidMatches > 0 || tracks == 0)
        if (trustUid) {
            val ours = uidMatches.coerceIn(0, announced)
            return Owner(
                announced = announced,
                ours = ours,
                others = announced - ours,
                uidTrusted = true,
                ourTracks = tracks,
            )
        }
        val ours = minOf(tracks, announced)
        return Owner(
            announced = announced,
            ours = ours,
            others = announced - ours,
            uidTrusted = false,
            ourTracks = tracks,
        )
    }

    /** Morceau de la ligne « Seconde N ». */
    fun playbackPhrase(o: Owner): String {
        if (o.announced < 0) return "lectures pas encore annoncées."
        val how = if (o.uidTrusted) {
            "compteur client Android"
        } else {
            "AudioTrack de cette app, le compteur client d'Android ne répond pas"
        }
        return "lectures de cette app ${o.ours}, autres apps ${o.others} ($how)."
    }

    /**
     * Phrase de la fiche. Dit explicitement quand l'ancien « Zuno 0,
     * box 1 » était notre propre AudioTrack.
     */
    fun playbackNote(o: Owner, audible: Boolean): String {
        if (o.announced < 0) {
            return "Lectures audio : pas encore annoncées par Android."
        }
        if (!o.uidTrusted && o.ourTracks > 0 && o.others == 0) {
            return "Lectures audio : Android en annonce ${o.announced}, notre AudioTrack est vivant → " +
                "c'est cette app. On ne dit plus « Zuno 0, box 1 » : ce « 1 (film) » naît avec notre " +
                "AudioTrack, et Android 16 ne donne pas le compteur client."
        }
        if (!o.uidTrusted && o.ourTracks > 0 && o.others > 0) {
            return "Lectures audio : Android en annonce ${o.announced}, notre AudioTrack est vivant, " +
                "autres apps ${o.others}. Une autre application joue en même temps."
        }
        if (o.ourTracks == 0 && o.announced == 0 && audible) {
            return "Lectures audio : 0 annoncée, alors que le lecteur joue. " +
                "La fiche a été écrite avant que Android compte cette lecture."
        }
        if (o.ourTracks == 0 && o.announced == 0) {
            return "Lectures audio : 0. Le lecteur ne joue pas encore, " +
                "ou la lecture est arrêtée (Home, pause, zap en cours). " +
                "Si le son s'entend quand même, la fiche a été prise avant le démarrage de l'AudioTrack."
        }
        if (o.ourTracks == 0 && o.announced > 0) {
            return "Lectures audio : Android en annonce ${o.announced}, notre AudioTrack est arrêté. " +
                "Ce son n'est pas le nôtre, ou la fiche est en avance sur le démarrage."
        }
        return "Lectures audio : cette app ${o.ours}, autres apps ${o.others}."
    }

    /** Ligne « Chemin ». Le ⚠ est là seulement si le chemin est celui d'un appel. */
    fun pathLine(f: Facts): String {
        val warn = if (callPath(f.mode) || f.bluetoothSco || earpiece(f.routedType)) {
            " ⚠ chemin d'appel"
        } else {
            ""
        }
        val spk = if (f.speakerphone) "allumé" else "coupé"
        val sco = if (f.bluetoothSco) "allumé" else "coupé"
        val name = safeName(f.routedName)
        val routed = deviceLabel(f.routedType) + if (name.isEmpty()) "" else " « $name »"
        val planned = if (f.plannedTypes.isEmpty()) {
            "non lus"
        } else {
            f.plannedTypes.joinToString(", ") { deviceLabel(it) }
        }
        return "Chemin : mode ${modeLabel(f.mode)}$warn, haut-parleur d'appel $spk, " +
            "Bluetooth appel $sco, sortie $routed, appareils prévus $planned, " +
            "flux ${streamLabel(f.usage, f.contentType)}."
    }

    private fun earpiece(type: Int): Boolean =
        type == TYPE_BUILTIN_EARPIECE || type == TYPE_BLUETOOTH_SCO || type == TYPE_BLE_HEADSET
}
