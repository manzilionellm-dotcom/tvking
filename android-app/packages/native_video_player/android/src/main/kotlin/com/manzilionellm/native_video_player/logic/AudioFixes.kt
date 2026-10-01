package com.manzilionellm.native_video_player.logic

/**
 * Réglages OPTIONNELS du diagnostic audio. Les deux sont FAUX par défaut :
 * le lecteur garde exactement le chemin de la v106.
 *
 *   • [probe] — la sonde PCM ([AudioProbeProcessor]) se met à mesurer.
 *     Coupée, elle renvoie NOT_SET : Media3 ne la met pas dans la chaîne,
 *     comme « voix claire » quand elle est coupée.
 *   • [keepFfmpeg] — au prochain `setUrl`, on redemande FFmpeg pour
 *     l'AAC / le MP2 même si un repli précédent avait rendu la main à la
 *     box. Le filet des 8 s ([requestBoxAudioFallback]) reste armé :
 *     si FFmpeg ne démarre pas, on revient à la box pour CETTE chaîne.
 */
object AudioFixes {
    const val KEY_PROBE: String = "zuno.audio.diag.probe"
    const val KEY_FFMPEG: String = "zuno.audio.fix.ffmpeg"

    @Volatile
    var probe: Boolean = false

    @Volatile
    var keepFfmpeg: Boolean = false

    /**
     * Valeur de `forceBoxAacDecoder` à utiliser pour la prochaine ouverture.
     * [keepFfmpeg] faux → on ne touche pas au drapeau (comportement inchangé).
     * [keepFfmpeg] vrai → on réessaie FFmpeg (le drapeau de repli repart à faux).
     */
    fun forceBoxAfterOpen(keepFfmpeg: Boolean, forceBox: Boolean): Boolean {
        return if (keepFfmpeg) false else forceBox
    }
}
