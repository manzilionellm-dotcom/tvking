import com.manzilionellm.native_video_player.logic.LowRamBuffer
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LowRamBufferTest {
    private val mib = 1024L * 1024L

    @Test
    fun fireTvStickA899MoEstPlafonnee() {
        // Fire TV AFTSS du journal : 899 Mo de RAM totale.
        assertEquals(LowRamBuffer.TIGHT_TARGET_BYTES, LowRamBuffer.targetBytes(899 * mib, false))
        assertEquals(LowRamBuffer.TIGHT_TARGET_BYTES, LowRamBuffer.targetBytes(1024 * mib, false))
    }

    @Test
    fun drapeauLowRamAndroidSuffit() {
        assertEquals(LowRamBuffer.TIGHT_TARGET_BYTES, LowRamBuffer.targetBytes(2048 * mib, true))
    }

    @Test
    fun boxPlusGrossesGardentLeDefautMedia3() {
        assertNull(LowRamBuffer.targetBytes(1025 * mib, false))
        assertNull(LowRamBuffer.targetBytes(2048 * mib, false))
        assertNull(LowRamBuffer.targetBytes(4096 * mib, false))
        // Mémoire inconnue (0) : pas de plafond, comme BoxMemoryBudget.
        assertNull(LowRamBuffer.targetBytes(0, false))
    }

    @Test
    fun lePlafondLaissePasserLesCinqSecondesDeDemarrage() {
        // Même à 25 Mbit/s, 5 s = ~15,6 Mo < 32 Mio : le démarrage n'est
        // jamais raccourci (la priorité au temps le garantit de toute façon).
        val fiveSecondsAt25Mbps = 25_000_000L / 8L * 5L
        assertTrue(LowRamBuffer.TIGHT_TARGET_BYTES > fiveSecondsAt25Mbps)
        // Et 45 s d'un flux HD à 6 Mbit/s tiennent encore dedans.
        val fortyFiveSecondsAt5Mbps = 5_000_000L / 8L * 45L
        assertTrue(LowRamBuffer.TIGHT_TARGET_BYTES > fortyFiveSecondsAt5Mbps)
    }
}
