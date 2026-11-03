import com.manzilionellm.native_video_player.logic.VideoCadence
import com.manzilionellm.native_video_player.logic.VideoCadenceWindow
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class VideoCadenceWindowTest {
    private val counters = Any()

    @Test
    fun attendUneVraieFenetrePuisCompteLesDeltas() {
        val window = VideoCadenceWindow()
        assertNull(window.sample(counters, 1000, 200, 10, true))
        assertNull(window.sample(counters, 1500, 212, 10, true))
        assertEquals(VideoCadence(48, 2, 2000), window.sample(counters, 3000, 248, 12, true))
        // Une fenêtre sans image donne réellement zéro, sans inventer les
        // 60 i/s éventuelles du fichier ou le taux de rafraîchissement HDMI.
        assertEquals(VideoCadence(0, 0, 2000), window.sample(counters, 5000, 248, 12, true))
    }

    @Test
    fun pauseEtRepriseNeDiluentPasLaCadence() {
        val window = VideoCadenceWindow()
        window.sample(counters, 1000, 0, 0, true)
        assertNull(window.sample(counters, 2000, 24, 0, false))
        assertNull(window.sample(counters, 9000, 24, 0, true))
        assertEquals(VideoCadence(50, 1, 2000), window.sample(counters, 11000, 74, 1, true))
    }

    @Test
    fun nouveauDecodeurOuCompteurRemisAZeroExigeUneNouvelleFenetre() {
        val window = VideoCadenceWindow()
        val nextDecoder = Any()
        window.sample(counters, 1000, 150, 10, true)
        assertNull(window.sample(nextDecoder, 3000, 200, 11, true))
        assertEquals(VideoCadence(48, 0, 2000), window.sample(nextDecoder, 5000, 248, 11, true))
        assertNull(window.sample(nextDecoder, 7000, 5, 0, true))
        assertEquals(VideoCadence(48, 0, 2000), window.sample(nextDecoder, 9000, 53, 0, true))
    }

    @Test
    fun horlogeReculeeEtFenetreTropLongueNeProduisentPasDeFausseMesure() {
        val window = VideoCadenceWindow()
        window.sample(counters, 5000, 100, 0, true)
        assertNull(window.sample(counters, 4000, 101, 0, true))
        assertNull(window.sample(counters, 10000, 245, 0, true))
        assertEquals(VideoCadence(48, 0, 2000), window.sample(counters, 12000, 293, 0, true))
        window.reset()
        assertNull(window.sample(counters, 14000, 341, 0, true))
    }
}
