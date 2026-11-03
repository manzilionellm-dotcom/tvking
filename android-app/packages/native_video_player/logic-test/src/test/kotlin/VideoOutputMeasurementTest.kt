import com.manzilionellm.native_video_player.logic.MeasuredVideoSize
import com.manzilionellm.native_video_player.logic.VideoOutputMeasurement
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class VideoOutputMeasurementTest {
    @Test
    fun tailleReelleDeSortieGlSansImposerCelleDuFormatSource() {
        assertEquals(MeasuredVideoSize(256, 144), VideoOutputMeasurement.fromGlFrame(true, "video/raw", 256, 144))
        // Un effet peut produire une autre taille : conserver la mesure,
        // sans la rabattre sur une taille de source ou de mire codée en dur.
        assertEquals(MeasuredVideoSize(2560, 1440), VideoOutputMeasurement.fromGlFrame(true, "video/raw", 2560, 1440))
    }

    @Test
    fun formatEntreeOuPipelineNonGlNeDevientJamaisUneMesureDeSortie() {
        for (mime in listOf("video/avc", "video/hevc", "video/dolby-vision", null)) {
            assertNull(VideoOutputMeasurement.fromGlFrame(true, mime, 3840, 2160))
        }
        assertNull(VideoOutputMeasurement.fromGlFrame(false, "video/raw", 3840, 2160))
    }

    @Test
    fun premiereImageSansTailleEtDimensionsInvalidesRestentInconnues() {
        assertNull(VideoOutputMeasurement.fromGlFrame(true, "video/raw", -1, -1))
        assertNull(VideoOutputMeasurement.fromGlFrame(true, "video/raw", 0, 144))
        assertNull(VideoOutputMeasurement.fromGlFrame(true, "video/raw", 256, 0))
        assertNull(VideoOutputMeasurement.fromGlFrame(true, "video/raw", Int.MAX_VALUE, 144))
    }
}
