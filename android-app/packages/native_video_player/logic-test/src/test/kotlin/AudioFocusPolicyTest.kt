import com.manzilionellm.native_video_player.logic.AudioFocusPolicy
import com.manzilionellm.native_video_player.logic.AudioFocusPolicy.Action
import com.manzilionellm.native_video_player.logic.AudioHandoff
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
        assertEquals(1f, d.volume)
        assertTrue(d.volume != 0.2f)
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
        // Même si rien ne joue encore (zap en cours) : on retient la perte,
        // sinon la nouvelle chaîne repartirait pendant que l'autre app a le son.
        val idle = AudioFocusPolicy.decide(AudioFocusPolicy.LOSS, pausedByFocus = false, playing = false)
        assertEquals(Action.PAUSE, idle.action)
        assertTrue(idle.pausedByFocus)
        assertEquals(1f, idle.volume)
    }

    @Test
    fun unGainQuiNarriveJamaisNeLaissePasLeSonA20Pourcent() {
        val duck = AudioFocusPolicy.decide(
            AudioFocusPolicy.LOSS_TRANSIENT_CAN_DUCK,
            pausedByFocus = false,
            playing = true,
        )
        // Pas de GAIN ensuite. Le volume reste 1, on n'est pas en pause.
        assertEquals(Action.IGNORE, duck.action)
        assertEquals(1f, duck.volume)
        assertFalse(duck.pausedByFocus)
        assertTrue(duck.volume != AudioHandoff.VOLUME_DUCK_FORBIDDEN)
    }

    @Test
    fun demandeRefuseeOuRetardeeNeTientPasLeFocus() {
        val refused = AudioFocusPolicy.onRequest(alreadyHeld = false, systemCode = AudioFocusPolicy.REQUEST_FAILED)
        assertTrue(refused.asked)
        assertFalse(refused.held)
        assertTrue(refused.line!!.contains("REFUSÉE"))
        val delayed = AudioFocusPolicy.onRequest(alreadyHeld = false, systemCode = AudioFocusPolicy.REQUEST_DELAYED)
        assertFalse(delayed.held)
        assertTrue(delayed.line!!.contains("REFUSÉE"))
    }

    @Test
    fun uneSecondeDemandeNeRappellePasAndroid() {
        val first = AudioFocusPolicy.onRequest(alreadyHeld = false, systemCode = AudioFocusPolicy.REQUEST_GRANTED)
        assertTrue(first.asked)
        assertTrue(first.held)
        assertTrue(first.line!!.contains("obtenu"))
        val second = AudioFocusPolicy.onRequest(alreadyHeld = true, systemCode = AudioFocusPolicy.REQUEST_FAILED)
        assertFalse(second.asked)
        assertTrue(second.held)
        assertEquals(null, second.line)
    }

    @Test
    fun apiAncienneEtApi26OntLaMemeDecision() {
        // Les deux méthodes Android renvoient 1 (accordé) ou 0 (refusé).
        // La décision ne dépend pas de l'API.
        val modern = AudioFocusPolicy.onRequest(false, AudioFocusPolicy.REQUEST_GRANTED)
        val legacy = AudioFocusPolicy.onRequest(false, 1)
        assertEquals(modern.held, legacy.held)
        assertEquals(modern.asked, legacy.asked)
        assertEquals(1, AudioFocusPolicy.REQUEST_GRANTED)
        assertEquals(0, AudioFocusPolicy.REQUEST_FAILED)
    }

    @Test
    fun media3NeGereLeFocusQueSiLeRepliEstAllume() {
        assertFalse(AudioFocusPolicy.media3HandlesFocus(false))
        assertTrue(AudioFocusPolicy.media3HandlesFocus(true))
    }
}
