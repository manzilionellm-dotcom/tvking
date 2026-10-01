import com.manzilionellm.native_video_player.logic.AudioSpectrum
import com.manzilionellm.native_video_player.logic.ClearVoiceGain
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

    /**
     * Chaîne par défaut, rejouée ici : copie PCM (sonde), gain 1
     * (voix claire coupée ou sous le seuil). Aucun passe-bas.
     * Le même bruit après un vrai passe-bas tombe en BASSE.
     */
    @Test
    fun chaineParDefautNeCoupePasLesAigus() {
        val src = noise(48_000, 0.4, seed = 42L)
        val before = measure(src, 48_000)
        val copied = src.copyOf()
        val afterCopy = measure(copied, 48_000)
        val gain = ClearVoiceGain.target(0.4f)
        assertEquals(1f, gain)
        // Même calcul que ClearVoiceProcessor : entier × gain, sans filtre.
        val gained = ShortArray(src.size) { i ->
            (src[i].toInt() * gain).toInt().coerceIn(-32768, 32767).toShort()
        }
        val afterGain = measure(gained, 48_000)
        val cut = measure(lowpassTwice(src, 48_000, 3400.0), 48_000)
        println("CHAINE avant=${before.highRatio} copie=${afterCopy.highRatio} gain=${afterGain.highRatio} passe-bas=${cut.highRatio}")
        assertEquals(AudioSpectrum.Band.WIDE, before.band)
        assertEquals(AudioSpectrum.Band.WIDE, afterCopy.band)
        assertEquals(AudioSpectrum.Band.WIDE, afterGain.band)
        assertEquals(before.highRatio, afterCopy.highRatio)
        assertTrue(kotlin.math.abs(before.highRatio - afterGain.highRatio) < 1e-9)
        assertEquals(AudioSpectrum.Band.LOW, cut.band)
    }

    /** Harmoniques de voix sous 3,2 kHz : le chiffre « 2 % » n'est pas un filtre. */
    @Test
    fun uneVoixSansAigusEstBasseSansQuOnAitFiltre() {
        val n = 48_000
        val sr = 48_000
        val raw = DoubleArray(n)
        var peak = 0.0
        val f0 = 140.0
        for (i in 0 until n) {
            var s = 0.0
            var k = 1
            while (f0 * k < 3200.0) {
                s += (1.0 / k) * sin(2.0 * PI * f0 * k * i / sr)
                k++
            }
            raw[i] = s
            if (kotlin.math.abs(s) > peak) peak = kotlin.math.abs(s)
        }
        val pcm = ShortArray(n) { i -> toShort(raw[i] / peak * 0.35) }
        val j = measure(pcm, sr)
        println("VOIX sous 3,2 kHz ratio=${j.highRatio} bande=${j.band}")
        assertEquals(AudioSpectrum.Band.LOW, j.band)
        assertTrue(j.highRatio < 0.05, "voix=${j.highRatio}")
    }

    @Test
    fun voiesOpposeesAnnulentLeMelangeMaisPasChaqueVoie() {
        val mono = noise(24_000, 0.4, seed = 42L)
        val stereo = ShortArray(mono.size * 2)
        for (i in mono.indices) {
            stereo[i * 2] = mono[i]
            val inv = -mono[i].toInt()
            stereo[i * 2 + 1] = inv.coerceIn(-32768, 32767).toShort()
        }
        var mix = AudioSpectrum.start(48_000)
        var left = AudioSpectrum.start(48_000)
        var right = AudioSpectrum.start(48_000)
        mix = AudioSpectrum.push(mix, stereo, 2)
        left = AudioSpectrum.pushChannel(left, stereo, 2, 0)
        right = AudioSpectrum.pushChannel(right, stereo, 2, 1)
        val mixJ = AudioSpectrum.judge(mix)
        val leftJ = AudioSpectrum.judge(left)
        val rightJ = AudioSpectrum.judge(right)
        println("VOIES mélange=${mixJ.highRatio}/${mixJ.band} G=${leftJ.highRatio} D=${rightJ.highRatio}")
        assertEquals(AudioSpectrum.Band.WIDE, leftJ.band)
        assertEquals(AudioSpectrum.Band.WIDE, rightJ.band)
        val heard = mixJ.copy(channelHighRatios = listOf(leftJ.highRatio, rightJ.highRatio))
        assertEquals(AudioSpectrum.Band.WIDE, AudioSpectrum.effectiveBand(heard))
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
