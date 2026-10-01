import com.manzilionellm.native_video_player.logic.DisplayModeOption
import com.manzilionellm.native_video_player.logic.FrameRateMatch
import com.manzilionellm.native_video_player.logic.PictureTune
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FrameRateMatchTest {
    private val modes = listOf(
        DisplayModeOption(1, 24f),
        DisplayModeOption(2, 50f),
        DisplayModeOption(3, 60f),
    )

    @Test
    fun coupeOnNeChangeRien() {
        assertNull(FrameRateMatch.pick(false, 25f, modes, currentModeId = 0))
    }

    @Test
    fun film24() {
        val pick = FrameRateMatch.pick(true, 23.976f, modes, currentModeId = 0)
        assertEquals(1, pick?.id)
        assertEquals(24f, pick?.refreshHz)
    }

    @Test
    fun tele25VaVers50() {
        val pick = FrameRateMatch.pick(true, 25f, modes, currentModeId = 0)
        assertEquals(2, pick?.id)
    }

    @Test
    fun tele30VaVers60() {
        val pick = FrameRateMatch.pick(true, 29.97f, modes, currentModeId = 0)
        assertEquals(3, pick?.id)
    }

    @Test
    fun dejaLeBonMode() {
        assertNull(FrameRateMatch.pick(true, 50f, modes, currentModeId = 2))
        assertNull(FrameRateMatch.pick(true, 60f, modes, currentModeId = 3))
    }

    @Test
    fun pasDeModeAssezProche() {
        val only60 = listOf(DisplayModeOption(3, 60f))
        assertNull(FrameRateMatch.pick(true, 24f, only60, currentModeId = 0))
    }

    @Test
    fun cadenceInconnue() {
        assertEquals(emptyList(), FrameRateMatch.preferredHz(0f))
        assertEquals(emptyList(), FrameRateMatch.preferredHz(15f))
    }

    @Test
    fun contrasteSeulementSiLeMaterielLePermet() {
        assertFalse(PictureTune.resolve(requested = true, hardwareAllows = false))
        assertFalse(PictureTune.resolve(requested = false, hardwareAllows = true))
        assertTrue(PictureTune.resolve(requested = true, hardwareAllows = true))
        assertEquals(0.08f, PictureTune.LIGHT_CONTRAST)
    }
}
