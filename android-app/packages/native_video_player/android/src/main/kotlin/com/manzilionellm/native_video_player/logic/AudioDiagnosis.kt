package com.manzilionellm.native_video_player.logic

/**
 * DIAGNOSTIC DU SON (01/10/2026) — « pourquoi le son ne sort pas net ? »
 *
 * Le lecteur note, pour la chaîne en cours, ce qu'il REÇOIT (le flux),
 * QUI le décode (la box ou FFmpeg) et ce qu'il ENVOIE à la sortie son
 * (AudioTrack). En comparant les trois, on sait si le défaut vient de la
 * SOURCE (le fournisseur) ou de la BOX, au lieu de deviner.
 *
 * La preuve la plus utile : le HE-AAC (très courant en IPTV) annonce
 * souvent 24 kHz dans le flux ; les aigus sont RECONSTRUITS au décodage
 * (SBR) et la sortie doit repasser à 48 kHz. Si la sortie reste à 24 kHz
 * avec le décodeur de la box, c'est lui qui a jeté les aigus : c'est
 * exactement le son « vieille radio ». Idem en stéréo : une source
 * stéréo qui sort en mono = stéréo paramétrique (PS) ignorée.
 *
 * Objet PUR (aucune dépendance Android) → testé dans logic-test/.
 */
data class AudioSnapshot(
    /** Type du flux reçu (« audio/mp4a-latm », « audio/ac3 »…). */
    val mime: String? = null,
    /** Profil exact si connu (« mp4a.40.2 » = AAC-LC, « .5 » = HE-AAC…). */
    val codecs: String? = null,
    /** Fréquence annoncée par le flux (Hz, 0 = inconnue). */
    val inSampleRate: Int = 0,
    /** Nombre de voies annoncé par le flux (0 = inconnu). */
    val inChannels: Int = 0,
    /** Débit annoncé (bit/s, 0 = inconnu : fréquent en direct .ts). */
    val bitrate: Int = 0,
    /** Nom du décodeur (« ffmpeg… », « c2.android.aac.decoder », « OMX.… »). */
    val decoder: String? = null,
    /** Ce qui part vers la sortie son. */
    val outSampleRate: Int = 0,
    val outChannels: Int = 0,
    /** « PCM 16 bits », « AC-3 »… */
    val outEncoding: String? = null,
    /** Vrai si le son part tel quel (Dolby / DTS) vers la TV / barre de son. */
    val passthrough: Boolean = false,
    /** Coupures de la sortie son depuis l'ouverture de la chaîne. */
    val underruns: Int = 0,
    /** « Voix claire / mode nuit » allumé. */
    val clearVoice: Boolean = false,
)

object AudioDiagnosis {

    /** Débit sous lequel un son stéréo s'entend « pauvre » (bit/s). */
    const val LOW_BITRATE: Int = 96_000

    /** Nom lisible du profil AAC d'après `codecs` (null si inconnu). */
    fun aacProfile(codecs: String?): String? {
        val c = codecs?.lowercase() ?: return null
        return when {
            c.startsWith("mp4a.40.29") -> "HE-AAC v2"
            c.startsWith("mp4a.40.5") -> "HE-AAC"
            c.startsWith("mp4a.40.2") -> "AAC-LC"
            else -> null
        }
    }

    fun isFfmpeg(decoder: String?): Boolean = decoder?.contains("ffmpeg", ignoreCase = true) == true

    private fun isAac(mime: String?): Boolean = mime?.contains("mp4a", ignoreCase = true) == true ||
        mime?.contains("aac", ignoreCase = true) == true

    private fun khz(hz: Int): String =
        if (hz % 1000 == 0) "${hz / 1000} kHz" else String.format(java.util.Locale.FRANCE, "%.1f kHz", hz / 1000.0)

