package com.manzilionellm.native_video_player.logic

/**
 * COPIE DE LA DERNIÈRE IMAGE (04/10/2026) — « écran noir après une
 * minute, le son continue ».
 *
 * Pendant une coupure (reconnexion, direct en retard, repli), le lecteur
 * pose par-dessus la surface une copie de la dernière image, prise avec
 * `PixelCopy` toutes les 4 s. Deux défauts possibles, lus dans le code :
 *
 *  1. Sur beaucoup de box, `PixelCopy` d'une SurfaceView vidéo rend une
 *     image NOIRE (la vidéo est dans une couche matérielle que le GPU ne
 *     lit pas) tout en répondant `SUCCESS`. On affichait alors du noir
 *     à la place de l'image.
 *  2. La copie n'était retirée qu'au signal « première image rendue » de
 *     la nouvelle session. Certaines box ne l'envoient pas quand la
 *     surface est réutilisée (déjà noté côté Dart pour le logo) : la
 *     copie, noire ou non, restait collée pendant que le son continuait.
 *
 * Règles pures, testées sans Android :
 *  - [looksBlank] : une copie dont aucun échantillon ne dépasse
 *    [BLANK_MAX_LUMA] n'est pas gardée (on préfère le carton de chaîne).
 *  - [shouldHide] : la copie est retirée dès qu'une trame a été rendue
 *    APRÈS son affichage, sans attendre le signal de première image.
 *
 * [legacy] vrai = ancien comportement exact (copie gardée même noire,
 * retirée seulement au signal). Faux par défaut.
 */
object HeldFrame {
    /** Luminance 0–255 au-dessous de laquelle un pixel compte comme noir. */
    const val BLANK_MAX_LUMA: Int = 10

    /** Repli : ancien comportement. Écrit par le réglage, lu sur le fil principal. */
    @Volatile
    var legacy: Boolean = false

    /** Luminance approximative (0–255) d'un pixel ARGB. */
    fun luma(argb: Int): Int {
        val r = (argb shr 16) and 0xFF
        val g = (argb shr 8) and 0xFF
        val b = argb and 0xFF
        return (r * 299 + g * 587 + b * 114) / 1000
    }

    /**
     * Vrai si la copie est inutilisable (tout noir). Une copie sans
     * échantillon est aussi inutilisable. En mode [legacy], jamais.
     */
    fun looksBlank(lumas: IntArray, legacy: Boolean = this.legacy): Boolean {
        if (legacy) return false
        if (lumas.isEmpty()) return true
        return lumas.all { it <= BLANK_MAX_LUMA }
    }

    /**
     * Vrai si la copie affichée doit être retirée maintenant.
     * [framesSinceShown] = trames rendues depuis l'affichage de la copie.
     */
    fun shouldHide(
        holdVisible: Boolean,
        framesSinceShown: Int,
        legacy: Boolean = this.legacy,
    ): Boolean {
        if (legacy || !holdVisible) return false
        return framesSinceShown > 0
    }
}
