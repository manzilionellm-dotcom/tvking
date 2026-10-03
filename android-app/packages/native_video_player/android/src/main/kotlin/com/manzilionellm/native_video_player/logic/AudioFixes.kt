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
     * Essai « type de contenu inconnu ». Faux par défaut : on annonce
     * « film » à Android, comme avant. Vrai : on annonce « inconnu »,
     * le défaut de Media3. La voix claire, si elle est allumée, reste
     * « parole ». Le PCM ne change pas : seul l'étiquette lue par les
     * traitements de la box ou du téléphone change.
     */
    const val KEY_REFERENCE_UNKNOWN: String = "zuno.audio.ref.content_unknown"

    @Volatile
    var androidFocus: Boolean = false

    /** Vrai = ancien passage (on n'attend pas l'AudioTrack). Faux par défaut. */
    @Volatile
    var immediateHandoff: Boolean = false

    /**
     * Vrai = annoncer le contenu « inconnu » (défaut Media3) au lieu de
     * « film ». Faux par défaut : le son annoncé reste « film ».
     */
    @Volatile
    var referenceUnknownContent: Boolean = false

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

    /**
     * Numéro de type de contenu Android à annoncer.
     *
     * Les numéros sont ceux d'[AudioRouteState] (les mêmes que le SDK) :
     * 0 inconnu, 1 parole, 3 film.
     *
     * Défaut (les deux faux) : film. C'est le chemin actuel, inchangé.
     * Voix claire allumée : parole, même si l'essai « inconnu » est allumé.
     * Essai seul : inconnu, comme un ExoPlayer qui n'a rien précisé.
     */
    fun announcedContentType(clearVoice: Boolean, referenceUnknown: Boolean): Int {
        if (clearVoice) return AudioRouteState.CONTENT_SPEECH
        if (referenceUnknown) return AudioRouteState.CONTENT_UNKNOWN
        return AudioRouteState.CONTENT_MOVIE
    }
}
