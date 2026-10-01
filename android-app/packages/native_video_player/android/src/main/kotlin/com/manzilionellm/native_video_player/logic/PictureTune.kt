package com.manzilionellm.native_video_player.logic

/**
 * Contraste / netteté « légère ».
 *
 * Le seul filtre officiel de Media3 (module effect, OpenGL) fait quitter
 * le chemin Surface directe. C'est ce chemin qui a réparé l'image noire
 * sur les box. Tant que [hardwareAllows] est faux, on NE demande PAS
 * le filtre, même si la personne l'a allumé : une option qui noircit
 * l'écran n'est pas une option.
 *
 * Aujourd'hui le lecteur Android passe [hardwareAllows] à faux. Il n'y
 * a pas d'API publique de netteté sur une Surface MediaCodec. On ne
 * prétend pas le contraire.
 */
object PictureTune {
    /**
     * Valeur qu'on passerait à `Contrast` de Media3 si le matériel
     * l'acceptait (0 = rien, 1 = fort). Documentée pour ne pas être
     * inventée plus tard. Elle n'est appliquée nulle part dans cette
     * version.
     */
    const val LIGHT_CONTRAST: Float = 0.08f

    fun resolve(requested: Boolean, hardwareAllows: Boolean): Boolean =
        requested && hardwareAllows
}
