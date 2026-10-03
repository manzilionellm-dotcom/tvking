package com.manzilionellm.native_video_player.logic

import java.util.Locale
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * FORME DU SON (03/10/2026) — ce que « > 4 kHz » ne sait pas dire.
 *
 * Une parole naturelle a presque toute son énergie dans le grave.
 * Un filtre téléphone (300–3400 Hz) enlève ce grave. Le pourcentage
 * au-dessus de 4 kHz, lui, ne bouge presque pas : le dénominateur a
 * rétréci en même temps que le numérateur. Sur les témoins du banc
 * (`android-app/tools/audio_lab/mesure.py`, 03/10/2026) :
 *
 *   • parole harmonique propre : > 4 kHz = 1,12 %, grave/milieu = 3,47
 *   • la même, filtre ffmpeg 300–3400 Hz : > 4 kHz = 1,23 %, grave/milieu = 0,076
 *   • la même, passe-bas seul : grave/milieu = 3,61 (le grave est resté)
 *
 * Les deux premiers sont dans la même case « basse » de [AudioSpectrum].
 * Le rapport grave/milieu, non.
 *
 * Trois indicateurs, tous calculés sur une COPIE. Aucun ne modifie
 * un échantillon. Les seuils sont le milieu des trous mesurés, pas
 * une estimation :
 *
 *   • grave/milieu < [GRAVE_BAS] (0,10) : le grave est coupé.
 *     Trou mesuré : téléphone ≤ 0,0756, parole ou passe-bas ≥ 0,1438.
 *   • aigu/milieu < [AIGU_BAS] (0,015) : l'aigu au-dessus de 3,5 kHz
 *     est coupé. Trou : téléphone ≤ 0,0048, passe-haut = 0,063.
 *   • Les deux ensemble = forme téléphone. Le grave coupé seul =
 *     passe-haut (« maigre »). L'aigu coupé seul = parole sourde,
 *     pas un téléphone.
 *   • Écho ≥ [ECHO_MIN] (18) : un second exemplaire du même son,
 *     18 à 40 ms plus tard. Trou étroit : deux paroles différentes = 11,8,
 *     copie syllabique à 30 ms = 28. Le témoin long fait 173.
 *   • Chute ≥ [CHUTE_DB] (8 dB) entre les secondes où il y a du son.
 *     Trou : parole = 2,3 dB au plus, gain × 0,2 pendant 2,5 s = 14,4 dB.
 *     Une seconde muette (pause) est ignorée : elle ne compte pas.
 *
 * Objet PUR. La sonde Android ne fait qu'appeler [measure].
 */
object AudioQuality {

    /** Bande du grave de la parole, sous la coupure téléphone (300 Hz). */
    const val GRAVE_LO: Double = 80.0
    const val GRAVE_HI: Double = 280.0

    /** Bande « milieu », celle qu'un téléphone garde. */
    const val MILIEU_LO: Double = 300.0
    const val MILIEU_HI: Double = 3400.0

    /** Aigu encore dans la voix (souffle, harmoniques), sous 7 kHz. */
    const val AIGU_LO: Double = 3500.0
    const val AIGU_HI: Double = 7000.0

    /**
     * En dessous, le grave est coupé. Milieu géométrique du trou
     * 0,0756 … 0,1438, arrondi : le banc a mesuré 0,104.
     */
    const val GRAVE_BAS: Double = 0.10

    /**
     * En dessous, l'aigu est coupé. Milieu géométrique du trou
     * 0,0048 … 0,063 : le banc a mesuré 0,017. 0,015 est dans le trou
     * (vérifié par le script : max bas < 0,015 < min haut).
     */
    const val AIGU_BAS: Double = 0.015

    /**
     * Score d'écho à partir duquel on dit « second son ».
     * Pire faux positif du banc : deux paroles différentes = 11,8.
     * Plus petit vrai écho de parole (syllabes, copie à 30 ms) = 28.
     * L'écho ffmpeg du témoin long = 173. Milieu géométrique du trou
     * étroit (11,8 … 28) : 18. Une série harmonique fixe, sans
     * syllabes, ne s'allume pas (mesuré 7) : le pic se confond avec
     * la fondamentale. La parole, elle, se sépare.
     */
    const val ECHO_MIN: Double = 18.0

