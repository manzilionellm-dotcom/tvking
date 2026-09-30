package com.manzilionellm.native_video_player.logic

/**
 * Jeton de lecture. Chaque zap ou chaque « silence » en ouvre un
 * nouveau : un callback lancé pour l'ancien jeton ne doit plus
 * préparer, ni relancer le son.
 *
 * Pur Kotlin, sans Android : les tests JVM l'exécutent tel quel.
 * [com.manzilionellm.native_video_player.NativeVideoView] s'en sert.
 */
class PlaybackSession {
    var generation: Int = 0
        private set

    /** Nouvelle session. L'ancienne est morte immédiatement. */
    fun open(): Int {
        generation += 1
        return generation
    }

    fun isCurrent(token: Int): Boolean = token > 0 && token == generation
}
