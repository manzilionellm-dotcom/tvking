package com.manzilionellm.native_video_player.logic

/**
 * Une surface perdue n'autorise pas à oublier le décodeur. Seul le retour
 * réussi de release confirme qu'un travail GPU idle peut reprendre.
 */
object VideoRelease {
    fun attempt(clearSurface: () -> Unit, releasePlayer: () -> Unit): Boolean {
        try { clearSurface() } catch (_: RuntimeException) {
            // Continuer avec la vraie libération, même sans surface valide.
        }
        return try {
            releasePlayer()
            true
        } catch (_: RuntimeException) {
            false
        }
    }
}
