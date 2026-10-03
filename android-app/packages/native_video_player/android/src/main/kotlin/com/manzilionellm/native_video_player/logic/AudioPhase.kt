package com.manzilionellm.native_video_player.logic

import java.util.Locale
import kotlin.math.sqrt

/**
 * CORRÉLATION GAUCHE / DROITE (02/10/2026, précisé le 03/10).
 *
 * Le son « dans un trou » peut être une voix au centre annulée : la
 * voie droite est l'inverse de la gauche (G ≈ −D). Le rapport d'énergie
 * au-dessus de 4 kHz ne voit pas ça : les deux voies ont les mêmes
 * aigus, le mélange les additionne et la voix disparaît.
 *
 * Sur une seconde de PCM copié (le son qui sort n'est pas modifié) :
 *   • corrélation de Pearson entre G et D, de −1 à +1 ;
 *   • énergie de (G−D) divisée par l'énergie de (G+D) ;
 *   • le niveau (G−D)/(G+D) est la racine de ce rapport (0 si les
 *     voies sont les mêmes, infini si elles sont l'inverse exact) ;
 *   • part d'énergie qu'un mélange mono (G+D)/2 garderait. C'est le
 *     haut-parleur unique et le Bluetooth d'appel. 0 = voix effacée.
 *
 * Proche de +1 : les deux voies disent la même chose, le mélange mono
 * garde la voix. Proche de −1 et mélange mono presque vide : elles
 * s'opposent, un haut-parleur mono annule la voix du centre. Un casque
 * stéréo, lui, joue chaque voie : la voix reste dans chaque oreille.
 *
 * Pur Kotlin. La sonde Android ne fait qu'appeler [push] puis [judge].
 * Aucun échantillon n'est réécrit.
 */
object AudioPhase {

    /** En dessous, on dit que les voies s'opposent (G ≈ −D). */
    const val INVERT_MAX: Double = -0.70

    /** (G−D)² / (G+D)² à partir duquel l'opposition est nette. */
    const val SIDE_MIN: Double = 1.0

    /**
     * En dessous, le mélange mono a effacé la voix : il reste moins de
     * 5 % de l'énergie de la voie la plus forte (−13 dB). Au-dessus,
     * la corrélation peut être négative sans que la voix disparaisse
     * (une voie inverse mais beaucoup plus faible, par exemple).
     */
    const val CANCEL_MAX: Double = 0.05

    /** Moins que ça, un chiffre de corrélation ne veut rien dire. */
    const val MIN_FRAMES: Int = 1_000

    data class Accum(
        val frames: Int = 0,
        val sumL: Double = 0.0,
        val sumR: Double = 0.0,
        val sumLL: Double = 0.0,
        val sumRR: Double = 0.0,
        val sumLR: Double = 0.0,
        val sumSide: Double = 0.0,
        val sumMid: Double = 0.0,
    )

    data class Reading(
        val correlation: Double,
        val sideToMid: Double,
        val frames: Int,
        val channels: Int,
        /** Deux voies, assez de son, corrélation très négative. */
        val opposed: Boolean,
        /**
         * Énergie de (G+D)/2 divisée par l'énergie de la voie la plus
         * forte. 0 = le mélange mono efface le son. 1 = il le garde.
         * NaN = silence, ou une seule voie.
         */
        val monoKept: Double = Double.NaN,
        /**
         * Vrai seulement en stéréo, quand [opposed] est vrai ET que le
         * mélange mono tombe sous [CANCEL_MAX]. Sur 6 voies on ne le
         * dit pas : la voix peut être au centre, que cette mesure ne
         * regarde pas.
         */
        val cancelled: Boolean = false,
    ) {
        fun correlationText(): String = when {
            correlation.isNaN() -> "illisible"
            else -> String.format(Locale.FRANCE, "%+.2f", correlation)
        }

        fun sideText(): String = when {
            sideToMid.isNaN() -> "illisible"
            sideToMid.isInfinite() -> "infini"
            else -> String.format(Locale.FRANCE, "%.2f", sideToMid)
        }

        /** (G−D)/(G+D) sur la seconde. Infini quand G = −D. */
        fun level(): Double = when {
            sideToMid.isNaN() -> Double.NaN
            sideToMid.isInfinite() -> Double.POSITIVE_INFINITY
            else -> sqrt(sideToMid)
        }

        fun levelText(): String {
            val v = level()
            return when {
                v.isNaN() -> "illisible"
                v.isInfinite() -> "infini"
                else -> String.format(Locale.FRANCE, "%.2f", v)
            }
        }

        fun monoKeptText(): String = when {
            monoKept.isNaN() -> "illisible"
            else -> String.format(Locale.FRANCE, "%.0f %%", monoKept * 100.0)
        }
    }

