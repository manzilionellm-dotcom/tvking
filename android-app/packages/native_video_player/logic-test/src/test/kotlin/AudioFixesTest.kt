import com.manzilionellm.native_video_player.logic.AudioFixes
import com.manzilionellm.native_video_player.logic.AudioRouteState
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
        assertEquals("zuno.audio.mode.normal", AudioFixes.KEY_NORMALIZE_MODE)
        assertEquals("zuno.audio.chain.stock", AudioFixes.KEY_STOCK)
        assertEquals("zuno.audio.ref.content_unknown", AudioFixes.KEY_REFERENCE_UNKNOWN)
        assertFalse(AudioFixes.androidFocus)
        assertFalse(AudioFixes.immediateHandoff)
        assertFalse(AudioFixes.normalizeMode)
        assertFalse(AudioFixes.pureMedia3Chain)
        assertFalse(AudioFixes.referenceUnknownContent)
    }

    @Test
    fun leTypeAnnonceResteFilmSaufEssai() {
        // Défaut : film. L'essai coupé ne change rien.
        assertEquals(
            AudioRouteState.CONTENT_MOVIE,
            AudioFixes.announcedContentType(clearVoice = false, referenceUnknown = false),
        )
        // Essai allumé : inconnu, le défaut de Media3.
        assertEquals(
            AudioRouteState.CONTENT_UNKNOWN,
            AudioFixes.announcedContentType(clearVoice = false, referenceUnknown = true),
        )
        // Voix claire gagne sur l'essai : on reste en parole.
        assertEquals(
            AudioRouteState.CONTENT_SPEECH,
            AudioFixes.announcedContentType(clearVoice = true, referenceUnknown = true),
        )
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
