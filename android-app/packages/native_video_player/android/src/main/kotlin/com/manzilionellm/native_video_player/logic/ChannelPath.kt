package com.manzilionellm.native_video_player.logic

import java.util.Locale
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * PHASE ET CANAUX (03/10/2026).
 *
 * Le son « dans un trou » peut arriver sans qu'aucun passe-bas n'existe :
 * la voix (souvent au centre, donc présente pareil à gauche et à droite)
 * s'annule quand on additionne les deux voies. Un téléphone et beaucoup
 * de téléviseurs additionnent. Le rapport d'énergie au-dessus de 4 kHz
 * ne voit pas ça.
 *
 * Cette classe ne change pas le lecteur. Elle décrit le chemin réel des
 * voies, et elle mesure un PCM de test. Personne ne l'appelle pendant
 * la lecture : les sondes restent celles d'[AudioPhase], coupées par
 * défaut.
 *
 * Chemin réel, lu dans Media3 1.5.1 (pas rejoué sur une box) :
 *
 * 1. Décodeur FFmpeg (`ffmpeg_jni.cc`) : le `SwrContext` garde le même
 *    nombre de voies et la même fréquence. Il passe du flottant planaire
 *    au 16 bits entrelacé. Il n'inverse pas une voie, il ne mélange pas
 *    un 5.1 vers la stéréo.
 * 2. `FfmpegAudioRenderer` ne redéfinit pas `getChannelMapping` :
 *    `DecoderAudioRenderer` envoie `null`. `ChannelMappingAudioProcessor`
 *    reste alors inactif (NOT_SET).
 * 3. Le décodeur de la box (`MediaCodecAudioRenderer`) ne pose un masque
 *    que dans deux cas, aucun des deux n'est l'AAC d'une box récente :
 *    le vieux Samsung S6/S7 (`OMX.SEC.aac.dec`, Android avant la version
 *    7) qui sort 6 voies pour un flux qui en annonce moins — on GARDE
 *    les premières voies et on JETTE le reste, sans les mélanger ;
 *    et un réordre Vorbis/Opus, pas AAC.
 * 4. Zuno n'ajoute pas de `ChannelMixingAudioProcessor`. Pas de downmix
 *    dans l'app. L'AudioTrack reçoit le nombre de voies du décodeur.
 * 5. [AudioPhase] lit la voie 0 et la voie 1. Le centre (voie 3 d'un
 *    5.1, index 2) n'entre pas dans la corrélation.
 *
 * Donc, pour un AAC-LC annoncé 2 voies et décodé 2 voies, le chemin
 * Zuno est l'identité : les échantillons sortent comme le décodeur les
 * a donnés.
 */
object ChannelPath {

    /** Bande où se tient une voix parlée, en hertz. */
    const val VOIX_BAS_HZ: Double = 300.0
    const val VOIX_HAUT_HZ: Double = 3_000.0

    /** En dessous, une corrélation ne veut rien dire (même seuil que [AudioPhase]). */
    const val MIN_FRAMES: Int = 1_000

    /**
     * Un bin de la bande de voix est « annulé » quand l'énergie de la
     * somme (G+D)/2 est au moins 12 dB sous la moyenne des deux voies.
     * 0,25 en amplitude = −12 dB.
     */
    const val SEUIL_ANNULATION: Double = 0.25

    /**
     * Part de bins annulés à partir de laquelle la somme est creuse.
     * Mesuré sur les signaux du banc : retard 2 ms → 0,16 ; retard
     * d'une trame AAC → 0,18 ; milieu/écart joué tel quel → 0,41 ;
     * deux voix différentes sans opposition → 0,00. Le seuil 0,12
     * est entre les deux.
     */
    const val CREUX_PARTIEL: Double = 0.12

    /** Part de bins annulés d'une opposition franche (presque toute la voix). */
    const val CREUX_PHASE: Double = 0.50

    /** Taille de la fenêtre d'analyse (puissance de deux). 8192 / 48 kHz ≈ 171 ms. */
    const val FFT: Int = 8_192

    /**
     * Ce qu'on entend quand les deux voies sont ensuite additionnées
     * (haut-parleur de téléphone, TV qui mélange). Ce n'est pas une
     * oreille : c'est un classement de chiffres.
     */
    enum class Effet {
        /** Les deux voies sont d'accord, ou une seule porte le son. */
        PAS_UN_TROU,

        /** G ≈ −D. La voix du milieu disparaît dans la somme. */
        TROU_PHASE,