    fun start(): Accum = Accum()

    /** Une seconde de son, à la fréquence du PCM. */
    fun windowFrames(sampleRate: Int): Int = sampleRate.coerceAtLeast(8_000)

    fun ready(acc: Accum, sampleRate: Int): Boolean = acc.frames >= windowFrames(sampleRate)

    /**
     * Ajoute un tampon entrelacé. Mono : on compte les trames, sans
     * inventer une deuxième voie. Plus de deux voies : gauche = première,
     * droite = deuxième (le centre et le caisson ne sont pas mélangés ici).
     */
    fun push(acc: Accum, pcm: ShortArray, channels: Int): Accum {
        val ch = channels.coerceAtLeast(1)
        val framesAvail = pcm.size / ch
        if (framesAvail <= 0) return acc
        if (ch < 2) return acc.copy(frames = acc.frames + framesAvail)
        var frames = acc.frames
        var sumL = acc.sumL
        var sumR = acc.sumR
        var sumLL = acc.sumLL
        var sumRR = acc.sumRR
        var sumLR = acc.sumLR
        var sumSide = acc.sumSide
        var sumMid = acc.sumMid
        var i = 0
        val limit = framesAvail * ch
        while (i < limit) {
            val l = pcm[i].toDouble()
            val r = pcm[i + 1].toDouble()
            sumL += l
            sumR += r
            sumLL += l * l
            sumRR += r * r
            sumLR += l * r
            val side = l - r
            val mid = l + r
            sumSide += side * side
            sumMid += mid * mid
            frames++
            i += ch
        }
        return Accum(frames, sumL, sumR, sumLL, sumRR, sumLR, sumSide, sumMid)
    }

    fun judge(acc: Accum, channels: Int): Reading {
        val ch = channels.coerceAtLeast(1)
        if (ch < 2 || acc.frames < MIN_FRAMES) {
            return Reading(
                Double.NaN, Double.NaN, acc.frames, ch,
                opposed = false, monoKept = Double.NaN, cancelled = false,
            )
        }
        val n = acc.frames.toDouble()
        val meanL = acc.sumL / n
        val meanR = acc.sumR / n
        val varL = acc.sumLL - n * meanL * meanL
        val varR = acc.sumRR - n * meanR * meanR
        val cov = acc.sumLR - n * meanL * meanR
        val corr = if (varL <= 1e-6 || varR <= 1e-6) {
            Double.NaN
        } else {
            (cov / sqrt(varL * varR)).coerceIn(-1.0, 1.0)
        }
        val side = when {
            acc.sumMid <= 1e-6 && acc.sumSide <= 1e-6 -> 0.0
            acc.sumMid <= 1e-6 -> Double.POSITIVE_INFINITY
            else -> acc.sumSide / acc.sumMid
        }
        val louder = maxOf(acc.sumLL, acc.sumRR)
        // (G+D)/2 au carré, sommé : sum((G+D)²) / 4.
        val monoKept = if (louder <= 1e-6) Double.NaN else (acc.sumMid / 4.0) / louder
        val opposed = !corr.isNaN() && corr <= INVERT_MAX &&
            (side.isInfinite() || side >= SIDE_MIN)
        // Stéréo seulement. Sur 5.1 la voix du film est souvent au centre
        // (3e voie) : G et D peuvent s'opposer sans effacer le dialogue.
        val cancelled = ch == 2 && opposed && !monoKept.isNaN() && monoKept <= CANCEL_MAX
        return Reading(corr, side, acc.frames, ch, opposed, monoKept, cancelled)
    }
}
