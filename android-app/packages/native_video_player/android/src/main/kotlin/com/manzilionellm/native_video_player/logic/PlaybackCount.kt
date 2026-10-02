package com.manzilionellm.native_video_player.logic

/**
 * COMPTEUR DE LECTURES AUDIO (02/10/2026) — remplace « lectures Zuno /
 * lectures de la box », qui était FAUX.
 *
 * L'ancien compteur lisait `AudioPlaybackConfiguration.getClientUid()` par
 * réflexion. Cette méthode est cachée (@SystemApi) : sur Android 9+ la
 * réflexion est refusée, l'appel renvoyait -1, aucune lecture ne portait
 * « notre » UID, et la fiche écrivait « lectures Zuno 0, lectures de la
 * box 1 (film) » pendant que Zuno jouait. Ce « 1 (film) » était Zuno
 * lui-même. On ne le réécrit pas : on dit comment on attribue.
 *
 * Trois méthodes, de la plus sûre à la moins sûre :
 *   • UID : Android a donné l'UID de chaque lecture (vieilles box où la
 *     réflexion passe encore) → c'est exact.
 *   • SESSION : Android a donné le numéro de session audio de chaque
 *     lecture, et on connaît les nôtres (Media3 les annonce) → exact.
 *   • ATTRIBUTS : on ne connaît ni l'UID ni la session. Une lecture qui
 *     porte NOS attributs (usage média + type film/parole/musique déclaré)
 *     est comptée comme la nôtre, UNE seule, et SEULEMENT si notre
 *     AudioTrack est vivant. Tout le reste est « autre ». Une autre app
 *     qui jouerait aussi un « film » serait alors comptée comme autre :
 *     c'est dit sur la fiche.
 *
 * Pur Kotlin. Les constantes d'AudioAttributes sont recopiées.
 */
object PlaybackCount {

    // ---- android.media.AudioAttributes.CONTENT_TYPE_* -------------------------
    const val CONTENT_UNKNOWN: Int = 0
    const val CONTENT_SPEECH: Int = 1
    const val CONTENT_MUSIC: Int = 2
    const val CONTENT_MOVIE: Int = 3
    const val CONTENT_SONIFICATION: Int = 4

    // ---- android.media.AudioAttributes.USAGE_* -------------------------------
    const val USAGE_UNKNOWN: Int = 0
    const val USAGE_MEDIA: Int = 1
    const val USAGE_VOICE_COMMUNICATION: Int = 2
    const val USAGE_VOICE_COMMUNICATION_SIGNALLING: Int = 3
    const val USAGE_ALARM: Int = 4
    const val USAGE_NOTIFICATION: Int = 5
    const val USAGE_NOTIFICATION_RINGTONE: Int = 6
    const val USAGE_ASSISTANCE_ACCESSIBILITY: Int = 11
    const val USAGE_ASSISTANCE_NAVIGATION_GUIDANCE: Int = 12
    const val USAGE_ASSISTANCE_SONIFICATION: Int = 13
    const val USAGE_GAME: Int = 14
    const val USAGE_ASSISTANT: Int = 16

    /** Une lecture annoncée par Android. [uid] / [sessionId] null = non lisible. */
    data class Playback(
        val contentType: Int,
        val usage: Int,
        val uid: Int? = null,
        val sessionId: Int? = null,
    )

    enum class Method { UID, SESSION, ATTRIBUTES, NONE }

    data class Count(
        val total: Int,
        val ours: Int,
        val others: Int,
        /** Types des lectures « autres », pour les nommer (« musique », « parole »…). */
        val othersLabels: List<String>,
        val method: Method,
    )

    fun contentLabel(type: Int): String = when (type) {
        CONTENT_MOVIE -> "film"
        CONTENT_SPEECH -> "parole"
        CONTENT_MUSIC -> "musique"
        CONTENT_SONIFICATION -> "bip système"
        else -> "autre"
    }

    fun usageLabel(usage: Int): String = when (usage) {
        USAGE_MEDIA -> "média"
        USAGE_VOICE_COMMUNICATION -> "APPEL"
        USAGE_VOICE_COMMUNICATION_SIGNALLING -> "signal d'appel"
        USAGE_ALARM -> "alarme"
        USAGE_NOTIFICATION, USAGE_NOTIFICATION_RINGTONE -> "notification"
        USAGE_ASSISTANCE_ACCESSIBILITY -> "accessibilité"
        USAGE_ASSISTANCE_NAVIGATION_GUIDANCE -> "navigation"
        USAGE_ASSISTANCE_SONIFICATION -> "bip"
        USAGE_GAME -> "jeu"
        USAGE_ASSISTANT -> "assistant"
        else -> "usage $usage"
    }

