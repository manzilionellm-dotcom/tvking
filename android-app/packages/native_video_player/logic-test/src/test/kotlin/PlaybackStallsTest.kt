import com.manzilionellm.native_video_player.logic.PlaybackStallTracker
import com.manzilionellm.native_video_player.logic.ResumeCushion
import com.manzilionellm.native_video_player.logic.StallText
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PlaybackStallsTest {

    /** Un lecteur qui a déjà joué (première image vue), octets reçus toutes les 100 ms jusqu'à [until]. */
    private fun playing(until: Long = 5_000L): PlaybackStallTracker {
        val t = PlaybackStallTracker()
        t.onOpen(0L)
        t.onReady(1_000L, 0)
        var ms = 1_000L
        while (ms <= until) {
            t.onBytes(ms, 4_000)
            ms += 100L
        }
        return t
    }

    @Test
    fun serveurMuet_laPauseEstMesureeEtAttribueeAuServeur() {
        val t = playing(until = 5_000L)
        t.onBuffering(5_200L, 400L, 0)
        t.onBytes(8_100L, 3_000) // le serveur se réveille 2,9 s plus tard
        val s = assertNotNull(t.onReady(8_300L, 0))
        assertEquals(1, s.number)
        assertEquals(3_100L, s.durationMs)
        assertEquals(400L, s.bufferedAtStartMs)
        assertEquals(200L, s.silentBeforeMs)
        assertEquals(2_900L, s.longestSilenceMs)
        assertEquals(3_000L, s.bytesDuring)
        assertTrue(StallText.verdict(s).contains("Le serveur n'envoyait rien"))
    }

    @Test
    fun donneesQuiArrivent_pasUnSilenceDuServeur() {
        val t = playing(until = 5_000L)
        t.onBuffering(5_200L, 300L, 0)
        var ms = 5_300L
        while (ms <= 8_200L) {
            t.onBytes(ms, 3_000) // 30 Ko/s … soit 240 kbit/s
            ms += 100L
        }
        val s = assertNotNull(t.onReady(8_200L, 0))
        assertTrue(s.longestSilenceMs < 500L)
        val verdict = StallText.verdict(s)
        assertTrue(verdict.contains("Des données arrivaient pendant toute la pause"), verdict)
        assertTrue(verdict.contains("kbit/s"), verdict)
    }

    @Test
    fun imagesPerdues_l_appareilNeSuitPas() {
        val t = playing(until = 5_000L)
        t.onBuffering(5_200L, 300L, 5)
        var ms = 5_300L
        while (ms <= 8_200L) {
            t.onBytes(ms, 3_000)
            ms += 100L
        }
        val s = assertNotNull(t.onReady(8_200L, 17))
        assertEquals(12, s.droppedFrames)
        assertTrue(StallText.verdict(s).contains("12 images ont été perdues"))
    }

    @Test
    fun avantLaPremiereImage_lAttenteEstNormale() {
        val t = PlaybackStallTracker()
        t.onOpen(0L)
        t.onBuffering(500L, 0L, 0)
        assertNull(t.onReady(4_000L, 0), "ouverture : pas une pause")
        // La suivante, elle, compte.
        t.onBuffering(10_000L, 200L, 0)
        assertNotNull(t.onReady(12_000L, 0))
    }

    @Test
    fun apresUnSaut_leTamponNEstPasUnePause() {
        val t = playing()
        t.onSeek(10_000L)
        t.onBuffering(10_500L, 0L, 0)
        assertNull(t.onReady(13_000L, 0))
        // Après le délai de grâce, une vraie pause est comptée.
        t.onBuffering(14_000L, 100L, 0)
        assertNotNull(t.onReady(16_000L, 0))
    }

    @Test
    fun pauseTropCourte_neSeCompteNiNeSEcrit() {
        val t = playing()
        t.onBuffering(6_000L, 500L, 0)
        assertNull(t.onReady(6_500L, 0), "500 ms ne s'entend pas")
        t.onBuffering(9_000L, 500L, 0)
        val s = assertNotNull(t.onReady(11_000L, 0))
        assertEquals(1, s.number, "la pause trop courte n'a pas pris de numéro")
    }

    @Test
    fun deuxBuffering_d_affilee_gardentLeDebutDeLaPause() {
        val t = playing()
        t.onBuffering(6_000L, 500L, 0)
        t.onBuffering(6_500L, 300L, 0) // ignoré : la pause a déjà commencé
        val s = assertNotNull(t.onReady(9_000L, 0))
        assertEquals(3_000L, s.durationMs)
        assertEquals(500L, s.bufferedAtStartMs)
    }

    @Test
    fun bilan_plusieursPauses_pourcentageDuTemps() {
        val t = PlaybackStallTracker()
        t.onOpen(0L)
        t.onReady(0L, 0)
        t.onBuffering(10_000L, 0L, 0)
        assertNotNull(t.onReady(13_000L, 0))
        t.onBuffering(40_000L, 0L, 0)
        val s = assertNotNull(t.onReady(42_000L, 0))
        assertEquals(2, s.totalStalls)
        assertEquals(5_000L, s.totalStalledMs)
        val line = StallText.line(s, "Wi-Fi")
        assertTrue(line.contains("2 pauses, 5,0 s depuis l'ouverture (11 %)"), line)
    }

    @Test
    fun nouvelleChaine_remetLesCompteursAZero() {
        val t = playing()
        t.onBuffering(6_000L, 0L, 0)
        assertNotNull(t.onReady(9_000L, 0))
        t.onOpen(20_000L)
        t.onReady(21_000L, 0)
        t.onBuffering(30_000L, 0L, 0)
        val s = assertNotNull(t.onReady(32_000L, 0))
        assertEquals(1, s.number)
        assertEquals(1, s.totalStalls)
        assertEquals(12_000L, s.sinceOpenMs)
    }

    @Test
    fun texte_chiffresEnFrancais_sansAdresse() {
        val t = playing(until = 1_000L)
        t.onBuffering(4_000L, 1_200L, 0) // 3 s sans octet avant la pause
        t.onBytes(7_100L, 2_048)
        val s = assertNotNull(t.onReady(7_100L, 3))
        val line = StallText.line(s, "Wi-Fi (-58 dBm)")
        assertTrue(line.startsWith("Pause n°1 : 3,1 s."), line)
        assertTrue(line.contains("Réserve au début : 1,2 s."), line)
        assertTrue(line.contains("Rien reçu depuis 3,0 s quand elle a commencé."), line)
        assertTrue(line.contains("Reçu pendant la pause : 2 Ko."), line)
        assertTrue(line.contains("Réseau : Wi-Fi (-58 dBm)."), line)
        assertFalse(line.contains("http"), "jamais d'adresse dans le journal")
        assertEquals("0,0 s", StallText.seconds(0L))
        assertEquals("15,0 s", StallText.seconds(15_000L))
        assertEquals("0,5 s", StallText.seconds(500L))
    }

    @Test
    fun rienRecu_toutLeLongDeLaPause_lePlusLongSilenceEstLaPauseEntiere() {
        val t = playing(until = 2_000L)
        t.onBuffering(3_000L, 0L, -1)
        val s = assertNotNull(t.onReady(7_000L, -1))
        assertEquals(4_000L, s.longestSilenceMs)
        assertEquals(0L, s.bytesDuring)
        assertEquals(-1, s.droppedFrames, "compteur d'images inconnu")
        assertFalse(StallText.line(s, "câble").contains("Images perdues"))
    }

    // ---------------- Coussin anti-coupure ----------------

    private val us = 1_000L
    private val noOffset = Long.MIN_VALUE + 1 // C.TIME_UNSET

    @Test
    fun coussinCoupe_ouPasUneCoupure_onSuitMedia3() {
        // Coupé : la décision de Media3 passe telle quelle, dans les deux sens.
        assertTrue(ResumeCushion.shouldResume(true, true, 2_100 * us, noOffset, 0L, enabled = false))
        assertFalse(ResumeCushion.shouldResume(false, true, 100 * us, noOffset, 0L, enabled = false))
        // Allumé mais ce n'est pas une coupure (démarrage, saut) : rien ne change.
        assertTrue(ResumeCushion.shouldResume(true, false, 1_100 * us, noOffset, 0L, enabled = true))
    }

    @Test
    fun coussinAllume_exigeCinqSecondes_apresUneCoupure() {
        assertFalse(ResumeCushion.shouldResume(true, true, 2_100 * us, noOffset, 1_000L, enabled = true))
        assertFalse(ResumeCushion.shouldResume(true, true, 4_900 * us, noOffset, 3_000L, enabled = true))
        assertTrue(ResumeCushion.shouldResume(true, true, 5_000 * us, noOffset, 5_000L, enabled = true))
    }

    @Test
    fun coussin_neFaitJamaisRepartirPlusTotQueMedia3() {
        assertFalse(ResumeCushion.shouldResume(false, true, 9_000 * us, noOffset, 0L, enabled = true))
        assertFalse(ResumeCushion.shouldResume(false, true, 9_000 * us, noOffset, 99_000L, enabled = true))
    }

    @Test
    fun coussin_respecteLaFenetreDuDirect() {
        // Direct HLS avec 6 s de retard visé : 5 s de réserve sont hors de portée ;
        // on s'arrête à la moitié du retard (3 s), comme Media3.
        val offset = 6_000 * us
        assertFalse(ResumeCushion.shouldResume(true, true, 2_900 * us, offset, 0L, enabled = true))
        assertTrue(ResumeCushion.shouldResume(true, true, 3_000 * us, offset, 0L, enabled = true))
    }

    @Test
    fun coussin_neBloqueJamaisUneChaine_auBoutDe10Secondes() {
        // Une réserve qui n'arrive pas ne doit pas laisser la chaîne sur le logo.
        assertFalse(ResumeCushion.shouldResume(true, true, 2_100 * us, noOffset, 9_999L, enabled = true))
        assertTrue(ResumeCushion.shouldResume(true, true, 2_100 * us, noOffset, 10_000L, enabled = true))
    }

    @Test
    fun coussin_valeursParDefaut() {
        assertEquals(2_000L, ResumeCushion.DEFAULT_MS, "réglage d'origine inchangé")
        assertEquals(5_000L, ResumeCushion.CUSHION_MS)
        assertFalse(ResumeCushion.enabled, "coupé par défaut")
    }
}
