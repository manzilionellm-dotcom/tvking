import com.manzilionellm.native_video_player.logic.AudioFixes
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class AudioFixesTest {
    @Test
    fun defautsCoupes() {
        assertFalse(AudioFixes.probe)
        assertFalse(AudioFixes.keepFfmpeg)
        assertEquals("zuno.audio.diag.probe", AudioFixes.KEY_PROBE)
        assertEquals("zuno.audio.fix.ffmpeg", AudioFixes.KEY_FFMPEG)
    }

    @Test
    fun leRepliBoxNeBougePasTantQueLeReglageEstCoupe() {
        assertEquals(true, AudioFixes.forceBoxAfterOpen(keepFfmpeg = false, forceBox = true))
        assertEquals(false, AudioFixes.forceBoxAfterOpen(keepFfmpeg = false, forceBox = false))
    }

    @Test
    fun leReglageRallumeFfmpegSansEtreLeDefaut() {
        assertEquals(false, AudioFixes.forceBoxAfterOpen(keepFfmpeg = true, forceBox = true))
    }
}
