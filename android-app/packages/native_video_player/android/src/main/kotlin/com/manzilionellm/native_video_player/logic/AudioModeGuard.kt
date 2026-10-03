package com.manzilionellm.native_video_player.logic

/**
 * GARDE « mode appel » (hypothèse H1).
 *
 * Le son « comme quand on t'appelle » peut venir d'Android resté en mode
 * communication : le chemin téléphone (bande étroite, traitement d'écho)
 * s'applique alors à toute lecture, y compris un autre lecteur.
 *
 * Ce fichier ne parle pas à Android. Il décide seulement s'il faut
 * demander le retour à normal. L'appel réel (AudioManager.setMode) est
 * dans le lecteur, et seulement quand [plan] dit [Action.SET_NORMAL].
 *
 * Interrupteur [KEY], coupé par défaut. Coupé : [plan] répond LEAVE,
 * personne n'appelle setMode, le son ne change pas.
 *
 * Allumé : on ne demande le retour que si le mode lu est un chemin
 * d'appel ([AudioRouteState.callPath]). Déjà normal, sonnerie, ou pas
 * encore lu (−1) : on ne touche pas.
 *
 * Limite, lue dans Android 16 (AudioService.setMode) : la demande
 * MODE_NORMAL retire la demande DE CETTE application. Une autre
 * application qui tient le mode n'est pas dégagée. [resultLine] le dit
 * quand le mode relu est encore un appel.
 */
object AudioModeGuard {

    const val KEY: String = "zuno.audio.mode.normal"

    enum class Action { LEAVE, SET_NORMAL }

    data class Plan(val action: Action)

    fun plan(enabled: Boolean, mode: Int): Plan {
        if (!enabled) return Plan(Action.LEAVE)
        if (!AudioRouteState.callPath(mode)) return Plan(Action.LEAVE)
        return Plan(Action.SET_NORMAL)
    }

    /** On a regardé le mode, et il n'y avait rien à remettre. */
    fun lookedLine(mode: Int): String {
        return "Mode audio : ${AudioRouteState.modeLabel(mode)}. Rien à remettre."
    }

    /**
     * Après la demande. [threw] = l'appel Android a levé une exception.
     * Si le mode relu est encore un appel, une autre application le tient,
     * ou Android a ignoré la demande (permission absente : il ne lève pas,
     * il ne fait rien).
     */
    fun resultLine(before: Int, after: Int, threw: Boolean): String {
        val from = AudioRouteState.modeLabel(before)
        if (threw) {
            return "Mode audio : $from, demande de retour à normal refusée par Android."
        }
        val to = AudioRouteState.modeLabel(after)
        if (!AudioRouteState.callPath(after)) {
            return "Mode audio : $from → $to."
        }
        return "Mode audio : toujours $to après la demande. " +
            "Une autre application tient peut-être ce mode, ou Android a ignoré la demande."
    }
}
