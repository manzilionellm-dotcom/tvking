import com.manzilionellm.native_video_player.logic.AudioFocusPolicy
import com.manzilionellm.native_video_player.logic.AudioFocusPolicy.Action
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Le son « dans un trou » : la baisse à 20 % n'est plus jamais appliquée. */
class AudioFocusPolicyTest {

    @Test
    fun laBaisseDeVolumeEstIgnoreeEtLeSonResteEntier() {
        val d = AudioFocusPolicy.decide(AudioFocusPolicy.LOSS_TRANSIENT_CAN_DUCK, pausedByFocus = false, playing = true)
        assertEquals(Action.IGNORE, d.action)
        assertFalse(d.pausedByFocus)
        assertTrue(d.line.contains("IGNORÉE"), d.line)
    }

    @Test
    fun pertePassagerePuisRetourReprendLaLecture() {
        val lost = AudioFocusPolicy.decide(AudioFocusPolicy.LOSS_TRANSIENT, pausedByFocus = false, playing = true)
        assertEquals(Action.PAUSE, lost.action)
        assertTrue(lost.pausedByFocus)
        val back = AudioFocusPolicy.decide(AudioFocusPolicy.GAIN, pausedByFocus = lost.pausedByFocus, playing = false)
        assertEquals(Action.RESUME, back.action)
        assertFalse(back.pausedByFocus)
    }

    @Test
    fun unGainSansPauseDeNotreFaitNeRelancePas() {
        // Lecture mise en pause PAR LA PERSONNE : un GAIN ne doit pas la relancer.
        val d = AudioFocusPolicy.decide(AudioFocusPolicy.GAIN, pausedByFocus = false, playing = false)
        assertEquals(Action.NONE, d.action)
    }

    @Test
    fun perteDefinitiveMetEnPauseSansReprise() {
        val d = AudioFocusPolicy.decide(AudioFocusPolicy.LOSS, pausedByFocus = false, playing = true)
        assertEquals(Action.PAUSE, d.action)
        assertTrue(d.pausedByFocus)
        val idle = AudioFocusPolicy.decide(AudioFocusPolicy.LOSS, pausedByFocus = false, playing = false)
        assertEquals(Action.NONE, idle.action)
    }
}
