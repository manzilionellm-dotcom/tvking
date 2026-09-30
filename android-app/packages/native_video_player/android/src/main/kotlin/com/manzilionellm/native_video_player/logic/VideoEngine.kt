package com.manzilionellm.native_video_player.logic

/**
 * Moteur vidéo choisi pour UNE lecture.
 *
 *  - [HARDWARE] : MediaCodec de la box (Amlogic, etc.). C'est le chemin
 *    qui affiche l'image depuis les versions 102 à 104. On y revient
 *    à chaque nouvelle chaîne, sauf si la personne a demandé autre chose.
 *  - [SOFTWARE] : le décodeur logiciel Android (`OMX.google.*` ou
 *    `c2.android.*`), mis en tête de liste. Plus de CPU, utile quand
 *    le décodeur de la box échoue ou reste noir.
 *  - [FFMPEG] : le rendu vidéo FFmpeg de Media3. On ne l'installe que
 *    si la bibliothèque native déclare un décodeur vidéo. Le binaire
 *    Jellyfin livré avec le son (v104) n'en a pas : ce cas reste alors
 *    fermé, et on ne construit pas le rendu (leçon v99–v101).
 *
 * Le nom [wire] est celui qui voyage vers Dart (`hardware`, `software`,
 * `ffmpeg`). Inconnu → matériel : on ne change pas l'image tout seul.
 */
enum class VideoEngine {
    HARDWARE,
    SOFTWARE,
    FFMPEG,
    ;

    val wire: String
        get() = name.lowercase()

    companion object {
        fun fromWire(raw: String?): VideoEngine = when (raw?.lowercase()) {
            "software" -> SOFTWARE
            "ffmpeg" -> FFMPEG
            else -> HARDWARE
        }
    }
}
