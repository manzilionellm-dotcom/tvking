package com.manzilionellm.native_video_player.logic

/**
 * TYPE DÉCLARÉ À ANDROID (03/10/2026) — essai « film / musique / parole ».
 *
 * Zuno dit aujourd'hui au téléphone et à la box : « c'est de la musique
 * au sens du volume (usage média), et le contenu est un film ». Android
 * peut alors appliquer un traitement d'après (Dolby, spatialisation,
 * renforcement de dialogue). Ce fichier ne change PAS ce défaut.
 *
 * [OFF] : on laisse la règle déjà en place.
 *   • voix claire coupée → film ;
 *   • voix claire allumée → parole.
 * [MOVIE], [MUSIC], [SPEECH] : on force ce type, le temps de l'essai.
 * Les échantillons PCM ne sont pas touchés. L'usage reste « média ».
 * Les numéros sont ceux d'Android (AudioAttributes), recopiés ici pour
 * que le test n'ait pas besoin du SDK.
 *
 * Pur Kotlin.
 */
object AudioContentChoice {

    /** Interrupteur coupé. Clé lue par l'écran Diagnostic du son. */
    const val KEY: String = "zuno.audio.diag.content_type"

    const val OFF: Int = -1
    const val SPEECH: Int = 1
    const val MUSIC: Int = 2
    const val MOVIE: Int = 3

    const val WIRE_OFF: String = "off"
    const val WIRE_MOVIE: String = "movie"
    const val WIRE_MUSIC: String = "music"
    const val WIRE_SPEECH: String = "speech"

    /**
     * Mot envoyé par l'écran. Tout ce qui n'est pas film, musique ou
     * parole reste coupé : une valeur illisible ne change pas le son.
     */
    fun fromWire(raw: String?): Int = when (raw) {
        WIRE_MOVIE -> MOVIE
        WIRE_MUSIC -> MUSIC
        WIRE_SPEECH -> SPEECH
        else -> OFF
    }

    fun toWire(choice: Int): String = when (choice) {
        MOVIE -> WIRE_MOVIE
        MUSIC -> WIRE_MUSIC
        SPEECH -> WIRE_SPEECH
        else -> WIRE_OFF
    }

    /** Ordre du bouton : coupé → film → musique → parole → coupé. */
    fun next(choice: Int): Int = when (choice) {
        OFF -> MOVIE
        MOVIE -> MUSIC
        MUSIC -> SPEECH
        else -> OFF
    }

    /**
     * Type réellement envoyé à l'AudioTrack et à la demande de focus.
     * L'essai gagne sur la voix claire : sinon on ne saurait pas si
     * c'est le compresseur ou le mot « parole » qui change l'oreille.
     */
    fun declared(choice: Int, clearVoice: Boolean): Int {
        return when (choice) {
            MOVIE -> MOVIE
            MUSIC -> MUSIC
            SPEECH -> SPEECH
            else -> if (clearVoice) SPEECH else MOVIE
        }
    }

    fun name(type: Int): String = when (type) {
        SPEECH -> "parole"
        MUSIC -> "musique"
        MOVIE -> "film"
        else -> "inconnu"
    }

    fun buttonLabel(choice: Int): String = when (choice) {
        MOVIE -> "Type : film"
        MUSIC -> "Type : musique"
        SPEECH -> "Type : parole"
        else -> "Type : coupé"
    }

    /**
     * Une ligne de boîte noire. Pas d'adresse, pas de mot de passe.
     * « coupé » = le chemin d'avant. « essai » = le bouton a été tourné.
     */
    fun diagLine(choice: Int, clearVoice: Boolean): String {
        val declared = declared(choice, clearVoice)
        val how = if (choice == OFF) "interrupteur coupé" else "essai"
        return "Type déclaré : ${name(declared)} ($how). " +
            "Usage musique, drapeaux 0, délestage coupé, tunnel coupé."
    }
}
