package com.manzilionellm.native_video_player.logic

import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/** Dimensions du tampon, distinctes de celles de la vue Android. */
data class VideoSurfaceBuffer(val width: Int, val height: Int)

/**
 * Media3 GL dessine à la taille du tampon de sortie. Sur une TV avec une
 * interface 1080p et une sortie 4K, laisser la taille de la vue réduirait donc
 * la vidéo à 1080p avant son affichage. On suit le rapport écran physique /
 * écran logique, en conservant le rapport de la vue (plein écran ou aperçu).
 *
 * null signifie setSizeFromLayout : rendu direct, écran déjà à l'échelle,
 * géométrie inconnue ou invalide. Les bornes empêchent une taille aberrante
 * fournie par un appareil de provoquer une allocation sans limite.
 */
object VideoSurfaceSize {
    const val MAX_SIDE = 8192
    const val MAX_PIXELS = 7680L * 4320L

    fun forContrast(
        pipelineInstalled: Boolean,
        viewWidth: Int,
        viewHeight: Int,
        logicalWidth: Int,
        logicalHeight: Int,
        physicalWidth: Int,
        physicalHeight: Int,
    ): VideoSurfaceBuffer? {
        if (!pipelineInstalled) return null
        if (minOf(viewWidth, viewHeight, logicalWidth, logicalHeight,
                physicalWidth, physicalHeight) <= 0) return null
        // Display.Mode peut rester dans son orientation naturelle après une
        // rotation. Le tampon doit suivre l'orientation logique de la fenêtre.
        val swap = (physicalWidth > physicalHeight) != (logicalWidth > logicalHeight)
        val displayWidth = if (swap) physicalHeight else physicalWidth
        val displayHeight = if (swap) physicalWidth else physicalHeight
        var scale = min(
            displayWidth.toDouble() / logicalWidth,
            displayHeight.toDouble() / logicalHeight,
        )
        scale = min(scale, min(displayWidth, MAX_SIDE).toDouble() / viewWidth)
        scale = min(scale, min(displayHeight, MAX_SIDE).toDouble() / viewHeight)
        scale = min(scale, sqrt(MAX_PIXELS.toDouble() / (viewWidth.toDouble() * viewHeight)))
        if (scale <= 1.0) return null
        val width = (viewWidth * scale).roundToInt().coerceIn(1, min(displayWidth, MAX_SIDE))
        val height = (viewHeight * scale).roundToInt().coerceIn(1, min(displayHeight, MAX_SIDE))
        // Les arrondis ne doivent pas dépasser la borne totale d'un pixel.
        if (width.toLong() * height > MAX_PIXELS) return null
        return VideoSurfaceBuffer(width, height)
    }
}
