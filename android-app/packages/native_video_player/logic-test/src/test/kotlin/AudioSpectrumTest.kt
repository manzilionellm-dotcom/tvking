import com.manzilionellm.native_video_player.logic.AudioSpectrum
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Signaux synthétiques. Le passe-bas qui FABRIQUE le cas « radio » est
 * écrit ici, pas réutilisé depuis [AudioSpectrum] : le détecteur ne
 * doit pas être juge et partie.
 */
class AudioSpectrumTest {

    @Test
    fun largeBandeNestPasUnSonRadioEtLePasseBasEstBas() {
        val wide = measure(noise(48_000, 0.4, seed = 42L), 48_000)
        val cut = measure(lowpassTwice(noise(48_000, 0.4, seed = 42L), 48_000, 3400.0), 48_000)
        println("SPECTRE large bande ratio=${wide.highRatio} bande=${wide.band}")
        println("SPECTRE passe-bas ratio=${cut.highRatio} bande=${cut.band}")
        assertEquals(AudioSpectrum.Band.WIDE, wide.band)
        assertEquals(AudioSpectrum.Band.LOW, cut.band)
        assertTrue(wide.highRatio >= AudioSpectrum.WIDE_MIN_RATIO, "large=${wide.highRatio}")
        assertTrue(cut.highRatio <= AudioSpectrum.LOW_MAX_RATIO, "bas=${cut.highRatio}")
        assertTrue(wide.highRatio - cut.highRatio > 0.50, "écart ${wide.highRatio - cut.highRatio}")
        assertTrue(wide.clippedFraction < AudioSpectrum.CLIP_GREY, "faux clipping large=${wide.clippedFraction}")
    }

    @Test
    fun melangeGraveEtAiguResteLarge() {
        val mix = mix(
            tone(48_000, 48_000, 1000.0, 0.25),
            tone(48_000, 48_000, 8000.0, 0.25),
        )
        val j = measure(mix, 48_000)
        println("SPECTRE 1 kHz + 8 kHz ratio=${j.highRatio}")
        assertEquals(AudioSpectrum.Band.WIDE, j.band)
    }

    @Test
    fun aiguSeulNestPasUneBandeCoupee() {
        val j = measure(tone(48_000, 48_000, 8000.0, 0.3), 48_000)
        println("SPECTRE 8 kHz seul ratio=${j.highRatio}")
        assertEquals(AudioSpectrum.Band.WIDE, j.band)
    }

    @Test
    fun entreLesDeuxNeTranchePas() {
        val j = measure(tone(48_000, 48_000, 3000.0, 0.3), 48_000)
        println("SPECTRE 3 kHz ratio=${j.highRatio} bande=${j.band}")
        assertEquals(AudioSpectrum.Band.MID, j.band)
    }

    @Test
    fun fenetreCourteEtSilenceNeConcluentPas() {
        val short = measure(noise(1000, 0.4, seed = 1L), 48_000)
        assertEquals(AudioSpectrum.Band.SHORT, short.band)
        val silent = measure(ShortArray(48_000), 48_000)
        assertEquals(AudioSpectrum.Band.SILENCE, silent.band)
        val slow = measure(noise(48_000, 0.4, seed = 2L), 8_000)
        assertEquals(AudioSpectrum.Band.RATE, slow.band)
    }

    @Test
    fun passeBasA24kHzResteDistinctDuLargeBande() {
        val wide = measure(noise(24_000, 0.4, seed = 3L), 24_000)
        val cut = measure(lowpassTwice(noise(24_000, 0.4, seed = 3L), 24_000, 3400.0), 24_000)
        println("SPECTRE 24 kHz large=${wide.highRatio} passe-bas=${cut.highRatio}")
        assertEquals(AudioSpectrum.Band.WIDE, wide.band)
        assertEquals(AudioSpectrum.Band.LOW, cut.band)
    }

    @Test
    fun saturationSurSignalEcreteEtPasSurLargeBande() {
        val clean = measure(noise(48_000, 0.4, seed = 9L), 48_000)
        val slammed = measure(hardClip(noise(48_000, 0.4, seed = 9L), 8.0), 48_000)
        println("CLIP large=${clean.clippedFraction} écrêté=${slammed.clippedFraction} pic=${slammed.peak}")
        assertTrue(clean.clippedFraction < AudioSpectrum.CLIP_GREY)
        assertTrue(slammed.clippedFraction >= AudioSpectrum.CLIP_SURE, "écrêté=${slammed.clippedFraction}")
        assertEquals(32768, slammed.peak)
    }

    @Test
    fun sinusPleineEchelleNestPasUneSaturationSure() {
        val full = measure(tone(48_000, 48_000, 1000.0, 1.0), 48_000)
        println("CLIP sinus pleine échelle=${full.clippedFraction}")
        assertTrue(full.clippedFraction < AudioSpectrum.CLIP_SURE, "plein=${full.clippedFraction}")
    }

    private fun measure(pcm: ShortArray, sampleRate: Int): AudioSpectrum.Judgement =
        AudioSpectrum.measure(pcm, sampleRate, channels = 1)

    private fun tone(n: Int, sampleRate: Int, hz: Double, amp: Double): ShortArray {
        val out = ShortArray(n)
        for (i in 0 until n) {
            val x = amp * sin(2.0 * PI * hz * i / sampleRate)
            out[i] = toShort(x)
        }
        return out
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

    private fun mix(a: ShortArray, b: ShortArray): ShortArray {
        val n = minOf(a.size, b.size)
        val out = ShortArray(n)
        for (i in 0 until n) out[i] = toShort((a[i] / 32768.0) + (b[i] / 32768.0))
        return out
    }

    private fun hardClip(src: ShortArray, gain: Double): ShortArray {
        val out = ShortArray(src.size)
        for (i in src.indices) out[i] = toShort((src[i] / 32768.0) * gain)
        return out
    }

    /** Passe-bas Butterworth ordre 2, appliqué deux fois (pente plus raide). */
    private fun lowpassTwice(src: ShortArray, sampleRate: Int, fc: Double): ShortArray {
        val once = lowpass(src, sampleRate, fc)
        return lowpass(once, sampleRate, fc)
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
        val scaled = (x * 32767.0).toInt()
        val clamped = scaled.coerceIn(-32768, 32767)
        return clamped.toShort()
    }
}
