import com.manzilionellm.native_video_player.logic.GlSurfaceGate
import com.manzilionellm.native_video_player.logic.HdrToneMap
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GlSurfaceGateTest {
    @Test
    fun effetsSeulementSurUneSurfaceReelle() {
        assertFalse(GlSurfaceGate.effectsReady(surfaceValid = false, width = 1920, height = 1080))
        assertFalse(GlSurfaceGate.effectsReady(surfaceValid = true, width = 0, height = 1080))
        assertFalse(GlSurfaceGate.effectsReady(surfaceValid = true, width = 1920, height = 0))
        assertTrue(GlSurfaceGate.effectsReady(surfaceValid = true, width = 1920, height = 1080))
    }

    @Test
    fun uneSortieGlVideNeComptePasCommeUneImage() {
        assertFalse(GlSurfaceGate.countsAsVisibleFrame(true, "video/raw", 0, 0))
        assertFalse(GlSurfaceGate.countsAsVisibleFrame(true, "video/raw", -1, 720))
        assertTrue(GlSurfaceGate.outputUnusable(true, "video/raw", 0, 1080))
        assertTrue(GlSurfaceGate.countsAsVisibleFrame(true, "video/raw", 256, 144))
        // Le chemin direct (AVC) n'est pas un graphe GL : on compte la trame.
        assertTrue(GlSurfaceGate.countsAsVisibleFrame(false, "video/avc", 0, 0))
        assertFalse(GlSurfaceGate.outputUnusable(false, "video/raw", 0, 0))
        assertFalse(GlSurfaceGate.outputUnusable(true, "video/avc", 0, 0))
    }

    @Test
    fun onAbandonneUneSortieResteeAZero() {
        assertFalse(GlSurfaceGate.abandonZeroOutput(0, sawPositiveFrame = false))
        assertFalse(GlSurfaceGate.abandonZeroOutput(GlSurfaceGate.ZERO_OUTPUT_MS - 1, sawPositiveFrame = false))
        assertTrue(GlSurfaceGate.abandonZeroOutput(GlSurfaceGate.ZERO_OUTPUT_MS, sawPositiveFrame = false))
        // Une image déjà vue : un trou court (changement de qualité) ne coupe pas.
        assertFalse(GlSurfaceGate.abandonZeroOutput(GlSurfaceGate.ZERO_OUTPUT_MS, sawPositiveFrame = true))
        assertTrue(GlSurfaceGate.abandonZeroOutput(8_000L, sawPositiveFrame = true))
    }

    @Test
    fun retoucherLeTamponApresLeGrapheNoircitLImage() {
        assertFalse(GlSurfaceGate.resizeWouldBlank(graphBound = false))
        assertTrue(GlSurfaceGate.resizeWouldBlank(graphBound = true))
    }

    @Test
    fun hdrVersSdrSeulementSiLEcranNeSaitPas() {
        assertFalse(HdrToneMap.requestSdr(displaySupportsHdr = true, sdkInt = 35, transferIsHdr = true))
        assertFalse(HdrToneMap.requestSdr(displaySupportsHdr = false, sdkInt = 29, transferIsHdr = true))
        assertFalse(HdrToneMap.requestSdr(displaySupportsHdr = false, sdkInt = 35, transferIsHdr = false))
        assertTrue(HdrToneMap.requestSdr(displaySupportsHdr = false, sdkInt = 31, transferIsHdr = true))
        assertTrue(HdrToneMap.requestSdr(displaySupportsHdr = false, sdkInt = 35, transferIsHdr = true))
    }
}
