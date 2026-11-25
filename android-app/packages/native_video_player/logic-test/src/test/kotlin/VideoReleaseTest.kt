import com.manzilionellm.native_video_player.logic.VideoRelease
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class VideoReleaseTest {
    @Test
    fun uneSurfacePerdueNeSautePasLaLiberationDuDecodeur() {
        val calls = mutableListOf<String>()
        assertTrue(VideoRelease.attempt(
            clearSurface = { calls += "surface"; throw IllegalStateException("surface perdue") },
            releasePlayer = { calls += "release" },
        ))
        assertEquals(listOf("surface", "release"), calls)
    }

    @Test
    fun unDecodeurNonLibereNeRendPasDeConfirmationGpuIdle() {
        assertFalse(VideoRelease.attempt(clearSurface = {},
            releasePlayer = { throw IllegalStateException("délai de libération") }))
        assertFalse(VideoRelease.attempt(
            clearSurface = { throw IllegalStateException("surface perdue") },
            releasePlayer = { throw IllegalStateException("délai de libération") },
        ))
    }
}