    /** Ligne factuelle : ce qui entre, qui décode, ce qui sort. */
    fun describe(s: AudioSnapshot): String {
        val codec = when {
            isAac(s.mime) -> aacProfile(s.codecs) ?: "AAC"
            s.mime != null -> s.mime.substringAfter('/').uppercase()
            else -> "?"
        }
        val entree = buildList {
            add(codec)
            if (s.inSampleRate > 0) add(khz(s.inSampleRate))
            if (s.inChannels > 0) add(if (s.inChannels == 1) "mono" else "${s.inChannels} voies")
            if (s.bitrate > 0) add("${s.bitrate / 1000} kb/s")
        }.joinToString(" ")
        val qui = when {
            s.decoder == null -> if (s.passthrough) "aucun (tel quel)" else "?"
            isFfmpeg(s.decoder) -> "FFmpeg"
            else -> "box (${s.decoder})"
        }
        val sortie = buildList {
            add(s.outEncoding ?: "?")
            if (s.outSampleRate > 0) add(khz(s.outSampleRate))
            if (s.outChannels > 0) add(if (s.outChannels == 1) "mono" else "${s.outChannels} voies")
            if (s.passthrough) add("vers TV/barre de son")
        }.joinToString(" ")
        return "reçu : $entree · décodé par : $qui · sortie : $sortie"
    }

    /**
     * Verdicts en français simple, du plus probable au moins probable.
     * Toujours au moins une ligne.
     */
    fun verdicts(s: AudioSnapshot): List<String> {
        val out = mutableListOf<String>()
        val aac = isAac(s.mime)
        val boxDecoder = s.decoder != null && !isFfmpeg(s.decoder)

        // 1) PREUVE « vieille radio » : HE-AAC dont la box n'a pas
        //    reconstruit les aigus (sortie restée à la fréquence du cœur).
        if (aac && boxDecoder && s.outSampleRate in 1..24_000 && !s.passthrough) {
            out += "BOX : son sorti à ${khz(s.outSampleRate)} → aigus perdus au décodage " +
                "(HE-AAC mal décodé par la box). C'est le son « vieille radio ». Il faut FFmpeg."
        }
        // 2) Stéréo perdue au décodage (stéréo paramétrique ignorée).
        if (aac && boxDecoder && s.inChannels >= 2 && s.outChannels == 1) {
            out += "BOX : source en stéréo mais sortie en MONO → stéréo perdue au décodage."
        }
        // 3) HE-AAC annoncé mais profil décodé par la box : à surveiller.
        val profile = aacProfile(s.codecs)
        if (out.isEmpty() && aac && boxDecoder && profile != null && profile.startsWith("HE-AAC")) {
            out += "À surveiller : $profile décodé par la box (certaines box perdent les aigus)."
        }
        // 4) Défauts de la SOURCE (le fournisseur), pas de l'app.
        if (s.inChannels == 1) {
            out += "SOURCE : le flux est MONO à l'origine (le fournisseur l'envoie ainsi)."
        }
        if (s.bitrate in 1 until LOW_BITRATE) {
            out += "SOURCE : débit audio faible (${s.bitrate / 1000} kb/s) → qualité limitée par le fournisseur."
        }
        if (!aac && s.inSampleRate in 1 until 32_000) {
            out += "SOURCE : son échantillonné à ${khz(s.inSampleRate)} → aigus absents dès l'origine."
        }
        // 5) Craquements / coupures : sortie son affamée.
        if (s.underruns > 0) {
            out += "SORTIE : ${s.underruns} coupure(s) du son → box trop chargée ou flux qui arrive par à-coups."
        }
        // 6) Informations utiles (pas des défauts).
        if (s.passthrough) {
            out += "Info : son Dolby/DTS envoyé tel quel → la qualité dépend de la TV ou de la barre de son."
        }
        if (s.clearVoice) {
            out += "Info : « Voix claire » allumée (elle baisse les pics forts)."
        }
        if (out.isEmpty()) {
            out += if (isFfmpeg(s.decoder)) {
                "Rien d'anormal côté app (décodage complet FFmpeg). Si le son reste mauvais : " +
                    "comparer la MÊME chaîne dans une autre app (source)."
            } else {
                "Rien d'anormal détecté. Si le son reste mauvais : comparer la MÊME chaîne " +
                    "dans une autre app (source)."
            }
        }
        return out
    }
}