    /**
     * Écart de niveau, en dB, à partir duquel la baisse est tenue.
     * Trou : 2,3 dB (parole, et parole avec 2 s de silence) … 14,4 dB
     * (gain × 0,2). Le milieu du trou est 8 dB.
     */
    const val CHUTE_DB: Double = 8.0

    /**
     * Une seconde plus basse que ça sous la seconde la plus forte
     * est une pause, pas une baisse. 20 dB laisse passer un gain × 0,2
     * (−14 dB) et sort un trou numérique.
     */
    const val PAUSE_DB: Double = 20.0

    /** Fenêtre d'analyse. 32 768 trames à 48 kHz ≈ 0,68 s. */
    const val FFT_N: Int = 32_768

    /** En dessous, l'aigu à 7 kHz n'existe pas : on ne classe pas. */
    const val MIN_SAMPLE_RATE: Int = 16_000

    /** Moins que ça, le cepstre et les bandes ne veulent rien dire. */
    const val MIN_FRAMES: Int = 8_192

    /** Énergie moyenne sous laquelle la fenêtre est un silence. */
    const val SILENCE_MEAN_SQUARE: Double = 1e-8

    enum class Profil {
        /** Grave et aigu présents. */
        LARGE,

        /** Grave coupé ET aigu coupé : passe-bande 300–3400 Hz. */
        TELEPHONE,

        /** Aigu coupé, grave présent. Parole sourde ou passe-bas seul. */
        SOURD,

        /** Grave coupé, aigu présent. Passe-haut, pas un téléphone. */
        MAIGRE,

        /** Pas assez de trames. */
        COURT,

        /** Signal trop faible. */
        SILENCE,

        /** Fréquence trop basse pour voir l'aigu. */
        RATE,
    }

    /**
     * Une fenêtre. [chuteDb] est null tant qu'on n'a pas plusieurs
     * secondes : une seule fenêtre ne peut pas voir une baisse lente.
     * [fortDb] est le niveau fort DE cette fenêtre (90e centile).
     */
    data class Reading(
        val profil: Profil,
        val graveRatio: Double,
        val aiguRatio: Double,
        val echo: Double,
        val echoMs: Double,
        val fortDb: Double,
        val chuteDb: Double?,
        val sampleRate: Int,
        val frames: Int,
    ) {
        /** Second son décalé, sur une fenêtre qui a vraiment du son. */
        val echoNet: Boolean
            get() = echo >= ECHO_MIN && profil != Profil.SILENCE && profil != Profil.COURT && profil != Profil.RATE

        /** Baisse tenue entre secondes actives. */
        val chuteNette: Boolean
            get() = chuteDb != null && !chuteDb.isNaN() && chuteDb >= CHUTE_DB

        fun profilText(): String = when (profil) {
            Profil.LARGE -> "large (grave et aigu présents)"
            Profil.TELEPHONE -> "téléphone (grave et aigu coupés ensemble)"
            Profil.SOURD -> "sourd (aigu bas, grave présent)"
            Profil.MAIGRE -> "maigre (grave coupé, aigu présent)"
            Profil.COURT -> "pas assez d'échantillons"
            Profil.SILENCE -> "silence"
            Profil.RATE -> "fréquence trop basse"
        }

        fun ratioText(v: Double): String =
            if (v.isNaN()) "illisible" else String.format(Locale.FRANCE, "%.3f", v)

        fun echoText(): String = when {
            echo.isNaN() -> "illisible"
            echo >= 999.0 -> "> 999"
            else -> String.format(Locale.FRANCE, "%.0f", echo)
        }
    }

