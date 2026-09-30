import com.manzilionellm.native_video_player.logic.AudioTrackBuffer
import com.manzilionellm.native_video_player.logic.ClearVoiceGain
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ClearVoiceGainTest {
    @Test
    fun sousLeSeuilOnNeChangeRien() {
        assertEquals(1f, ClearVoiceGain.target(0.2f))
        assertEquals(1f, ClearVoiceGain.target(ClearVoiceGain.THRESHOLD))
    }

    @Test
    fun unPicEstRameneSansEtreEteint() {
        val gain = ClearVoiceGain.target(1f)
        // 0,40 + 0,60/3 = 0,60 → gain 0,60.
        assertEquals(0.60f, gain, 0.001f)
        assertTrue(gain >= ClearVoiceGain.MIN_GAIN)
    }

    @Test
    fun leGainGlisseSansSauter() {
        val eased = ClearVoiceGain.smooth(1f, 0.6f)
        assertTrue(eased < 1f)
        assertTrue(eased > 0.6f)
    }

    @Test
    fun tamponAudioDoubleEtAligne() {
        assertEquals(2000, AudioTrackBuffer.sized(1000, 4))
        val big = 2 * 1024 * 1024
        val sized = AudioTrackBuffer.sized(big, 4)
        assertEquals(big + 256 * 1024, sized)
        assertEquals(0, sized % 4)
    }
}
