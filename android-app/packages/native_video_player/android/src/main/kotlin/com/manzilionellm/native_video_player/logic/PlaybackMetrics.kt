package com.manzilionellm.native_video_player.logic

/**
 * Mesures d'une lecture logique, indépendantes d'Android pour être vérifiables.
 * Toutes les heures viennent d'elapsedRealtime, jamais de l'horloge civile.
 * Une reconstruction de décodeur change la génération, pas cette session.
 */
class PlaybackMetrics(
    val sessionId: Long,
    val mediaId: Long,
    val startedElapsedMs: Long,
) {
    enum class State { BUFFERING, READY, ENDED, OTHER }
    enum class EndReason(val wire: String) {
        MEDIA_CHANGED("media_changed"), SILENCED("silenced"),
        ENDED("ended"), DISPOSED("disposed"), DISABLED("disabled"),
    }

    private var generation: Int? = null
    private var generationOpenedMs = startedElapsedMs
    private var firstFrameMs: Long? = null
    private var finished = false
    private var lastStateMs = startedElapsedMs
    private var plannedInterruption = false
    private var rebufferStartedMs: Long? = null
    private var rebufferCount = 0L
    private var rebufferTotalMs = 0L
    private var decoderIdentity: Any? = null
    private var decoderLastDropped = 0L
    private var decoderDropped = 0L
    private var decoderObserved = false
    private var listenerDropped = 0L
    private var listenerObserved = false
    private var liveOffsetMs: Long? = null

    init {
        require(sessionId in 1..MAX_VALUE && mediaId in 1..MAX_VALUE)
        require(startedElapsedMs in 0..MAX_VALUE)
    }

    fun activateGeneration(value: Int, openedElapsedMs: Long) {
        if (finished || openedElapsedMs < startedElapsedMs) return
        generation = value
        generationOpenedMs = openedElapsedMs
    }

    fun invalidateGeneration() {
        generation = null
    }

    fun accepts(value: Int, eventElapsedMs: Long): Boolean =
        !finished && generation == value && eventElapsedMs >= generationOpenedMs &&
            eventElapsedMs <= MAX_VALUE

    /** Une ancienne première image ne devient jamais celle du nouveau média. */
    fun firstFrame(
        generation: Int,
        eventElapsedMs: Long,
        renderedElapsedMs: Long,
    ): PlaybackMetricsSnapshot? {
        if (!accepts(generation, eventElapsedMs) || firstFrameMs != null ||
            renderedElapsedMs < generationOpenedMs || renderedElapsedMs > eventElapsedMs
        ) return null
        firstFrameMs = renderedElapsedMs
        return snapshot("first_frame", eventElapsedMs, null)
    }

    fun state(value: Int, atMs: Long, state: State, mayPlay: Boolean) {
        if (!accepts(value, atMs) || atMs < lastStateMs) return
        lastStateMs = atMs
        when {
            !mayPlay -> closeRebuffer(atMs)
            state == State.READY -> {
                closeRebuffer(atMs)
                plannedInterruption = false
            }
            state == State.ENDED -> closeRebuffer(atMs)
            state == State.BUFFERING && firstFrameMs != null &&
                !plannedInterruption && rebufferStartedMs == null -> {
                rebufferStartedMs = atMs
                rebufferCount = addBounded(rebufferCount, 1)
            }
        }
    }

    /** Pause, recherche, Home et Cast ne sont pas des pannes réseau. */
    fun plannedInterruption(atMs: Long) {
        if (finished || atMs < lastStateMs || atMs > MAX_VALUE) return
        closeRebuffer(atMs)
        lastStateMs = atMs
        plannedInterruption = true
    }

    /** Une commande sans interruption réelle ne masque pas la panne suivante. */
    fun readyObserved(value: Int, atMs: Long) {
        if (accepts(value, atMs)) plannedInterruption = false
    }

    /** Le compteur présent avant le zap appartient encore à l'ancien média. */
    fun decoderBaseline(identity: Any, dropped: Long) {
        if (finished || dropped < 0) return
        decoderIdentity = identity
        decoderLastDropped = dropped.coerceAtMost(MAX_VALUE)
    }

    /** Compteur cumulatif principal ; relire le même total n'ajoute rien. */
    fun decoderSample(identity: Any, dropped: Long) {
        if (finished || dropped < 0) return
        val total = dropped.coerceAtMost(MAX_VALUE)
        val delta = if (identity === decoderIdentity && total >= decoderLastDropped) {
            total - decoderLastDropped
        } else {
            // Nouveau décodeur, ou compteur remis à zéro dans le même objet.
            total
        }
        decoderDropped = addBounded(decoderDropped, delta)
        decoderIdentity = identity
        decoderLastDropped = total
        decoderObserved = true
    }

    /** Repli seulement : ce total n'est JAMAIS ajouté au total du décodeur. */
    fun droppedFrames(value: Int, atMs: Long, count: Long) {
        if (!accepts(value, atMs) || count < 0) return
        listenerDropped = addBounded(listenerDropped, count.coerceAtMost(MAX_VALUE))
        listenerObserved = true
    }

    fun liveOffset(value: Long?) {
        if (finished) return
        // Une valeur négative connue reste visible ; inconnue reste null.
        liveOffsetMs = value?.takeIf { it in -MAX_VALUE..MAX_VALUE }
    }

    fun finish(reason: EndReason, atMs: Long): PlaybackMetricsSnapshot? {
        if (finished || atMs < startedElapsedMs || atMs < lastStateMs || atMs > MAX_VALUE) return null
        closeRebuffer(atMs)
        finished = true
        generation = null
        return snapshot("summary", atMs, reason.wire)
    }

    private fun closeRebuffer(atMs: Long) {
        val start = rebufferStartedMs ?: return
        if (atMs < start) return
        rebufferTotalMs = addBounded(rebufferTotalMs, atMs - start)
        rebufferStartedMs = null
    }

    private fun snapshot(kind: String, atMs: Long, reason: String?) = PlaybackMetricsSnapshot(
        kind = kind,
        sessionId = sessionId,
        mediaId = mediaId,
        startedElapsedMs = startedElapsedMs,
        observedElapsedMs = atMs,
        firstFrameElapsedMs = firstFrameMs,
        startupMs = firstFrameMs?.minus(startedElapsedMs),
        elapsedMs = atMs - startedElapsedMs,
        droppedFrames = when {
            decoderObserved -> decoderDropped
            listenerObserved -> listenerDropped
            else -> null
        },
        droppedSource = when {
            decoderObserved -> "decoder"
            listenerObserved -> "listener"
            else -> null
        },
        rebufferCount = rebufferCount,
        rebufferMs = rebufferTotalMs,
        liveOffsetMs = liveOffsetMs,
        endReason = reason,
    )

    companion object {
        // Entier exact sur les deux côtés du canal ; aucune liste de trames.
        const val MAX_VALUE = 9_000_000_000_000_000L
        private fun addBounded(a: Long, b: Long): Long = a + b.coerceAtMost(MAX_VALUE - a)
    }
}

