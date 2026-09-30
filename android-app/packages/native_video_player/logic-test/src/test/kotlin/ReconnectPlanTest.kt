import com.manzilionellm.native_video_player.logic.ReconnectGate
import com.manzilionellm.native_video_player.logic.ReconnectPlan
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ReconnectPlanTest {
    @Test
    fun attenteCroissantePuisPlafond() {
        assertEquals(0L, ReconnectPlan.delayMs(0))
        assertEquals(1_000L, ReconnectPlan.delayMs(1))
        assertEquals(2_000L, ReconnectPlan.delayMs(2))
        assertEquals(4_000L, ReconnectPlan.delayMs(3))
        assertEquals(8_000L, ReconnectPlan.delayMs(4))
        assertEquals(8_000L, ReconnectPlan.delayMs(8))
        assertEquals(8_000L, ReconnectPlan.delayMs(20))
    }

    @Test
    fun pasDeSecondEssaiPendantLAttente() {
        val gate = ReconnectGate()
        assertEquals(1_000L, gate.onFailure())
        assertTrue(gate.retryPending)
        assertTrue(gate.holdMute)
        assertNull(gate.onFailure(), "un second prepare ferait deux sons")
        assertEquals(1, gate.attempt)
        assertTrue(gate.onRetryFired())
        assertFalse(gate.onRetryFired())
        assertEquals(2_000L, gate.onFailure())
    }

    @Test
    fun budgetEpuiseOnPrevientLEcran() {
        val gate = ReconnectGate()
        repeat(ReconnectPlan.MAX_SILENT) { i ->
            assertEquals(ReconnectPlan.delayMs(i + 1), gate.onFailure())
            assertTrue(gate.onRetryFired())
        }
        assertNull(gate.onFailure())
        assertEquals(ReconnectPlan.MAX_SILENT, gate.attempt)
    }

    @Test
    fun zapRemetLeBudgetUneMemeAdresseLeGarde() {
        val gate = ReconnectGate()
        assertEquals(1_000L, gate.onFailure())
        assertTrue(gate.onRetryFired())
        gate.onExternalReopen()
        assertEquals(1, gate.attempt)
        assertEquals(2_000L, gate.onFailure())
        gate.onDifferentUrl()
        assertEquals(0, gate.attempt)
        assertFalse(gate.retryPending)
        assertEquals(1_000L, gate.onFailure())
    }

    @Test
    fun volumeResteAZeroJusquaLaNouvelleSession() {
        val gate = ReconnectGate()
        gate.onFailure()
        assertTrue(gate.holdMute)
        assertTrue(gate.onNewSoundAllowed())
        assertFalse(gate.holdMute)
        assertFalse(gate.onNewSoundAllowed(), "un second feu ne remonte pas le volume deux fois")
        gate.onExternalReopen()
        assertTrue(gate.holdMute)
        assertTrue(gate.onNewSoundAllowed())
    }

    @Test
    fun imageDejaVueMemeAdressePasDePanneauNoir() {
        assertTrue(ReconnectPlan.coverWithLoader(hadFrame = false, sameUrl = true))
        assertFalse(ReconnectPlan.coverWithLoader(hadFrame = true, sameUrl = true))
        assertTrue(ReconnectPlan.coverWithLoader(hadFrame = true, sameUrl = false))
    }

    @Test
    fun budgetApplicatifSousDeuxSecondes() {
        assertEquals(1_000, ReconnectPlan.BUFFER_FOR_PLAYBACK_MS)
        assertEquals(180, ReconnectPlan.ZAP_SETTLE_MS)
        val budget = ReconnectPlan.appSideBudgetMs()
        println("MESURE budget_app_ms=$budget tampon_ms=${ReconnectPlan.BUFFER_FOR_PLAYBACK_MS} zap_ms=${ReconnectPlan.ZAP_SETTLE_MS}")
        assertTrue(budget < ReconnectPlan.STARTUP_TARGET_MS)
        val started = System.nanoTime()
        var last = 0L
        repeat(20) { i ->
            last = ReconnectPlan.delayMs(i + 1)
            ReconnectPlan.coverWithLoader(hadFrame = true, sameUrl = i % 2 == 0)
        }
        val micros = (System.nanoTime() - started) / 1000
        println("MESURE decision_reconnexion_20_microsecondes=$micros dernier_delai_ms=$last")
        assertTrue(micros < 50_000)
        assertEquals(8_000L, last)
    }

    @Test
    fun annulerLAttenteNeRemetPasLeCompteurAZero() {
        val gate = ReconnectGate()
        assertEquals(1_000L, gate.onFailure())
        gate.cancelWait()
        assertFalse(gate.retryPending)
        assertEquals(1, gate.attempt)
        assertEquals(2_000L, gate.onFailure())
    }

    @Test
    fun repriseApresImageOublieLesPannes() {
        val gate = ReconnectGate()
        gate.onFailure()
        gate.onRetryFired()
        gate.onRecovered()
        assertEquals(0, gate.attempt)
        assertFalse(gate.retryPending)
        assertEquals(1_000L, gate.onFailure())
    }
}
