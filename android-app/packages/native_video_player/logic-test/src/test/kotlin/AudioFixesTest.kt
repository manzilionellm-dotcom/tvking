import com.manzilionellm.native_video_player.logic.AudioFixes
import com.manzilionellm.native_video_player.logic.PlaybackCount
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
        assertEquals("zuno.audio.fix.mode_normal", AudioFixes.KEY_MODE_NORMAL)
        assertEquals("zuno.audio.attr.content", AudioFixes.KEY_CONTENT_TYPE)
        assertFalse(AudioFixes.forceNormalMode)
        assertEquals(AudioFixes.CONTENT_FILM, AudioFixes.contentType)
        // Type déclaré : « film » par défaut (v106), la voix claire impose « parole ».
        assertEquals(PlaybackCount.CONTENT_MOVIE, AudioFixes.contentTypeFor(false, AudioFixes.CONTENT_FILM))
        assertEquals(PlaybackCount.CONTENT_MOVIE, AudioFixes.contentTypeFor(false, "n'importe quoi"))
        assertEquals(PlaybackCount.CONTENT_MUSIC, AudioFixes.contentTypeFor(false, AudioFixes.CONTENT_MUSIQUE))
        assertEquals(PlaybackCount.CONTENT_SPEECH, AudioFixes.contentTypeFor(false, AudioFixes.CONTENT_PAROLE))
        assertEquals(PlaybackCount.CONTENT_SPEECH, AudioFixes.contentTypeFor(true, AudioFixes.CONTENT_MUSIQUE))
        assertEquals(AudioFixes.CONTENT_MUSIQUE, AudioFixes.nextContentType(AudioFixes.CONTENT_FILM))
        assertEquals(AudioFixes.CONTENT_PAROLE, AudioFixes.nextContentType(AudioFixes.CONTENT_MUSIQUE))
        assertEquals(AudioFixes.CONTENT_FILM, AudioFixes.nextContentType(AudioFixes.CONTENT_PAROLE))
        assertFalse(AudioFixes.androidFocus)
        assertFalse(AudioFixes.immediateHandoff)
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
