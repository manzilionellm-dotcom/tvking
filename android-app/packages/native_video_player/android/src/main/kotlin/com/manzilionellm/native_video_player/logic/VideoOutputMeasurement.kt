package com.manzilionellm.native_video_player.logic

data class MeasuredVideoSize(val width: Int, val height: Int)

/**
 * Media3 1.5.1 ne remonte pas onVideoSizeChanged sur le chemin VideoSink/GL
 * (b/292111083). Son PlaybackVideoGraphWrapper fournit en revanche la taille
 * de sortie observée au VideoFrameMetadataListener, dans un format VIDEO_RAW.
 * Un format d'entrée AVC/HEVC, même valide, ne prouve jamais cette taille.
 */
object VideoOutputMeasurement {
    fun fromGlFrame(
        glPipeline: Boolean,
        sampleMimeType: String?,
        width: Int,
        height: Int,
    ): MeasuredVideoSize? {
        if (!glPipeline || sampleMimeType != "video/raw") return null
        if (width !in 1..32768 || height !in 1..32768) return null
        return MeasuredVideoSize(width, height)
    }
}
