import com.manzilionellm.native_video_player.logic.AacRoute
import com.manzilionellm.native_video_player.logic.PlayerCensus
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Compteurs de vie : lecteurs, décodeurs audio, AudioTrack. Le test
 * rejoue l'ordre des événements Media3 d'un zap (release de l'ancien
 * décodeur et de l'ancien AudioTrack, puis création des nouveaux) et
 * ÉCHOUE s'il reste plus d'un vivant.
 */
class PlayerCensusTest {

    @BeforeTest
    fun fresh() {
        PlayerCensus.reset()
        AacRoute.forgetAll()
        AacRoute.sessionWide = false
    }

    @AfterTest
    fun clean() {
        PlayerCensus.reset()
        AacRoute.forgetAll()
    }

    private val formats = listOf(
        "test://aac-lc-48k-stereo",
        "test://mp2-44k1-stereo",
        "test://aac-5-1",
        "test://he-aac-24k",
    )

    @Test
    fun cinquanteZapsEntreFormatsLaissentUnSeulDeChaque() {
        PlayerCensus.playerCreated()
        var first: PlayerCensus.Snapshot? = null
        repeat(50) { n ->
            val url = formats[n % formats.size]
            PlayerCensus.onZap(AacRoute.key(url))
            // Ordre Media3 à un zap : stop() rend décodeur + AudioTrack de
            // l'ancienne chaîne, puis prepare() en crée de nouveaux.
            if (n > 0) {
                PlayerCensus.audioDecoderClosed()
                PlayerCensus.audioTrackClosed()
            }
            PlayerCensus.audioDecoderOpened()
            PlayerCensus.audioTrackOpened()
            if (n == 0) first = PlayerCensus.snapshot(AacRoute.key(url), null)
        }
        // Retour sur la première chaîne.
        val url0 = formats[0]
        PlayerCensus.onZap(AacRoute.key(url0))
        PlayerCensus.audioDecoderClosed()
        PlayerCensus.audioTrackClosed()
        PlayerCensus.audioDecoderOpened()
        PlayerCensus.audioTrackOpened()
        val back = PlayerCensus.snapshot(AacRoute.key(url0), null)
        println("CENSUS " + PlayerCensus.describe(back))
        assertEquals(51, back.zap)
        assertEquals(1, back.playersAlive)
        assertEquals(1, back.audioDecodersAlive)
        assertEquals(1, back.audioTracksAlive)
        assertFalse(PlayerCensus.overlapping(back), "plus d'un actif après 50 zaps")
        // Vue 13 fois avant celle-ci (n = 0, 4, 8, …, 48).
        assertEquals(13, back.seenBefore)
        assertEquals(0, first!!.seenBefore)
        assertTrue(PlayerCensus.describe(first!!).contains("ouverte pour la 1re fois"))
        assertTrue(PlayerCensus.describe(back).contains("déjà ouverte avant (14e fois)"))
    }

    @Test
    fun unDecodeurNonRenduEstSignale() {
        PlayerCensus.playerCreated()
        PlayerCensus.onZap(1)
        PlayerCensus.audioDecoderOpened()
        PlayerCensus.audioTrackOpened()
        PlayerCensus.onZap(2)
        // L'ancien décodeur n'est PAS rendu (fuite simulée).
        PlayerCensus.audioDecoderOpened()
        PlayerCensus.audioTrackClosed()
        PlayerCensus.audioTrackOpened()
        val s = PlayerCensus.snapshot(2, null)
        assertEquals(2, s.audioDecodersAlive)
        assertTrue(PlayerCensus.overlapping(s))
        assertTrue(PlayerCensus.describe(s).contains("plus d'un actif"))
    }

    @Test
    fun deuxLecteursVivantsSontSignales() {
        PlayerCensus.playerCreated()
        PlayerCensus.playerCreated()
        val s = PlayerCensus.snapshot(0, null)
        assertEquals(2, s.playersAlive)
        assertTrue(PlayerCensus.overlapping(s))
        PlayerCensus.playerReleased()
        assertFalse(PlayerCensus.overlapping(PlayerCensus.snapshot(0, null)))
    }

    @Test
    fun laLigneDitLeRepliEtSaCause() {
        PlayerCensus.playerCreated()
        PlayerCensus.onZap(AacRoute.key("test://x"))
        val f = AacRoute.markFailed("test://x", AacRoute.Reason.TIMEOUT, 7)
        val line = PlayerCensus.describe(PlayerCensus.snapshot(AacRoute.key("test://x"), f))
        println("CENSUS " + line)
        assertTrue(line.contains("repli box : ACTIF pour cette chaîne (délai de 8 s, au zap n°7)"), line)
        assertTrue(line.contains("1 chaîne(s) sur la box dans ce processus"), line)
        val none = PlayerCensus.describe(PlayerCensus.snapshot(AacRoute.key("test://y"), null))
        assertTrue(none.contains("repli box : aucun pour cette chaîne"), none)
    }

    @Test
    fun lesCompteursNeDescendentPasSousZero() {
        PlayerCensus.audioDecoderClosed()
        PlayerCensus.audioTrackClosed()
        PlayerCensus.playerReleased()
        val s = PlayerCensus.snapshot(0, null)
        assertEquals(0, s.audioDecodersAlive)
        assertEquals(0, s.audioTracksAlive)
        assertEquals(0, s.playersAlive)
    }
}
