import com.manzilionellm.native_video_player.logic.AacRoute
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Reproduit le défaut terrain : le son « vieille radio » (décodeur de la
 * box) qui revient sur des chaînes déjà vues après beaucoup de zapping.
 * Les adresses sont des placeholders de test (aucun vrai flux).
 */
class AacRouteTest {

    private val channels = List(12) { i -> "test://chaine-$i/stream" }

    @BeforeTest
    fun fresh() {
        AacRoute.sessionWide = false
        AacRoute.forgetAll()
    }

    @AfterTest
    fun clean() {
        AacRoute.sessionWide = false
        AacRoute.forgetAll()
    }

    /** 50 zaps, une seule panne FFmpeg sur la chaîne 7. La chaîne 1 garde FFmpeg. */
    @Test
    fun cinquanteZapsUnePanneSeuleLaChaineEnPanneVaSurLaBox() {
        var zap = 0
        var boxOpenings = 0
        repeat(50) { n ->
            val url = channels[n % channels.size]
            zap++
            val f = AacRoute.decideForOpen(url, keepFfmpeg = false)
            if (f != null) boxOpenings++
            // Au 20e zap, FFmpeg tombe en panne sur la chaîne 7 (= n % 12 == 7 → n = 19).
            if (n == 19) {
                assertEquals(channels[7], url)
                AacRoute.markFailed(url, AacRoute.Reason.TIMEOUT, zap)
            }
        }
        // Retour sur la première chaîne : FFmpeg, comme au début.
        assertNull(AacRoute.decideForOpen(channels[0], keepFfmpeg = false), "chaîne 0 doit rester FFmpeg")
        // La chaîne en panne reste sur la box, sans attendre 8 s.
        val seven = AacRoute.decideForOpen(channels[7], keepFfmpeg = false)
        assertNotNull(seven)
        assertEquals(AacRoute.Reason.TIMEOUT, seven.reason)
        assertEquals(20, seven.zap)
        // Après la panne, seuls les retours sur la chaîne 7 ont ouvert en mode box :
        // zaps n° 32 et 44 (n = 31, 43).
        println("AACROUTE 50 zaps : ouvertures box = $boxOpenings, chaînes mémorisées = ${AacRoute.count()}")
        assertEquals(2, boxOpenings)
        assertEquals(1, AacRoute.count())
    }

    /** L'ancien comportement (interrupteur de repli) : une panne, et TOUT va sur la box. */
    @Test
    fun modeSessionEntiereReproduitLeDefautDAvant() {
        AacRoute.sessionWide = true
        repeat(19) { n -> assertNull(AacRoute.decideForOpen(channels[n % 12], keepFfmpeg = false)) }
        AacRoute.markFailed(channels[7], AacRoute.Reason.RENDERER_ERROR, 20)
        // La chaîne 0, qui sonnait bien, passe à la box : c'est le bug observé.
        val zero = AacRoute.decideForOpen(channels[0], keepFfmpeg = false)
        assertNotNull(zero, "ancien mode : la chaîne 0 est envoyée à la box")
        assertEquals(AacRoute.Reason.RENDERER_ERROR, zero.reason)
        // « FFmpeg : réessayer » efface tout en mode session.
        assertNull(AacRoute.decideForOpen(channels[0], keepFfmpeg = true))
        assertNull(AacRoute.decideForOpen(channels[7], keepFfmpeg = false))
    }

    /** « FFmpeg : réessayer » n'oublie que la chaîne qu'on rouvre. */
    @Test
    fun reessayerNOublieQueCetteChaine() {
        AacRoute.markFailed(channels[3], AacRoute.Reason.SINK_ERROR, 5)
        AacRoute.markFailed(channels[4], AacRoute.Reason.CODEC_ERROR, 6)
        assertNull(AacRoute.decideForOpen(channels[3], keepFfmpeg = true))
        assertNull(AacRoute.decideForOpen(channels[3], keepFfmpeg = false))
        assertNotNull(AacRoute.decideForOpen(channels[4], keepFfmpeg = false))
        assertEquals(1, AacRoute.count())
    }

    /** La mémoire est bornée : la plus ancienne panne part en premier. */
    @Test
    fun memoireBornee() {
        for (i in 0 until AacRoute.MAX_REMEMBERED + 5) {
            AacRoute.markFailed("test://many-$i", AacRoute.Reason.TIMEOUT, i + 1)
        }
        assertEquals(AacRoute.MAX_REMEMBERED, AacRoute.count())
        assertNull(AacRoute.boxFor("test://many-0"))
        assertNull(AacRoute.boxFor("test://many-4"))
        assertNotNull(AacRoute.boxFor("test://many-5"))
        assertNotNull(AacRoute.boxFor("test://many-${AacRoute.MAX_REMEMBERED + 4}"))
    }

    /** Aucune adresse n'est gardée : la clé est un hachage. */
    @Test
    fun laCleNestPasLAdresse() {
        val url = "test://user:motdepasse@serveur/flux"
        val f = AacRoute.markFailed(url, AacRoute.Reason.TIMEOUT, 1)
        assertEquals(url.hashCode(), f.key)
        assertTrue(f.toString().contains("key=") && !f.toString().contains("motdepasse"))
    }
}
