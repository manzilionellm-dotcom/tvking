import com.manzilionellm.native_video_player.logic.VideoSurfaceBinding
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class VideoSurfaceBindingTest {
    @Test
    fun surfaceAbsenteOuVueVideNeBranchePas() {
        val binding = VideoSurfaceBinding()
        assertFalse(binding.onSurfaceReady(valid = false, width = 1920, height = 1080))
        assertFalse(binding.onSurfaceReady(valid = true, width = 0, height = 1080))
        assertFalse(binding.onSurfaceReady(valid = true, width = 1, height = 1))
        assertFalse(binding.onSurfaceReady(valid = true, width = 1920, height = -1))
        assertFalse(binding.bound)
    }

    @Test
    fun premiereTailleReelleBrancheUneSeuleFois() {
        val binding = VideoSurfaceBinding()
        assertTrue(binding.onSurfaceReady(true, 1920, 1080))
        assertTrue(binding.bound)
        assertFalse(
            binding.onSurfaceReady(true, 1920, 1080),
            "la même taille ne doit pas réattacher (setFixedSize casserait le graphe)",
        )
    }

    @Test
    fun unPixelPuisLaVraieTailleBrancheUneFois() {
        val binding = VideoSurfaceBinding()
        assertFalse(binding.onSurfaceReady(true, 1, 1))
        assertTrue(binding.onSurfaceReady(true, 1280, 720))
        assertFalse(binding.onSurfaceReady(true, 1280, 720))
    }

    @Test
    fun destructionOuNouveauLecteurReattache() {
        val binding = VideoSurfaceBinding()
        assertTrue(binding.onSurfaceReady(true, 1920, 1080))
        binding.onSurfaceDestroyed()
        assertFalse(binding.bound)
        assertTrue(binding.onSurfaceReady(true, 1920, 1080))
        binding.onPlayerReplaced()
        assertFalse(binding.bound)
        assertTrue(binding.onSurfaceReady(true, 1920, 1080))
    }
}
