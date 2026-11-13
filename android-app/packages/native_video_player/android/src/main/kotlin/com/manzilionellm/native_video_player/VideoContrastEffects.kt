package com.manzilionellm.native_video_player

import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Contrast
import androidx.media3.effect.RgbMatrix
import com.manzilionellm.native_video_player.logic.PictureTune

/**
 * Même matrice dynamique pendant toute la vie de la vue. Media3 relit
 * getMatrix pour chaque image : ON/OFF ne remplace donc pas la chaîne de
 * traitements pendant la lecture, ce qui pouvait figer le graphe 1.5.1.
 */
@UnstableApi
internal class VideoContrastEffects : RgbMatrix {
    @Volatile private var enabled = PictureTune.DEFAULT_ENABLED
    private val contrast = Contrast(PictureTune.LIGHT_CONTRAST)

    // Identité EXACTE : Contrast(0) emploierait la formule avec 1.0001f.
    private val identity = floatArrayOf(
        1f, 0f, 0f, 0f,
        0f, 1f, 0f, 0f,
        0f, 0f, 1f, 0f,
        0f, 0f, 0f, 1f,
    )

    fun setEnabled(requested: Boolean, hardwareAllows: Boolean) {
        enabled = PictureTune.resolve(requested, hardwareAllows)
    }

    override fun getMatrix(presentationTimeUs: Long, useHdr: Boolean): FloatArray =
        if (enabled && !useHdr) contrast.getMatrix(presentationTimeUs, false) else identity

    // OFF n'est que l'état courant : laisser Media3 éliminer cet effet
    // empêcherait un ON ultérieur de modifier les pixels sans reconstruction.
    override fun isNoOp(inputWidth: Int, inputHeight: Int): Boolean = false
}
