package com.manzilionellm.native_video_player.logic

/**
 * Choix de la piste audio par défaut.
 *
 * Même règle que `spoken_track.dart` :
 *  1. la langue de l'application, si une piste la porte ;
 *  2. pas un commentaire ni une audiodescription, s'il reste une
 *     autre piste ;
 *  3. null = on ne touche pas au choix déjà bon (pas de second
 *     basculement, qui craque).
 *
 * Les drapeaux sont ceux de Media3 (`C.ROLE_FLAG_COMMENTARY` = 8,
 * `C.ROLE_FLAG_DESCRIBES_VIDEO` = 512). On les recopie en constantes
 * pour que ce fichier n'importe pas Android.
 */
data class SpokenCandidate(
    val group: Int,
    val index: Int,
    val language: String?,
    val label: String?,
    val channels: Int = 0,
    val selected: Boolean = false,
    val roleFlags: Int = 0,
)

object SpokenTrackChoice {
    const val ROLE_COMMENTARY: Int = 8
    const val ROLE_DESCRIBES_VIDEO: Int = 512

    private val undetermined = setOf("und", "undetermined", "mul", "mis", "zxx", "xx")

    private val iso3 = mapOf(
        "fre" to "fr", "fra" to "fr", "eng" to "en", "spa" to "es",
        "por" to "pt", "ita" to "it", "ger" to "de", "deu" to "de",
        "dut" to "nl", "nld" to "nl", "ara" to "ar", "tur" to "tr",
        "rus" to "ru", "pol" to "pl", "swe" to "sv", "dan" to "da",
        "nor" to "nb", "nob" to "nb", "nno" to "nb", "fin" to "fi",
        "chi" to "zh", "zho" to "zh", "jpn" to "ja", "kor" to "ko",
        "ron" to "ro", "rum" to "ro", "gre" to "el", "ell" to "el",
        "cze" to "cs", "ces" to "cs", "hun" to "hu", "ukr" to "uk",
        "vie" to "vi", "tha" to "th", "hin" to "hi", "ind" to "id",
    )

    private val sideWords = setOf(
        "commentary", "commentaire", "commentaires", "comment", "comments",
        "descriptive", "description", "audiodescription", "audiodesc",
        "director", "narration", "narrateur", "narrator", "voiceover",
        "voixoff", "ad",
    )

    private val word = Regex("[a-z0-9]+")

    /** « fre » → « fr ». null si vide ou langue inconnue (« und »). */
    fun language(raw: String?): String? {
        if (raw == null) return null
        var code = raw.trim().lowercase()
        if (code.isEmpty()) return null
        val dash = code.indexOfAny(charArrayOf('-', '_'))
        if (dash > 0) code = code.substring(0, dash)
        code = iso3[code] ?: code
        if (code in undetermined) return null
        return code
    }

    fun isSideTrack(track: SpokenCandidate): Boolean {
        if (track.roleFlags and ROLE_COMMENTARY != 0) return true
        if (track.roleFlags and ROLE_DESCRIBES_VIDEO != 0) return true
        val blob = fold("${track.label ?: ""} ${track.language ?: ""}")
        return word.findAll(blob).any { it.value in sideWords }
    }

    /**
     * Piste à forcer, ou null si le choix actuel convient déjà.
     * [appLanguage] peut être « fr », « fre » ou « en-US ».
     */
    fun pick(tracks: List<SpokenCandidate>, appLanguage: String?): SpokenCandidate? {
        if (tracks.isEmpty()) return null
        val want = language(appLanguage)
        val main = tracks.filter { !isSideTrack(it) }
        val selected = tracks.firstOrNull { it.selected }
        var pool = main
        if (want != null) {
            val inLang = main.filter { language(it.language) == want }
            if (inLang.isNotEmpty()) pool = inLang
        }
        if (pool.isEmpty()) return null
        if (selected != null && pool.any { it.group == selected.group && it.index == selected.index }) {
            return null
        }
        return pool.first()
    }

    private fun fold(raw: String): String {
        val from = "àáâãäåçèéêëìíîïñòóôõöùúûüýÿœæ"
        val to = "aaaaaaceeeeiiiinooooouuuuyyoa"
        val out = StringBuilder()
        for (ch in raw.lowercase()) {
            val i = from.indexOf(ch)
            out.append(if (i >= 0) to[i] else ch)
        }
        return out.toString()
    }
}
