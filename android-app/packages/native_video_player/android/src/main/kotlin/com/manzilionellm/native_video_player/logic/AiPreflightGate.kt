package com.manzilionellm.native_video_player.logic

import java.util.concurrent.atomic.AtomicLong

/**
 * Le GPU sert d'abord le premier écran et les lecteurs. Le préflight ne devient
 * éligible qu'après la première image de CHAQUE moteur encore attaché, hors vidéo.
 * Un moteur sans interface le suspend jusqu'à son détachement : le rendu natif
 * reste disponible sans rapport IA. Aucun délai arbitraire ne simule un écran prêt.
 */
class AiPreflightGate(private val onReady: () -> Unit) {
    private val interfaces = LinkedHashMap<UiRegistration, Boolean>()
    private val uiEpoch = AtomicLong()
    private val playback = AiPlaybackLeases { notifyIfReady() }

    val hasPlayback: Boolean get() = playback.hasActive
    val playbackGeneration: Long get() = playback.generation
    val uiGeneration: Long get() = uiEpoch.get()
    val canRun: Boolean get() = synchronized(interfaces) {
        interfaces.isNotEmpty() && interfaces.values.all { it }
    } && !hasPlayback

    fun acquirePlayback(owner: Any): AutoCloseable = playback.acquire(owner)

    fun attachUi(): UiRegistration = synchronized(interfaces) {
        UiRegistration().also {
            interfaces[it] = false
            // Même attaché/détaché entre deux checkpoints, un nouveau démarrage
            // invalide le travail GPU qui était déjà en cours.
            uiEpoch.incrementAndGet()
        }
    }

    private fun notifyIfReady() {
        if (canRun) onReady()
    }

    inner class UiRegistration internal constructor() : AutoCloseable {
        fun firstFrameDisplayed() {
            val changed = synchronized(interfaces) {
                if (interfaces[this] != false) false
                else { interfaces[this] = true; true }
            }
            // Un callback posté avant detach ne recrée jamais son propriétaire.
            if (changed) notifyIfReady()
        }

        override fun close() {
            val wasReady = synchronized(interfaces) { interfaces.remove(this) }
            // Retirer le dernier moteur en attente peut libérer un autre moteur
            // déjà affiché. Fermer deux fois ne relance aucun travail.
            if (wasReady == false) notifyIfReady()
        }
    }
}