        /**
         * Une partie de la voix s'annule dans la somme, sans que les
         * voies soient l'inverse l'une de l'autre. Mesuré : un retard
         * de 2 ms ou d'une trame AAC (1 024 échantillons) entre les
         * voies, et un couple milieu/écart joué comme gauche/droite.
         */
        TROU_CREUX,

        /**
         * Deux programmes différents (deux langues, ou le milieu d'un
         * côté et l'écart de l'autre). On les entend se battre. Ce n'est
         * pas une annulation : la somme garde les deux.
         */
        DEUX_PROGRAMMES,
    }

    data class Mesure(
        val correlation: Double,
        /** Énergie (G−D)² / (G+D)². Déjà calculée par [AudioPhase]. */
        val energieCote: Double,
        /** Niveau RMS(G−D) / RMS(G+D). */
        val niveau: Double,
        /** Énergie 300 Hz – 3 kHz / énergie totale, voie gauche. */
        val partVoixGauche: Double,
        val partVoixDroite: Double,
        /** La même part, sur (G+D)/2. */
        val partVoixSomme: Double,
        /**
         * Énergie de voix de (G+D)/2 divisée par celle de la gauche.
         * Proche de 1 : la somme garde la voix. Proche de 0 : elle l'a perdue.
         * Une droite muette donne environ 0,25 (la somme est G/2) : ce n'est
         * qu'un volume, pas un trou.
         */
        val gardeVoix: Double,
        /** Part des bins 300 Hz – 3 kHz où la somme est annulée. */
        val creuxInter: Double,
        val effet: Effet,
        val raison: String,
    ) {
        fun ligne(nom: String): String {
            return String.format(
                Locale.FRANCE,
                "%-28s  corr %s  niveau %s  garde-voix %s  creux %s  %s",
                nom,
                nombre(correlation),
                nombre(niveau),
                nombre(gardeVoix),
                nombre(creuxInter),
                effet.name,
            )
        }

        private fun nombre(v: Double): String = when {
            v.isNaN() -> "    illisible"
            v.isInfinite() -> "      infini"
            else -> String.format(Locale.FRANCE, "%12.4f", v)
        }
    }

    /**
     * Copie. C'est le chemin Zuno pour un AAC stéréo : aucune voie
     * réordonnée, aucune inversée, aucun gain.
     */
    fun identite(pcm: ShortArray): ShortArray = pcm.copyOf()

    /**
     * Masque de Media3 quand il jette des voies au lieu de les mélanger :
     * la sortie i reçoit l'entrée i. Le centre d'un 5.1 (index 2) n'est
     * pas dans les deux premières.
     */
    fun garderPremieres(pcm: ShortArray, canaux: Int, garder: Int): ShortArray {
        val ch = canaux.coerceAtLeast(1)
        val outCh = garder.coerceIn(1, ch)
        val frames = pcm.size / ch
        val out = ShortArray(frames * outCh)
        for (frame in 0 until frames) {
            for (c in 0 until outCh) {
                out[frame * outCh + c] = pcm[frame * ch + c]
            }
        }
        return out
    }

    /**
     * Downmix stéréo ITU-R BS.775, ordre FFmpeg / Android d'un 5.1 :
     * L, R, C, LFE, Ls, Rs. Le centre est gardé à −3 dB (0,707).
     * Le caisson est jeté. Ce n'est PAS le chemin de Zuno : Zuno ne
     * mélange pas. Sert de témoin pour dire ce qu'une autre app peut
     * faire, et ce que le masque « premières voies » rate.
     */
    fun ituStereo(pcm: ShortArray, canaux: Int): ShortArray {
        require(canaux == 6) { "Le témoin ITU de ce banc est écrit pour un 5.1 (6 voies)." }
        val frames = pcm.size / 6
        val out = ShortArray(frames * 2)
        val cGain = 0.707
        for (frame in 0 until frames) {
            val base = frame * 6
            val l = pcm[base].toDouble()
            val r = pcm[base + 1].toDouble()
            val c = pcm[base + 2].toDouble()
            val ls = pcm[base + 4].toDouble()
            val rs = pcm[base + 5].toDouble()
            out[frame * 2] = sature(l + cGain * c + cGain * ls)
            out[frame * 2 + 1] = sature(r + cGain * c + cGain * rs)
        }
        return out
    }

