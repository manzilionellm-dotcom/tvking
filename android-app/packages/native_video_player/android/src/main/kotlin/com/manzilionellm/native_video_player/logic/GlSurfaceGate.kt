package com.manzilionellm.native_video_player.logic

/**
 * Quand le processeur d'image (OpenGL, Media3 1.5.1) a le droit de
 * s'accrocher à la SurfaceView.
 *
 * Le graphe GL fige la taille de sa sortie au moment où on le prépare.
 * Une surface absente, ou large de 0 (la vue Flutter n'est pas encore dans
 * la fenêtre), donne une sortie 0×0 : le son part, l'image reste noire, et
 * les « trames » comptées par le métadonnées ne prouvent rien. On attend
 * donc une surface valide et non nulle AVANT d'installer les effets.
 *
 * Une fois le graphe créé, changer la taille du tampon (setFixedSize)
 * détruit la surface. Media3 1.5.1 ne rebranche pas la sortie : écran noir
 * là aussi. On ne retaille plus après l'installation.
 */
object GlSurfaceGate {
    /** Délai après lequel on prépare SANS effet si la surface n'arrive pas. */
    const val SURFACE_WAIT_MS = 800L

    /** Une sortie GL restée à 0 pendant ce délai n'affichera rien. */
    const val ZERO_OUTPUT_MS = 400L

    fun effectsReady(surfaceValid: Boolean, width: Int, height: Int): Boolean =
        surfaceValid && width > 0 && height > 0

    /**
     * Trame VIDEO_RAW sans taille : le GL dessine dans le vide.
     * On ne la compte pas comme une image visible.
     */
    fun countsAsVisibleFrame(
        glPipeline: Boolean,
        mimeType: String?,
        width: Int,
        height: Int,
    ): Boolean {
        if (outputUnusable(glPipeline, mimeType, width, height)) return false
        return true
    }

    fun outputUnusable(
        glPipeline: Boolean,
        mimeType: String?,
        width: Int,
        height: Int,
    ): Boolean = glPipeline && mimeType == "video/raw" && (width <= 0 || height <= 0)

    fun abandonZeroOutput(zeroForMs: Long): Boolean = zeroForMs >= ZERO_OUTPUT_MS

    /** Vrai : retoucher le tampon casserait le graphe déjà en place. */
    fun resizeWouldBlank(graphBound: Boolean): Boolean = graphBound
}
