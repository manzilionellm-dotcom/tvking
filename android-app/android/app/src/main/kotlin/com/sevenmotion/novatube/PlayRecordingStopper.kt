package com.sevenmotion.novatube

import java.util.concurrent.atomic.AtomicBoolean

/**
 * Arrêt idempotent réservé à NOVATUBE Play.
 *
 * Le système laisse quelques secondes après onTimeout : retirer le service
 * du premier plan et appeler stopSelf doit précéder toute fermeture réseau
 * ou attente d'un thread. Chaque nettoyage reste tenté si un autre échoue.
 * Les callbacks réseau planifient leur travail hors du thread principal.
 */
class PlayRecordingStopper(
    private val endForeground: () -> Unit,
    private val releaseLocks: () -> Unit,
    private val cancelProducer: () -> Unit,
    private val notifyStopped: (String) -> Unit,
    private val onFailure: (Throwable) -> Unit,
) {
    private val stopped = AtomicBoolean(false)
    val isStopped: Boolean get() = stopped.get()

    fun stop(reason: String): Boolean {
        if (!stopped.compareAndSet(false, true)) return false
        for (step in listOf(endForeground, releaseLocks, cancelProducer, { notifyStopped(reason) })) {
            try {
                step()
            } catch (error: Throwable) {
                onFailure(error)
            }
        }
        return true
    }
}
