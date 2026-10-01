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
