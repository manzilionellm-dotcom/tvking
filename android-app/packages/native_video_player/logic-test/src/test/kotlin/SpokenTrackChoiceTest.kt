import com.manzilionellm.native_video_player.logic.SpokenCandidate
import com.manzilionellm.native_video_player.logic.SpokenTrackChoice
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SpokenTrackChoiceTest {
    private fun t(
        index: Int,
        language: String? = null,
        label: String? = null,
        selected: Boolean = false,
        roleFlags: Int = 0,
    ) = SpokenCandidate(
        group = 0,
        index = index,
        language = language,
        label = label,
        selected = selected,
        roleFlags = roleFlags,
    )

    @Test
    fun codesLangue() {
        assertEquals("fr", SpokenTrackChoice.language("fre"))
        assertEquals("fr", SpokenTrackChoice.language("fra"))
        assertEquals("en", SpokenTrackChoice.language("en-US"))
        assertNull(SpokenTrackChoice.language("und"))
        assertNull(SpokenTrackChoice.language(""))
    }

    @Test
    fun langueDeLAppGagne() {
        val pick = SpokenTrackChoice.pick(
            listOf(
                t(0, language = "eng", label = "English", selected = true),
                t(1, language = "fre", label = "VF"),
            ),
            "fr",
        )
        assertEquals(1, pick?.index)
    }

    @Test
    fun commentaireNeRemplacePasLaVf() {
        val pick = SpokenTrackChoice.pick(
            listOf(
                t(0, language = "fr", label = "Commentaire", selected = true),
                t(1, language = "fr", label = "VF"),
            ),
            "fr",
        )
        assertEquals(1, pick?.index)
        assertTrue(SpokenTrackChoice.isSideTrack(t(0, label = "Audio Description")))
        assertFalse(SpokenTrackChoice.isSideTrack(t(0, label = "VF")))
    }

    @Test
    fun drapeauCommentaire() {
        val pick = SpokenTrackChoice.pick(
            listOf(
                t(0, language = "fr", selected = true, roleFlags = SpokenTrackChoice.ROLE_COMMENTARY),
                t(1, language = "fr"),
            ),
            "fr",
        )
        assertEquals(1, pick?.index)
        assertTrue(
            SpokenTrackChoice.isSideTrack(
                t(0, roleFlags = SpokenTrackChoice.ROLE_DESCRIBES_VIDEO),
            ),
        )
    }

    @Test
    fun dejaBonnePisteOnNeChangeRien() {
        val pick = SpokenTrackChoice.pick(
            listOf(
                t(0, language = "en", label = "English"),
                t(1, language = "fr", label = "VF", selected = true),
            ),
            "fr",
        )
        assertNull(pick)
    }

    @Test
    fun sansLaLangueOnQuitteLeCommentaire() {
        val pick = SpokenTrackChoice.pick(
            listOf(
                t(0, language = "en", label = "Director commentary", selected = true),
                t(1, language = "de", label = "Deutsch"),
            ),
            "fr",
        )
        assertEquals(1, pick?.index)
    }

    @Test
    fun queDesCommentairesOnNeCoupePas() {
        val pick = SpokenTrackChoice.pick(
            listOf(
                t(0, label = "Commentary", selected = true),
                t(1, label = "AD"),
            ),
            "fr",
        )
        assertNull(pick)
    }
}
