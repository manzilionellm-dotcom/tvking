package com.manzilionellm.native_video_player.logic

/**
 * Contraste vidéo léger, COUPÉ par défaut : la personne l'allume dans
 * Réglages → Contraste.
 *
 * Le traitement Android est réalisé par Contrast de Media3, dans un
 * processeur OpenGL avant la SurfaceView. Ce n'est ni de la netteté ni
 * une restauration de détails. [hardwareAllows] décrit maintenant le
 * chemin de lecture courant : MediaCodec SDR, sans repli GPU. HDR/DRM
 * et rendu FFmpeg conservent leur chemin direct.
 *
 * Pourquoi coupé (mesuré sur mire BT.709, émulateurs API 29 et 35) :
 *  - la matrice Media3 Contrast(0.08) vaut 1,174·x − 0,087 sur le R'G'B'.
 *    Tout ce qui est sous 19/255 devient noir, tout ce qui dépasse
 *    236/255 devient blanc : détails des ombres et des hautes lumières
 *    perdus sur toutes les chaînes ;
 *  - le passage OpenGL lui-même (même à contraste nul) remplace la
 *    sortie directe MediaCodec → SurfaceView. Sur API 35 il ne livrait
 *    que 9 images/s d'un flux 60 i/s, sur API 29 l'image se figeait puis
 *    la chaîne tombait en erreur. La sortie directe est celle que la doc
 *    Media3 recommande (page « Surface types ») : cadence exacte, HDR,
 *    pleine résolution de l'écran sur les TV à interface 1080p.
 */
object PictureTune {
    const val DEFAULT_ENABLED: Boolean = false

    /** Intensité Media3, pas un pourcentage de netteté ou de luminosité. */
    const val LIGHT_CONTRAST: Float = 0.08f

    fun resolve(requested: Boolean, hardwareAllows: Boolean): Boolean =
        requested && hardwareAllows

    /** HDR et DRM gardent le rendu direct, sans conversion par le filtre SDR. */
    fun directReason(isHdr: Boolean, hasDrm: Boolean): String? = when {
        hasDrm -> "drm"
        isHdr -> "hdr"
        else -> null
    }
}
