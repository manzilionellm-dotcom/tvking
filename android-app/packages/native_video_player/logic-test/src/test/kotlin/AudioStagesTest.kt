import com.manzilionellm.native_video_player.logic.AudioSpectrum
import com.manzilionellm.native_video_player.logic.AudioStages
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Les quatre sondes copient. Une copie ne change pas le rapport.
 * Un passe-bas entre deux copies doit être nommé, et seulement là.
 */
class AudioStagesTest {

    @Test
    fun quatreCopiesGardentLeLargeBande() {
        val src = noise(48_000, 0.4, seed = 42L)
        val copy = { pcm: ShortArray -> pcm.copyOf() }
        val steps = AudioStages.ORDER.map { id -> id to copy }
        val readings = AudioStages.trace(src, 48_000, 1, steps)
        println(
            "ETAGES " + readings.joinToString(" ") {
                "${it.id}=${it.judgement.highRatio}"
            },
        )
        assertEquals(4, readings.size)
        assertTrue(readings.all { it.judgement.band == AudioSpectrum.Band.WIDE })
        val ratio = readings.first().judgement.highRatio
        assertTrue(readings.all { it.judgement.highRatio == ratio })
        assertNull(AudioStages.firstDrop(readings))
        assertTrue(AudioStages.sameBand(readings))
    }

    @Test
    fun unPasseBasEntreDecodeurEtVoixEstVisible() {
        val src = noise(48_000, 0.4, seed = 42L)
        val copy = { pcm: ShortArray -> pcm.copyOf() }
        val cut = { pcm: ShortArray -> lowpassTwice(pcm, 48_000, 3400.0) }
        val readings = AudioStages.trace(
            src,
            48_000,
            1,
            listOf(
                AudioStages.DECODER to copy,
                AudioStages.VOICE to cut,
                AudioStages.SILENCE to copy,
                AudioStages.SINK to copy,
            ),
        )
        println(
            "BAISSE voix " + readings.joinToString(" ") {
                "${it.id}=${it.judgement.band}/${it.judgement.highRatio}"
            },
        )
        assertEquals(AudioSpectrum.Band.WIDE, readings[0].judgement.band)
        assertEquals(AudioSpectrum.Band.LOW, readings[1].judgement.band)
        assertEquals(AudioSpectrum.Band.LOW, readings[2].judgement.band)
        assertEquals(AudioSpectrum.Band.LOW, readings[3].judgement.band)
        assertEquals(AudioStages.VOICE, AudioStages.firstDrop(readings)?.id)
        assertFalse(AudioStages.sameBand(readings))
    }

    @Test
    fun unPasseBasAvantAudioTrackEstNommeSonic() {
        val src = noise(48_000, 0.4, seed = 7L)
        val copy = { pcm: ShortArray -> pcm.copyOf() }
        val cut = { pcm: ShortArray -> lowpassTwice(pcm, 48_000, 3400.0) }
        val readings = AudioStages.trace(
            src,
            48_000,
            1,
            listOf(
                AudioStages.DECODER to copy,
                AudioStages.VOICE to copy,
                AudioStages.SILENCE to copy,
                AudioStages.SINK to cut,
            ),
        )
        assertEquals(AudioStages.SINK, AudioStages.firstDrop(readings)?.id)
        assertEquals(AudioSpectrum.Band.WIDE, readings[2].judgement.band)
        assertEquals(AudioSpectrum.Band.LOW, readings[3].judgement.band)
    }

    @Test
    fun unSignalDejaBasResteBasPartout() {
        val src = lowpassTwice(noise(48_000, 0.4, seed = 9L), 48_000, 3400.0)
        val copy = { pcm: ShortArray -> pcm.copyOf() }
        val readings = AudioStages.trace(src, 48_000, 1, AudioStages.ORDER.map { it to copy })
        assertTrue(readings.all { it.judgement.band == AudioSpectrum.Band.LOW })
        assertNull(AudioStages.firstDrop(readings))
        assertTrue(AudioStages.sameBand(readings))
    }

    private fun noise(n: Int, amp: Double, seed: Long): ShortArray {
        var s = seed
        val out = ShortArray(n)
        for (i in 0 until n) {
            s = s xor (s shl 13)
            s = s xor (s ushr 7)
            s = s xor (s shl 17)
            val u = ((s and 0xFFFFFF) / 0x1000000.toDouble()) * 2.0 - 1.0
            out[i] = toShort(u * amp)
        }
        return out
    }

    private fun lowpassTwice(src: ShortArray, sampleRate: Int, fc: Double): ShortArray {
        return lowpass(lowpass(src, sampleRate, fc), sampleRate, fc)
    }

    private fun lowpass(src: ShortArray, sampleRate: Int, fc: Double): ShortArray {
        val q = sqrt(0.5)
        val w0 = 2.0 * PI * fc / sampleRate
        val c = cos(w0)
        val alpha = sin(w0) / (2.0 * q)
        val a0 = 1.0 + alpha
        val b0 = ((1.0 - c) / 2.0) / a0
        val b1 = (1.0 - c) / a0
        val b2 = ((1.0 - c) / 2.0) / a0
        val a1 = (-2.0 * c) / a0
        val a2 = (1.0 - alpha) / a0
        var x1 = 0.0
        var x2 = 0.0
        var y1 = 0.0
        var y2 = 0.0
        val out = ShortArray(src.size)
        for (i in src.indices) {
            val x = src[i] / 32768.0
            val y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = y
            out[i] = toShort(y)
        }
        return out
    }

    private fun toShort(x: Double): Short {
        val v = (x * 32767.0).toInt()
        return v.coerceIn(-32768, 32767).toShort()
    }
}
