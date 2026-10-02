package com.manzilionellm.native_video_player.logic

import java.util.Locale
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * IMAGE STÉRÉO (02/10/2026) — hypothèse H3 : « la voix du centre s'annule ».
 *
 * Si une voie est en opposition de phase avec l'autre (G ≈ −D), tout ce qui
 * est au centre (la voix) disparaît dès que les deux voies se mélangent :
 * dans une enceinte mono, une barre de son, ou à l'oreille entre deux
 * haut-parleurs proches. Ça sonne « dans un trou », effet karaoké. Les
 * sondes de bande (énergie > 4 kHz) ne le voient pas : chaque voie seule
 * a toujours ses aigus.
 *
 * On mesure donc, sur la même fenêtre que le spectre :
 *   • la corrélation G/D (−1 = opposées, +1 = identiques, ~0 = stéréo large) ;
 *   • l'énergie de (G − D) rapportée à (G + D).
 *
 * Objet PUR, testé dans logic-test/. La sonde Android copie le PCM et
 * appelle [push] : rien n'est modifié.
 */
object StereoImage {

    /** Même fenêtre minimale que [AudioSpectrum]. */
    const val MIN_FRAMES: Int = AudioSpectrum.MIN_FRAMES

    /** En dessous : opposition de phase. Une vraie stéréo ne descend pas là. */
    const val INVERTED_MAX: Double = -0.5

    /** Au-dessus : la voix est au centre, stéréo normale d'une chaîne d'info. */
    const val CENTERED_MIN: Double = 0.9

    /** (G−D)² / (G+D)² sous lequel les deux voies sont la même (mono dupliqué). */
    const val IDENTICAL_SIDE_MAX: Double = 1e-4

    /** Énergie moyenne par trame sous laquelle on ne juge pas. */
    const val SILENCE_MEAN_SQUARE: Double = 1e-8

    enum class Verdict {
        /** Pas deux voies : rien à comparer. */
        NOT_STEREO,

        /** Pas assez d'échantillons. */
        SHORT,

        /** Presque rien dans les deux voies. */
        SILENCE,

        /** G = D : mono dupliqué (source mono, ou témoin). */
        IDENTICAL,

        /** Corrélation forte positive : voix au centre, stéréo normale. */
        CENTERED,

        /** Corrélation faible : stéréo large (musique, ambiance). */
        WIDE,

        /** Corrélation forte NÉGATIVE : opposition de phase, le centre s'annule. */
        INVERTED,
    }

    data class Accum(
        val channels: Int,
        val frames: Int,
        val sumLL: Double,
        val sumRR: Double,
        val sumLR: Double,
        val sumSide: Double,
        val sumMid: Double,
    )

    data class Judgement(
        val verdict: Verdict,
        /** Corrélation G/D, entre −1 et +1. 0 si non mesurable. */
        val correlation: Double,
        /** Énergie (G−D) / énergie (G+D). 0 si non mesurable. */
        val sideToMid: Double,
        val frames: Int,
    )

    fun start(channels: Int): Accum = Accum(channels, 0, 0.0, 0.0, 0.0, 0.0, 0.0)

    /** Ajoute un tampon PCM 16 bits entrelacé. Autre chose que 2 voies : inchangé. */
    fun push(acc: Accum, pcm: ShortArray, channels: Int): Accum {
        if (channels != 2 || acc.channels != 2) return acc
        var frames = acc.frames
        var ll = acc.sumLL
        var rr = acc.sumRR
        var lr = acc.sumLR
        var side = acc.sumSide
        var mid = acc.sumMid
        var i = 0
        val limit = pcm.size - (pcm.size % 2)
        while (i < limit) {
            val l = pcm[i] / 32768.0
            val r = pcm[i + 1] / 32768.0
            ll += l * l
            rr += r * r
            lr += l * r
            val s = l - r
            val m = l + r
            side += s * s
            mid += m * m
            frames++
            i += 2
        }
        return acc.copy(frames = frames, sumLL = ll, sumRR = rr, sumLR = lr, sumSide = side, sumMid = mid)
    }

    fun judge(acc: Accum): Judgement {
        if (acc.channels != 2) return Judgement(Verdict.NOT_STEREO, 0.0, 0.0, acc.frames)
        if (acc.frames < MIN_FRAMES) return Judgement(Verdict.SHORT, 0.0, 0.0, acc.frames)
        val energy = (acc.sumLL + acc.sumRR) / acc.frames
        if (energy < SILENCE_MEAN_SQUARE) return Judgement(Verdict.SILENCE, 0.0, 0.0, acc.frames)
        val denom = sqrt(acc.sumLL * acc.sumRR)
        val corr = if (denom <= 0.0) 0.0 else (acc.sumLR / denom).coerceIn(-1.0, 1.0)
        val sideToMid = if (acc.sumMid <= 0.0) {
            // Tout est dans (G−D) : opposition parfaite.
            if (acc.sumSide > 0.0) Double.MAX_VALUE else 0.0
        } else {
            acc.sumSide / acc.sumMid
        }
        val verdict = when {
            sideToMid <= IDENTICAL_SIDE_MAX -> Verdict.IDENTICAL
            corr <= INVERTED_MAX -> Verdict.INVERTED
            corr >= CENTERED_MIN -> Verdict.CENTERED
            else -> Verdict.WIDE
        }
        return Judgement(verdict, corr, sideToMid, acc.frames)
    }

    /** [start] + [push] + [judge], pour les tests. */
    fun measure(pcm: ShortArray, channels: Int): Judgement = judge(push(start(channels), pcm, channels))

    private fun corr(j: Judgement): String =
        String.format(Locale.FRANCE, "%+.2f", j.correlation)

    /** Texte court pour la ligne d'une sonde. */
    fun describe(j: Judgement): String = when (j.verdict) {
        Verdict.NOT_STEREO -> "stéréo : pas deux voies"
        Verdict.SHORT -> "stéréo : pas assez d'échantillons"
        Verdict.SILENCE -> "stéréo : signal trop faible"
        Verdict.IDENTICAL -> "stéréo : voies IDENTIQUES (mono dupliqué), corrélation ${corr(j)}"
        Verdict.CENTERED -> "stéréo : voix au centre, corrélation ${corr(j)} — normal"
        Verdict.WIDE -> "stéréo : large, corrélation ${corr(j)} — normal"
        Verdict.INVERTED -> "stéréo : OPPOSITION DE PHASE, corrélation ${corr(j)} — le centre (la voix) " +
            "s'annule au mélange : « dans un trou »"
    }

    /** Vrai si [after] est inversée alors que [before] ne l'était pas (et était jugeable). */
    fun inverts(before: Judgement?, after: Judgement?): Boolean {
        if (before == null || after == null) return false
        if (after.verdict != Verdict.INVERTED) return false
        return when (before.verdict) {
            Verdict.IDENTICAL, Verdict.CENTERED, Verdict.WIDE -> true
            else -> false
        }
    }

    /** Pour les tests : la corrélation est bien symétrique et bornée. */
    fun bounded(j: Judgement): Boolean = abs(j.correlation) <= 1.0
}
