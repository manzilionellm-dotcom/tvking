import com.manzilionellm.native_video_player.logic.AudioContentChoice
import com.manzilionellm.native_video_player.logic.AudioFixes
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AudioFixesTest {
    @Test
    fun defautsCoupes() {
        assertFalse(AudioFixes.probe)
        assertFalse(AudioFixes.keepFfmpeg)
        assertFalse(AudioFixes.preferPlatformAac)
        assertEquals("zuno.audio.diag.probe", AudioFixes.KEY_PROBE)
        assertEquals("zuno.audio.fix.ffmpeg", AudioFixes.KEY_FFMPEG)
        assertEquals("zuno.audio.fix.platform", AudioFixes.KEY_PLATFORM)
        assertEquals("zuno.audio.fix.session_fallback", AudioFixes.KEY_SESSION_WIDE)
        assertEquals("zuno.audio.focus.android", AudioFixes.KEY_ANDROID_FOCUS)
        assertEquals("zuno.audio.handoff.immediate", AudioFixes.KEY_IMMEDIATE_HANDOFF)
        assertFalse(AudioFixes.androidFocus)
        assertFalse(AudioFixes.immediateHandoff)
        assertEquals(AudioContentChoice.OFF, AudioFixes.contentChoice)
        assertEquals("zuno.audio.diag.content_type", AudioFixes.KEY_CONTENT_TYPE)
    }

    @Test
    fun aacResteSurFfmpegTantQueLeReglageEstCoupe() {
        assertTrue(
            AudioFixes.ffmpegForAac(
                preferPlatform = false,
                gaveUpToFfmpeg = false,
                forceBox = false,
                ffmpegReady = true,
                ffmpegSupports = true,
            ),
        )
    }

    @Test
    fun lessaiBoxCacheFfmpegEtLeRepliYRevient() {
        assertFalse(
            AudioFixes.ffmpegForAac(
                preferPlatform = true,
                gaveUpToFfmpeg = false,
                forceBox = false,
                ffmpegReady = true,
                ffmpegSupports = true,
            ),
        )
        assertTrue(
            AudioFixes.ffmpegForAac(
                preferPlatform = true,
                gaveUpToFfmpeg = true,
                forceBox = true,
                ffmpegReady = true,
                ffmpegSupports = true,
            ),
        )
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
