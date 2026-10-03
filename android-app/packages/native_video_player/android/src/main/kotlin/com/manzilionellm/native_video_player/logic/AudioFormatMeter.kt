package com.manzilionellm.native_video_player.logic

import java.util.Locale
import kotlin.math.abs

/**
 * COMPTEURS DE TAMPON, DE FORMAT ET DE RYTHME (03/10/2026).
 *
 * Le son « vieille radio » a déjà été cherché dans le décodeur et dans
 * un passe-bas. Ici on note, sans toucher un seul échantillon, ce qui
 * peut encore changer le timbre APRÈS la sonde :
 *
 *   • l'AudioTrack affamé (getUnderrunCount) — un trou, pas un filtre ;
 *   • la latence et sa dérive — l'horloge qui prend de l'avance ou
 *     du retard, sans que le code ne corrige la vitesse (elle est figée) ;
 *   • la fréquence de la piste comparée à celle du mélangeur Android —
 *     si elles diffèrent, AudioFlinger rééchantillonne après notre PCM ;
 *   • la vitesse et la hauteur réellement demandées, et si Sonic tourne ;
 *   • la part d'échantillons collés au plafond 16 bits.
 *
 * Objet PUR : les chiffres viennent de l'appareil, le texte est décidé ici.
 * Aucun de ces calculs ne change le son.
 */
object AudioFormatMeter {

    /** Écart de vitesse encore affiché « 1,00 » : on ne le compte pas. */
    const val SPEED_EPSILON: Float = 0.005f

    /** Combien de latences on garde pour voir si le tampon se remplit. */
    const val LATENCY_KEEP: Int = 12

    /** En dessous, deux fréquences sont le même horloge (48 000 et 48 000). */
    private const val RATE_SLACK: Double = 0.005

    /** Écart de latence (ms) à partir duquel on parle de dérive. */
    private const val DRIFT_MS: Int = 40

    /** Stable si le min et le max restent dans cette fenêtre. */
    private const val STABLE_MS: Int = 30

    enum class Resample {
        /** Piste et mélangeur au même rythme : pas de conversion Android. */
        SAME,

        /** Le mélangeur est plus haut : conversion vers le haut, après la sonde. */
        DEVICE_HIGHER,

        /** Le mélangeur est plus bas : conversion vers le bas, après la sonde. */
        DEVICE_LOWER,

        /** Il manque une des deux fréquences : on ne devine pas. */
        UNKNOWN,
    }

    /**
     * Une photo. Les null veulent dire « l'appareil n'a pas répondu »,
     * jamais « zéro inventé ».
     */
    data class Reading(
        /** AudioTrack.getUnderrunCount. Null = piste illisible. */
        val trackUnderruns: Int? = null,
        /** AudioTrack.getLatency, brut, en ms. Souvent plus grand que le tampon. */
        val latencyMs: Int? = null,
        /** Taille du tampon de la piste, en ms. */
        val bufferMs: Int? = null,
        /** Fréquence demandée à l'AudioTrack (Hz). 0 = inconnue. */
        val trackHz: Int = 0,
        /** AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE (Hz). Null = inconnue. */
        val deviceHz: Int? = null,
        /** PROPERTY_OUTPUT_FRAMES_PER_BUFFER. Null = inconnu. */
        val deviceFrames: Int? = null,
        /** « PCM 16 bits », etc. Null = pas lu. */
        val encoding: String? = null,
        /** Player.playbackParameters.speed. */
        val speed: Float = 1f,
        /** Player.playbackParameters.pitch. */
        val pitch: Float = 1f,
        /** Plus petite vitesse vue depuis l'ouverture. */
        val speedMin: Float = 1f,
        /** Plus grande vitesse vue depuis l'ouverture. */
        val speedMax: Float = 1f,
        /** Nombre de fois où la vitesse a QUITTÉ 1 (pas chaque seconde). */
        val speedMoves: Int = 0,
        /** SonicAudioProcessor.isActive. Null = chaîne pas encore là. */
        val sonicActive: Boolean? = null,
        /** Vitesse que Sonic a reçue. Null = pas encore appliquée. */
        val sonicSpeed: Float? = null,
        val sonicPitch: Float? = null,
        /**
         * Faux dans ce lecteur : buildAudioSink ne demande pas
         * AudioTrack.setPlaybackParams. On l'écrit pour que la fiche
         * le rappelle. Ce n'est pas une mesure.
         */
        val trackParamsEnabled: Boolean = false,
        /** Vitesse lue sur l'AudioTrack, si getPlaybackParams répond. */
        val trackPlaybackSpeed: Float? = null,
        /** Part 0..1 d'échantillons |s| ≥ plafond. Null = sonde muette. */
        val clippedFraction: Double? = null,
        /** D'où vient [clippedFraction]. */
        val clipSource: String = "sonde coupée",
        /** Latences brutes, dans l'ordre, pour la dérive. */
        val latencySeries: List<Int> = emptyList(),
    )

