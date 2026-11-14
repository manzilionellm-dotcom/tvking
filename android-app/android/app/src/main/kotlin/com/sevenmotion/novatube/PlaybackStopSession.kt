package com.sevenmotion.novatube

/**
 * Identité de la notification Cast, indépendante des API Android pour tester
 * les courses de Stop sans prétendre exécuter un service sur appareil.
 * Toutes les utilisations réelles viennent du thread principal du service.
 */
class PlaybackStopSession {
    var activeCastId: String? = null
        private set
    private var lastUserStoppedId: String? = null

    fun startCast(sessionId: String): Boolean {
        // Une permission de notification peut se terminer juste après Stop.
        // Le même démarrage tardif ne doit pas ressusciter le service.
        if (sessionId.isBlank() || sessionId == lastUserStoppedId) return false
        activeCastId = sessionId
        return true
    }

    fun startAudio() {
        activeCastId = null
    }

    fun stopFromApp(sessionId: String?): Boolean {
        // null représente l'usage audio historique. Il n'est pas propriétaire
        // d'une nouvelle notification Cast ; un ancien Stop non plus.
        if (sessionId != activeCastId) return false
        activeCastId = null
        return true
    }

    fun stopFromNotification(sessionId: String?): Boolean {
        if (sessionId == null || sessionId != activeCastId) return false
        activeCastId = null
        lastUserStoppedId = sessionId
        return true
    }

    fun release(sessionId: String?) {
        if (sessionId == activeCastId) activeCastId = null
    }
}
