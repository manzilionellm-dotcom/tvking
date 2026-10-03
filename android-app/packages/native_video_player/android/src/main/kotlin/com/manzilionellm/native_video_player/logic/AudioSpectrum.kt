package com.manzilionellm.native_video_player.logic

import java.util.Locale
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * MESURE DE BANDE (01/10/2026) — « est-ce que les aigus au-dessus de 4 kHz
 * sont là ? »
 *
 * Le son « vieille radio / dans une boîte » est un signal dont l'énergie
 * au-dessus d'environ 4 kHz a été coupée (passe-bas, téléphone, SBR non
 * reconstruit). On ne devine pas à l'oreille : on fait passer le PCM dans
 * un passe-haut de Butterworth (ordre 2, 4 kHz) et on compare l'énergie
 * qui sort à l'énergie du signal.
 *
 * Trois zones, écartées exprès pour ne pas se tromper :
 *   • LARGE  : rapport ≥ [WIDE_MIN_RATIO]. Un bruit large bande ou un
 *     mélange grave + aigu tombe ici. On a le DROIT de dire « ce n'est
 *     pas un son radio ».
 *   • BASSE  : rapport ≤ [LOW_MAX_RATIO]. Un large bande après passe-bas
 *     (~3,4 kHz) tombe ici. Une voix naturelle, pauvre en aigus, peut
 *     y tomber AUSSI : ce seul chiffre ne prouve donc PAS un bug du
 *     lecteur. [AudioDiagnosis] le dit « cause incertaine », sauf si une
 *     AUTRE règle (décodeur, fréquence) est déjà sûre.
 *   • MILIEU : entre les deux. On ne tranche pas.
 *
 * Objet PUR (aucun Android) : les tests de logic-test/ fabriquent les
 * signaux et vérifient que le large bande n'est jamais classé « basse ».
 */
object AudioSpectrum {

    /** Coupure du passe-haut, en hertz. */
    const val SPLIT_HZ: Double = 4000.0

    /**
     * En dessous de cette fréquence d'échantillonnage, le Nyquist est trop
     * près de 4 kHz : l'absence d'énergie au-dessus ne veut rien dire.
     * 12 kHz → Nyquist 6 kHz, il reste une bande mesurable.
     */
    const val MIN_SAMPLE_RATE: Int = 12_000

    /** Il faut au moins ça d'échantillons utiles (après la mise en route du filtre). */
    const val MIN_FRAMES: Int = 8_192

    /** Le filtre met quelques centaines d'échantillons à se stabiliser : on ne les compte pas. */
    const val WARMUP_FRAMES: Int = 512

    /**
     * Rapport haute / totale à partir duquel le signal est large bande.
     * Mesuré : bruit blanc ~0,82, 1 kHz + 8 kHz ~0,48. Le seuil 0,40
     * est en dessous des deux, loin de la zone basse.
     */
    const val WIDE_MIN_RATIO: Double = 0.40

    /**
     * Rapport en dessous duquel la bande haute est « basse ».
     * Mesuré : bruit blanc passé deux fois à 3,4 kHz ~0,08.
     * 0,12 laisse une marge, et reste très loin de 0,40.
     */
    const val LOW_MAX_RATIO: Double = 0.12

    /** Énergie moyenne sous laquelle on considère le signal comme du silence. */
    const val SILENCE_MEAN_SQUARE: Double = 1e-8

    /** |échantillon| à partir duquel on compte un pic collé au plafond (16 bits). */
    const val CLIP_ABS: Int = 32_760

    /** Part des échantillons au plafond : au-dessus, la saturation est sûre.
     *  Un sinus à pleine échelle en touche ~4 % (mesuré 0,0417) : ce n'est
     *  PAS un écrêtage. Un bruit écrêté en touche ~69 %. Le seuil 0,10
     *  est entre les deux. */
    const val CLIP_SURE: Double = 0.10