    data class Clip(val fraction: Double?, val source: String)

    /**
     * L'écrêtage utile est celui de la DERNIÈRE sonde (PCM qui entre
     * dans l'AudioTrack). À défaut, la sonde décodeur. Sans les deux,
     * on dit pourquoi, on n'invente pas 0 %.
     */
    fun clip(sink: Double?, decoder: Double?, probeOn: Boolean): Clip {
        if (sink != null) return Clip(sink, "sonde audiotrack")
        if (decoder != null) return Clip(decoder, "sonde décodeur")
        return Clip(null, if (probeOn) "sonde pas encore pleine" else "sonde coupée")
    }

    /** Le plus grand des deux compteurs. Un null plateforme ne vaut pas 0. */
    fun underrunCount(media3: Int, track: Int?): Int = maxOf(media3, track ?: 0)

    fun resample(trackHz: Int, deviceHz: Int?): Resample {
        if (trackHz <= 0 || deviceHz == null || deviceHz <= 0) return Resample.UNKNOWN
        val gap = abs(trackHz - deviceHz).toDouble() / trackHz.toDouble()
        if (gap <= RATE_SLACK) return Resample.SAME
        return if (deviceHz > trackHz) Resample.DEVICE_HIGHER else Resample.DEVICE_LOWER
    }

    /** Vrai si le lecteur, Sonic ou l'AudioTrack a quitté le temps réel. */
    fun rhythmMoved(r: Reading): Boolean {
        if (r.speedMoves > 0) return true
        if (abs(r.speed - 1f) > SPEED_EPSILON) return true
        if (abs(r.pitch - 1f) > SPEED_EPSILON) return true
        if (r.sonicActive == true) return true
        val sonic = r.sonicSpeed
        if (sonic != null && abs(sonic - 1f) > SPEED_EPSILON) return true
        val track = r.trackPlaybackSpeed
        if (track != null && abs(track - 1f) > SPEED_EPSILON) return true
        return false
    }

    /**
     * Trois latences au moins. On regarde le premier et le dernier point,
     * et l'écart total : une oscillation ne doit pas être lue comme
     * « le tampon se remplit ».
     */
    fun drift(samples: List<Int>): String {
        if (samples.size < 3) return "pas assez de latences pour voir une dérive"
        val span = samples.max() - samples.min()
        if (span <= STABLE_MS) return "latence stable"
        val first = samples.first()
        val last = samples.last()
        if (last >= first + DRIFT_MS) {
            return "latence en hausse (tampon qui se remplit, rythme non corrigé)"
        }
        if (last <= first - DRIFT_MS) return "latence en baisse (tampon qui se vide)"
        return "latence qui oscille"
    }

    /**
     * Lignes ajoutées à la fiche. [media3Underruns] est le compteur déjà
     * tenu par le rappel onAudioUnderrun : on le montre À CÔTÉ de
     * getUnderrunCount, parce que les deux ne comptent pas pareil.
     */
    fun block(reading: Reading?, media3Underruns: Int): String {
        if (reading == null) {
            return "Tampon : pas encore lu sur l'appareil. Rappel Media3 : " +
                "$media3Underruns coupure(s). Float coupé dans le code, " +
                "setPlaybackParams coupé, vitesse du direct figée à 1."
        }
        return buildString {
            append(bufferLine(reading, media3Underruns))
            append("\n")
            append(formatLine(reading))
            append("\n")
            append(rhythmLine(reading))
            append("\n")
            append(clipLine(reading))
        }
    }

    /** Phrases du haut de fiche, seulement quand un chiffre sort de l'ordinaire. */
    fun notices(r: Reading): List<String> {
        val out = ArrayList<String>(2)
        when (resample(r.trackHz, r.deviceHz)) {
            Resample.DEVICE_HIGHER, Resample.DEVICE_LOWER ->
                out += "FORMAT : piste ${hz(r.trackHz)}, mélangeur ${hz(r.deviceHz ?: 0)} " +
                    "→ Android rééchantillonne après la sonde."
            Resample.SAME, Resample.UNKNOWN -> Unit
        }
        if (rhythmMoved(r)) {
            out += "RYTHME : vitesse ${speed(r.speed)}, Sonic ${sonicWord(r.sonicActive)}."
        }
        return out
    }

