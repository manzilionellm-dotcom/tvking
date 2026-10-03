import com.manzilionellm.native_video_player.logic.AacRoute
import com.manzilionellm.native_video_player.logic.ExclusiveAudio
import com.manzilionellm.native_video_player.logic.PlayerCensus
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * ÉTAT QUI SURVIT AU ZAP ET AU HOME (03/10/2026).
 *
 * On ne joue rien. On rejoue, en mémoire, ce que les objets du
 * processus gardent quand personne ne les remet à zéro, et la
 * politique lue dans les écrans : qui est coupé au Home, qui ne
 * l'est pas. La table est la même que `AudioSources.codeStopsOnHome`
 * côté Dart. Elle ne coupe aucun lecteur : elle dit ce que le code
 * fait déjà.
 */
class GlobalAudioStateTest {

    /** Vrai = l'écran coupe le son au Home (réglage par défaut). */
    private val stopsOnHome = mapOf(
        "plein_ecran" to true,
        "apercu" to false,
        "film" to true,
        "enregistrement_tv" to true,
        "sonde" to false,
        "temoin" to false,
        "telephone" to false,
        "pub" to false,
        "enregistrement_tel" to false,
        "service_fond" to false,
        "service_enregistrement" to false,
        "voix" to false,
    )

    @BeforeTest
    fun setUp() {
        PlayerCensus.reset()
        AacRoute.forgetAll()
        AacRoute.sessionWide = false
    }

    @AfterTest
    fun tearDown() {
        PlayerCensus.reset()
        AacRoute.forgetAll()
        AacRoute.sessionWide = false
    }

    @Test
    fun aacRouteSurvitAuHomeEtAuZap() {
        AacRoute.markFailed("chaine-a", AacRoute.Reason.TIMEOUT, 4)
        // Home et les zaps suivants n'appellent pas forget.
        repeat(50) { n ->
            assertNull(AacRoute.boxFor("chaine-$n"))
        }
        val kept = AacRoute.boxFor("chaine-a")
        assertNotNull(kept)
        assertEquals(AacRoute.Reason.TIMEOUT, kept.reason)
        assertEquals(4, kept.zap)
        assertEquals(1, AacRoute.count())
    }

    @Test
    fun registreDartOublieSurvitSiOnNeDesinscritPas() {
        val book = ExclusiveAudio()
        val first = book.register { }
        val second = book.register { }
        book.claim(second)
        // Le plein écran part au Home sans unregister : les deux restent.
        assertEquals(2, book.registeredCount)
        assertEquals(second, book.owner)
        book.unregister(second)
        assertEquals(1, book.registeredCount)
        assertNull(book.owner)
        assertEquals(1, book.registeredCount)
        book.unregister(first)
        assertEquals(0, book.registeredCount)
    }

    @Test
    fun censusEtPisteSurviventSiLeLecteurNEstPasRelache() {
        PlayerCensus.playerCreated()
        PlayerCensus.audioDecoderOpened()
        PlayerCensus.audioTrackOpened()
        PlayerCensus.onZap(1)
        // Home sans playerReleased / audioTrackClosed.
        val s = PlayerCensus.snapshot(1, null, nativeOwners = 1)
        assertEquals(1, s.playersAlive)
        assertEquals(1, s.audioDecodersAlive)
        assertEquals(1, s.audioTracksAlive)
        assertEquals(1, s.nativeOwners)
        assertFalse(PlayerCensus.overlapping(s))
        val line = PlayerCensus.describe(s)
        assertTrue(line.contains("registre natif 1"), line)
        assertFalse(line.contains("plusieurs lecteurs inscrits"), line)
    }

    @Test
    fun deuxInscritsNatifsSontNommes() {
        val s = PlayerCensus.snapshot(0, null, nativeOwners = 2)
        val line = PlayerCensus.describe(s)
        assertTrue(line.contains("registre natif 2 ⚠ plusieurs lecteurs inscrits"), line)
        // Le champ n'est pas demandé : la ligne d'avant ne change pas.
        val old = PlayerCensus.describe(PlayerCensus.snapshot(0, null))
        assertFalse(old.contains("registre natif"), old)
    }

