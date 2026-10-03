package com.manzilionellm.native_video_player.logic

/**
 * Arrêt du son quand l'app quitte le premier plan (Home).
 *
 * Le lecteur natif ne doit pas attendre le message Flutter « paused » :
 * sur une box, la surface part dès `onPause` et l'AudioTrack, lui,
 * continue. On coupe donc dans l'activité.
 *
 * On distingue quand même ce qui laisse l'app visible :
 *   • perte de focus seule (overlay, bandeau) → on ne coupe pas ;
 *   • `onPause` SANS que l'utilisateur ait quitté (`onUserLeaveHint`)
 *     → dialogue qui laisse l'activité visible : on ne coupe pas encore ;
 *   • `onStop` → l'app n'est plus visible (Home sans indice, écran éteint,
 *     dialogue qui a fini par tout couvrir) → on coupe ;
 *   • Home : `onUserLeaveHint` puis `onPause` → on coupe tout de suite.
 *
 * Tant que c'est coupé, aucune réouverture (nouveau flux, essai, repli,
 * focus). Seul `onResume` rouvre.
 *
 * [flutterOnly] vrai = interrupteur de repli : l'activité ne décide plus,
 * l'ancien chemin Flutter reprend la main. Faux par défaut.
 *
 * Pur Kotlin : testé sans box.
 */
class BackgroundGate {
    var flutterOnly: Boolean = false

    /** Vrai après un arrêt, jusqu'au retour au premier plan. */
    var inBackground: Boolean = false
        private set

    /** Home vient d'être demandé : le prochain onPause coupe tout de suite. */
    private var userLeaving: Boolean = false

    /** Une seule ligne « réouverture refusée » par séjour en arrière-plan. */
    private var refuseNoted: Boolean = false

    fun on(signal: Signal): Step {
        // Repli : on ne touche pas au lecteur depuis l'activité.
        if (flutterOnly) {
            if (signal == Signal.RESUME) userLeaving = false
            return Step(stop = false, resume = false, line = null)
        }
        return when (signal) {
            Signal.USER_LEAVE -> {
                userLeaving = true
                Step(stop = false, resume = false, line = null)
            }
            // Overlay : l'activité est encore affichée. On ne coupe pas.
            Signal.FOCUS_LOST, Signal.FOCUS_GAINED ->
                Step(stop = false, resume = false, line = null)
            Signal.PAUSE -> {
                // Dialogue bref : pas de Home, l'app peut rester visible.
                // On attend onStop pour savoir si elle a vraiment disparu.
                if (inBackground || !userLeaving) {
                    Step(stop = false, resume = false, line = null)
                } else {
                    enterBackground()
                }
            }
            Signal.STOP -> {
                if (inBackground) {
                    Step(stop = false, resume = false, line = null)
                } else {
                    enterBackground()
                }
            }
            Signal.RESUME -> {
                userLeaving = false
                if (!inBackground) {
                    Step(stop = false, resume = false, line = null)
                } else {
                    inBackground = false
                    refuseNoted = false
                    Step(stop = false, resume = true, line = null)
                }
            }
        }
    }

    /** Faux = on est dehors et le nouveau comportement est actif. */
    fun allowsReopen(): Boolean = flutterOnly || !inBackground

    /**
     * Ligne à écrire une fois quand une réouverture est bloquée.
     * Null si on a le droit d'ouvrir, ou si on l'a déjà dit.
     */
    fun noteRefuse(): String? {
        if (allowsReopen() || refuseNoted) return null
        refuseNoted = true
        return REFUSE_LINE
    }

    /** Réservé aux tests du hub : repart au premier plan, repli coupé. */
    fun resetForTest() {
        flutterOnly = false
        inBackground = false
        userLeaving = false
        refuseNoted = false
    }

    private fun enterBackground(): Step {
        inBackground = true
        userLeaving = false
        refuseNoted = false
        return Step(stop = true, resume = false, line = STOP_LINE)
    }

    enum class Signal {
        USER_LEAVE,
        PAUSE,
        STOP,
        RESUME,
        FOCUS_LOST,
        FOCUS_GAINED,
    }

    data class Step(val stop: Boolean, val resume: Boolean, val line: String?)

    companion object {
        const val STOP_LINE: String =
            "Arrêt hors app : lecture coupée, décodeur et AudioTrack rendus."
        const val REFUSE_LINE: String =
            "Réouverture refusée : l'app est en arrière-plan."
    }
}

/**
 * Un seul décideur pour tout le processus. L'activité Android l'appelle ;
 * chaque lecteur s'inscrit. Pas d'import Android : les tests s'en servent.
 */
object AppForeground {
    private val gate = BackgroundGate()
    private var nextId = 0
    private val listeners = LinkedHashMap<Int, Listener>()

    private data class Listener(
        val onBackground: (Boolean) -> Unit,
        val stop: () -> Unit,
        val resume: () -> Unit,
    )

    var flutterOnly: Boolean
        get() = gate.flutterOnly
        set(value) {
            gate.flutterOnly = value
        }

    fun watch(
        onBackground: (Boolean) -> Unit,
        stop: () -> Unit,
        resume: () -> Unit,
    ): Int {
        nextId += 1
        listeners[nextId] = Listener(onBackground, stop, resume)
        return nextId
    }

    fun unwatch(id: Int) {
        if (id < 0) return
        listeners.remove(id)
    }

    fun onUserLeaveHint() = dispatch(BackgroundGate.Signal.USER_LEAVE)
    fun onPause() = dispatch(BackgroundGate.Signal.PAUSE)
    fun onStop() = dispatch(BackgroundGate.Signal.STOP)
    fun onResume() = dispatch(BackgroundGate.Signal.RESUME)
    fun onWindowFocus(hasFocus: Boolean) {
        dispatch(if (hasFocus) BackgroundGate.Signal.FOCUS_GAINED else BackgroundGate.Signal.FOCUS_LOST)
    }

    fun allowsReopen(): Boolean = gate.allowsReopen()

    fun noteRefuse(): String? = gate.noteRefuse()

    private fun dispatch(signal: BackgroundGate.Signal) {
        val step = gate.on(signal)
        val copy = listeners.values.toList()
        if (step.stop) {
            // Le drapeau d'abord : un essai déclenché par l'arrêt voit
            // déjà « dehors » et ne rouvre pas.
            copy.forEach { it.onBackground(true) }
            copy.forEach { it.stop() }
        }
        if (step.resume) {
            copy.forEach { it.onBackground(false) }
            copy.forEach { it.resume() }
        }
    }

    /** Remet le décideur à zéro. Réservé aux tests. */
    fun debugReset() {
        listeners.clear()
        nextId = 0
        gate.resetForTest()
    }
}
