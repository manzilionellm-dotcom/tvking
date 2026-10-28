package com.manzilionellm.native_video_player.logic

import kotlin.math.roundToInt

/**
 * Taille d'affichage de la vidéo, sans étirer ni rogner le flux.
 * Les pixels ne sont pas toujours carrés (ex. certaines chaînes 720 × 576).
 * Ce calcul ne filtre pas les images et ne quitte pas la Surface matérielle.
 */
data class VideoBounds(val width: Int, val height: Int)

object VideoGeometry {
    fun fit(
        viewportWidth: Int,
        viewportHeight: Int,
        videoWidth: Int,
        videoHeight: Int,
        pixelRatio: Float = 1f,
    ): VideoBounds {
        val w = viewportWidth.coerceAtLeast(0)
        val h = viewportHeight.coerceAtLeast(0)
        if (w == 0 || h == 0 || videoWidth <= 0 || videoHeight <= 0) {
            return VideoBounds(w, h)
        }
        val pixels = if (pixelRatio.isFinite() && pixelRatio > 0f) pixelRatio else 1f
        val ratio = videoWidth.toDouble() * pixels / videoHeight
        return if (w.toDouble() / h > ratio) {
            VideoBounds((h * ratio).roundToInt().coerceIn(1, w), h)
        } else {
            VideoBounds(w, (w / ratio).roundToInt().coerceIn(1, h))
        }
    }

    /** Une interface 1080p sur une sortie HDMI 4K ne doit pas plafonner le flux. */
    fun screenHeight(physicalWidth: Int, physicalHeight: Int, fallbackHeight: Int): Int =
        if (physicalWidth > 0 && physicalHeight > 0) {
            // La piste est classée selon son petit côté, quel que soit le sens du téléphone.
            minOf(physicalWidth, physicalHeight)
        } else {
            fallbackHeight.coerceAtLeast(0)
        }
}
