package com.manzilionellm.native_video_player.logic

/**
 * Réglages OPTIONNELS du diagnostic audio. Tous FAUX par défaut :
 * le lecteur garde exactement le chemin de la v106 (AAC → FFmpeg).
 *
 *   • [probe] — la sonde PCM ([AudioProbeProcessor]) se met à mesurer.
 *     Coupée, elle renvoie NOT_SET : Media3 ne la met pas dans la chaîne,
 *     comme « voix claire » quand elle est coupée.
 *   • [keepFfmpeg] — au prochain `setUrl`, on redemande FFmpeg pour
 *     l'AAC / le MP2 même si un repli précédent avait rendu la main à la
 *     box. Le filet des 8 s ([requestBoxAudioFallback]) reste armé :
 *     si FFmpeg ne démarre pas, on revient à la box pour CETTE chaîne.
 *   • [preferPlatformAac] — au prochain `setUrl`, l'AAC passe par le
 *     décodeur de la box (comme ExoPlayer par défaut), pas par FFmpeg.
 *     Le MP2 ne change pas. Si la box échoue, on revient à FFmpeg
 *     pour cette ouverture seulement.
 */
object AudioFixes {
    const val KEY_PROBE: String = "zuno.audio.diag.probe"
    const val KEY_FFMPEG: String = "zuno.audio.fix.ffmpeg"
    const val KEY_PLATFORM: String = "zuno.audio.fix.platform"

    /**
     * Interrupteur de REPLI du correctif « repli AAC par chaîne » : vrai =
     * ancien comportement (une panne FFmpeg → la box pour toutes les
     * chaînes du processus). Faux par défaut. Voir [AacRoute.sessionWide].
     */
    const val KEY_SESSION_WIDE: String = "zuno.audio.fix.session_fallback"

    /**
     * Interrupteur de REPLI du correctif « focus audio » : vrai = Media3 gère
     * le focus comme avant (et baisse le son à 20 % quand une autre app le
     * demande). Faux par défaut : Zuno gère le focus lui-même, sans baisse.
     * Voir [AudioFocusPolicy].
     */
    const val KEY_ANDROID_FOCUS: String = "zuno.audio.focus.android"

    /**
     * Interrupteur de REPLI du passage « un seul AudioTrack ». Vrai = on
     * ouvre la chaîne suivante sans attendre que l'AudioTrack précédent
     * soit rendu (Media3 1.5.1 le rend en retard : deux pistes se
     * chevauchent). Faux par défaut : on attend.
     */
    const val KEY_IMMEDIATE_HANDOFF: String = "zuno.audio.handoff.immediate"

    /**
     * CORRECTIF CANDIDAT H1 (02/10/2026) : vrai = avant chaque ouverture,
     * si le système est en mode « appel / communication », si le
     * haut-parleur d'appel ou le Bluetooth SCO est allumé, on remet le
     * mode à normal (voir [AudioRoute.repairPlan]). Faux par défaut : on
     * ne touche jamais au système tant que le journal ne montre pas
     * l'anomalie. Réglage « Mode : normal forcé ».
     */
    const val KEY_MODE_NORMAL: String = "zuno.audio.fix.mode_normal"

    /**
     * ESSAI H2 (02/10/2026) : le type de contenu déclaré au système.
     * « film » (défaut v106, CONTENT_TYPE_MOVIE), « musique » ou « parole ».
     * Certains appareils appliquent un traitement « cinéma » (virtualisation,
     * égaliseur) au type film. Réglage « Type : film / musique / parole ».
     */
    const val KEY_CONTENT_TYPE: String = "zuno.audio.attr.content"

    const val CONTENT_FILM: String = "film"
    const val CONTENT_MUSIQUE: String = "musique"
    const val CONTENT_PAROLE: String = "parole"

    @Volatile
    var forceNormalMode: Boolean = false

    /** Un des trois libellés ci-dessus. Tout autre texte vaut « film ». */
    @Volatile
    var contentType: String = CONTENT_FILM

    /** Valeur suivante dans le cycle film → musique → parole → film. */
    fun nextContentType(current: String): String = when (current) {
        CONTENT_FILM -> CONTENT_MUSIQUE
        CONTENT_MUSIQUE -> CONTENT_PAROLE
        else -> CONTENT_FILM
    }

    /**
     * Type de contenu à déclarer (constantes de [PlaybackCount]). La voix
     * claire garde son comportement d'avant : elle impose « parole ».
     * Sinon le réglage décide ; un réglage inconnu vaut « film » (v106).
     */
    fun contentTypeFor(clearVoice: Boolean, setting: String): Int {
        if (clearVoice) return PlaybackCount.CONTENT_SPEECH
        return when (setting) {
            CONTENT_MUSIQUE -> PlaybackCount.CONTENT_MUSIC
            CONTENT_PAROLE -> PlaybackCount.CONTENT_SPEECH
            else -> PlaybackCount.CONTENT_MOVIE
        }
    }

    /** Libellé lisible du type déclaré, pour la fiche. */
    fun contentTypeLabel(clearVoice: Boolean, setting: String): String =
        PlaybackCount.contentLabel(contentTypeFor(clearVoice, setting)) +
            (if (clearVoice) " (imposé par la voix claire)" else "")

    @Volatile
    var androidFocus: Boolean = false

    /** Vrai = ancien passage (on n'attend pas l'AudioTrack). Faux par défaut. */
    @Volatile
    var immediateHandoff: Boolean = false

    @Volatile
    var probe: Boolean = false

    @Volatile
    var keepFfmpeg: Boolean = false

    @Volatile
    var preferPlatformAac: Boolean = false

    /**
     * Faut-il cacher le décodeur AAC de la box pour laisser FFmpeg ?
     *
     * Défaut (tout faux, FFmpeg disponible) : oui, comme la v106.
     * [preferPlatform] vrai : non, la box décode l'AAC.
     * [gaveUpToFfmpeg] vrai : la box vient d'échouer, on reste sur FFmpeg
     * même si un repli box est armé (sinon les deux se renverraient la balle).
     */
    fun ffmpegForAac(
        preferPlatform: Boolean,
        gaveUpToFfmpeg: Boolean,
        forceBox: Boolean,
        ffmpegReady: Boolean,
        ffmpegSupports: Boolean,
    ): Boolean {
        if (!ffmpegReady || !ffmpegSupports) return false
        if (gaveUpToFfmpeg) return true
        if (forceBox || preferPlatform) return false
        return true
    }

    /**
     * Valeur de `forceBoxAacDecoder` à utiliser pour la prochaine ouverture.
     * [keepFfmpeg] faux → on ne touche pas au drapeau (comportement inchangé).
     * [keepFfmpeg] vrai → on réessaie FFmpeg (le drapeau de repli repart à faux).
     */
    fun forceBoxAfterOpen(keepFfmpeg: Boolean, forceBox: Boolean): Boolean {
        return if (keepFfmpeg) false else forceBox
    }
}