    /**
     * Échange le centre (index 2) et le caisson (index 3). Beaucoup de
     * downmix jettent ensuite le caisson : la voix, si elle était au
     * centre, part avec lui.
     */
    fun echangerCentreEtCaisson(pcm: ShortArray, canaux: Int): ShortArray {
        require(canaux >= 4)
        val out = pcm.copyOf()
        val frames = pcm.size / canaux
        for (frame in 0 until frames) {
            val base = frame * canaux
            val centre = out[base + 2]
            out[base + 2] = out[base + 3]
            out[base + 3] = centre
        }
        return out
    }

    /**
     * Ordre des éléments AAC 5.1 (ISO 14496-3, config 6) : C, L, R, Ls, Rs, LFE.
     * L'ordre FFmpeg et l'ordre Android `CHANNEL_OUT_5POINT1` sont :
     * L, R, C, LFE, Ls, Rs. Si un décodeur oublie le réordre, le tampon
     * est dans l'ordre des éléments alors que le lecteur le croit dans
     * l'ordre FFmpeg. On fabrique ce tampon faux à partir d'un 5.1 juste.
     */
    fun ordreElementsAac(ffmpeg: ShortArray): ShortArray {
        val frames = ffmpeg.size / 6
        val out = ShortArray(frames * 6)
        for (frame in 0 until frames) {
            val i = frame * 6
            val l = ffmpeg[i]
            val r = ffmpeg[i + 1]
            val c = ffmpeg[i + 2]
            val lfe = ffmpeg[i + 3]
            val ls = ffmpeg[i + 4]
            val rs = ffmpeg[i + 5]
            out[i] = c
            out[i + 1] = l
            out[i + 2] = r
            out[i + 3] = ls
            out[i + 4] = rs
            out[i + 5] = lfe
        }
        return out
    }

    /**
     * Un décodeur planaire écrit LLLL…RRRR. Si on lit ça comme de
     * l'entrelacé G,D,G,D, les paires sont deux échantillons gauches
     * de suite, puis plus loin deux échantillons droits.
     */
    fun planaireLuCommeEntrelace(gauche: ShortArray, droite: ShortArray): ShortArray {
        val n = minOf(gauche.size, droite.size)
        val planar = ShortArray(n * 2)
        for (i in 0 until n) {
            planar[i] = gauche[i]
            planar[n + i] = droite[i]
        }
        return planar
    }

    /**
     * Mesure les deux premières voies, comme la sonde. [canaux] est le
     * nombre de voies du tampon entrelacé.
     */
    fun mesurer(pcm: ShortArray, canaux: Int, sampleRate: Int = 48_000): Mesure {
        val phase = AudioPhase.judge(AudioPhase.push(AudioPhase.start(), pcm, canaux), canaux)
        val g = extraire(pcm, canaux, 0)
        val d = if (canaux >= 2) extraire(pcm, canaux, 1) else DoubleArray(g.size)
        val somme = DoubleArray(g.size) { i -> (g[i] + d[i]) / 2.0 }
        val partG = partVoix(g, sampleRate)
        val partD = partVoix(d, sampleRate)
        val partS = partVoix(somme, sampleRate)
        val eG = energieVoix(g, sampleRate)
        val eS = energieVoix(somme, sampleRate)
        val garde = if (eG <= 1e-12) Double.NaN else eS / eG
        val creux = creuxInter(g, d, sampleRate)
        val (effet, raison) = classer(
            correlation = phase.correlation,
            niveau = phase.levelRatio,
            creux = creux,
            energieG = energie(g),
            energieD = energie(d),
        )
        return Mesure(
            correlation = phase.correlation,
            energieCote = phase.sideToMid,
            niveau = phase.levelRatio,
            partVoixGauche = partG,
            partVoixDroite = partD,
            partVoixSomme = partS,
            gardeVoix = garde,
            creuxInter = creux,
            effet = effet,
            raison = raison,
        )
    }

    /**
     * La voix du centre a-t-elle survécu au passage en stéréo ?
     * [voixSortie] et [voixTemoin] sont des énergies de bande (pas des
     * parts). Le témoin est le downmix qui garde le centre.
     */
    fun centrePerdu(voixSortie: Double, voixTemoin: Double): Boolean {
        if (voixTemoin <= 1e-12) return false
        // 0,40 : le banc mesure ~0,03 quand on ne garde que L et R d'un 5.1
        // dont la voix est au centre, et bien moins de 0,40 quand le centre
        // a été mis à la place du caisson puis jeté. Un downmix qui garde
        // le centre reste à 1.
        return voixSortie < 0.40 * voixTemoin
    }

