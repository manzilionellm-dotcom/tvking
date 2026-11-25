import com.manzilionellm.native_video_player.logic.PictureTune
import com.manzilionellm.native_video_player.logic.VideoSurfaceBuffer
import com.manzilionellm.native_video_player.logic.VideoSurfaceSize
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class VideoSurfaceSizeTest {
    @Test
    fun interface1080pSurEcran4kConserveUnTampon4k() {
        assertEquals(
            VideoSurfaceBuffer(3840, 2160),
            size(viewWidth = 1920, viewHeight = 1080),
        )
    }

    @Test
    fun ecranEtInterfaceIdentiquesGardentLaTailleDeLaVue() {
        assertNull(size(1920, 1080, physicalWidth = 1920, physicalHeight = 1080))
    }

    @Test
    fun apercuEtPipGardentLeurPartDeLEcranSansAllouerUnPleinEcran() {
        assertEquals(VideoSurfaceBuffer(1280, 720), size(640, 360))
        assertEquals(VideoSurfaceBuffer(640, 360), size(320, 180))
    }

    @Test
    fun rotationAligneLeModePhysiqueSurLEcranLogique() {
        assertEquals(
            VideoSurfaceBuffer(2160, 3840),
            size(1080, 1920, logicalWidth = 1080, logicalHeight = 1920),
        )
        assertEquals(
            VideoSurfaceBuffer(3840, 2160),
            size(1920, 1080, physicalWidth = 2160, physicalHeight = 3840),
        )
    }

    @Test
    fun formatDeVueDifferentConserveSesProportionsEtLesBornesEcran() {
        val buffer = size(1600, 1080)!!
        assertEquals(VideoSurfaceBuffer(3200, 2160), buffer)
        assertTrue(abs(buffer.width.toDouble() / buffer.height - 1600.0 / 1080) < 0.001)
    }

    @Test
    fun geometrieInconnueOuNegativeNeDemandeAucuneAllocation() {
        assertNull(size(0, 1080))
        assertNull(size(1920, -1))
        assertNull(size(1920, 1080, logicalWidth = 0))
        assertNull(size(1920, 1080, physicalHeight = -1))
    }

    @Test
    fun dimensionsAberrantesNeDepassentJamaisLesBornes() {
        val buffer = size(1920, 1080, physicalWidth = Int.MAX_VALUE, physicalHeight = Int.MAX_VALUE)!!
        assertTrue(buffer.width in 1..VideoSurfaceSize.MAX_SIDE)
        assertTrue(buffer.height in 1..VideoSurfaceSize.MAX_SIDE)
        assertTrue(buffer.width.toLong() * buffer.height <= VideoSurfaceSize.MAX_PIXELS)
        assertNull(size(Int.MAX_VALUE, Int.MAX_VALUE))
    }

    @Test
    fun repliHdrOuDrmRetablitLaTailleDeLayoutDuCheminDirect() {
        assertEquals("hdr", PictureTune.directReason(isHdr = true, hasDrm = false))
        assertEquals("drm", PictureTune.directReason(isHdr = true, hasDrm = true))
        assertEquals("drm", PictureTune.directReason(isHdr = false, hasDrm = true))
        assertNull(PictureTune.directReason(isHdr = false, hasDrm = false))
        for (reason in listOf("hdr", "drm", "processing_error", "ffmpeg")) {
            assertNull(
                VideoSurfaceSize.forContrast(false, 1920, 1080, 1920, 1080, 3840, 2160),
                "Le chemin direct ($reason) doit appeler setSizeFromLayout",
            )
        }
    }

    private fun size(
        viewWidth: Int,
        viewHeight: Int,
        logicalWidth: Int = 1920,
        logicalHeight: Int = 1080,
        physicalWidth: Int = 3840,
        physicalHeight: Int = 2160,
    ) = VideoSurfaceSize.forContrast(
        true, viewWidth, viewHeight, logicalWidth, logicalHeight, physicalWidth, physicalHeight,
    )
}
