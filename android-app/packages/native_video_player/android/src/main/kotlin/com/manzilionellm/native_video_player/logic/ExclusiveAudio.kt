package com.manzilionellm.native_video_player.logic

/**
 * Un seul lecteur a le droit de sortir du son.
 *
 * [claim] fait taire TOUS les autres inscrits, tout de suite, avant
 * que le nouveau ne démarre. Le rappel de silence ne doit pas rappeler
 * [claim] : sinon deux lecteurs se couperaient l'un l'autre sans fin.
 *
 * Pur Kotlin (pas d'Android) pour pouvoir le tester sans box.
 */
class ExclusiveAudio {
    private val silence = LinkedHashMap<Int, () -> Unit>()
    private var nextId = 0

    /** Lecteur autorisé à parler. null = personne. */
    var owner: Int? = null
        private set

    val registeredCount: Int get() = silence.size

    fun register(onSilence: () -> Unit): Int {
        nextId += 1
        silence[nextId] = onSilence
        return nextId
    }

    fun unregister(id: Int) {
        silence.remove(id)
        if (owner == id) owner = null
    }

    fun claim(id: Int) {
        owner = id
        val others = silence.keys.toList()
        for (other in others) {
            if (other != id) silence[other]?.invoke()
        }
    }
}
