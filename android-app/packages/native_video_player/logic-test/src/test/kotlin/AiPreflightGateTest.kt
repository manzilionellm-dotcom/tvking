import com.manzilionellm.native_video_player.logic.AiPreflightGate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class AiPreflightGateTest {
    @Test
    fun aucunePreparationAvantLaPremiereImageEtUneSeuleNotificationParMoteur() {
        var starts = 0
        val gate = AiPreflightGate { starts++ }
        assertFalse(gate.canRun)
        val ui = gate.attachUi()
        assertFalse(gate.canRun)
        assertEquals(0, starts)
        ui.firstFrameDisplayed()
        assertTrue(gate.canRun)
        ui.firstFrameDisplayed()
        assertEquals(1, starts)
    }

    @Test
    fun premiereImagePendantUneVideoAttendLeDernierBailPuisReprend() {
        var starts = 0
        val gate = AiPreflightGate { starts++ }
        val ui = gate.attachUi()
        val preview = gate.acquirePlayback(Any())
        val fullscreen = gate.acquirePlayback(Any())
        ui.firstFrameDisplayed()
        assertEquals(0, starts)
        preview.close()
        assertFalse(gate.canRun)
        assertEquals(0, starts)
        fullscreen.close()
        assertTrue(gate.canRun)
        assertEquals(1, starts)
        fullscreen.close()
        assertEquals(1, starts)
        // Un futur arrêt vidéo conserve l'opportunisme historique du préflight.
        gate.acquirePlayback(Any()).close()
        assertEquals(2, starts)
    }

    @Test
    fun callbackDePremiereImagePosteAvantDetachEstIgnore() {
        var starts = 0
        val gate = AiPreflightGate { starts++ }
        val old = gate.attachUi()
        val posted = { old.firstFrameDisplayed() }
        old.close()
        val current = gate.attachUi()
        posted()
        assertEquals(0, starts)
        assertFalse(gate.canRun)
        current.firstFrameDisplayed()
        assertEquals(1, starts)
        old.close()
        assertTrue(gate.canRun)
        current.close()
        assertFalse(gate.canRun)
    }

    @Test
    fun deuxMoteursAttendentLeursPropresImagesSansSeLibererMutuellement() {
        var starts = 0
        val gate = AiPreflightGate { starts++ }
        val first = gate.attachUi()
        val second = gate.attachUi()
        first.firstFrameDisplayed()
        assertEquals(0, starts)
        assertFalse(gate.canRun)
        second.firstFrameDisplayed()
        assertEquals(1, starts)
        first.close()
        assertTrue(gate.canRun)
        assertEquals(1, starts)
        second.close()
        assertFalse(gate.canRun)
    }

    @Test
    fun moteurSansUiSuspendLeTravailJusquaSonDetachement() {
        var starts = 0
        val gate = AiPreflightGate { starts++ }
        val displayed = gate.attachUi()
        displayed.firstFrameDisplayed()
        val previousEpoch = gate.uiGeneration
        val headless = gate.attachUi()
        assertFalse(gate.canRun)
        assertNotEquals(previousEpoch, gate.uiGeneration)
        headless.close()
        assertTrue(gate.canRun)
        assertEquals(2, starts)
        headless.firstFrameDisplayed()
        assertEquals(2, starts)
    }

    @Test
    fun detachNeRelanceRienSiUnAutreLecteurResteActif() {
        var starts = 0
        val gate = AiPreflightGate { starts++ }
        val displayed = gate.attachUi()
        displayed.firstFrameDisplayed()
        val pending = gate.attachUi()
        val playback = gate.acquirePlayback(Any())
        pending.close()
        assertEquals(1, starts)
        assertFalse(gate.canRun)
        playback.close()
        assertEquals(2, starts)
    }

    @Test
    fun lectureOuDemarrageEntierEntreDeuxCheckpointsResteDetectable() {
        val gate = AiPreflightGate {}
        gate.attachUi().firstFrameDisplayed()
        val playbackEpoch = gate.playbackGeneration
        gate.acquirePlayback(Any()).close()
        assertFalse(gate.hasPlayback)
        assertNotEquals(playbackEpoch, gate.playbackGeneration)
        val uiEpoch = gate.uiGeneration
        gate.attachUi().close()
        assertTrue(gate.canRun)
        assertNotEquals(uiEpoch, gate.uiGeneration)
    }
}