    private fun label(p: Playback): String {
        val content = contentLabel(p.contentType)
        return if (p.usage == USAGE_MEDIA || p.usage == USAGE_UNKNOWN) content else "$content, ${usageLabel(p.usage)}"
    }

    /**
     * Attribue chaque lecture. [ourSessionIds] = numéros de session que
     * Media3 nous a annoncés pour CE processus. [ourTrackAlive] = notre
     * AudioTrack est compté vivant (PlayerCensus).
     */
    fun count(
        list: List<Playback>,
        ourUid: Int?,
        ourSessionIds: Set<Int>,
        ourContentType: Int,
        ourUsage: Int,
        ourTrackAlive: Boolean,
    ): Count {
        if (list.isEmpty()) return Count(0, 0, 0, emptyList(), Method.NONE)
        if (ourUid != null && list.all { it.uid != null }) {
            val mine = list.filter { it.uid == ourUid }
            val rest = list.filter { it.uid != ourUid }
            return Count(list.size, mine.size, rest.size, rest.map(::label), Method.UID)
        }
        if (ourSessionIds.isNotEmpty() && list.all { it.sessionId != null }) {
            val mine = list.filter { it.sessionId in ourSessionIds }
            val rest = list.filter { it.sessionId !in ourSessionIds }
            return Count(list.size, mine.size, rest.size, rest.map(::label), Method.SESSION)
        }
        val candidates = list.filter { it.contentType == ourContentType && it.usage == ourUsage }
        val ours = if (ourTrackAlive && candidates.isNotEmpty()) 1 else 0
        val rest = ArrayList<Playback>()
        var skipped = false
        for (p in list) {
            val isCandidate = p.contentType == ourContentType && p.usage == ourUsage
            if (isCandidate && ours == 1 && !skipped) {
                skipped = true
                continue
            }
            rest.add(p)
        }
        return Count(list.size, ours, rest.size, rest.map(::label), Method.ATTRIBUTES)
    }

    private fun methodNote(m: Method): String = when (m) {
        Method.UID -> "attribution exacte (UID)"
        Method.SESSION -> "attribution exacte (session audio)"
        Method.ATTRIBUTES -> "attribution par les attributs déclarés : Android ne dit pas quelle app joue ; " +
            "une autre app qui jouerait aussi un « film » serait comptée comme autre"
        Method.NONE -> ""
    }

    /** Ligne de boîte noire à chaque changement. */
    fun line(c: Count): String {
        if (c.total == 0) return "Lectures audio sur l'appareil : 0 — aucune (le lecteur n'a pas encore démarré, ou tout est arrêté)."
        val sb = StringBuilder("Lectures audio sur l'appareil : ").append(c.total).append(" — ")
        sb.append(
            when (c.ours) {
                0 -> "aucune n'est la nôtre"
                1 -> "la nôtre"
                else -> "${c.ours} à nous (⚠ chevauchement)"
            },
        )
        if (c.others > 0) {
            sb.append(" + ").append(c.others).append(" autre(s) (")
            sb.append(c.othersLabels.joinToString(", ")).append(") → une autre app joue en même temps")
        } else if (c.ours >= 1) {
            sb.append(" seulement")
        }
        sb.append(" [").append(methodNote(c.method)).append("].")
        return sb.toString()
    }

    /** Court, pour « Seconde N ». */
    fun short(c: Count?): String {
        if (c == null) return "lectures pas encore comptées"
        if (c.total == 0) return "lectures 0"
        return "lectures ${c.total} (nôtre ${c.ours}, autres ${c.others})"
    }

    /**
     * Ce que veut dire le compteur sur la fiche. Un 0 pendant que le son
     * s'entend = la fiche est en avance sur Android, pas une absence de son.
     */
    fun note(c: Count?, audible: Boolean): String {
        if (c == null) {
            return "Lectures audio sur l'appareil : pas encore comptées. " +
                "Android n'a pas encore rappelé, ou la fiche part avant le démarrage."
        }
        if (c.total == 0 && audible) {
            return "Lectures audio sur l'appareil : 0 alors que le lecteur joue. " +
                "La fiche a été écrite avant le rappel d'Android. Les lignes « Seconde 1 » à " +
                "« Seconde ${VolumeTrace.SECONDS} » de la boîte noire donnent le chiffre pendant que ça joue."
        }
        return line(c)
    }
}
