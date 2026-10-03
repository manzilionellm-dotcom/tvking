import com.manzilionellm.native_video_player.logic.AppForeground
import com.manzilionellm.native_video_player.logic.BackgroundGate
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Home coupe dès onPause. Un overlay ou un dialogue qui laisse l'app
 * visible ne coupe pas. Rien ne rouvre tant qu'on est dehors.
 */
class BackgroundGateTest {

    @AfterTest
    fun cleanHub() {
        AppForeground.debugReset()
    }

    private fun gate(): BackgroundGate = BackgroundGate()

    @Test
    fun overlayNeCoupePas() {
        val g = gate()
        val lost = g.on(BackgroundGate.Signal.FOCUS_LOST)
        assertFalse(lost.stop)
        assertFalse(lost.resume)
        assertTrue(g.allowsReopen())
        val back = g.on(BackgroundGate.Signal.FOCUS_GAINED)
        assertFalse(back.stop)
        assertNull(g.noteRefuse())
    }

    @Test
    fun dialogueBrefNeCoupePas() {
        val g = gate()
        // Pas de Home : onPause seul (dialogue), puis onResume.
        val pause = g.on(BackgroundGate.Signal.PAUSE)
        assertFalse(pause.stop)
        assertTrue(g.allowsReopen())
        val resume = g.on(BackgroundGate.Signal.RESUME)
        assertFalse(resume.resume)
        assertFalse(g.inBackground)
    }

    @Test
    fun onStopCoupeSiPlusVisible() {
        val g = gate()
        g.on(BackgroundGate.Signal.PAUSE)
        val stop = g.on(BackgroundGate.Signal.STOP)
        assertTrue(stop.stop)
        assertEquals(BackgroundGate.STOP_LINE, stop.line)
        assertTrue(g.inBackground)
        assertFalse(g.allowsReopen())
        // Un second onStop ne recoupe pas.
        val again = g.on(BackgroundGate.Signal.STOP)
        assertFalse(again.stop)
        assertNull(again.line)
    }

    @Test
    fun homeCoupeDesOnPause() {
        val g = gate()
        g.on(BackgroundGate.Signal.USER_LEAVE)
        val pause = g.on(BackgroundGate.Signal.PAUSE)
        assertTrue(pause.stop)
        assertEquals(BackgroundGate.STOP_LINE, pause.line)
        assertFalse(g.allowsReopen())
        // onStop suit : pas un deuxième arrêt.
        assertFalse(g.on(BackgroundGate.Signal.STOP).stop)
        val refused = g.noteRefuse()
        assertEquals(BackgroundGate.REFUSE_LINE, refused)
        assertNull(g.noteRefuse())
    }

    @Test
    fun retourRouvreUneFois() {
        val g = gate()
        g.on(BackgroundGate.Signal.USER_LEAVE)
        g.on(BackgroundGate.Signal.PAUSE)
        g.noteRefuse()
        val back = g.on(BackgroundGate.Signal.RESUME)
        assertTrue(back.resume)
        assertFalse(g.inBackground)
        assertTrue(g.allowsReopen())
        assertNull(g.noteRefuse())
        // Déjà au premier plan : onResume ne relance pas une seconde fois.
        assertFalse(g.on(BackgroundGate.Signal.RESUME).resume)
        // Un nouveau Home coupe encore.
        g.on(BackgroundGate.Signal.USER_LEAVE)
        assertTrue(g.on(BackgroundGate.Signal.PAUSE).stop)
        assertEquals(BackgroundGate.REFUSE_LINE, g.noteRefuse())
    }

    @Test
    fun repliLaisseDeciderFlutter() {
        val g = gate()
        g.flutterOnly = true
        g.on(BackgroundGate.Signal.USER_LEAVE)
        assertFalse(g.on(BackgroundGate.Signal.PAUSE).stop)
        assertFalse(g.on(BackgroundGate.Signal.STOP).stop)
        assertTrue(g.allowsReopen())
        assertNull(g.noteRefuse())
        assertFalse(g.on(BackgroundGate.Signal.RESUME).resume)
    }

    @Test
    fun hubUneSeuleCoupeEtUneSeuleReprise() {
        AppForeground.debugReset()
        var stops = 0
        var resumes = 0
        val flags = ArrayList<Boolean>()
        val id = AppForeground.watch(
            onBackground = { flags.add(it) },
            stop = { stops += 1 },
            resume = { resumes += 1 },
        )
        AppForeground.onWindowFocus(false)
        AppForeground.onPause()
        assertEquals(0, stops)
        AppForeground.onUserLeaveHint()
        AppForeground.onPause()
        AppForeground.onStop()
        assertEquals(1, stops)
        assertEquals(listOf(true), flags)
        assertFalse(AppForeground.allowsReopen())
        assertEquals(BackgroundGate.REFUSE_LINE, AppForeground.noteRefuse())
        assertNull(AppForeground.noteRefuse())
        AppForeground.onResume()
        assertEquals(1, resumes)
        assertEquals(listOf(true, false), flags)
        assertTrue(AppForeground.allowsReopen())
        AppForeground.unwatch(id)
        AppForeground.onUserLeaveHint()
        AppForeground.onPause()
        assertEquals(1, stops)
        AppForeground.debugReset()
    }

    @Test
    fun hubRepliNeCoupePas() {
        AppForeground.debugReset()
        AppForeground.flutterOnly = true
        var stops = 0
        val id = AppForeground.watch(
            onBackground = {},
            stop = { stops += 1 },
            resume = {},
        )
        AppForeground.onUserLeaveHint()
        AppForeground.onPause()
        AppForeground.onStop()
        assertEquals(0, stops)
        assertTrue(AppForeground.allowsReopen())
        AppForeground.unwatch(id)
        AppForeground.debugReset()
    }
}
