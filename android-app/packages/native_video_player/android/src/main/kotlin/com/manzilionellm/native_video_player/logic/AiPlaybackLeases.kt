package com.manzilionellm.native_video_player.logic

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/** Un propriétaire peut avoir plusieurs décodeurs ; chaque bail est indépendant. */
class AiPlaybackLeases(private val onIdle: () -> Unit = {}) {
    private val next = AtomicLong()
    private val owners = ConcurrentHashMap<Long, Any>()
    val hasActive: Boolean get() = owners.isNotEmpty()
    /** Détecte aussi acquire+close entièrement entre deux checkpoints de calcul. */
    val generation: Long get() = next.get()

    fun acquire(owner: Any): AutoCloseable {
        val id = next.incrementAndGet()
        owners[id] = owner
        val closed = AtomicBoolean(false)
        return AutoCloseable {
            if (closed.compareAndSet(false, true)) {
                owners.remove(id)
                if (!hasActive) onIdle()
            }
        }
    }
}