    private fun bufferLine(r: Reading, media3Underruns: Int): String {
        val platform = if (r.trackUnderruns == null) {
            "underruns AudioTrack non lisibles"
        } else {
            "underruns AudioTrack ${r.trackUnderruns}"
        }
        val latency = if (r.latencyMs == null) {
            "latence non lisible"
        } else {
            val shown = (r.latencyMs / 10) * 10
            val doubleCount = r.bufferMs != null && r.bufferMs > 0 && r.latencyMs > r.bufferMs * 3 / 2
            if (doubleCount) {
                "getLatency ~$shown ms (souvent le double du tampon de ${r.bufferMs} ms)"
            } else {
                "getLatency ~$shown ms"
            }
        }
        val buffer = if (r.bufferMs == null) "tampon non lisible" else "tampon ${r.bufferMs} ms"
        return "Tampon : $platform · rappel Media3 $media3Underruns · $latency · $buffer · ${drift(r.latencySeries)}"
    }

    private fun formatLine(r: Reading): String {
        val enc = r.encoding ?: "codage non lu"
        val track = if (r.trackHz > 0) hz(r.trackHz) else "fréquence de piste inconnue"
        val device = if (r.deviceHz != null && r.deviceHz > 0) hz(r.deviceHz) else "inconnue"
        val period = mixerPeriod(r)
        val periodBit = if (period == null) "" else " · période mélangeur $period ms"
        return "Format : $enc · piste $track · mélangeur $device$periodBit · " +
            resampleWords(resample(r.trackHz, r.deviceHz)) +
            " · float coupé · pas de dither (ToInt16 inactif si c'est déjà du 16 bits)"
    }

    private fun rhythmLine(r: Reading): String {
        val sonicSpeed = r.sonicSpeed?.let { " · Sonic a reçu ${speed(it)}" } ?: ""
        val trackSpeed = r.trackPlaybackSpeed?.let { " · vitesse lue sur l'AudioTrack ${speed(it)}" } ?: ""
        val params = if (r.trackParamsEnabled) "setPlaybackParams allumé" else "setPlaybackParams coupé"
        return "Rythme : vitesse ${speed(r.speed)} (de ${speed(r.speedMin)} à ${speed(r.speedMax)}, " +
            "${r.speedMoves} écart(s)) · hauteur ${speed(r.pitch)} · Sonic ${sonicWord(r.sonicActive)}" +
            sonicSpeed + " · $params" + trackSpeed
    }

    private fun clipLine(r: Reading): String {
        val frac = r.clippedFraction
        if (frac == null) return "Écrêtage : non mesuré (${r.clipSource})"
        val pct = String.format(Locale.FRANCE, "%.2f %%", frac * 100.0)
        return "Écrêtage : $pct des échantillons au plafond " +
            "(|s| ≥ ${AudioSpectrum.CLIP_ABS}, ${r.clipSource})"
    }

    private fun mixerPeriod(r: Reading): Int? {
        val frames = r.deviceFrames ?: return null
        val rate = r.deviceHz ?: return null
        if (frames <= 0 || rate <= 0) return null
        return frames * 1000 / rate
    }

    private fun resampleWords(kind: Resample): String = when (kind) {
        Resample.SAME -> "mêmes fréquences : AudioFlinger n'a pas à rééchantillonner"
        Resample.DEVICE_HIGHER -> "Android rééchantillonne vers le haut après la sonde"
        Resample.DEVICE_LOWER -> "Android rééchantillonne vers le bas après la sonde"
        Resample.UNKNOWN -> "rééchantillonnage Android inconnu (une fréquence manque)"
    }

    private fun sonicWord(active: Boolean?): String = when (active) {
        true -> "actif"
        false -> "inactif"
        null -> "inconnu"
    }

    private fun hz(rate: Int): String =
        if (rate % 1000 == 0) "${rate / 1000} kHz"
        else String.format(Locale.FRANCE, "%.1f kHz", rate / 1000.0)

    private fun speed(v: Float): String = String.format(Locale.FRANCE, "%.2f", v)
}