    /**
     * Mesure une fenêtre PCM 16 bits entrelacée. Ne modifie pas [pcm].
     * [chuteDb] reste null : l'appelant empile [Reading.fortDb] et
     * rappelle [chuteDb].
     */
    fun measure(pcm: ShortArray, sampleRate: Int, channels: Int): Reading {
        val rate = sampleRate.coerceAtLeast(1)
        val mono = downmix(pcm, channels)
        val rms = meanSquare(mono)
        val fort = niveauFortDb(mono, rate)
        if (rate < MIN_SAMPLE_RATE) {
            return vide(Profil.RATE, rate, mono.size, fort)
        }
        if (mono.size < MIN_FRAMES) {
            return vide(Profil.COURT, rate, mono.size, fort)
        }
        if (rms < SILENCE_MEAN_SQUARE) {
            return vide(Profil.SILENCE, rate, mono.size, fort)
        }
        val n = fftSize(mono.size)
        val (power, used) = powerSpectrum(mono, n)
        val grave = bandEnergy(power, n, rate, GRAVE_LO, GRAVE_HI)
        val milieu = bandEnergy(power, n, rate, MILIEU_LO, MILIEU_HI)
        val aigu = bandEnergy(power, n, rate, AIGU_LO, AIGU_HI)
        val graveRatio = if (milieu > 0.0) grave / milieu else Double.NaN
        val aiguRatio = if (milieu > 0.0) aigu / milieu else Double.NaN
        val (echo, echoMs) = echoScore(power, n, rate)
        val profil = classer(graveRatio, aiguRatio)
        return Reading(
            profil = profil,
            graveRatio = graveRatio,
            aiguRatio = aiguRatio,
            echo = echo,
            echoMs = echoMs,
            fortDb = fort,
            chuteDb = null,
            sampleRate = rate,
            frames = used,
        )
    }

    /**
     * Écart max−min des niveaux forts, en ignorant les secondes muettes.
     * Moins de deux secondes actives → NaN (on ne conclut pas).
     */
    fun chuteDb(niveauxFortDb: List<Double>): Double {
        val ok = niveauxFortDb.filter { !it.isNaN() && !it.isInfinite() }
        if (ok.size < 2) return Double.NaN
        val pic = ok.max()
        val gardes = ok.filter { it >= pic - PAUSE_DB }
        if (gardes.size < 2) return 0.0
        return gardes.max() - gardes.min()
    }

    /**
     * Niveau « fort » d'une fenêtre : 90e centile des RMS de 20 ms.
     * Les silences entre syllabes ne tirent pas ce chiffre vers le bas.
     * En dBFS (0 dB = amplitude 1).
     */
    fun niveauFortDb(mono: DoubleArray, sampleRate: Int): Double {
        val long = (0.020 * sampleRate).toInt().coerceAtLeast(8)
        val pas = (long / 2).coerceAtLeast(1)
        if (mono.size < long) return Double.NaN
        val frames = ArrayList<Double>(mono.size / pas + 1)
        var i = 0
        while (i + long <= mono.size) {
            var s = 0.0
            for (k in 0 until long) {
                val v = mono[i + k]
                s += v * v
            }
            frames.add(sqrt(s / long))
            i += pas
        }
        if (frames.isEmpty()) return Double.NaN
        frames.sort()
        // Rang 90 %. Pour un signal constant, toutes les cases sont
        // égales : l'interpolation de numpy ne changerait rien.
        val idx = ((frames.size - 1) * 0.90).roundToInt().coerceIn(0, frames.size - 1)
        return 20.0 * ln(frames[idx] + 1e-30) / ln(10.0)
    }

    private fun classer(grave: Double, aigu: Double): Profil {
        if (grave.isNaN() || aigu.isNaN()) return Profil.SILENCE
        val graveBas = grave < GRAVE_BAS
        val aiguBas = aigu < AIGU_BAS
        return when {
            graveBas && aiguBas -> Profil.TELEPHONE
            graveBas && !aiguBas -> Profil.MAIGRE
            !graveBas && aiguBas -> Profil.SOURD
            else -> Profil.LARGE
        }
    }

