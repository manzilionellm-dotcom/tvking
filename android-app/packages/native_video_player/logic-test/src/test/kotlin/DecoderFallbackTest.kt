import com.manzilionellm.native_video_player.logic.CodecOrder
import com.manzilionellm.native_video_player.logic.DecoderFallback
import com.manzilionellm.native_video_player.logic.NamedCodec
import com.manzilionellm.native_video_player.logic.PictureHealth
import com.manzilionellm.native_video_player.logic.PictureSignal
import com.manzilionellm.native_video_player.logic.VideoEngine
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DecoderFallbackTest {
    @Test
    fun reseauNeChangePasDeMoteur() {
        val d = DecoderFallback.next(
            VideoEngine.HARDWARE,
            PictureSignal.NETWORK,
            ffmpegVideoReady = true,
            tried = emptySet(),
        )
        assertFalse(d.reopen)
        assertFalse(d.giveUp)
        assertEquals(VideoEngine.HARDWARE, d.engine)
    }

    @Test
    fun erreurDecodePasseAuLogiciel() {
        val d = DecoderFallback.next(
            VideoEngine.HARDWARE,
            PictureSignal.DECODE,
            ffmpegVideoReady = true,
            tried = emptySet(),
        )
        assertTrue(d.reopen)
        assertEquals(VideoEngine.SOFTWARE, d.engine)
    }

    @Test
    fun imageNoireMemeEchelle() {
        val d = DecoderFallback.next(
            VideoEngine.HARDWARE,
            PictureSignal.BLACK_OR_FROZEN,
            ffmpegVideoReady = false,
            tried = emptySet(),
        )
        assertEquals(VideoEngine.SOFTWARE, d.engine)
    }

    @Test
    fun logicielPuisFfmpegSeulementSilEstLa() {
        val avec = DecoderFallback.next(
            VideoEngine.SOFTWARE,
            PictureSignal.DECODE,
            ffmpegVideoReady = true,
            tried = setOf(VideoEngine.HARDWARE),
        )
        assertEquals(VideoEngine.FFMPEG, avec.engine)
        assertTrue(avec.reopen)

        val sans = DecoderFallback.next(
            VideoEngine.SOFTWARE,
            PictureSignal.DECODE,
            ffmpegVideoReady = false,
            tried = setOf(VideoEngine.HARDWARE),
        )
        assertFalse(sans.reopen)
        assertTrue(sans.giveUp)
    }

    @Test
    fun onNeRevientPasAuMaterielToutSeul() {
        val d = DecoderFallback.next(
            VideoEngine.SOFTWARE,
            PictureSignal.DECODE,
            ffmpegVideoReady = false,
            tried = emptySet(),
        )
        assertTrue(d.giveUp)
        assertEquals(VideoEngine.SOFTWARE, d.engine)
    }

    @Test
    fun unMoteurDejaEssayeEstSaute() {
        val d = DecoderFallback.next(
            VideoEngine.HARDWARE,
            PictureSignal.DECODE,
            ffmpegVideoReady = true,
            tried = setOf(VideoEngine.SOFTWARE),
        )
        assertEquals(VideoEngine.FFMPEG, d.engine)
    }

    @Test
    fun codesMedia3() {
        assertEquals(PictureSignal.DECODE, DecoderFallback.classify(4001, "MediaCodecVideoRenderer"))
        assertEquals(PictureSignal.DECODE, DecoderFallback.classify(4003, "MediaCodecVideoRenderer"))
        assertEquals(PictureSignal.AUDIO, DecoderFallback.classify(4003, "MediaCodecAudioRenderer"))
        assertEquals(PictureSignal.AUDIO, DecoderFallback.classify(5001, "MediaCodecAudioRenderer"))
        assertEquals(PictureSignal.NETWORK, DecoderFallback.classify(2001, null))
        assertEquals(PictureSignal.NETWORK, DecoderFallback.classify(1002, "MediaCodecVideoRenderer"))
        assertEquals(PictureSignal.OTHER, DecoderFallback.classify(3001, "MediaCodecVideoRenderer"))
        assertEquals(
            PictureSignal.AUDIO,
            DecoderFallback.classify(4001, "FfmpegAudioRenderer"),
        )
    }

    @Test
    fun imageNoireSeulementQuandLeDecodeurEstPret() {
        assertFalse(
            PictureHealth.black(
                decoderReady = true,
                framesRendered = 0,
                playbackReady = false,
                buffering = true,
                elapsedMs = 20_000,
            ),
        )
        assertFalse(
            PictureHealth.black(
                decoderReady = true,
                framesRendered = 0,
                playbackReady = true,
                buffering = false,
                elapsedMs = 3_000,
            ),
        )
        assertTrue(
            PictureHealth.black(
                decoderReady = true,
                framesRendered = 0,
                playbackReady = true,
                buffering = false,
                elapsedMs = 8_000,
            ),
        )
    }

    @Test
    fun imageFigeeSeulementEnLecture() {
        assertFalse(
            PictureHealth.frozen(
                framesRendered = 10,
                playing = false,
                buffering = false,
                msSinceLastFrame = 20_000,
            ),
        )
        assertTrue(
            PictureHealth.frozen(
                framesRendered = 10,
                playing = true,
                buffering = false,
                msSinceLastFrame = 8_000,
            ),
        )
    }

    @Test
    fun ordreDesCodecs() {
        val box = NamedCodec("OMX.amlogic.avc.decoder.awesome")
        val soft = NamedCodec("OMX.google.h264.decoder")
        val c2 = NamedCodec("c2.android.avc.decoder")
        val listed = listOf(box, soft, c2)
        assertEquals(listed, CodecOrder.order(listed, preferSoftware = false))
        assertEquals(listOf(soft, c2, box), CodecOrder.order(listed, preferSoftware = true))
        assertEquals(listOf(box), CodecOrder.order(listOf(box), preferSoftware = true))
        assertEquals(emptyList(), CodecOrder.order(emptyList(), preferSoftware = true))
        assertTrue(CodecOrder.isSoftware("c2.android.hevc.decoder"))
        assertFalse(CodecOrder.isSoftware("c2.amlogic.hevc.decoder"))
    }

    @Test
    fun nomInconnuResteMateriel() {
        assertEquals(VideoEngine.HARDWARE, VideoEngine.fromWire(null))
        assertEquals(VideoEngine.HARDWARE, VideoEngine.fromWire("vlc"))
        assertEquals(VideoEngine.SOFTWARE, VideoEngine.fromWire("software"))
        assertEquals("ffmpeg", VideoEngine.FFMPEG.wire)
    }
}
