package com.manzilionellm.native_video_player.logic

/**
 * Mesures de bande à chaque étage qu'on peut atteindre sans changer le son.
 *
 * Ordre réel dans Media3 1.5.1, PCM 16 bits :
 *   ToInt16 (no-op si c'est déjà du 16 bits) → mapping de canaux → trim
 *   → sonde [DECODER]
 *   → voix claire (inactive si coupée)
 *   → sonde [VOICE]
 *   → silence (inactif : skipSilence false)
 *   → sonde [SILENCE]
 *   → Sonic (inactif à vitesse 1 et même fréquence)
 *   → sonde [SINK]  (= PCM écrit dans l'AudioTrack)
 *
 * ToInt16, le mapping et le trim ne sont pas des passe-bas. On ne peut pas
 * poser une sonde avant eux : DefaultAudioSink les met devant la chaîne.
 * Il n'y a pas de boucle HDMI : [SINK] est le dernier PCM dans l'app.
 */
object AudioStages {
    const val DECODER: String = "decodeur"
    const val VOICE: String = "voix_claire"
    const val SILENCE: String = "silence"
    const val SINK: String = "audiotrack"

    val ORDER: List<String> = listOf(DECODER, VOICE, SILENCE, SINK)

    data class Reading(
        val id: String,
        val judgement: AudioSpectrum.Judgement,
    )

    /** Bande qui baisse entre deux étapes (large → bas ou milieu). */
    fun dropped(earlier: AudioSpectrum.Judgement, later: AudioSpectrum.Judgement): Boolean {
        val before = AudioSpectrum.effectiveBand(earlier)
        val after = AudioSpectrum.effectiveBand(later)
        return before == AudioSpectrum.Band.WIDE &&
            (after == AudioSpectrum.Band.LOW || after == AudioSpectrum.Band.MID)
    }

    /** Première étape dont la bande est plus basse que la précédente. */
    fun firstDrop(readings: List<Reading>): Reading? {
        for (i in 1 until readings.size) {
            if (dropped(readings[i - 1].judgement, readings[i].judgement)) return readings[i]
        }
        return null
    }

    /** Toutes les étapes disent la même bande (assez de son pour conclure). */
    fun sameBand(readings: List<Reading>): Boolean {
        if (readings.size < 2) return false
        val bands = readings.map { AudioSpectrum.effectiveBand(it.judgement) }
        if (bands.any { it == AudioSpectrum.Band.SHORT || it == AudioSpectrum.Band.SILENCE }) {
            return false
        }
        return bands.all { it == bands.first() }
    }

    /**
     * Enchaîne des copies ou des filtres et mesure après chacun.
     * Sert aux tests : la sonde réelle copie, elle ne filtre pas.
     */
    fun trace(
        pcm: ShortArray,
        sampleRate: Int,
        channels: Int,
        steps: List<Pair<String, (ShortArray) -> ShortArray>>,
    ): List<Reading> {
        var current = pcm
        val out = ArrayList<Reading>(steps.size)
        for ((id, step) in steps) {
            current = step(current)
            out += Reading(id, AudioSpectrum.measure(current, sampleRate, channels))
        }
        return out
    }
}