    private fun vide(profil: Profil, rate: Int, frames: Int, fort: Double) = Reading(
        profil = profil,
        graveRatio = Double.NaN,
        aiguRatio = Double.NaN,
        echo = Double.NaN,
        echoMs = Double.NaN,
        fortDb = fort,
        chuteDb = null,
        sampleRate = rate,
        frames = frames,
    )

    /**
     * Mélange les voies. Si G ≈ −D, le mélange est un silence et le
     * spectre mentirait : on mesure la voie gauche. La corrélation,
     * elle, est déjà dans [AudioPhase].
     */
    internal fun downmix(pcm: ShortArray, channels: Int): DoubleArray {
        val ch = channels.coerceAtLeast(1)
        val frames = pcm.size / ch
        val mono = DoubleArray(frames)
        var mixE = 0.0
        var leftE = 0.0
        var i = 0
        var f = 0
        while (f < frames) {
            val left = pcm[i] / 32768.0
            leftE += left * left
            var sum = 0.0
            for (c in 0 until ch) sum += pcm[i + c] / 32768.0
            val m = sum / ch
            mono[f] = m
            mixE += m * m
            i += ch
            f++
        }
        if (ch >= 2 && mixE < 1e-4 * (leftE + 1e-30)) {
            i = 0
            for (k in 0 until frames) {
                mono[k] = pcm[i] / 32768.0
                i += ch
            }
        }
        return mono
    }

    private fun meanSquare(x: DoubleArray): Double {
        if (x.isEmpty()) return 0.0
        var s = 0.0
        for (v in x) s += v * v
        return s / x.size
    }

    private fun fftSize(length: Int): Int {
        var n = 1
        val cap = minOf(length, FFT_N)
        while (n * 2 <= cap) n *= 2
        return n
    }

    /**
     * Puissance par bin (0 … n/2). Fenêtre de Hann symétrique, la même
     * que `numpy.hanning` : 0,5 − 0,5·cos(2π·i/(n−1)).
     * Si le milieu de [mono] est un silence, on prend le début.
     */
    private fun powerSpectrum(mono: DoubleArray, n: Int): Pair<DoubleArray, Int> {
        var start = if (mono.size >= n) (mono.size - n) / 2 else 0
        if (mono.size >= n && meanSquare(mono, start, n) < SILENCE_MEAN_SQUARE) start = 0
        val re = DoubleArray(n)
        val im = DoubleArray(n)
        for (i in 0 until n) {
            val x = if (start + i < mono.size) mono[start + i] else 0.0
            re[i] = x * hann(i, n)
        }
        Fft.transform(re, im, inverse = false)
        val bins = n / 2 + 1
        val power = DoubleArray(bins)
        for (k in 0 until bins) power[k] = re[k] * re[k] + im[k] * im[k]
        return power to n
    }

    private fun meanSquare(x: DoubleArray, start: Int, n: Int): Double {
        var s = 0.0
        val fin = minOf(x.size, start + n)
        val count = (fin - start).coerceAtLeast(1)
        for (i in start until fin) s += x[i] * x[i]
        return s / count
    }

    /** `numpy.hanning`, pas la fenêtre périodique. */
    internal fun hann(i: Int, n: Int): Double {
        if (n <= 1) return 1.0
        return 0.5 - 0.5 * cos(2.0 * PI * i / (n - 1))
    }

    private fun bandEnergy(power: DoubleArray, n: Int, sr: Int, lo: Double, hi: Double): Double {
        var k0 = ceil(lo * n / sr).toInt()
        if (k0 < 1) k0 = 1
        var k1 = floor((hi - 1e-9) * n / sr).toInt()
        if (k1 > n / 2) k1 = n / 2
        if (k1 < k0) return 0.0
        var s = 0.0
        for (k in k0..k1) s += power[k]
        return s
    }

