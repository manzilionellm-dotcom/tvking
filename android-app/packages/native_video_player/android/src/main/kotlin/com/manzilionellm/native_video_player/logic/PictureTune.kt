package com.manzilionellm.native_video_player.logic

/**
 * Contraste vidéo léger, activé au premier démarrage.
 *
 * Le traitement Android est réalisé par Contrast de Media3, dans un
 * processeur OpenGL avant la SurfaceView. Ce n'est ni de la netteté ni
 * une restauration de détails. [hardwareAllows] décrit maintenant le
 * chemin de lecture courant : MediaCodec SDR, sans repli GPU. HDR/DRM
 * et rendu FFmpeg conservent leur chemin direct.
 */
object PictureTune {
    const val DEFAULT_ENABLED: Boolean = true

    /** Intensité Media3, pas un pourcentage de netteté ou de luminosité. */
    const val LIGHT_CONTRAST: Float = 0.08f

    fun resolve(requested: Boolean, hardwareAllows: Boolean): Boolean =
        requested && hardwareAllows
}