    @Test
    fun homeSelonLaPolitiqueLueDansLesEcrans() {
        val alive = linkedMapOf(
            "apercu" to true,
            "plein_ecran" to true,
            "telephone" to true,
            "temoin" to true,
            "service_fond" to true,
        )
        // Ce que le code fait au Home : il ne coupe que ceux de la table.
        val still = alive.filter { (id, on) -> on && stopsOnHome[id] == false }.keys
        assertEquals(setOf("apercu", "telephone", "temoin", "service_fond"), still)
        assertFalse(still.contains("plein_ecran"))
    }

    @Test
    fun cinquanteZapsUneSeuleSourcePuisHomeApercu() {
        val ledger = SourceSim()
        val screen = ledger.open("plein_ecran")
        ledger.sound(screen)
        repeat(50) { ledger.zap() }
        assertEquals(1, ledger.sounding().size)
        assertEquals(listOf("plein_ecran"), ledger.sounding())
        // Retour grille : le plein écran est coupé par sa politique,
        // l'aperçu ne l'est pas.
        ledger.silence(screen)
        val preview = ledger.open("apercu")
        ledger.sound(preview)
        val home = ledger.home(stopsOnHome)
        assertEquals(listOf("apercu"), home)
        assertEquals(1, ledger.sounding().size)
        println("SOURCES home=$home zap=${ledger.zapCount} sons=${ledger.sounding()}")
    }

    @Test
    fun apercuEtPleinEcranEnsembleCestDeuxSons() {
        val ledger = SourceSim()
        ledger.sound(ledger.open("apercu"))
        ledger.sound(ledger.open("plein_ecran"))
        assertEquals(listOf("apercu", "plein_ecran"), ledger.sounding())
        // Le claim du plein écran fait taire l'aperçu : un seul son.
        ledger.silenceOthers("plein_ecran")
        assertEquals(listOf("plein_ecran"), ledger.sounding())
    }

    @Test
    fun pubPuisTelephoneDeuxSonsJusquALaLiberation() {
        val ledger = SourceSim()
        val ad = ledger.open("pub")
        ledger.sound(ad)
        ledger.sound(ledger.open("telephone"))
        assertEquals(2, ledger.sounding().size)
        ledger.close(ad)
        assertEquals(listOf("telephone"), ledger.sounding())
        // Home : la table ne coupe pas le téléphone.
        assertEquals(listOf("telephone"), ledger.home(stopsOnHome))
    }

    /**
     * Mini registre, même idée que le compteur Dart. Il vit dans le
     * test : l'application n'en a pas un deuxième.
     */
    private class SourceSim {
        private var seq = 0
        private val rows = linkedMapOf<Int, Pair<String, Boolean>>()
        var zapCount = 0
            private set

        fun open(id: String): Int {
            seq += 1
            rows[seq] = id to false
            return seq
        }

        fun close(token: Int) {
            rows.remove(token)
        }

        fun sound(token: Int) {
            val row = rows[token] ?: return
            rows[token] = row.first to true
        }

        fun silence(token: Int) {
            val row = rows[token] ?: return
            rows[token] = row.first to false
        }

        fun silenceOthers(keepId: String) {
            for ((token, row) in rows) {
                if (row.first != keepId) rows[token] = row.first to false
            }
        }

        fun zap() {
            zapCount += 1
        }

        fun sounding(): List<String> =
            rows.values.filter { it.second }.map { it.first }.distinct()

        /** Applique la table : ceux qu'elle coupe passent à silence. */
        fun home(stops: Map<String, Boolean>): List<String> {
            for ((token, row) in rows.toList()) {
                if (stops[row.first] == true) rows[token] = row.first to false
            }
            return sounding()
        }
    }
}
