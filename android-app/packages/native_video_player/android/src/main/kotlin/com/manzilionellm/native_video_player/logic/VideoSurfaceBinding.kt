package com.manzilionellm.native_video_player.logic

/**
 * Décide QUAND brancher le lecteur sur la SurfaceView.
 *
 * Flutter (hybrid composition) construit la vue avant que la surface
 * existe, puis la déplace dans la fenêtre : Android détruit la surface
 * et en crée une autre. Si Media3 reçoit setVideoSurfaceView pendant que
 * la surface est absente ou que la vue fait 0×0, le graphe OpenGL du
 * contraste (Media3 1.5) mémorise une sortie vide. Le son part, l'image
 * reste noire.
 *
 * On n'attache que lorsque la surface est valide ET la vue dépasse 1 px
 * (Flutter mesure souvent 1 px avant le plein écran). Après une
 * destruction, le prochain moment valide réattache. Une taille déjà
 * réelle ne réattache pas : retoucher le tampon ensuite (setFixedSize)
 * détruit la surface et Media3 1.5.1 ne rebranche pas la sortie.
 */
class VideoSurfaceBinding {
    var bound: Boolean = false
        private set

    private var boundWidth: Int = 0
    private var boundHeight: Int = 0

    /** Nouveau ExoPlayer : l'ancien branchement ne le concerne plus. */
    fun onPlayerReplaced() {
        bound = false
        boundWidth = 0
        boundHeight = 0
    }

    /** La surface Android n'existe plus (reparent Flutter, ou Home). */
    fun onSurfaceDestroyed() {
        bound = false
        boundWidth = 0
        boundHeight = 0
    }

    /**
     * @param width hauteur de la VUE (layout), pas la taille du tampon
     *        fixée par setFixedSize.
     * @return true s'il faut appeler setVideoSurfaceView maintenant.
     */
    fun onSurfaceReady(valid: Boolean, width: Int, height: Int): Boolean {
        if (!valid || width <= 1 || height <= 1) return false
        if (!bound) {
            bound = true
            boundWidth = width
            boundHeight = height
            return true
        }
        boundWidth = width
        boundHeight = height
        return false
    }
}
