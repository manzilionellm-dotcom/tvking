package com.manzilionellm.native_video_player.logic

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin

/**
 * VOIES, POLARITÉ, MÉLANGE MONO (03/10/2026).
 *
 * On fabrique des PCM de test et on calcule ce qu'un mélange en ferait.
 * Rien n'est branché sur le lecteur : le son par défaut ne change pas,
 * aucun interrupteur n'est ajouté.
 *
 * Lu dans les sources, pas rejoué sur le téléphone ni sur la box :
 *
 * 1. Media3 1.5.1, `ChannelMappingAudioProcessor`. Il recopie des
 *    échantillons selon une carte d'indices. Pas de signe moins. Carte
 *    null → `onConfigure` renvoie NOT_SET, le processeur est absent.
 *    Zuno ne donne pas de carte : `DecoderAudioRenderer.getChannelMapping`
 *    renvoie null, et le contournement Vorbis ne concerne pas l'AAC.
 * 2. Media3 1.5.1, `ChannelMixingMatrix.create(2, 1)` = `[0,5  0,5]`.
 *    Le constructeur refuse un coefficient négatif. Zuno n'ajoute pas
 *    de `ChannelMixingAudioProcessor` (`NativeVideoView.buildAudioSink`).
 * 3. Media3 1.5.1, `DefaultAudioSink.configure` : avant la chaîne de
 *    l'app, ToInt16, puis le mapping, puis le trim. ToInt16 ne change
 *    pas une voie par rapport à l'autre. Le trim enlève un délai, pas
 *    une polarité.
 * 4. `ffmpeg_jni.cc` (Media3 1.5.1) : le `SwrContext` a la MÊME
 *    disposition de voies en entrée et en sortie, et le format de
 *    sortie est `AV_SAMPLE_FMT_S16` (16 bits entrelacé : G, D, G, D).
 *    Le décodeur AAC de FFmpeg, lui, sort du flottant planaire
 *    (toutes les gauches, puis toutes les droites). Ce planaire
 *    n'arrive pas à la sonde : swr l'entrelace avant. Le `.so` Jellyfin
 *    de la box n'a pas été exécuté ici.
 * 5. `c2.android.aac.decoder` écrit déjà du PCM 16 bits entrelacé.
 *    `MediaCodecAudioRenderer` ne pose une carte que pour jeter des
 *    voies en trop (indices 0, 1, 2… dans l'ordre) ou pour le Vorbis.
 *    Pas d'inversion.
 *
 * Conséquence pour une stéréo AAC-LC : aucun étage de Zuno n'inverse
 * une voie tant que les sondes, la voix claire, le saut de silence et
 * Sonic sont inactifs (leur défaut). Une opposition mesurée à la sonde
 * décodeur est déjà dans le PCM du décodeur.
 */
object AudioChannels {

    const val RATE: Int = 48_000

    /** `ChannelMixingMatrix.create(2, 1)` dans Media3 1.5.1. */
    const val FOLD_LEFT: Double = 0.5
    const val FOLD_RIGHT: Double = 0.5

    /**
     * Voix synthétique, une seconde à 48 kHz.
     * Fondamentale 140 Hz, harmoniques jusqu'à 3,2 kHz (rien au-dessus :
     * une vraie voix est pauvre après 4 kHz), enveloppe lente.
     * Valeur entre −1 et 1.
     */
    fun voice(frame: Int, rate: Int = RATE): Double {
        val raw = voiceRaw(frame, rate)
        val peak = if (rate == RATE) voicePeak48k else peakOf(rate)
        return if (peak <= 0.0) 0.0 else raw / peak
    }

    /**
     * Stéréo entrelacée. [left] et [right] sont entre −1 et 1.
     * [gain] 1 reste sous le plafond. [gain] 8 sature : on écrête à
     * ±32767 (on évite −32768, dont l'opposé ne tient pas dans un Short).
     */
    fun stereo(
        frames: Int,
        gain: Double = 1.0,
        left: (Int) -> Double,
        right: (Int) -> Double,
    ): ShortArray {
        val pcm = ShortArray(frames * 2)
        for (i in 0 until frames) {
            pcm[i * 2] = quantize(left(i), gain)
            pcm[i * 2 + 1] = quantize(right(i), gain)
        }
        return pcm
    }

    /** Mono dupliqué : D = G. La voix est la même des deux côtés. */
    fun duplicatedMono(frames: Int, gain: Double = 0.55, sample: (Int) -> Double = ::voice): ShortArray =
        stereo(frames, gain, left = sample, right = sample)

    /** Opposition : D = −G. La voix du centre s'annule dans un mélange. */
    fun opposed(frames: Int, gain: Double = 0.55, sample: (Int) -> Double = ::voice): ShortArray =
        stereo(frames, gain, left = sample, right = { -sample(it) })

    fun silence(frames: Int, channels: Int = 2): ShortArray = ShortArray(frames * channels)

    /**
     * Mélange deux voies : cG·G + cD·D, ramené à un Short.
     * Le défaut est le repli stéréo → mono de Media3 (0,5 et 0,5).
     * Un Bluetooth d'appel ou un haut-parleur unique fait ce repli.
     * Un casque stéréo ne le fait pas : chaque oreille garde sa voie.
     */
    fun fold(
        pcm: ShortArray,
        channels: Int = 2,
        leftCoef: Double = FOLD_LEFT,
        rightCoef: Double = FOLD_RIGHT,
    ): ShortArray {
        val frames = pcm.size / channels
        val out = ShortArray(frames)
        for (i in 0 until frames) {
            val l = pcm[i * channels].toDouble()
            val r = pcm[i * channels + 1].toDouble()
            val m = leftCoef * l + rightCoef * r
            out[i] = m.toInt().coerceIn(-32768, 32767).toShort()
        }
        return out
    }

