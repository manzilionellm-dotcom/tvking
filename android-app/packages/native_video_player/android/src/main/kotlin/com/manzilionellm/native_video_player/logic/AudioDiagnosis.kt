package com.manzilionellm.native_video_player.logic

import java.util.Locale

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
    /**
     * Mesure PCM (sonde). Null = sonde coupée ou pas encore assez de son :
     * on ne conclut PAS sur la bande à partir de rien.
     */
    val spectrum: AudioSpectrum.Judgement? = null,
    /**
     * Décalage image/son mesuré, en millisecondes. Null = pas de mesure
     * fiable : on n'invente pas un décalage.
     */
    val avOffsetMs: Int? = null,
    /** Nombre de pistes audio jouables vues dans le flux. */
    val audioTrackCount: Int = 0,
    /** Plus grand nombre de voies parmi les pistes audio NON choisies. */
    val widerTrackChannels: Int = 0,
    /** Note de repli (échec du décodeur de la box, retour à FFmpeg). */
    val routeNote: String? = null,
    /** Player.skipSilenceEnabled au moment du rapport. */
    val skipSilence: Boolean = false,
    /** Vitesse de lecture (1 = temps réel). */
    val playbackSpeed: Float = 1f,
    /**
     * Spectre à chaque sonde, dans l'ordre [AudioStages.ORDER].
     * Vide si la sonde est coupée. [spectrum] reprend alors la sonde
     * décodeur : les règles déjà écrites ne changent pas de chiffre.
     */
    val stages: List<AudioStages.Reading> = emptyList(),
    /**
     * Cycle de vie au moment du rapport : numéro du zap, chaîne déjà vue,
     * lecteurs / décodeurs / AudioTrack vivants, repli box de cette chaîne.
     * Null = pas encore relevé.
     */
    val cycle: PlayerCensus.Snapshot? = null,
    /**
     * Réglage Spectre au moment du rapport. Faux = on ne mesure pas.
     * Vrai ne veut pas encore dire que Media3 a mis la sonde dans la chaîne.
     */
    val probeRequested: Boolean = false,
    /** Dernier onConfigure a accepté le PCM : la sonde est dans la chaîne. */
    val probeInChain: Boolean = false,
    /** Trames vues par la sonde depuis la dernière configuration (pas depuis le dernier flush). */
    val probeFrames: Int = 0,
    /** Pourquoi onConfigure a renvoyé NOT_SET. Null si accepté ou pas encore appelé. */
    val probeReject: String? = null,
    /**
     * Lectures annoncées, les nôtres, les autres. Le compteur client
     * d'Android 16 n'est plus pris pour argent comptant.
     */
    val playback: AudioRouteState.Owner = AudioRouteState.Owner.unknown(),
    /**
     * Ligne « Chemin » (mode, haut-parleur d'appel, Bluetooth, sortie,
     * flux réel). Null = pas encore lue.
     */
    val routeLine: String? = null,
    /**
     * Ligne « Attributs » : le contenu envoyé à l'AudioTrack (film,
     * musique, parole, ou le défaut Media3). Null = pas encore posée.
     * Ce n'est pas une cause : l'essai est coupé par défaut.
     */
    val attributeLine: String? = null,
    /** Le lecteur dit qu'il joue (image et son en cours). */
    val playerAudible: Boolean = false,
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

        // 0) REPLI : cette chaîne a été renvoyée au décodeur de la box après
        //    une panne FFmpeg. C'est le chemin de la v98 (celui du son
        //    « vieille radio ») : on le dit en premier, avec la cause.
        val fail = s.cycle?.boxFailure
        if (fail != null) {
            out += "REPLI : l'AAC de cette chaîne passe par le décodeur de la box depuis le zap " +
                "n°${fail.zap} (${fail.reason.label}). C'est le chemin qui faisait le son " +
                "« vieille radio ». « FFmpeg : réessayer » le remet sur FFmpeg."
        }
        val cycle = s.cycle
        if (cycle != null && PlayerCensus.overlapping(cycle)) {
            // Les chiffres tout de suite, en haut de la fiche : lequel est en double.
            out += "CHEVAUCHEMENT : lecteurs vivants ${cycle.playersAlive} · décodeurs audio vivants " +
                "${cycle.audioDecodersAlive} · AudioTrack vivants ${cycle.audioTracksAlive} " +
                "(zap n°${cycle.zap}) → plus d'un actif, deux sons peuvent se mélanger."
        }

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

    // ---------------------------------------------------------------------
    //  Rapport professionnel (étend describe / verdicts, ne les remplace pas)
    // ---------------------------------------------------------------------

    /** Décalage |image − son| encore dans la tolérance : pas un défaut. */
    const val OFFSET_OK_MS: Int = 80

    /** À partir de là, le décalage est assez grand pour être sûr. */
    const val OFFSET_SURE_MS: Int = 200

    private const val FILE_VIEW =
        "android-app/packages/native_video_player/android/src/main/kotlin/" +
            "com/manzilionellm/native_video_player/NativeVideoView.kt"

    private const val FILE_PROBE =
        "android-app/packages/native_video_player/android/src/main/kotlin/" +
            "com/manzilionellm/native_video_player/AudioProbeProcessor.kt"

    private const val FILE_SPECTRUM =
        "android-app/packages/native_video_player/android/src/main/kotlin/" +
            "com/manzilionellm/native_video_player/logic/AudioSpectrum.kt"

    private const val FILE_STAGES =
        "android-app/packages/native_video_player/android/src/main/kotlin/" +
            "com/manzilionellm/native_video_player/logic/AudioStages.kt"

    private const val FILE_CLEAR =
        "android-app/packages/native_video_player/android/src/main/kotlin/" +
            "com/manzilionellm/native_video_player/ClearVoiceProcessor.kt"

    private const val FILE_GAIN =
        "android-app/packages/native_video_player/android/src/main/kotlin/" +
            "com/manzilionellm/native_video_player/logic/ClearVoiceGain.kt"

    private const val FILE_SPOKEN =
        "android-app/packages/native_video_player/android/src/main/kotlin/" +
            "com/manzilionellm/native_video_player/logic/SpokenTrackChoice.kt"

    enum class Confidence { HAUTE, INCERTAINE }

    /** CAUSE = un défaut possible. INFO = un constat qui n'est pas un défaut. */
    enum class Kind { CAUSE, INFO }

    data class Fix(
        val file: String,
        val symbol: String,
        val media3: String,
        val action: String,
        /** Null : aucun interrupteur, on n'applique rien. */
        val settingKey: String? = null,
    )

    data class Finding(
        val id: String,
        val confidence: Confidence,
        val kind: Kind,
        val symptom: String,
        val cause: String,
        val fix: Fix,
    )

    /** Nom de codec lisible : AAC-LC, HE-AAC/SBR, AC-3, E-AC-3, MP2, MP3… */
    fun codecName(s: AudioSnapshot): String {
        val mime = s.mime?.lowercase()
        if (isAac(s.mime)) {
            return when (aacProfile(s.codecs)) {
                "HE-AAC v2" -> "HE-AAC v2 (SBR+PS)"
                "HE-AAC" -> "HE-AAC/SBR"
                "AAC-LC" -> "AAC-LC"
                else -> "AAC"
            }
        }
        if (mime == null) return "?"
        return when {
            mime.contains("eac3") || mime.contains("e-ac-3") || mime.contains("ec-3") -> "E-AC-3"
            mime.contains("ac3") || mime.contains("ac-3") -> "AC-3"
            mime.contains("mpeg-l2") || mime.contains("/mp2") -> "MP2"
            mime.contains("mpeg") || mime.contains("mp3") -> "MP3"
            mime.contains("dts") -> "DTS"
            else -> mime.substringAfter('/').uppercase()
        }
    }

    /**
     * Une cause par règle, dans l'ordre. Une règle ne s'allume que si
     * TOUTES ses conditions sont vraies. Sinon elle se tait (pas de
     * demi-certitude). Les tests positifs ET négatifs sont dans
     * AudioDiagnosisTest / AudioSpectrumTest.
     */
    fun findings(s: AudioSnapshot): List<Finding> {
        val out = ArrayList<Finding>()
        val aac = isAac(s.mime)
        val profile = aacProfile(s.codecs)
        val heAac = profile != null && profile.startsWith("HE-AAC")
        val box = s.decoder != null && !isFfmpeg(s.decoder)
        val ffmpeg = isFfmpeg(s.decoder)

        // R1 — HE-AAC (ou AAC dont la sortie est restée au cœur) décodé
        // par la box à ≤ 24 kHz. C'est la règle déjà prouvée par verdicts() :
        // le SBR aurait dû ramener la sortie vers 48 kHz.
        val sbrMissing = aac && box && !s.passthrough && s.outSampleRate in 1..24_000
        if (sbrMissing) {
            out += Finding(
                id = "decodeur_sans_sbr",
                confidence = Confidence.HAUTE,
                kind = Kind.CAUSE,
                symptom = "Sortie à ${khz(s.outSampleRate)} sur un ${codecName(s)} décodé par la box.",
                cause = "Le décodeur AAC de la box n'a pas reconstruit le SBR : " +
                    "les aigus qui auraient dû revenir au-dessus du cœur sont absents. " +
                    "C'est le son « vieille radio » quand la sortie reste à la fréquence du cœur.",
                fix = ffmpegFix(
                    "Au prochain setUrl, remettre forceBoxAacDecoder à faux pour que " +
                        "preferFfmpegFor cache à nouveau le décodeur AAC de la box " +
                        "(liste MediaCodec vide) et que FfmpegAudioRenderer prenne la piste. " +
                        "Ne pas le faire tout seul : le filet des 8 s doit rester.",
                ),
            )
        }

        // R1 négatif élargi : FFmpeg lui-même sort à ≤ 24 kHz. On ne accuse
        // PAS la box (elle ne décode pas). On ne change pas le défaut.
        if (aac && ffmpeg && !s.passthrough && s.outSampleRate in 1..24_000) {
            out += Finding(
                id = "ffmpeg_sortie_basse",
                confidence = Confidence.INCERTAINE,
                kind = Kind.CAUSE,
                symptom = "FFmpeg sort à ${khz(s.outSampleRate)} sur ${codecName(s)}.",
                cause = "Le décodeur de référence n'a pas non plus remonté la fréquence. " +
                    "Ça peut être le flux (cœur sans SBR) ou le .so. Les signaux ne disent pas lequel.",
                fix = Fix(
                    file = FILE_VIEW,
                    symbol = "NativeVideoView.ffmpegAac / FfmpegLibrary.supportsFormat",
                    media3 = "FfmpegAudioRenderer (extension media3-decoder-ffmpeg)",
                    action = "Ne pas changer preferFfmpegFor. Vérifier que le .so déclare l'AAC. " +
                        "Aucun réglage ne force un autre décodeur dans ce cas.",
                    settingKey = null,
                ),
            )
        }

        // R2 — stéréo paramétrique perdue : même condition que verdicts().
        if (aac && box && s.inChannels >= 2 && s.outChannels == 1 && !s.passthrough) {
            out += Finding(
                id = "stereo_perdue",
                confidence = Confidence.HAUTE,
                kind = Kind.CAUSE,
                symptom = "Entrée ${s.inChannels} voies, sortie mono, décodeur de la box.",
                cause = "La stéréo paramétrique (HE-AAC v2 / PS) a été ignorée au décodage.",
                fix = ffmpegFix(
                    "Même correctif que le SBR : FfmpegAudioRenderer via preferFfmpegFor, " +
                        "seulement si le réglage est allumé.",
                ),
            )
        }

        // R3 — downmix 5.1 → stéréo ou mono. Fait constaté, pas une preuve de « radio ».
        if (!s.passthrough && s.inChannels >= 6 && s.outChannels in 1..2) {
            out += Finding(
                id = "downmix",
                confidence = Confidence.HAUTE,
                kind = Kind.INFO,
                symptom = "Entrée ${s.inChannels} voies, sortie ${s.outChannels} voies.",
                cause = "Media3 a mélangé le 5.1 vers la sortie de la box. " +
                    "Un downmix n'enlève pas les aigus : ce n'est pas, à lui seul, le son radio.",
                fix = Fix(
                    file = FILE_VIEW,
                    symbol = "NativeVideoView.buildAudioSink",
                    media3 = "DefaultAudioSink.Builder — le masque de canaux vient de l'AudioTrack",
                    action = "Ne pas changer le masque de canaux ni ajouter de ChannelMixingAudioProcessor. " +
                        "Le downmix par défaut de Media3 reste en place.",
                    settingKey = null,
                ),
            )
        }

        // R4 — piste mono alors qu'une piste plus large existe.
        if (s.inChannels == 1 && s.widerTrackChannels >= 2) {
            out += Finding(
                id = "piste_plus_large",
                confidence = Confidence.INCERTAINE,
                kind = Kind.CAUSE,
                symptom = "La piste en cours est mono ; une autre a ${s.widerTrackChannels} voies.",
                cause = "Le son étroit PEUT venir de la piste choisie (commentaire, mono). " +
                    "On ne sait pas si l'autre piste est la bonne langue : on ne la force pas.",
                fix = Fix(
                    file = FILE_VIEW,
                    symbol = "NativeVideoView.onTracksChanged / SpokenTrackChoice.pick",
                    media3 = "DefaultTrackSelector.setOverrideForType(TrackSelectionOverride)",
                    action = "Choisir la piste à la main (selectTrack). Ne pas modifier SpokenTrackChoice.pick : " +
                        "il reste sur la langue de l'app, pas sur le nombre de voies.",
                    settingKey = null,
                ),
            )
        } else if (s.inChannels == 1) {
            out += Finding(
                id = "source_mono",
                confidence = Confidence.HAUTE,
                kind = Kind.CAUSE,
                symptom = "Le flux en cours est mono.",
                cause = "La piste choisie est mono à l'origine. Le lecteur ne l'a pas réduite " +
                    "(aucune autre piste plus large n'est annoncée).",
                fix = Fix(
                    file = FILE_SPOKEN,
                    symbol = "SpokenTrackChoice.pick",
                    media3 = "TrackSelectionParameters.setPreferredAudioLanguage",
                    action = "Rien à changer dans le décodeur. Le fournisseur envoie cette piste en mono.",
                    settingKey = null,
                ),
            )
        }

        if (s.bitrate in 1 until LOW_BITRATE) {
            out += Finding(
                id = "debit_faible",
                confidence = Confidence.HAUTE,
                kind = Kind.CAUSE,
                symptom = "Débit audio ${s.bitrate / 1000} kb/s.",
                cause = "Le débit annoncé est bas : le fournisseur a déjà limité la qualité.",
                fix = Fix(
                    file = FILE_VIEW,
                    symbol = "onAudioInputFormatChanged (lecture de Format.bitrate)",
                    media3 = "Format.bitrate — informatif, pas un réglage de décodeur",
                    action = "Ne pas ré-encoder ni gonfler le débit dans le lecteur.",
                    settingKey = null,
                ),
            )
        }

        if (!aac && s.inSampleRate in 1 until 32_000) {
            out += Finding(
                id = "source_basse_freq",
                confidence = Confidence.HAUTE,
                kind = Kind.CAUSE,
                symptom = "Flux non AAC annoncé à ${khz(s.inSampleRate)}.",
                cause = "Les aigus au-dessus de la moitié de cette fréquence n'existent pas dans le flux.",
                fix = Fix(
                    file = FILE_VIEW,
                    symbol = "onAudioInputFormatChanged",
                    media3 = "Format.sampleRate",
                    action = "Ne pas sur-échantillonner pour « inventer » des aigus. Le défaut est dans la source.",
                    settingKey = null,
                ),
            )
        }

        // R5 — HE-AAC décodé par la box MAIS la sortie est déjà ≥ 32 kHz.
        // Le SBR a peut-être été appliqué (ou seulement rééchantillonné).
        // Sans spectre large qui innocente, on ne tranche pas.
        val boxHeAacHighRate = heAac && box && !s.passthrough && s.outSampleRate >= 32_000
        val spectrumClearsRadio = s.spectrum?.band == AudioSpectrum.Band.WIDE
        if (boxHeAacHighRate && !spectrumClearsRadio) {
            out += Finding(
                id = "heaac_box_freq_haute",
                confidence = Confidence.INCERTAINE,
                kind = Kind.CAUSE,
                symptom = "$profile décodé par la box, sortie ${khz(s.outSampleRate)}.",
                cause = "La fréquence de sortie a remonté : le SBR a pu être fait, ou le son a " +
                    "seulement été rééchantillonné. Le spectre ne prouve pas une coupure. On ne change rien.",
                fix = Fix(
                    file = FILE_VIEW,
                    symbol = "preferFfmpegFor",
                    media3 = "MediaCodecSelector + FfmpegAudioRenderer",
                    action = "Ne pas imposer FFmpeg. Le réglage zuno.audio.fix.ffmpeg reste un essai volontaire, " +
                        "pas la conclusion de cette règle.",
                    settingKey = null,
                ),
            )
        }

        spectrumFinding(s)?.let { out += it }
        cancellationFinding(s)?.let { out += it }
        out += stageFindings(s)
        ffmpegLowBandFinding(s)?.let { out += it }
        clippingFinding(s)?.let { out += it }
        delayFinding(s.avOffsetMs)?.let { out += it }

        if (s.underruns > 0) {
            out += Finding(
                id = "coupures",
                confidence = Confidence.HAUTE,
                kind = Kind.CAUSE,
                symptom = "${s.underruns} coupure(s) de la sortie son.",
                cause = "L'AudioTrack a été affamé (box chargée ou flux en à-coups). Ce n'est pas un passe-bas.",
                fix = Fix(
                    file = FILE_VIEW,
                    symbol = "NativeVideoView.buildAudioSink / AudioTrackBuffer.sized",
                    media3 = "DefaultAudioSink.AudioTrackBufferSizeProvider",
                    action = "Ne pas agrandir encore le tampon sans mesure sur la box. Le calcul actuel reste le défaut.",
                    settingKey = null,
                ),
            )
        }

        if (s.passthrough) {
            out += Finding(
                id = "passthrough",
                confidence = Confidence.HAUTE,
                kind = Kind.INFO,
                symptom = "Le son part tel quel (${s.outEncoding ?: "Dolby/DTS"}).",
                cause = "Pas de PCM dans l'app : la sonde et « voix claire » ne voient pas ce flux. " +
                    "La qualité dépend de la TV ou de la barre de son.",
                fix = Fix(
                    file = FILE_VIEW,
                    symbol = "buildAudioRenderers / preferFfmpegFor",
                    media3 = "DefaultRenderersFactory — passthrough AC-3 / E-AC-3 / DTS",
                    action = "Ne pas décoder de force en PCM : on perdrait le passthrough HDMI.",
                    settingKey = null,
                ),
            )
        }

        if (s.clearVoice) {
            out += Finding(
                id = "voix_claire",
                confidence = Confidence.HAUTE,
                kind = Kind.INFO,
                symptom = "« Voix claire » est allumée.",
                cause = "ClearVoiceGain baisse les pics (compresseur). Ce n'est pas un passe-bas : " +
                    "ça n'enlève pas l'énergie au-dessus de 4 kHz.",
                fix = Fix(
                    file = FILE_CLEAR,
                    symbol = "ClearVoiceProcessor.queueInput / ClearVoiceGain.target",
                    media3 = "DefaultAudioSink.setAudioProcessors",
                    action = "La couper est le réglage déjà existant (zuno.player.clear_voice.v1). " +
                        "Ce diagnostic ne la coupe pas et ne l'allume pas.",
                    settingKey = null,
                ),
            )
        }

        // spectre_absent n'est plus un bloc : la ligne « Spectre > 4 kHz »
        // dit déjà pourquoi il n'y a pas de chiffre. Répété 2 ou 3 fois
        // par chaîne, ce bloc noyait la fiche sans rien décider.
        out += phaseFindings(s)
        return out
    }

    /** Causes sûres seulement : celles qu'on a le droit de nommer sans réserve. */
    fun sureCauses(s: AudioSnapshot): List<Finding> =
        findings(s).filter { it.kind == Kind.CAUSE && it.confidence == Confidence.HAUTE }

    /**
     * Rapport court, sans URL et sans mot de passe. [redact] est rappelé
     * à la fin au cas où un libellé de décodeur contiendrait un secret.
     */
    fun report(s: AudioSnapshot): String {
        val header = buildString {
            append("Codec : ").append(codecName(s))
            if (!s.codecs.isNullOrBlank()) append(" (").append(s.codecs).append(')')
            append("\nEntrée : ")
            append(if (s.inSampleRate > 0) khz(s.inSampleRate) else "fréquence inconnue")
            append(", ")
            append(if (s.inChannels > 0) "${s.inChannels} voies" else "voies inconnues")
            if (s.bitrate > 0) append(", ${s.bitrate / 1000} kb/s")
            append("\nDécodeur : ")
            append(
                when {
                    s.decoder == null -> if (s.passthrough) "aucun (tel quel)" else "inconnu"
                    isFfmpeg(s.decoder) -> "FFmpeg (${s.decoder})"
                    else -> "box (${s.decoder})"
                },
            )
            append("\nSortie : ")
            append(s.outEncoding ?: "?")
            if (s.outSampleRate > 0) append(", ").append(khz(s.outSampleRate))
            if (s.outChannels > 0) append(", ${s.outChannels} voies")
            val spec = s.spectrum
            if (s.stages.isEmpty()) {
                append("\nPoint de mesure : PCM 16 bits du décodeur, après conversion entier, ")
                append("avant Sonic et avant l'AudioTrack.")
            } else {
                append("\nPoints de mesure (copie, le son n'est pas modifié) :")
                for (reading in s.stages) {
                    append("\n- ").append(stageLine(reading))
                }
                append("\nToInt16, le mapping de canaux et le trim sont avant « decodeur ». ")
                append("Ce ne sont pas des passe-bas. Pas de boucle HDMI : ")
                append("« audiotrack » est le dernier PCM dans l'app.")
            }
            append("\nEffets dans l'app : voix claire ")
            append(if (s.clearVoice) "allumée" else "coupée")
            append(", float coupé, silences ")
            append(if (s.skipSilence) "sautés" else "non sautés")
            append(", vitesse ")
            append(String.format(Locale.FRANCE, "%.2f", s.playbackSpeed))
            append(". Pas d'égaliseur, pas de DynamicsProcessing, pas de LoudnessEnhancer.")
            if (!s.routeNote.isNullOrBlank()) {
                append("\nEssai : ").append(s.routeNote)
            }
            if (s.cycle != null) {
                append("\n").append(PlayerCensus.describe(s.cycle))
            }
            append("\n").append(VolumeTrace.playbackNote(s.playback, s.playerAudible))
            if (!s.routeLine.isNullOrBlank()) {
                append("\n").append(s.routeLine)
            }
            if (!s.attributeLine.isNullOrBlank()) {
                append("\n").append(s.attributeLine)
            }
            append("\nSpectre > 4 kHz : ")
            append(
                when (spec?.band) {
                    null -> if (s.passthrough) {
                        "pas de PCM : le son part tel quel vers la TV"
                    } else {
                        ProbeAttach.absence(
                            requested = s.probeRequested,
                            inChain = s.probeInChain,
                            frames = s.probeFrames,
                            reject = s.probeReject,
                        ).symptom
                    }
                    AudioSpectrum.Band.WIDE -> "présent (${spec.percent()}) — pas un son radio"
                    AudioSpectrum.Band.LOW -> "bas (${spec.percent()}) — compatible passe-bas, cause non tranchée seule"
                    AudioSpectrum.Band.MID -> "intermédiaire (${spec.percent()}) — ne tranche pas"
                    AudioSpectrum.Band.SHORT -> "pas assez d'échantillons"
                    AudioSpectrum.Band.SILENCE -> "signal trop faible"
                    AudioSpectrum.Band.RATE -> "fréquence de sortie trop basse pour mesurer"
                },
            )
            val phase = spec?.phase
            if (phase != null && phase.channels >= 2 && !phase.correlation.isNaN()) {
                append("\nCorrélation gauche/droite (1 s, copie) : ")
                append(phase.correlationText())
                append(" · (G−D)/(G+D) ")
                append(phase.sideText())
                if (phase.opposed) append(" → voies opposées (voix centrale annulée)")
            }
            val recent = spec?.recentHighRatio
            if (recent != null) {
                append("\nDernière seconde > 4 kHz : ")
                append(String.format(Locale.FRANCE, "%.1f %%", recent * 100.0))
            }
            if (spec != null && spec.channelHighRatios.isNotEmpty()) {
                append("\nPar voie : ")
                spec.channelHighRatios.forEachIndexed { i, r ->
                    if (i > 0) append(" · ")
                    append("voie ").append(i + 1).append(' ')
                    append(String.format(Locale.FRANCE, "%.1f %%", r * 100.0))
                }
            }
            if (spec != null && spec.clippedFraction > 0.0) {
                append("\nSaturation : ")
                append(String.format(Locale.FRANCE, "%.2f %%", spec.clippedFraction * 100.0))
                append(" des échantillons au plafond")
            }
        }
        val lines = findings(s).joinToString("\n") { f ->
            val tag = if (f.confidence == Confidence.HAUTE) "HAUTE" else "INCERTAINE"
            val kind = if (f.kind == Kind.CAUSE) "CAUSE" else "INFO"
            buildString {
                append("\n[").append(tag).append(" · ").append(kind).append("] ").append(f.id)
                append("\nSymptôme : ").append(f.symptom)
                append("\nCause : ").append(f.cause)
                append("\nCorrectif : ").append(f.fix.file)
                append(" → ").append(f.fix.symbol)
                append("\nMedia3 : ").append(f.fix.media3)
                append("\nAction : ").append(f.fix.action)
                if (f.fix.settingKey != null) {
                    append("\nRéglage : ").append(f.fix.settingKey).append(" (défaut coupé, non imposé)")
                }
            }
        }
        val sure = sureCauses(s)
        val foot = if (sure.isEmpty()) {
            "\nConclusion : aucune cause sûre. On ne change pas le chemin par défaut."
        } else {
            "\nConclusion : ${sure.size} cause(s) sûre(s) — ${sure.joinToString(", ") { it.id }}. " +
                "Le correctif correspondant reste derrière son réglage, coupé par défaut."
        }
        return redact(header + lines + foot)
    }

    /** Retire une URL ou un secret si un libellé en portait un. */
    fun redact(text: String): String {
        var s = text
        s = Regex("https?://\\S+", RegexOption.IGNORE_CASE).replace(s, "[url]")
        s = Regex("\\b[\\w.+-]+:[^\\s/@]{1,80}@").replace(s, "[secret]@")
        s = Regex("(?i)(password|passwd|pwd|token|secret)=[^\\s&]+").replace(s) { m ->
            "${m.groupValues[1]}=[secret]"
        }
        return s
    }

    private fun ffmpegFix(action: String): Fix = Fix(
        file = FILE_VIEW,
        symbol = "NativeVideoView.preferFfmpegFor / buildAudioRenderers",
        media3 = "MediaCodecSelector (liste vide pour audio/mp4a-latm) + FfmpegAudioRenderer",
        action = action,
        settingKey = AudioFixes.KEY_FFMPEG,
    )

    /** Une ligne de fiche : id, pourcentage, bande, et où se trouve la sonde. */
    private fun stageLine(reading: AudioStages.Reading): String {
        val j = reading.judgement
        val place = when (reading.id) {
            AudioStages.DECODER ->
                "PCM 16 bits après ToInt16, mapping et trim, avant la voix claire"
            AudioStages.VOICE -> "après la voix claire"
            AudioStages.SILENCE -> "après le saut de silence, avant Sonic"
            AudioStages.SINK -> "PCM écrit dans l'AudioTrack, après Sonic"
            else -> reading.id
        }
        val band = when (AudioSpectrum.effectiveBand(j)) {
            AudioSpectrum.Band.WIDE -> "large"
            AudioSpectrum.Band.LOW -> "basse"
            AudioSpectrum.Band.MID -> "intermédiaire"
            AudioSpectrum.Band.SHORT -> "trop court"
            AudioSpectrum.Band.SILENCE -> "silence"
            AudioSpectrum.Band.RATE -> "fréquence trop basse"
        }
        val channels = if (j.channelHighRatios.isEmpty()) {
            ""
        } else {
            j.channelHighRatios.mapIndexed { i, ratio ->
                "voie ${i + 1} " + String.format(Locale.FRANCE, "%.1f %%", ratio * 100.0)
            }.joinToString(", ", prefix = " (", postfix = ")")
        }
        val phaseBit = j.phase?.let { p ->
            if (p.channels < 2 || p.correlation.isNaN()) {
                ""
            } else {
                " · G/D ${p.correlationText()}"
            }
        } ?: ""
        return "${reading.id} : ${j.percent()} $band — $place$channels$phaseBit"
    }

    /**
     * G ≈ −D : la voix au centre s'annule. On le dit, on ne change pas
     * le décodeur. Si seule une sonde plus tard est opposée, l'étage
     * entre les deux a inversé une voie.
     */
    private fun phaseFindings(s: AudioSnapshot): List<Finding> {
        val decoder = s.stages.firstOrNull { it.id == AudioStages.DECODER }?.judgement?.phase
            ?: s.spectrum?.phase
        val sink = s.stages.firstOrNull { it.id == AudioStages.SINK }?.judgement?.phase
        val out = ArrayList<Finding>(2)
        if (decoder != null && decoder.opposed) {
            out += Finding(
                id = "voies_opposees",
                confidence = Confidence.HAUTE,
                kind = Kind.INFO,
                symptom = "Corrélation gauche/droite ${decoder.correlationText()} sur 1 s, " +
                    "(G−D)/(G+D) = ${decoder.sideText()}.",
                cause = "Les deux voies s'opposent déjà au PCM du décodeur : une voix au centre " +
                    "s'annule, le son tombe « dans un trou ». Ce n'est pas un passe-bas. " +
                    "Le son témoin (voix puis bruit, voies ensemble) dit si l'appareil fait pareil.",
                fix = Fix(
                    file = FILE_PROBE,
                    symbol = "AudioProbeProcessor / AudioPhase",
                    media3 = "copie PCM, aucun échantillon modifié",
                    action = "Ne pas changer le décodeur sur ce seul chiffre. Comparer avec le son témoin " +
                        "et avec la sonde audiotrack.",
                    settingKey = null,
                ),
            )
        }
        if (decoder != null && sink != null && !decoder.correlation.isNaN() && !sink.correlation.isNaN() &&
            decoder.correlation >= 0.5 && sink.opposed
        ) {
            out += Finding(
                id = "inversion_etage",
                confidence = Confidence.HAUTE,
                kind = Kind.INFO,
                symptom = "Sonde décodeur ${decoder.correlationText()}, sonde audiotrack ${sink.correlationText()}.",
                cause = "Les voies sont ensemble après le décodeur et opposées juste avant l'AudioTrack. " +
                    "L'étage entre les deux (voix claire, silence ou Sonic) a inversé ou mélangé une voie. " +
                    "Les sondes, elles, copient.",
                fix = Fix(
                    file = FILE_STAGES,
                    symbol = "AudioStages / ZunoAudioChain",
                    media3 = "AudioProcessorChain entre decodeur et audiotrack",
                    action = "Noter quel étage change la corrélation. Ne pas changer le décodeur.",
                    settingKey = null,
                ),
            )
        }
        return out
    }

    /**
     * Compare les sondes entre elles. Une baisse WIDE → LOW/MID entre
     * deux sondes nomme l'étage. La même bande partout dit que les
     * processeurs après la sonde décodeur n'ont pas coupé.
     */
    private fun stageFindings(s: AudioSnapshot): List<Finding> {
        val readings = s.stages
        if (readings.size < 2) return emptyList()
        val drop = AudioStages.firstDrop(readings)
        if (drop != null) return listOf(stageDropFinding(readings, drop))
        if (!AudioStages.sameBand(readings)) return emptyList()
        return listOf(stagesAgreeFinding(readings))
    }

    private fun stageDropFinding(
        readings: List<AudioStages.Reading>,
        drop: AudioStages.Reading,
    ): Finding {
        val index = readings.indexOfFirst { it.id == drop.id }
        val before = readings[index - 1]
        val where = when (drop.id) {
            AudioStages.VOICE -> "entre la sonde décodeur et la sonde voix claire"
            AudioStages.SILENCE -> "entre la sonde voix claire et la sonde silence"
            AudioStages.SINK -> "entre la sonde silence et la sonde AudioTrack (Sonic)"
            else -> "à l'étape ${drop.id}"
        }
        val fix = when (drop.id) {
            AudioStages.VOICE -> Fix(
                file = FILE_CLEAR,
                symbol = "ClearVoiceProcessor.queueInput",
                media3 = "AudioProcessorChain : ClearVoiceProcessor entre decodeur et voix_claire",
                action = "La baisse est mesurée sur cet étage. « Voix claire » est un gain, " +
                    "pas un passe-bas : si elle est allumée, la couper (réglage déjà là) et remesurer. " +
                    "Ce diagnostic ne la coupe pas et ne change pas le décodeur.",
                settingKey = null,
            )
            AudioStages.SILENCE -> Fix(
                file = FILE_VIEW,
                symbol = "ZunoAudioChain.applySkipSilenceEnabled",
                media3 = "SilenceSkippingAudioProcessor (Player.skipSilenceEnabled)",
                action = "Les silences ne sont pas sautés (skipSilenceEnabled = false). " +
                    "Si la fiche montre quand même la baisse ici, c'est cet étage. " +
                    "On ne l'allume pas et on ne change pas le décodeur.",
                settingKey = null,
            )
            else -> Fix(
                file = FILE_VIEW,
                symbol = "ZunoAudioChain.applyPlaybackParameters",
                media3 = "SonicAudioProcessor, avant la sonde audiotrack",
                action = "La vitesse du direct est déjà figée à 1,0. Sonic ne rééchantillonne " +
                    "que si la fréquence ou la hauteur change. On ne change pas l'AudioTrack " +
                    "ni le décodeur : la baisse, si la fiche la montre, est ici.",
                settingKey = null,
            )
        }
        return Finding(
            id = "etage_coupe",
            confidence = Confidence.HAUTE,
            kind = Kind.CAUSE,
            symptom = "${before.id} ${before.judgement.percent()} puis ${drop.id} " +
                "${drop.judgement.percent()} ($where).",
            cause = "Un large bande est devenu plus étroit sur cet étage seulement. " +
                "Les copies d'identité ne font pas ça : le test le mesure. " +
                "Les sondes elles-mêmes copient le PCM, elles ne filtrent pas.",
            fix = fix,
        )
    }

    private fun stagesAgreeFinding(readings: List<AudioStages.Reading>): Finding {
        val band = AudioSpectrum.effectiveBand(readings.first().judgement)
        val nums = readings.joinToString(", ") { "${it.id} ${it.judgement.percent()}" }
        val low = band == AudioSpectrum.Band.LOW
        return Finding(
            id = "etages_pareils",
            confidence = if (band == AudioSpectrum.Band.WIDE) Confidence.HAUTE else Confidence.INCERTAINE,
            kind = Kind.INFO,
            symptom = "Même bande à chaque sonde : $nums.",
            cause = if (low) {
                "La bande au-dessus de 4 kHz est déjà basse à la sonde décodeur. " +
                    "Voix claire, silence et Sonic ne l'ont pas baissée ensuite. " +
                    "ToInt16, le mapping et le trim sont avant cette sonde et ne sont pas des passe-bas. " +
                    "Reste le contenu (une parole est naturellement basse) ou le PCM écrit par le décodeur."
            } else {
                "Aucun processeur après la sonde décodeur n'a changé la bande. " +
                    "On n'accuse pas la voix claire, le silence, Sonic, ni le mixage entre ces sondes."
            },
            fix = Fix(
                file = FILE_STAGES,
                symbol = "AudioStages.firstDrop / AudioStages.sameBand",
                media3 = "AudioProcessorChain (sondes en copie, NOT_SET si coupées)",
                action = "Ne pas changer le chemin par défaut sur ce seul accord. " +
                    "L'essai du décodeur de la box reste l'interrupteur zuno.audio.fix.platform, coupé.",
                settingKey = null,
            ),
        )
    }

    private fun spectrumFinding(s: AudioSnapshot): Finding? {
        val raw = s.spectrum ?: return null
        val band = AudioSpectrum.effectiveBand(raw)
        val loudest = raw.channelHighRatios.maxOrNull()
        val spec = if (band == AudioSpectrum.Band.WIDE && loudest != null && loudest > raw.highRatio) {
            raw.copy(band = band, highRatio = loudest)
        } else {
            raw.copy(band = band)
        }
        return when (spec.band) {
            AudioSpectrum.Band.WIDE -> Finding(
                id = "spectre_large",
                confidence = Confidence.HAUTE,
                kind = Kind.INFO,
                symptom = "Énergie au-dessus de 4 kHz = ${spec.percent()} (seuil large ${pct(AudioSpectrum.WIDE_MIN_RATIO)}).",
                cause = "Le signal mesuré est large bande. Ce n'est pas un son « vieille radio » " +
                    "par coupure au-dessus de 4 kHz. On ne change pas le décodeur pour cette raison.",
                fix = Fix(
                    file = FILE_SPECTRUM,
                    symbol = "AudioSpectrum.judge",
                    media3 = "AudioProcessor (sonde en copie, sans gain)",
                    action = "Aucun correctif. La règle WIDE interdit d'accuser un passe-bas.",
                    settingKey = null,
                ),
            )
            AudioSpectrum.Band.LOW -> Finding(
                id = "spectre_bas",
                confidence = Confidence.INCERTAINE,
                kind = Kind.CAUSE,
                symptom = "Énergie au-dessus de 4 kHz = ${spec.percent()} (seuil bas ${pct(AudioSpectrum.LOW_MAX_RATIO)}).",
                cause = "Ce rapport est celui d'un large bande après passe-bas, MAIS une voix " +
                    "naturelle (peu d'aigus) tombe dans la même zone. Sans une autre règle sûre " +
                    "(décodeur bloqué à 24 kHz, par exemple), on ne désigne pas le coupable.",
                fix = Fix(
                    file = FILE_SPECTRUM,
                    symbol = "AudioSpectrum.judge",
                    media3 = "AudioProcessor passe-haut 4 kHz (mesure seule, le son n'est pas filtré)",
                    action = "Ne pas ajouter de passe-bas, ne pas forcer FFmpeg sur ce seul chiffre.",
                    settingKey = null,
                ),
            )
            AudioSpectrum.Band.MID -> Finding(
                id = "spectre_incertain",
                confidence = Confidence.INCERTAINE,
                kind = Kind.CAUSE,
                symptom = "Énergie au-dessus de 4 kHz = ${spec.percent()} (entre ${pct(AudioSpectrum.LOW_MAX_RATIO)} et ${pct(AudioSpectrum.WIDE_MIN_RATIO)}).",
                cause = "Les deux seuils ne sont pas franchis. Cause incertaine : on ne conclut pas à un son radio.",
                fix = Fix(
                    file = FILE_SPECTRUM,
                    symbol = "AudioSpectrum.WIDE_MIN_RATIO / LOW_MAX_RATIO",
                    media3 = "AudioProcessor",
                    action = "Ne rien changer dans le lecteur.",
                    settingKey = null,
                ),
            )
            AudioSpectrum.Band.SHORT,
            AudioSpectrum.Band.SILENCE,
            AudioSpectrum.Band.RATE,
            -> null
        }
    }

    /**
     * Le mélange des voies est bas, mais une voie est large : les aigus
     * sont là, ils s'annulent dans le mélange. Ce n'est pas un passe-bas.
     */
    private fun cancellationFinding(s: AudioSnapshot): Finding? {
        val spec = s.spectrum ?: return null
        if (spec.band != AudioSpectrum.Band.LOW) return null
        if (AudioSpectrum.effectiveBand(spec) != AudioSpectrum.Band.WIDE) return null
        return Finding(
            id = "spectre_annulation",
            confidence = Confidence.HAUTE,
            kind = Kind.INFO,
            symptom = "Mélange des voies bas (${spec.percent()}), mais une voie reste large.",
            cause = "Les aigus sont présents sur au moins une voie. Le mélange les annule. " +
                "Ce n'est pas une coupure de bande du décodeur.",
            fix = Fix(
                file = FILE_SPECTRUM,
                symbol = "AudioSpectrum.effectiveBand / pushChannel",
                media3 = "AudioProcessor (mesure par voie, le son n'est pas modifié)",
                action = "Ne pas changer le décodeur sur le seul mélange.",
                settingKey = null,
            ),
        )
    }

    /**
     * Fiche du type France 24 : FFmpeg, AAC, 48 kHz, énergie haute basse.
     * Une voix naturelle donne le même chiffre. On ne change PAS le défaut.
     * L'essai « décodeur de la box » est proposé, coupé.
     */
    private fun ffmpegLowBandFinding(s: AudioSnapshot): Finding? {
        val spec = s.spectrum ?: return null
        if (AudioSpectrum.effectiveBand(spec) != AudioSpectrum.Band.LOW) return null
        if (!isFfmpeg(s.decoder) || !isAac(s.mime) || s.passthrough) return null
        if (s.outSampleRate < 32_000) return null
        return Finding(
            id = "ffmpeg_essai_box",
            confidence = Confidence.INCERTAINE,
            kind = Kind.CAUSE,
            symptom = "FFmpeg sort un ${codecName(s)} à ${khz(s.outSampleRate)}, " +
                "énergie > 4 kHz = ${spec.percent()}.",
            cause = "Deux lectures possibles, et les tests ne les séparent pas : " +
                "une voix (France 24) est naturellement pauvre au-dessus de 4 kHz, " +
                "OU le décodeur FFmpeg n'a pas reconstruit des aigus que le décodeur " +
                "de la box aurait gardés (SBR mal signalé, vu comme AAC-LC). " +
                "Un AAC-LC large bande à 128 kb/s décodé par FFmpeg 6.1 reste large " +
                "(mesure 72 %). On n'accuse donc pas FFmpeg sans l'essai sur la box.",
            fix = Fix(
                file = FILE_VIEW,
                symbol = "AudioFixes.ffmpegForAac / NativeVideoView.preferFfmpegFor",
                media3 = "MediaCodecSelector : liste normale (décodeur de la box) au lieu de la liste vide",
                action = "Allumer zuno.audio.fix.platform et rouvrir la chaîne. " +
                    "Comparer le pourcentage. S'il reste bas, c'est le contenu, pas le décodeur. " +
                    "S'il devient large, FFmpeg était en cause sur CETTE chaîne. " +
                    "Le défaut (réglage coupé) reste FFmpeg. Si la box échoue, on revient à FFmpeg " +
                    "pour cette ouverture.",
                settingKey = AudioFixes.KEY_PLATFORM,
            ),
        )
    }

    private fun clippingFinding(s: AudioSnapshot): Finding? {
        val spec = s.spectrum ?: return null
        val frac = spec.clippedFraction
        if (frac < AudioSpectrum.CLIP_GREY) return null
        val sure = frac >= AudioSpectrum.CLIP_SURE
        val already = s.clearVoice
        return Finding(
            id = "saturation",
            confidence = if (sure && !already) Confidence.HAUTE else Confidence.INCERTAINE,
            kind = Kind.CAUSE,
            symptom = String.format(
                Locale.FRANCE,
                "%.2f %% des échantillons |s| ≥ %d (pic %d).",
                frac * 100.0,
                AudioSpectrum.CLIP_ABS,
                spec.peak,
            ),
            cause = if (already) {
                "Des pics touchent encore le plafond alors que « voix claire » est déjà allumée. " +
                    "ClearVoiceGain ne descend pas sous ${ClearVoiceGain.MIN_GAIN}. On ne compresse pas plus."
            } else if (sure) {
                "Assez d'échantillons sont collés au plafond 16 bits pour parler de saturation, " +
                    "pas d'un simple passage à pleine échelle."
            } else {
                "Quelques échantillons touchent le plafond. Ça peut être un vrai écrêtage ou " +
                    "juste un signal fort. Cause incertaine."
            },
            fix = Fix(
                file = FILE_GAIN,
                symbol = "ClearVoiceGain.target / ClearVoiceProcessor.queueInput",
                media3 = "DefaultAudioSink.setAudioProcessors(ClearVoiceProcessor)",
                action = "Le réglage existant « voix claire » (zuno.player.clear_voice.v1) baisse les pics. " +
                    "Ce diagnostic ne l'allume pas : le défaut reste coupé.",
                settingKey = null,
            ),
        )
    }

    /**
     * Décalage image/son. Null ou dans la tolérance → pas de ligne
     * (un petit écart n'est pas un défaut, et une absence de mesure
     * n'est pas un décalage).
     */
    fun delayFinding(offsetMs: Int?): Finding? {
        if (offsetMs == null) return null
        val abs = if (offsetMs < 0) -offsetMs else offsetMs
        if (abs <= OFFSET_OK_MS) return null
        val sure = abs >= OFFSET_SURE_MS
        return Finding(
            id = "decalage",
            confidence = if (sure) Confidence.HAUTE else Confidence.INCERTAINE,
            kind = Kind.CAUSE,
            symptom = "Écart image/son ${offsetMs} ms.",
            cause = if (sure) {
                "L'écart dépasse ${OFFSET_SURE_MS} ms."
            } else {
                "L'écart est entre ${OFFSET_OK_MS} et ${OFFSET_SURE_MS} ms : cause incertaine."
            },
            fix = Fix(
                file = FILE_VIEW,
                symbol = "ExoPlayer.Builder.setVideoChangeFrameRateStrategy / attachToSurface",
                media3 = "C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_OFF et Player.skipSilenceEnabled = false",
                action = "Ces deux réglages sont DÉJÀ en place (changer la fréquence HDMI et sauter " +
                    "les silences décalaient le son). Ne pas y toucher. Aucune nouvelle correction " +
                    "n'est appliquée : la box ne fournit pas encore cette mesure toute seule.",
                settingKey = null,
            ),
        )
    }

    private fun pct(ratio: Double): String =
        String.format(Locale.FRANCE, "%.0f %%", ratio * 100.0)
}
