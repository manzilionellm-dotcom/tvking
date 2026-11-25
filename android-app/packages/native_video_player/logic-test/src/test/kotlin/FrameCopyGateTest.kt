import com.manzilionellm.native_video_player.logic.FrameCopyGate
import com.manzilionellm.native_video_player.logic.FrameCopyGate.Completion
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FrameCopyGateTest {
    @Test
    fun callbackAApresPremiereImageB_rejetteAEtLibereUneCopieFraicheB() {
        val copies = FrameCopyGate()
        val a = assertNotNull(copies.begin(1, "source-a"))
        // A écrit encore : B ne lance pas une deuxième allocation.
        assertNull(copies.begin(2, "source-b"))
        assertTrue(copies.inFlight)
        assertEquals(Completion.REFRESH_CURRENT, copies.finish(a, 2, "source-b", true))
        assertFalse(copies.inFlight)
        // Le callback libère effectivement B, qui peut être mis en pause.
        val b = assertNotNull(copies.begin(2, "source-b"))
        assertEquals(Completion.KEEP, copies.finish(b, 2, "source-b", true))
        assertFalse(copies.inFlight)
    }

    @Test
    fun ancienCallbackNeLiberePasLaCopieBDejaEnCours() {
        val copies = FrameCopyGate()
        val a = assertNotNull(copies.begin(1, "source-a"))
        copies.finish(a, 2, "source-b", true)
        val b = assertNotNull(copies.begin(2, "source-b"))
        assertEquals(Completion.DISCARD, copies.finish(a, 2, "source-b", true))
        assertTrue(copies.inFlight)
        assertNull(copies.begin(3, "source-c"))
        assertEquals(Completion.KEEP, copies.finish(b, 2, "source-b", true))
    }

    @Test
    fun reouvertureDeLaMemeAdresseInvalideLaCopieDeLaSessionPrecedente() {
        val copies = FrameCopyGate()
        val beforeReopen = assertNotNull(copies.begin(1, "source-a"))
        assertEquals(
            Completion.REFRESH_CURRENT,
            copies.finish(beforeReopen, 2, "source-a", true),
        )
    }

    @Test
    fun nouvelleAdresseInvalideLaCopieMemeAvantLeChangementDeSession() {
        val copies = FrameCopyGate()
        val beforeZap = assertNotNull(copies.begin(1, "source-a"))
        assertEquals(
            Completion.REFRESH_CURRENT,
            copies.finish(beforeZap, 1, "source-b", true),
        )
    }

    @Test
    fun destructionOuSurfaceSansImage_rejetteSansRelancerDeCopie() {
        val copies = FrameCopyGate()
        val a = assertNotNull(copies.begin(1, "source-a"))
        assertEquals(Completion.DISCARD, copies.finish(a, 2, "source-b", false))
        assertFalse(copies.inFlight)
    }

    @Test
    fun exceptionAvantCallback_libereLeCreneauSansBoucleDeRelance() {
        val copies = FrameCopyGate()
        val failed = assertNotNull(copies.begin(1, "source-a"))
        assertEquals(Completion.DISCARD, copies.finish(failed, 1, "source-a", false))
        val next = assertNotNull(copies.begin(1, "source-a"))
        assertEquals(Completion.KEEP, copies.finish(next, 1, "source-a", true))
    }

    @Test
    fun aucunTicketAvantUneSourceEtUneSessionValides() {
        val copies = FrameCopyGate()
        assertNull(copies.begin(0, "source-a"))
        assertNull(copies.begin(1, null))
        assertNull(copies.begin(1, ""))
        assertFalse(copies.inFlight)
    }
}