    /**
     * Énergie du mélange / énergie de la voie la plus forte.
     * 0 = la voix a disparu. 1 = elle est entière (mono dupliqué,
     * coefficients 0,5 et 0,5). NaN = silence.
     */
    fun monoKept(
        pcm: ShortArray,
        channels: Int = 2,
        leftCoef: Double = FOLD_LEFT,
        rightCoef: Double = FOLD_RIGHT,
    ): Double {
        val frames = pcm.size / channels
        var eMix = 0.0
        var eL = 0.0
        var eR = 0.0
        for (i in 0 until frames) {
            val l = pcm[i * channels].toDouble()
            val r = pcm[i * channels + 1].toDouble()
            val m = leftCoef * l + rightCoef * r
            eMix += m * m
            eL += l * l
            eR += r * r
        }
        val louder = maxOf(eL, eR)
        if (louder <= 1e-6) return Double.NaN
        return eMix / louder
    }

    /**
     * Repli qui garde aussi le centre (3e voie, index 2).
     * Coefficients indicatifs, pas ceux d'une puce : 0,5 G + 0,5 D + 0,7 C.
     * Sert à montrer qu'une sonde qui ne regarde que G et D peut crier
     * « annulé » alors que le dialogue, lui, est au centre.
     */
    fun monoKeptWithCenter(pcm: ShortArray, channels: Int): Double {
        require(channels >= 3)
        val frames = pcm.size / channels
        var eMix = 0.0
        var eC = 0.0
        for (i in 0 until frames) {
            val base = i * channels
            val l = pcm[base].toDouble()
            val r = pcm[base + 1].toDouble()
            val c = pcm[base + 2].toDouble()
            val m = 0.5 * l + 0.5 * r + 0.7 * c
            eMix += m * m
            eC += c * c
        }
        if (eC <= 1e-6) return Double.NaN
        return eMix / eC
    }

    /**
     * Deux plans (toute la gauche, puis toute la droite) relus comme
     * de l'entrelacé. C'est l'erreur si on oublie que FFmpeg AAC est
     * planaire AVANT swr. Sur une voix grave, deux échantillons
     * voisins de la MÊME voie se ressemblent : la corrélation part
     * vers +1 et l'opposition, qui est dans l'autre plan, disparaît.
     */
    fun misreadPlanar(left: ShortArray, right: ShortArray): ShortArray {
        require(left.size == right.size)
        val pcm = ShortArray(left.size + right.size)
        left.copyInto(pcm, 0)
        right.copyInto(pcm, left.size)
        return pcm
    }

    /**
     * Même geste que `ChannelMappingAudioProcessor` : on recopie des
     * indices, on ne multiplie pas par −1. [map] dit, pour chaque voie
     * de sortie, quelle voie d'entrée prendre.
     */
    fun remap(pcm: ShortArray, channels: Int, map: IntArray): ShortArray {
        val frames = pcm.size / channels
        val out = ShortArray(frames * map.size)
        for (i in 0 until frames) {
            for (o in map.indices) {
                out[i * map.size + o] = pcm[i * channels + map[o]]
            }
        }
        return out
    }

    /** Inverse une voie. Le mapping de Media3 ne le fait pas. */
    fun invertChannel(pcm: ShortArray, channels: Int, index: Int): ShortArray {
        val out = pcm.copyOf()
        val frames = pcm.size / channels
        for (i in 0 until frames) {
            val at = i * channels + index
            val n = (-out[at].toInt()).coerceIn(-32767, 32767)
            out[at] = n.toShort()
        }
        return out
    }

    /** Même gain sur toutes les voies, comme la voix claire. */
    fun applyGain(pcm: ShortArray, gain: Double): ShortArray =
        ShortArray(pcm.size) { i ->
            (pcm[i].toInt() * gain).toInt().coerceIn(-32768, 32767).toShort()
        }

    fun energy(pcm: ShortArray): Double {
        var e = 0.0
        for (s in pcm) {
            val v = s.toDouble()
            e += v * v
        }
        return e
    }

    /** Part des échantillons collés au plafond 16 bits. */
    fun clippedFraction(pcm: ShortArray): Double {
        if (pcm.isEmpty()) return 0.0
        var n = 0
        for (s in pcm) {
            val a = abs(s.toInt())
            if (a >= 32_760) n++
        }
        return n.toDouble() / pcm.size
    }

    private fun quantize(unit: Double, gain: Double): Short {
        val v = (unit * gain * 32_767.0).toInt()
        return v.coerceIn(-32_767, 32_767).toShort()
    }

    /** Fondamentale + harmoniques, avant normalisation. */
    private fun voiceRaw(frame: Int, rate: Int): Double {
        val t = frame.toDouble() / rate
        var s = 0.0
        var h = 1
        val f0 = 140.0
        while (h * f0 <= 3_200.0) {
            s += sin(2.0 * PI * f0 * h * t) / h.toDouble()
            h++
        }
        val env = 0.65 + 0.35 * sin(2.0 * PI * 3.5 * t)
        return s * env
    }

    private val voicePeak48k: Double = peakOf(RATE)

    private fun peakOf(rate: Int): Double {
        var p = 0.0
        for (i in 0 until rate) {
            val a = abs(voiceRaw(i, rate))
            if (a > p) p = a
        }
        return p
    }
}