    /** Entre ce plancher et [CLIP_SURE], on ne tranche pas.
     *  0,02 est sous le sinus pleine échelle (~0,042) : il reste « incertain »,
     *  pas « rien ». Un signal à mi-échelle (0 %) ne s'allume pas. */
    const val CLIP_GREY: Double = 0.02

    enum class Band {
        /** Énergie au-dessus de 4 kHz nettement présente. */
        WIDE,

        /** Énergie au-dessus de 4 kHz au niveau d'un passe-bas. */
        LOW,

        /** Entre les deux seuils : les chiffres ne tranchent pas. */
        MID,

        /** Pas assez d'échantillons pour conclure. */
        SHORT,

        /** Quasi silence : un rapport n'aurait aucun sens. */
        SILENCE,

        /** Fréquence trop basse pour voir au-dessus de 4 kHz. */
        RATE,
    }

    /**
     * Résultat d'une fenêtre. [highRatio] = énergie du passe-haut / énergie
     * totale, sur les échantillons APRÈS la mise en route. [clippedFraction]
     * compte, lui, tous les échantillons bruts (un pic ne dépend pas du filtre).
     */
    data class Judgement(
        val band: Band,
        val highRatio: Double,
        val clippedFraction: Double,
        val peak: Int,
        val frames: Int,
        val sampleRate: Int,
        /**
         * Rapport haute / totale de CHAQUE voie, dans l'ordre du PCM.
         * Vide si on n'a mesuré que le mélange. Une voie large alors que
         * le mélange est bas = les voies s'annulent, pas un passe-bas.
         */
        val channelHighRatios: List<Double> = emptyList(),
        /**
         * Corrélation gauche/droite de la dernière seconde. Null tant
         * qu'une seconde n'est pas pleine, ou si on n'a pas mesuré.
         */
        val phase: AudioPhase.Reading? = null,
        /**
         * Énergie > 4 kHz sur la dernière seconde seulement.
         * Le [highRatio] du dessus, lui, cumule depuis l'ouverture :
         * une voix puis un bruit restent moyens. Ce chiffre suit le
         * son qu'on entend maintenant.
         */
        val recentHighRatio: Double? = null,
        /**
         * Forme grave/aigu, écho, chute. Null tant qu'une seconde
         * n'est pas pleine, ou si on n'a pas mesuré. La sonde copie :
         * ce chiffre ne change aucun échantillon.
         */
        val quality: AudioQuality.Reading? = null,
    ) {
        fun percent(): String =
            String.format(Locale.FRANCE, "%.1f %%", highRatio * 100.0)
    }

    /**
     * Bande à lire. Si une voie est large, le signal a des aigus :
     * le mélange (qui peut les annuler) ne fait pas un son radio.
     */
    fun effectiveBand(j: Judgement): Band {
        if (j.channelHighRatios.any { it >= WIDE_MIN_RATIO }) return Band.WIDE
        return j.band
    }

    /**
     * Pousse UNE voie d'un tampon entrelacé dans [acc].
     * [channel] commence à 0. Le mélange des voies n'est pas refait ici.
     */
    fun pushChannel(acc: Accum, pcm: ShortArray, channels: Int, channel: Int): Accum {
        val ch = channels.coerceAtLeast(1)
        if (channel !in 0 until ch) return acc
        val n = pcm.size / ch
        if (n <= 0) return acc
        val one = ShortArray(n)
        var j = 0
        var i = channel
        val limit = n * ch
        while (i < limit) {
            one[j] = pcm[i]
            j++
            i += ch
        }
        return push(acc, one, 1)
    }

    /**
     * État du filtre + compteurs. Immuable : chaque tampon rend un nouvel
     * état, ce qui se teste sans synchronisation.
     */
    data class Accum(
        val sampleRate: Int,
        val frames: Int,
        val sumSq: Double,
        val sumSqHigh: Double,
        val rawSamples: Int,
        val clipped: Int,
        val peak: Int,
        val b0: Double,
        val b1: Double,
        val b2: Double,
        val a1: Double,
        val a2: Double,
        val x1: Double,
        val x2: Double,
        val y1: Double,
        val y2: Double,
    )

