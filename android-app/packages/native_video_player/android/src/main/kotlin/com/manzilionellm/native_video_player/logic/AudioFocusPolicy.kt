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

    data class Decision(val action: Action, val pausedByFocus: Boolean, val line: String)

    /**
     * @param change code AudioManager reçu.
     * @param pausedByFocus vrai si NOUS avons mis en pause à cause d'une perte.
     * @param playing vrai si le lecteur jouait au moment de l'événement.
     */
    fun decide(change: Int, pausedByFocus: Boolean, playing: Boolean): Decision = when (change) {
        LOSS -> Decision(
            if (playing) Action.PAUSE else Action.NONE,
            pausedByFocus = playing,
            line = "Focus audio : PERDU (une autre app a pris le son) → pause.",
        )
        LOSS_TRANSIENT -> Decision(
            if (playing) Action.PAUSE else Action.NONE,
            pausedByFocus = playing || pausedByFocus,
            line = "Focus audio : perte passagère (autre son) → pause, reprise au retour.",
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
