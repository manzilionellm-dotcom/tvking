package com.manzilionellm.native_video_player.logic

/**
 * Propriété locale du réseau pendant un Cast. Le verrou est indépendant du
 * cycle Home/retour et partagé avec les fils de chargement Media3.
 *
 * Une source est comptée AVANT open(), même si open échoue. Elle n'est rendue
 * qu'après close() réussi. L'ACK Stop du lecteur ne suffit donc jamais seul
 * à donner le réseau au récepteur.
 */
class CastNetworkHandoff {
    enum class StopState { WAITING, READY, FAILED, CANCELLED }

    private var held = false
    private var hasCastHandoff = false
    private var revoked = false
    private var disposed = false
    private var generation = 0
    private var stopAcknowledged = false
    private var stopFailed = false
    private var nextSource = 0
    private val sources = mutableSetOf<Int>()
    private val failedCloses = mutableSetOf<Int>()

    @Synchronized fun isHeld(): Boolean = held

    @Synchronized fun allowsLocalOpen(): Boolean = !held && !revoked && !disposed

    @Synchronized fun currentGeneration(): Int = generation

    /** Seul un nouveau choix explicite peut rendre son droit à un ancien lecteur. */
    @Synchronized fun onNewSelection() {
        if (!held && !disposed) revoked = false
    }

    /** null : une ouverture tardive est refusée AVANT toute connexion. */
    @Synchronized fun acquireSource(): Int? {
        if (!allowsLocalOpen()) return null
        return (++nextSource).also { sources.add(it) }
    }

    @Synchronized fun sourceClosed(source: Int, success: Boolean) {
        if (source !in sources) return
        if (success) {
            sources.remove(source)
            failedCloses.remove(source)
        } else {
            // Ne pas « compter fermé » un close qui a levé une exception.
            failedCloses.add(source)
        }
    }

    @Synchronized fun beginHold(): Int {
        check(!disposed && !revoked) { "Le lecteur a été quitté." }
        held = true
        hasCastHandoff = true
        stopAcknowledged = false
        stopFailed = false
        return ++generation
    }

    @Synchronized fun acknowledgeStop(ticket: Int) {
        if (ticket == generation && held && !disposed && !revoked) {
            stopAcknowledged = true
        }
    }

    @Synchronized fun failStop(ticket: Int) {
        if (ticket == generation && held) stopFailed = true
    }

    @Synchronized fun stopState(ticket: Int): StopState = when {
        disposed || revoked || !held || ticket != generation -> StopState.CANCELLED
        stopFailed || failedCloses.isNotEmpty() -> StopState.FAILED
        stopAcknowledged && sources.isEmpty() -> StopState.READY
        else -> StopState.WAITING
    }

    /** Seul le message explicite « fin du Cast » lève le verrou. */
    @Synchronized fun resumeAfterHold(): Boolean {
        if (stopState(generation) != StopState.READY) return false
        held = false
        stopAcknowledged = false
        ++generation
        return true
    }

    @Synchronized fun revoke() {
        if (hasCastHandoff) held = true
        revoked = true
        ++generation
    }

    @Synchronized fun dispose() {
        disposed = true
        held = true
        ++generation
    }
}