data class PlaybackMetricsSnapshot(
    val kind: String,
    val sessionId: Long,
    val mediaId: Long,
    val startedElapsedMs: Long,
    val observedElapsedMs: Long,
    val firstFrameElapsedMs: Long?,
    val startupMs: Long?,
    val elapsedMs: Long,
    val droppedFrames: Long?,
    val droppedSource: String?,
    val rebufferCount: Long,
    val rebufferMs: Long,
    val liveOffsetMs: Long?,
    val endReason: String?,
) {
    /** Contrat fermé : ni URL, ni titre, ni identifiant du fournisseur. */
    fun toWire(): Map<String, Any?> = mapOf(
        "schema" to 1, "origin" to "android_media3", "kind" to kind,
        "sessionId" to sessionId, "mediaId" to mediaId,
        "startedElapsedMs" to startedElapsedMs, "observedElapsedMs" to observedElapsedMs,
        "firstFrameElapsedMs" to firstFrameElapsedMs, "startupMs" to startupMs,
        "elapsedMs" to elapsedMs, "droppedFrames" to droppedFrames,
        "droppedSource" to droppedSource, "rebufferCount" to rebufferCount,
        "rebufferMs" to rebufferMs, "liveOffsetMs" to liveOffsetMs,
        "endReason" to endReason,
    )
}
