import com.manzilionellm.native_video_player.logic.HeldFrame
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Écran noir après une coupure : la copie de la dernière image ne doit
 * être ni noire, ni collée après la reprise.
 */
class HeldFrameTest {
    @Test
    fun uneCopieToutNoireEstRejetee() {
        val black = IntArray(64) { 0 }
        assertTrue(HeldFrame.looksBlank(black, legacy = false))
        // Un gris très sombre (bandes noires + logo faible) reste noir.
        val dark = IntArray(64) { HeldFrame.BLANK_MAX_LUMA }
        assertTrue(HeldFrame.looksBlank(dark, legacy = false))
    }

    @Test
    fun uneCopieAvecUnSeulPixelVisibleEstGardee() {
        val lumas = IntArray(64) { 0 }
        lumas[37] = 40
        assertFalse(HeldFrame.looksBlank(lumas, legacy = false))
    }

    @Test
    fun uneCopieSansEchantillonEstRejetee() {
        assertTrue(HeldFrame.looksBlank(IntArray(0), legacy = false))
    }

    @Test
    fun leRepliGardeLaCopieMemeNoire() {
        assertFalse(HeldFrame.looksBlank(IntArray(64) { 0 }, legacy = true))
    }

    @Test
    fun laCopieEstRetireeDesQuUneTrameEstRendueApresSonAffichage() {
        assertFalse(HeldFrame.shouldHide(holdVisible = true, framesSinceShown = 0, legacy = false))
        assertTrue(HeldFrame.shouldHide(holdVisible = true, framesSinceShown = 1, legacy = false))
        assertFalse(HeldFrame.shouldHide(holdVisible = false, framesSinceShown = 5, legacy = false))
        // Repli : on attend le signal de première image, comme avant.
        assertFalse(HeldFrame.shouldHide(holdVisible = true, framesSinceShown = 9, legacy = true))
    }

    @Test
    fun laLuminanceSuitLesCoefficientsClassiques() {
        assertEquals(0, HeldFrame.luma(0xFF000000.toInt()))
        assertEquals(255, HeldFrame.luma(0xFFFFFFFF.toInt()))
        assertEquals(76, HeldFrame.luma(0xFFFF0000.toInt()))
    }
}