    /** Énergie de la bande 300 Hz – 3 kHz sur une voie d'un tampon entrelacé. */
    fun energieVoixCanal(pcm: ShortArray, canaux: Int, canal: Int, sampleRate: Int = 48_000): Double {
        return energieVoix(extraire(pcm, canaux, canal), sampleRate)
    }

    fun classer(
        correlation: Double,
        niveau: Double,
        creux: Double,
        energieG: Double,
        energieD: Double,
    ): Pair<Effet, String> {
        val deux = energieG > 1e-4 && energieD > 1e-4
        if (deux && !correlation.isNaN() && correlation <= AudioPhase.INVERT_MAX && creux >= CREUX_PHASE) {
            return Effet.TROU_PHASE to
                "Les voies s'opposent (corrélation $correlation). Dans la somme, " +
                "la bande de voix est annulée sur ${pct(creux)} des fréquences. " +
                "Un haut-parleur qui additionne G et D entend un trou."
        }
        if (deux && !correlation.isNaN() && correlation > AudioPhase.INVERT_MAX &&
            creux >= CREUX_PARTIEL && (niveau.isInfinite() || niveau >= 0.35)
        ) {
            return Effet.TROU_CREUX to
                "Les voies ne sont pas l'inverse l'une de l'autre, mais ${pct(creux)} de la " +
                "bande de voix s'annule dans la somme. Un retard entre la gauche et la droite " +
                "fait ça (son creux, « dans un trou »). Le milieu et l'écart d'un couple, " +
                "joués comme s'ils étaient la gauche et la droite, le font aussi : un des " +
                "deux programmes disparaît dans la somme, et en stéréo on entend deux sons."
        }
        if (deux && creux < CREUX_PARTIEL && (correlation.isNaN() || abs(correlation) < 0.35)) {
            return Effet.DEUX_PROGRAMMES to
                "Les deux voies portent du son, elles ne se ressemblent pas " +
                "(corrélation $correlation), et la somme ne les annule presque pas. " +
                "On entend deux programmes en même temps, pas une voix effacée."
        }
        return Effet.PAS_UN_TROU to
            "La somme garde la voix, ou une seule voie porte le son. " +
            "Ce cas ne reproduit pas le trou par les canaux."
    }

    private fun pct(part: Double): String = String.format(Locale.FRANCE, "%.0f %%", part * 100.0)

    private fun extraire(pcm: ShortArray, canaux: Int, canal: Int): DoubleArray {
        val ch = canaux.coerceAtLeast(1)
        val frames = pcm.size / ch
        val out = DoubleArray(frames)
        if (canal !in 0 until ch) return out
        for (i in 0 until frames) out[i] = pcm[i * ch + canal].toDouble()
        return out
    }

    private fun energie(x: DoubleArray): Double {
        var s = 0.0
        for (v in x) s += v * v
        return s
    }

    /** Part de l'énergie qui tombe dans 300 Hz – 3 kHz. Silence → NaN. */
    private fun partVoix(x: DoubleArray, rate: Int): Double {
        val total = energie(x)
        if (total <= 1e-6) return Double.NaN
        return energieVoix(x, rate) / total
    }

    /**
     * Énergie après un passe-haut à 300 Hz puis un passe-bas à 3 kHz
     * (Butterworth ordre 2, deux fois de suite pour un flanc plus net).
     * Les 512 premiers échantillons, le temps que le filtre se cale,
     * ne comptent pas.
     */
    fun energieVoix(x: DoubleArray, rate: Int): Double {
        if (x.size <= 512) return 0.0
        val hp = butterworth(rate, VOIX_BAS_HZ, passeHaut = true)
        val lp = butterworth(rate, VOIX_HAUT_HZ, passeHaut = false)
        val y = filtrer(filtrer(filtrer(filtrer(x, hp), hp), lp), lp)
        var s = 0.0
        for (i in 512 until y.size) s += y[i] * y[i]
        return s
    }

    private data class Biquad(val b0: Double, val b1: Double, val b2: Double, val a1: Double, val a2: Double)

    private fun butterworth(rate: Int, coupe: Double, passeHaut: Boolean): Biquad {
        val q = sqrt(0.5)
        val w0 = 2.0 * PI * coupe / rate.coerceAtLeast(1)
        val c = cos(w0)
        val alpha = sin(w0) / (2.0 * q)
        val a0 = 1.0 + alpha
        val b0: Double
        val b1: Double
        val b2: Double
        if (passeHaut) {
            b0 = ((1.0 + c) / 2.0) / a0
            b1 = (-(1.0 + c)) / a0
            b2 = ((1.0 + c) / 2.0) / a0
        } else {
            b0 = ((1.0 - c) / 2.0) / a0
            b1 = (1.0 - c) / a0
            b2 = ((1.0 - c) / 2.0) / a0
        }
        return Biquad(b0, b1, b2, (-2.0 * c) / a0, (1.0 - alpha) / a0)
    }