    /** Passe-haut Butterworth ordre 2 (Q = 1/√2), forme directe I, coefficients normalisés. */
    fun start(sampleRate: Int): Accum {
        val q = sqrt(0.5)
        val w0 = 2.0 * PI * SPLIT_HZ / sampleRate.coerceAtLeast(1)
        val c = cos(w0)
        val alpha = sin(w0) / (2.0 * q)
        val a0 = 1.0 + alpha
        return Accum(
            sampleRate = sampleRate,
            frames = 0,
            sumSq = 0.0,
            sumSqHigh = 0.0,
            rawSamples = 0,
            clipped = 0,
            peak = 0,
            b0 = ((1.0 + c) / 2.0) / a0,
            b1 = (-(1.0 + c)) / a0,
            b2 = ((1.0 + c) / 2.0) / a0,
            a1 = (-2.0 * c) / a0,
            a2 = (1.0 - alpha) / a0,
            x1 = 0.0,
            x2 = 0.0,
            y1 = 0.0,
            y2 = 0.0,
        )
    }

    /**
     * Ajoute un tampon PCM 16 bits entrelacé. On mélange les voies d'une
     * même trame (la coupure de bande se voit sur le mélange) et on compte
     * la saturation sur CHAQUE échantillon.
     */
    fun push(acc: Accum, pcm: ShortArray, channels: Int): Accum {
        val ch = channels.coerceAtLeast(1)
        var frames = acc.frames
        var sumSq = acc.sumSq
        var sumSqHigh = acc.sumSqHigh
        var raw = acc.rawSamples
        var clipped = acc.clipped
        var peak = acc.peak
        var x1 = acc.x1
        var x2 = acc.x2
        var y1 = acc.y1
        var y2 = acc.y2
        var i = 0
        val limit = pcm.size - (pcm.size % ch)
        while (i < limit) {
            var mix = 0.0
            for (c in 0 until ch) {
                val s = pcm[i + c].toInt()
                val a = if (s < 0) -s else s
                if (a > peak) peak = a
                if (a >= CLIP_ABS) clipped++
                mix += s
                raw++
            }
            val x = (mix / ch) / 32768.0
            val y = acc.b0 * x + acc.b1 * x1 + acc.b2 * x2 - acc.a1 * y1 - acc.a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = y
            frames++
            if (frames > WARMUP_FRAMES) {
                sumSq += x * x
                sumSqHigh += y * y
            }
            i += ch
        }
        return acc.copy(
            frames = frames,
            sumSq = sumSq,
            sumSqHigh = sumSqHigh,
            rawSamples = raw,
            clipped = clipped,
            peak = peak,
            x1 = x1,
            x2 = x2,
            y1 = y1,
            y2 = y2,
        )
    }

    fun judge(acc: Accum): Judgement {
        val useful = (acc.frames - WARMUP_FRAMES).coerceAtLeast(0)
        val ratio = if (acc.sumSq <= 0.0) 0.0 else acc.sumSqHigh / acc.sumSq
        val clip = if (acc.rawSamples <= 0) 0.0 else acc.clipped.toDouble() / acc.rawSamples
        val band = when {
            acc.sampleRate < MIN_SAMPLE_RATE -> Band.RATE
            useful < MIN_FRAMES -> Band.SHORT
            acc.sumSq / useful < SILENCE_MEAN_SQUARE -> Band.SILENCE
            ratio >= WIDE_MIN_RATIO -> Band.WIDE
            ratio <= LOW_MAX_RATIO -> Band.LOW
            else -> Band.MID
        }
        return Judgement(
            band = band,
            highRatio = ratio,
            clippedFraction = clip,
            peak = acc.peak,
            frames = useful,
            sampleRate = acc.sampleRate,
        )
    }

    /** Enchaîne [start] + [push] + [judge]. Pratique pour les tests. */
    fun measure(pcm: ShortArray, sampleRate: Int, channels: Int = 1): Judgement {
        return judge(push(start(sampleRate), pcm, channels))
    }
}
