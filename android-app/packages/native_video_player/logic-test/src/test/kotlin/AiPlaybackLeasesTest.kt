import com.manzilionellm.native_video_player.logic.AiPlaybackLeases
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AiPlaybackLeasesTest {
    @Test
    fun fermerUnApercuNeRelancePasLeBenchmarkPendantLePleinEcran() {
        var idle = 0
        val leases = AiPlaybackLeases { idle++ }
        val preview = leases.acquire(Any())
        val fullscreen = leases.acquire(Any())
        assertTrue(leases.hasActive)
        preview.close()
        assertTrue(leases.hasActive)
        assertEquals(0, idle)
        preview.close() // cleanup idempotent
        assertTrue(leases.hasActive)
        fullscreen.close()
        assertFalse(leases.hasActive)
        assertEquals(1, idle)
    }

    @Test
    fun unAllerRetourLectureEntreDeuxCheckpointsInvalideLaGeneration() {
        val leases = AiPlaybackLeases()
        val captured = leases.generation
        leases.acquire(Any()).close()
        assertFalse(leases.hasActive)
        assertTrue(leases.generation != captured)
    }

    @Test
    fun deuxBauxDuMemeProprietaireRestentIndependants() {
        val leases = AiPlaybackLeases()
        val owner = Any()
        val a = leases.acquire(owner)
        val b = leases.acquire(owner)
        a.close()
        assertTrue(leases.hasActive)
        b.close()
        assertFalse(leases.hasActive)
    }
}