    private fun filtrer(x: DoubleArray, q: Biquad): DoubleArray {
        val y = DoubleArray(x.size)
        var x1 = 0.0
        var x2 = 0.0
        var y1 = 0.0
        var y2 = 0.0
        for (i in x.indices) {
            val xn = x[i]
            val yn = q.b0 * xn + q.b1 * x1 + q.b2 * x2 - q.a1 * y1 - q.a2 * y2
            x2 = x1
            x1 = xn
            y2 = y1
            y1 = yn
            y[i] = yn
        }
        return y
    }

    /**
     * Part des bins de voix où |(G+D)/2| est très en dessous de la
     * moyenne des deux spectres. Une voix naturelle a des creux de
     * formants, mais ils sont dans les deux voies : la somme les garde.
     * Seule une opposition entre les voies allume ce chiffre.
     */
    fun creuxInter(gauche: DoubleArray, droite: DoubleArray, rate: Int): Double {
        val n = minOf(gauche.size, droite.size)
        if (n < FFT) return Double.NaN
        val start = (n - FFT) / 2
        val g = fenetre(gauche, start)
        val d = fenetre(droite, start)
        val s = DoubleArray(FFT) { i -> (g[i] + d[i]) / 2.0 }
        val magG = fftMagnitude(g)
        val magD = fftMagnitude(d)
        val magS = fftMagnitude(s)
        val binBas = (VOIX_BAS_HZ * FFT / rate).toInt().coerceIn(1, FFT / 2 - 1)
        val binHaut = (VOIX_HAUT_HZ * FFT / rate).toInt().coerceIn(binBas + 1, FFT / 2)
        var peak = 0.0
        for (k in binBas until binHaut) {
            val m = magG[k] + magD[k]
            if (m > peak) peak = m
        }
        if (peak <= 1e-9) return 0.0
        val plancher = 0.02 * peak
        var utiles = 0
        var annules = 0
        for (k in binBas until binHaut) {
            val ref = (magG[k] + magD[k]) / 2.0
            if (ref < plancher) continue
            utiles++
            if (magS[k] < SEUIL_ANNULATION * ref) annules++
        }
        if (utiles == 0) return 0.0
        return annules.toDouble() / utiles
    }

    private fun fenetre(x: DoubleArray, start: Int): DoubleArray {
        val out = DoubleArray(FFT)
        for (i in 0 until FFT) {
            val hann = 0.5 * (1.0 - cos(2.0 * PI * i / (FFT - 1)))
            out[i] = x[start + i] * hann
        }
        return out
    }

    /** Module de la FFT réelle (moitié utile). Fenêtre déjà appliquée. */
    private fun fftMagnitude(x: DoubleArray): DoubleArray {
        val n = x.size
        val re = x.copyOf()
        val im = DoubleArray(n)
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
            }
        }
        var len = 2
        while (len <= n) {
            val ang = -2.0 * PI / len
            val wlenRe = cos(ang)
            val wlenIm = sin(ang)
            var i = 0
            while (i < n) {
                var wRe = 1.0
                var wIm = 0.0
                for (k in 0 until len / 2) {
                    val ur = re[i + k]
                    val ui = im[i + k]
                    val vr = re[i + k + len / 2] * wRe - im[i + k + len / 2] * wIm
                    val vi = re[i + k + len / 2] * wIm + im[i + k + len / 2] * wRe
                    re[i + k] = ur + vr
                    im[i + k] = ui + vi
                    re[i + k + len / 2] = ur - vr
                    im[i + k + len / 2] = ui - vi
                    val nwRe = wRe * wlenRe - wIm * wlenIm
                    wIm = wRe * wlenIm + wIm * wlenRe
                    wRe = nwRe
                }
                i += len
            }
            len = len shl 1
        }
        return DoubleArray(n / 2) { i -> sqrt(re[i] * re[i] + im[i] * im[i]) }
    }

    private fun sature(v: Double): Short {
        val n = v.toInt()
        return when {
            n > 32767 -> 32767
            n < -32768 -> -32768
            else -> n.toShort()
        }
    }
}
