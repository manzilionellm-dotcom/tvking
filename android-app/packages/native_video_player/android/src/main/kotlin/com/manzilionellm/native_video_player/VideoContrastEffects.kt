package com.manzilionellm.native_video_player

import androidx.media3.common.Effect
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Contrast
import com.manzilionellm.native_video_player.logic.PictureTune

/**
 * Le lien entre le choix mémorisé et le traitement de pixels réellement
 * transmis à ExoPlayer. Garder ce code hors de la logique JVM : Contrast
 * est un effet Android/OpenGL, pas un booléen décoratif pour l'interface.
 */
@UnstableApi
internal object VideoContrastEffects {
    fun create(requested: Boolean, hardwareAllows: Boolean): List<Effect> =
        if (PictureTune.resolve(requested, hardwareAllows)) {
            listOf(Contrast(PictureTune.LIGHT_CONTRAST))
        } else {
            emptyList()
        }
}