    /**
     * Pic du cepstre entre 18 et 40 ms, divisé par la médiane de cette
     * zone. On retire d'abord la fondamentale (2,5–12 ms) et ses
     * multiples : une voix à 120 Hz a un pic vers 25 ms qui n'est pas
     * un écho. Renvoie (score, retard en ms).
     */
    private fun echoScore(power: DoubleArray, n: Int, sr: Int): Pair<Double, Double> {
        val re = DoubleArray(n)
        val im = DoubleArray(n)
        val bins = n / 2
        for (k in 0..bins) {
            val amp = sqrt(power[k].coerceAtLeast(0.0))
            re[k] = ln(amp + 1e-12)
        }
        for (k in 1 until bins) re[n - k] = re[k]
        Fft.transform(re, im, inverse = true)
        val p0 = maxOf(1, (0.0025 * sr).roundToInt())
        val p1 = minOf(bins, (0.012 * sr).roundToInt())
        val i0 = maxOf(1, (0.018 * sr).roundToInt())
        val i1 = minOf(bins, (0.040 * sr).roundToInt())
        if (p1 <= p0 || i1 <= i0 + 2) return Double.NaN to Double.NaN
        var pitchAt = p0
        var pitchMax = re[p0]
        for (i in p0 until p1) {
            if (re[i] > pitchMax) {
                pitchMax = re[i]
                pitchAt = i
            }
        }
        val zone = DoubleArray(i1 - i0)
        for (i in i0 until i1) zone[i - i0] = re[i]
        for (k in 2..6) {
            val centre = k * pitchAt
            val tol = (0.05 * centre).roundToInt()
            val a = maxOf(i0, centre - tol)
            val b = minOf(i1, centre + tol + 1)
            for (i in a until b) zone[i - i0] = 0.0
        }
        val abs = DoubleArray(zone.size) { kotlin.math.abs(re[i0 + it]) }
        abs.sort()
        val med = if (abs.size % 2 == 1) {
            abs[abs.size / 2]
        } else {
            (abs[abs.size / 2 - 1] + abs[abs.size / 2]) / 2.0
        } + 1e-12
        var pic = zone[0]
        var picAt = 0
        for (i in zone.indices) {
            if (zone[i] > pic) {
                pic = zone[i]
                picAt = i
            }
        }
        if (pic <= 0.0) return 0.0 to Double.NaN
        val ms = (i0 + picAt) * 1000.0 / sr
        return (pic / med) to ms
    }

    /**
     * FFT radix-2. [inverse] vrai : signe opposé et division par n,
     * comme `numpy.fft.ifft`. n doit être une puissance de 2.
     */
    internal object Fft {
        fun transform(re: DoubleArray, im: DoubleArray, inverse: Boolean) {
            val n = re.size
            var j = 0
            for (i in 1 until n) {
                var bit = n shr 1
                while (j and bit != 0) {
                    j = j xor bit
                    bit = bit shr 1
                }
                j = j xor bit
                if (i < j) {
                    val tr = re[i]
                    re[i] = re[j]
                    re[j] = tr
                    val ti = im[i]
                    im[i] = im[j]
                    im[j] = ti
                }
            }
            var len = 2
            while (len <= n) {
                val ang = 2.0 * PI / len * (if (inverse) 1.0 else -1.0)
                val wlenRe = cos(ang)
                val wlenIm = sin(ang)
                var i = 0
                while (i < n) {
                    var wRe = 1.0
                    var wIm = 0.0
                    val half = len / 2
                    for (k in 0 until half) {
                        val uRe = re[i + k]
                        val uIm = im[i + k]
                        val vRe = re[i + k + half] * wRe - im[i + k + half] * wIm
                        val vIm = re[i + k + half] * wIm + im[i + k + half] * wRe
                        re[i + k] = uRe + vRe
                        im[i + k] = uIm + vIm
                        re[i + k + half] = uRe - vRe
                        im[i + k + half] = uIm - vIm
                        val nextRe = wRe * wlenRe - wIm * wlenIm
                        wIm = wRe * wlenIm + wIm * wlenRe
                        wRe = nextRe
                    }
                    i += len
                }
                len = len shl 1
            }
            if (inverse) {
                for (i in 0 until n) {
                    re[i] /= n
                    im[i] /= n
                }
            }
        }
    }
}
