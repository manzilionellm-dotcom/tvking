package com.manzilionellm.native_video_player.logic

/**
 * Taille du tampon de SORTIE audio (AudioTrack), pas le tampon réseau.
 *
 * Le LoadControl (5 s / 45 s, reprise 2 s) n'est PAS modifié : l'avoir
 * allongé en v99–v101 a laissé des chaînes sur le logo. Ici on double
 * seulement le petit tampon du haut-parleur, plafonné à +256 Ko, pour
 * absorber un MPEG-TS irrégulier (craquements) sans garder des secondes
 * de l'ancienne chaîne. Le résultat est un multiple de la taille d'une
 * frame, comme l'exige AudioTrack.
 */
object AudioTrackBuffer {
    private const val EXTRA_CAP_BYTES: Int = 256 * 1024

    fun sized(minBytes: Int, pcmFrameSize: Int): Int {
        if (minBytes <= 0) return 0
        val frame = if (pcmFrameSize > 0) pcmFrameSize else 1
        val doubled = minBytes.toLong() * 2L
        val cap = minBytes.toLong() + EXTRA_CAP_BYTES.toLong()
        var sized = minOf(doubled, cap)
        if (sized < minBytes) sized = minBytes.toLong()
        val aligned = sized - (sized % frame)
        return if (aligned < minBytes) minBytes else aligned.toInt()
    }
}
