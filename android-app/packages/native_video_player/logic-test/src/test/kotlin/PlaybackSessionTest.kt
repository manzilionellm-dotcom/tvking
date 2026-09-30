import com.manzilionellm.native_video_player.logic.ExclusiveAudio
import com.manzilionellm.native_video_player.logic.PlaybackSession
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PlaybackSessionTest {
    @Test
    fun unNouveauJetonInvalideLAncien() {
        val session = PlaybackSession()
        val first = session.open()
        val second = session.open()
        assertFalse(session.isCurrent(first))
        assertTrue(session.isCurrent(second))
        assertFalse(session.isCurrent(0))
    }

    @Test
    fun prendreLeSonCoupeLesAutres() {
        val audio = ExclusiveAudio()
        val silenced = mutableListOf<Int>()
        val a = audio.register { silenced.add(1) }
        val b = audio.register { silenced.add(2) }
        audio.register { silenced.add(3) }
        audio.claim(b)
        assertEquals(b, audio.owner)
        assertEquals(listOf(1, 3), silenced)
        silenced.clear()
        audio.claim(a)
        assertEquals(listOf(2, 3), silenced)
    }

    @Test
    fun vingtZapsUnSeulProprietaire() {
        val audio = ExclusiveAudio()
        val audible = booleanArrayOf(false, false)
        val left = audio.register { audible[0] = false }
        val right = audio.register { audible[1] = false }
        val started = System.nanoTime()
        var last = left
        repeat(20) { i ->
            last = if (i % 2 == 0) left else right
            audible[0] = last == left
            audible[1] = last == right
            audio.claim(last)
        }
        val micros = (System.nanoTime() - started) / 1000
        println("MESURE zap_20_microsecondes=$micros")
        assertTrue(micros < 50_000)
        assertEquals(right, audio.owner)
        assertEquals(1, audible.count { it })
        assertFalse(audible[0])
        assertTrue(audible[1])
    }
}
