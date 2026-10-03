package com.manzilionellm.native_video_player.logic

/**
 * ESSAI D'ATTRIBUTS AUDIO (03/10/2026) — film / musique / parole / défaut Media3.
 *
 * Zuno envoie aujourd'hui un contenu « film » (CONTENT_TYPE_MOVIE) avec
 * l'usage « média ». Le défaut de Media3 1.5.1, et le constructeur ancien
 * de VLC 3.0 (STREAM_MUSIC) sur Android 14 et 15, laissent le contenu
 * « inconnu ». Android dit que ce contenu sert à brancher des traitements
 * APRÈS l'AudioTrack (surround virtuel, voix, Dolby). Les sondes PCM ne
 * voient pas cet étage : elles s'arrêtent avant l'AudioTrack.
 *
 * Cet objet ne parle pas à Android. Il choisit les chiffres. Coupé
 * ([OFF]), les chiffres sont ceux d'aujourd'hui : film, ou parole si la
 * voix claire est allumée. Les autres modes sont un essai. Aucun mode
 * n'allume le tunneling, l'offload, ni un drapeau. Le tampon ne se décide
 * pas ici.
 *
 * Les numéros sont ceux d'Android et de Media3 (C.USAGE_MEDIA = 1,
 * CONTENT_TYPE_UNKNOWN = 0, SPEECH = 1, MUSIC = 2, MOVIE = 3,
 * ALLOW_CAPTURE_BY_ALL = 1, SPATIALIZATION_BEHAVIOR_AUTO = 0,
 * AudioTrack.PERFORMANCE_MODE_NONE = 0). Recopiés pour le test sans SDK.
 */
object AudioProfile {

    const val KEY: String = "zuno.audio.profile"

    const val OFF: String = "off"
    const val FILM: String = "film"
    const val MUSIC: String = "musique"
    const val SPEECH: String = "parole"
    const val MEDIA3: String = "media3"

    /** Ordre du bouton Diagnostic du son. Le premier est le défaut. */
    val ORDER: List<String> = listOf(OFF, FILM, MUSIC, SPEECH, MEDIA3)

    const val USAGE_MEDIA: Int = 1
    const val CONTENT_UNKNOWN: Int = 0
    const val CONTENT_SPEECH: Int = 1
    const val CONTENT_MUSIC: Int = 2
    const val CONTENT_MOVIE: Int = 3

    const val FLAGS_NONE: Int = 0
    const val CAPTURE_ALL: Int = 1
    const val SPATIAL_AUTO: Int = 0
    const val PERFORMANCE_NONE: Int = 0

    /**
     * Réglage en cours, partagé par les vues. « off » au démarrage :
     * une préférence absente ne change pas le son.
     */
    @Volatile
    var current: String = OFF

    /**
     * Chiffres qui partiront vers l'AudioTrack et vers la demande de focus.
     * [trial] faux = comportement d'aujourd'hui, même si les chiffres
     * coïncident avec « film ».
     */
    data class Choice(
        val wire: String,
        val trial: Boolean,
        val usage: Int,
        val contentType: Int,
        val flags: Int,
        val allowedCapturePolicy: Int,
        val spatializationBehavior: Int,
        val offload: Boolean,
        val tunneling: Boolean,
        val performanceMode: Int,
        /** Vrai : la voix claire voulait « parole », l'essai a choisi autre chose. */
        val overridesClearVoice: Boolean,
    )

    /** Texte inconnu, vide ou null → coupé. On ne devine pas un mode. */
    fun parse(raw: String?): String = when (raw) {
        FILM, MUSIC, SPEECH, MEDIA3 -> raw
        else -> OFF
    }

    fun next(raw: String?): String {
        val cur = parse(raw)
        val i = ORDER.indexOf(cur)
        return ORDER[(i + 1) % ORDER.size]
    }

    /**
     * Faut-il rouvrir la chaîne pour que l'AudioTrack naisse avec les
     * nouveaux chiffres ? Seulement si elle joue ET que le mode change.
     * Repousser « off » alors qu'on est déjà coupé ne rouvre pas.
     */
    fun shouldReopen(previous: String?, next: String?, playing: Boolean): Boolean {
        if (!playing) return false
        return parse(previous) != parse(next)
    }

    fun resolve(raw: String?, clearVoice: Boolean): Choice {
        val wire = parse(raw)
        val content = when (wire) {
            FILM -> CONTENT_MOVIE
            MUSIC -> CONTENT_MUSIC
            SPEECH -> CONTENT_SPEECH
            MEDIA3 -> CONTENT_UNKNOWN
            else -> if (clearVoice) CONTENT_SPEECH else CONTENT_MOVIE
        }
        return Choice(
            wire = wire,
            trial = wire != OFF,
            usage = USAGE_MEDIA,
            contentType = content,
            flags = FLAGS_NONE,
            allowedCapturePolicy = CAPTURE_ALL,
            spatializationBehavior = SPATIAL_AUTO,
            offload = false,
            tunneling = false,
            performanceMode = PERFORMANCE_NONE,
            overridesClearVoice = clearVoice && wire != OFF && content != CONTENT_SPEECH,
        )
    }

    /** Défaut Media3 1.5.1 : AudioAttributes.DEFAULT (Builder vide côté Media3). */
    fun media3Default(): Choice = resolve(MEDIA3, clearVoice = false)

    /**
     * VLC 3.0.23 crée l'AudioTrack avec l'ancien STREAM_MUSIC, pas avec
     * un contenu « film ». Android 14 et 15 laissent alors le contenu
     * inconnu (ils refusent de deviner « musique » pour ce flux).
     * L'usage retombe sur média. Ce n'est pas un réglage écrit par VLC :
     * c'est la traduction du système.
     */
    fun vlc30LegacyContentType(): Int = CONTENT_UNKNOWN

    fun contentLabel(contentType: Int): String = when (contentType) {
        CONTENT_SPEECH -> "parole"
        CONTENT_MUSIC -> "musique"
        CONTENT_MOVIE -> "film"
        CONTENT_UNKNOWN -> "inconnu"
        else -> "type $contentType"
    }

    /** Une seule ligne, sans adresse et sans mot de passe. */
    fun line(choice: Choice): String {
        val trial = when (choice.wire) {
            FILM -> "essai film"
            MUSIC -> "essai musique"
            SPEECH -> "essai parole"
            MEDIA3 -> "essai défaut Media3"
            else -> "essai coupé"
        }
        val gap = if (choice.contentType == CONTENT_UNKNOWN) {
            "aucun écart de contenu avec le défaut Media3 (inconnu)"
        } else {
            "seul le contenu diffère du défaut Media3 (inconnu) : ici ${contentLabel(choice.contentType)}"
        }
        val voice = when {
            choice.overridesClearVoice ->
                " La voix claire reste un compresseur : cet essai remplace le contenu parole qu'elle mettait."
            choice.wire == OFF && choice.contentType == CONTENT_SPEECH ->
                " Contenu parole parce que la voix claire est allumée (comportement d'aujourd'hui)."
            else -> ""
        }
        return "Attributs : $trial, usage média, contenu ${contentLabel(choice.contentType)}, " +
            "drapeaux ${choice.flags}, capture tous, spatialisation auto, " +
            "performance aucune, tunneling ${if (choice.tunneling) "allumé" else "coupé"}, " +
            "offload ${if (choice.offload) "allumé" else "coupé"}, " +
            "session attribuée par Android. $gap. " +
            "VLC 3.0 (ancien flux musique) laisse le contenu inconnu. " +
            "Cet essai ne change pas le tampon ni le passthrough.$voice"
    }
}
