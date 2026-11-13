import com.manzilionellm.native_video_player.logic.VideoCandidate
import com.manzilionellm.native_video_player.logic.VideoTrackChoice
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class VideoTrackChoiceTest {
    private fun v(
        index: Int,
        height: Int,
        bitrate: Int,
        selected: Boolean = false,
        adaptive: Boolean = false,
        group: Int = 0,
    ) = VideoCandidate(
        group = group,
        index = index,
        width = height * 16 / 9,
        height = height,
        bitrate = bitrate,
        frameRate = 25f,
        mime = "video/avc",
        selected = selected,
        adaptive = adaptive,
    )

    @Test
    fun uneSeulePisteOnNeTouchePas() {
        assertNull(
            VideoTrackChoice.pick(listOf(v(0, 1080, 4_000_000)), bandwidthBps = 0, screenHeightPx = 1080),
        )
    }

    @Test
    fun leHlsAdaptatifResteAuLecteur() {
        val ladder = listOf(
            v(0, 720, 2_000_000, adaptive = true),
            v(1, 1080, 5_000_000, adaptive = true, selected = true),
        )
        assertNull(VideoTrackChoice.pick(ladder, bandwidthBps = 8_000_000, screenHeightPx = 1080))
    }

    @Test
    fun lesGroupesFixesNeRemplacentPasLeHlsAdaptatifSelectionne() {
        val tracks = listOf(
            v(0, 720, 2_000_000, adaptive = true, selected = true),
            v(1, 1080, 5_000_000, adaptive = true, selected = true),
            v(0, 1080, 8_000_000, group = 1),
            v(0, 2160, 15_000_000, group = 2),
        )
        assertNull(VideoTrackChoice.pick(tracks, bandwidthBps = 25_000_000, screenHeightPx = 2160))
    }

    @Test
    fun plusieursPistesDansUnGroupeNonAdaptatifRestentEligibles() {
        val tracks = listOf(
            v(0, 720, 2_000_000, selected = true),
            v(1, 1080, 5_000_000),
        )
        assertEquals(1, VideoTrackChoice.pick(tracks, 0, 1080)?.index)
    }

    @Test
    fun tv4kAvecInterface1080pConserveLaPiste4k() {
        val height = VideoTrackChoice.landscapeDisplayHeight(3840, 2160, fallbackHeightPx = 1080)
        val pick = VideoTrackChoice.pick(
            listOf(
                v(0, 1080, 5_000_000, group = 0, selected = true),
                v(0, 2160, 15_000_000, group = 1),
            ),
            bandwidthBps = 25_000_000,
            screenHeightPx = height,
        )
        assertEquals(2160, height)
        assertEquals(2160, pick?.height)
    }

    @Test
    fun ecranPortraitEtResolutionInconnueOntUnRepliCoherent() {
        assertEquals(1080, VideoTrackChoice.landscapeDisplayHeight(1080, 2400, 2400))
        assertEquals(720, VideoTrackChoice.landscapeDisplayHeight(0, 0, 720))
        assertEquals(720, VideoTrackChoice.landscapeDisplayHeight(3840, 0, 720))
        assertEquals(0, VideoTrackChoice.landscapeDisplayHeight(0, 0, -1))
    }

    @Test
    fun plusHauteQuiTientSurLecran() {
        val pick = VideoTrackChoice.pick(
            listOf(
                v(0, 720, 2_000_000, group = 0),
                v(0, 1080, 5_000_000, group = 1),
                v(0, 2160, 15_000_000, group = 2),
            ),
            bandwidthBps = 0,
            screenHeightPx = 1080,
        )
        assertEquals(1080, pick?.height)
        assertEquals(1, pick?.group)
    }

    @Test
    fun une4kSeuleEstQuandMemeJouee() {
        val only = v(0, 2160, 15_000_000)
        assertNull(VideoTrackChoice.pick(listOf(only), bandwidthBps = 1_000_000, screenHeightPx = 1080))
    }

    @Test
    fun debitConnuEcarteLaPisteTropLourde() {
        val pick = VideoTrackChoice.pick(
            listOf(
                v(0, 720, 2_000_000, group = 0),
                v(0, 1080, 8_000_000, group = 1),
            ),
            bandwidthBps = 5_000_000,
            screenHeightPx = 1080,
        )
        // 70 % de 5 Mbit = 3,5 Mbit : le 1080p à 8 Mbit ne passe pas.
        assertEquals(720, pick?.height)
    }

    @Test
    fun siRienNeTientOnPrendLaPlusLegere() {
        val pick = VideoTrackChoice.pick(
            listOf(
                v(0, 720, 4_000_000, group = 0),
                v(0, 1080, 8_000_000, group = 1),
            ),
            bandwidthBps = 1_000_000,
            screenHeightPx = 1080,
        )
        assertEquals(720, pick?.height)
    }

    @Test
    fun pisteDejaChoisieOnNeBasculePas() {
        val pick = VideoTrackChoice.pick(
            listOf(
                v(0, 720, 2_000_000, group = 0),
                v(0, 1080, 5_000_000, group = 1, selected = true),
            ),
            bandwidthBps = 0,
            screenHeightPx = 1080,
        )
        assertNull(pick)
    }

    @Test
    fun debitParDefautNestPasUnVraiDebit() {
        assertEquals(0L, VideoTrackChoice.bandwidthForChoice(1_000_000, bytesLoaded = 0))
        assertEquals(0L, VideoTrackChoice.bandwidthForChoice(1_000_000, bytesLoaded = 1000))
        assertEquals(
            4_000_000L,
            VideoTrackChoice.bandwidthForChoice(4_000_000, bytesLoaded = 200_000),
        )
    }
}
