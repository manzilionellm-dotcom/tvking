package com.manzilionellm.native_video_player.logic

/**
 * Compresseur très simple pour « voix claire / mode nuit ».
 *
 * Au-dessus d'un seuil, le pic est ramené avec un ratio 3:1.
 * En dessous, le gain reste 1 : on ne remonte PAS les chuchotements
 * (ça amplifierait le souffle). L'attaque est plus rapide que le
 * relâchement, pour qu'un pic ne claque pas et qu'une phrase ne
 * pompe pas.
 *
 * Ce n'est PAS une norme EBU R128. Les flux IPTV n'ont en général
 * pas de métadonnée de loudness fiable : un gain aveugle entre
 * chaînes peut saturer ou assourdir. On ne l'applique QUE si la
 * personne allume l'option (coupée par défaut), et seulement sur
 * le PCM (AAC, MP2). Le passthrough AC-3 / DTS ne passe pas ici.
 */
object ClearVoiceGain {
    /** Pic (0..1) à partir duquel on commence à réduire. */
    const val THRESHOLD: Float = 0.40f

    /** 3:1 au-dessus du seuil. */
    const val RATIO: Float = 3f

    /** Gain plancher : on n'étouffe pas une chaîne déjà forte jusqu'au silence. */
    const val MIN_GAIN: Float = 0.45f

    /**
     * Gain cible pour un pic normalisé (0 = silence, 1 = pleine échelle).
     * 1 = on ne change rien.
     */
    fun target(peak: Float): Float {
        if (peak <= THRESHOLD || peak <= 0f) return 1f
        val desired = THRESHOLD + (peak - THRESHOLD) / RATIO
        val gain = desired / peak
        return gain.coerceIn(MIN_GAIN, 1f)
    }

    /**
     * Glisse [current] vers [target]. [attack] vrai = le son monte
     * (on réduit vite). Faux = on relâche doucement.
     */
    fun smooth(current: Float, target: Float): Float {
        val coeff = if (target < current) 0.35f else 0.05f
        return (current + (target - current) * coeff).coerceIn(MIN_GAIN, 1f)
    }
}
