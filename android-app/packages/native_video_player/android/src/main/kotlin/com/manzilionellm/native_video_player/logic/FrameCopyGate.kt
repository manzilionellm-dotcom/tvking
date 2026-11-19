package com.manzilionellm.native_video_player.logic

/**
 * Une copie de surface appartient à la session ET à l'adresse qui l'ont
 * demandée. PixelCopy peut répondre après un zap : l'image A ne doit
 * jamais devenir la dernière image connue de B.
 *
 * Appelé uniquement sur le fil principal. Le créneau reste occupé jusqu'au
 * callback : on ne recycle pas un bitmap pendant que PixelCopy y écrit,
 * et les zaps rapides n'accumulent pas les allocations. Une réponse
 * périmée libère son propre créneau et demande une copie du flux courant.
 */
class FrameCopyGate {
    class Ticket internal constructor(internal val session: Int, internal val source: String)

    enum class Completion { KEEP, DISCARD, REFRESH_CURRENT }

    private var active: Ticket? = null

    val inFlight: Boolean get() = active != null

    fun begin(session: Int, source: String?): Ticket? {
        if (active != null || session <= 0 || source.isNullOrEmpty()) return null
        return Ticket(session, source).also { active = it }
    }

    /**
     * [currentFrameAvailable] décrit le lecteur actuel, pas le résultat de
     * PixelCopy. Un échec de A peut donc laisser B prendre sa propre image.
     * Un callback déjà terminé ne peut pas libérer le créneau de B.
     */
    fun finish(
        ticket: Ticket,
        currentSession: Int,
        currentSource: String?,
        currentFrameAvailable: Boolean,
    ): Completion {
        if (active !== ticket) return Completion.DISCARD
        active = null
        if (!currentFrameAvailable) return Completion.DISCARD
        return if (ticket.session == currentSession && ticket.source == currentSource) {
            Completion.KEEP
        } else {
            Completion.REFRESH_CURRENT
        }
    }
}
