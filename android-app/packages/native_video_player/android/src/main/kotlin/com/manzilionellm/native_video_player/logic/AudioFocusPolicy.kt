package com.manzilionellm.native_video_player.logic

/**
 * FOCUS AUDIO (01/10/2026) — le son « dans un trou », comme la musique
 * pendant un appel.
 *
 * Quand une autre app (ou un bip du système) demande le son « avec baisse
 * de volume » (LOSS_TRANSIENT_CAN_DUCK), Media3 baisse NOTRE son à 20 %
 * tout seul, sans rien dire, et ne le remonte que si le système renvoie
 * GAIN. Sur certaines box, ce GAIN n'arrive jamais : la chaîne reste à 20 %,
 * lointaine, « derrière une porte », jusqu'au prochain zap. C'est le son
 * que Lionel décrit (« la musique quand on t'appelle »).
 *
 * Ici on décide nous-mêmes, SANS baisser le volume :
 *   • perte définitive (LOSS)           → pause ;
 *   • perte passagère (LOSS_TRANSIENT)  → pause, et on reprend au GAIN ;
 *   • « baisse demandée » (CAN_DUCK)    → on ignore : une télé n'a pas à
 *     baisser le film pour un bip ;
 *   • GAIN                              → reprise seulement si c'est nous
 *     qui avions mis en pause.
 *
 * Pur Kotlin : les codes sont ceux d'android.media.AudioManager, recopiés.
 */
object AudioFocusPolicy {
    const val GAIN: Int = 1
    const val LOSS: Int = -1
    const val LOSS_TRANSIENT: Int = -2
    const val LOSS_TRANSIENT_CAN_DUCK: Int = -3

    enum class Action { PAUSE, RESUME, IGNORE, NONE }

    data class Decision(
        val action: Action,
        val pausedByFocus: Boolean,
        val line: String,
        /**
         * Volume à appliquer. Toujours 1 : Zuno ne baisse jamais.
         * Le 0,2 de Media3 (VOLUME_MULTIPLIER_DUCK) est interdit.
         */
        val volume: Float = AudioHandoff.VOLUME_FULL,
    )

    /**
     * Codes de retour de requestAudioFocus (API 26 et l'ancienne).
     * Recopiés d'AudioManager pour rester testables sans Android.
     */
    const val REQUEST_GRANTED: Int = 1
    const val REQUEST_FAILED: Int = 0
    const val REQUEST_DELAYED: Int = 2

    data class Grant(val held: Boolean, val asked: Boolean, val line: String?)

    /**
     * Une demande de focus.
     * Déjà tenu : on ne redemande PAS (deux demandes empilées).
     * Accordé (1) : on le tient. Refusé (0) ou retardé (2) : on ne le tient
     * pas, et on le dit. Même décision en API < 26 (méthode dépréciée) :
     * seuls les codes comptent, pas la méthode.
     */
    fun onRequest(alreadyHeld: Boolean, systemCode: Int): Grant {
        if (alreadyHeld) return Grant(held = true, asked = false, line = null)
        val ok = systemCode == REQUEST_GRANTED
        return Grant(
            held = ok,
            asked = true,
            line = if (ok) "Focus audio : obtenu."
            else "Focus audio : demande REFUSÉE par Android (une autre app le garde).",
        )
    }

    /**
     * Media3 ne gère le focus (et donc sa baisse à 20 %) que si le réglage
     * de repli est allumé. Défaut : faux, Zuno décide.
     */
    fun media3HandlesFocus(androidFocusSetting: Boolean): Boolean = androidFocusSetting

    /**
     * @param change code AudioManager reçu.
     * @param pausedByFocus vrai si NOUS avons mis en pause à cause d'une perte.
     * @param playing vrai si le lecteur jouait au moment de l'événement.
     * Une perte PENDANT un zap (le lecteur ne joue pas encore) est retenue :
     * sinon la nouvelle chaîne repartait alors qu'une autre app a le son.
     */
    fun decide(change: Int, pausedByFocus: Boolean, playing: Boolean): Decision = when (change) {
        LOSS -> Decision(
            Action.PAUSE,
            pausedByFocus = true,
            line = "Focus audio : PERDU (une autre app a pris le son) → pause" +
                (if (playing) "." else " (pendant un zap, la chaîne ne repart pas)."),
        )
        LOSS_TRANSIENT -> Decision(
            Action.PAUSE,
            pausedByFocus = true,
            line = "Focus audio : perte passagère (autre son) → pause, reprise au retour" +
                (if (playing) "." else " (retenue pendant le zap)."),
        )
        LOSS_TRANSIENT_CAN_DUCK -> Decision(
            Action.IGNORE,
            pausedByFocus = pausedByFocus,
            line = "Focus audio : baisse de volume demandée par une autre app → IGNORÉE " +
                "(avant : le son tombait à 20 %, « dans un trou »).",
        )
        GAIN -> Decision(
            if (pausedByFocus) Action.RESUME else Action.NONE,
            pausedByFocus = false,
            line = if (pausedByFocus) "Focus audio : repris → lecture relancée."
            else "Focus audio : repris.",
        )
        else -> Decision(Action.NONE, pausedByFocus, "Focus audio : code $change ignoré.")
    }
}
