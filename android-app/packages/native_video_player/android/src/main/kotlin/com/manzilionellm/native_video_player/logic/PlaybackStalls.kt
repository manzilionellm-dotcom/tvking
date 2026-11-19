package com.manzilionellm.native_video_player.logic

import java.util.Locale
import kotlin.math.max
import kotlin.math.min

/**
 * PAUSES DU LECTEUR (15/11/2026) — mesurer au lieu de deviner.
 *
 * Un journal du 15/11 montrait le son de TF1 qui s'arrête et repart (4 pauses
 * de 2 à 5 s en 80 s) sans rien dire de la CAUSE. Deux familles de causes
 * donnent la même pause :
 *
 *  - le SERVEUR (ou le réseau) n'envoie plus rien : le lecteur attend ;
 *  - l'APPAREIL ne suit pas : les données arrivent, mais le décodage ou
 *    l'affichage prend du retard.
 *
 * On les sépare en notant, pour chaque pause, ce que le réseau a livré pendant
 * qu'elle durait (octets, plus long silence) et les images perdues.
 *
 * Pur Kotlin (aucune classe Android) : testé dans logic-test. L'écoute des
 * octets reçus vient du TransferListener du lecteur (appelé hors du fil
 * principal) : toutes les méthodes sont synchronisées.
 */
class PlaybackStallTracker {

    /** Une pause terminée. */
    data class Stall(
        val number: Int,
        val durationMs: Long,
        /** Réserve de lecture quand la pause a commencé. */
        val bufferedAtStartMs: Long,
        /** Temps sans octet reçu quand la pause a commencé (−1 : aucun octet vu). */
        val silentBeforeMs: Long,
        /** Plus long silence du serveur PENDANT la pause. */
        val longestSilenceMs: Long,
        val bytesDuring: Long,
        /** Images perdues pendant la pause (−1 : inconnu). */
        val droppedFrames: Int,
        val totalStalls: Int,
        val totalStalledMs: Long,
        val sinceOpenMs: Long,
    )

    private var openedAtMs = 0L
    private var played = false
    private var seekGraceUntilMs = 0L

    private var lastBytesMs = -1L
    private var stallStartMs = -1L
    private var bufferedAtStartMs = 0L
    private var silentBeforeMs = -1L
    private var longestSilenceMs = 0L
    private var bytesDuring = 0L
    private var droppedAtStart = -1

    private var count = 0
    private var totalMs = 0L

    /** Nouvelle chaîne ou nouveau film : tout repart à zéro. */
    @Synchronized
    fun onOpen(nowMs: Long) {
        openedAtMs = nowMs
        played = false
        seekGraceUntilMs = 0L
        lastBytesMs = -1L
        stallStartMs = -1L
        count = 0
        totalMs = 0L
    }

    /** Saut demandé par la personne : le tampon qui suit n'est pas une pause. */
    @Synchronized
    fun onSeek(nowMs: Long) {
        seekGraceUntilMs = nowMs + SEEK_GRACE_MS
        stallStartMs = -1L
    }

    /** Des octets viennent d'arriver du réseau. Appelé très souvent : reste léger. */
    @Synchronized
    fun onBytes(nowMs: Long, bytes: Int) {
        if (stallStartMs >= 0L) {
            longestSilenceMs = max(longestSilenceMs, nowMs - max(lastBytesMs, stallStartMs))
            bytesDuring += bytes
        }
        lastBytesMs = nowMs
    }

    /** Le lecteur passe en « tampon » (STATE_BUFFERING). */
    @Synchronized
    fun onBuffering(nowMs: Long, bufferedMs: Long, droppedFrames: Int) {
        // Avant la première image (ouverture) ou juste après un saut : attendu.
        if (!played || nowMs < seekGraceUntilMs) return
        if (stallStartMs >= 0L) return
        stallStartMs = nowMs
        bufferedAtStartMs = bufferedMs
        silentBeforeMs = if (lastBytesMs < 0L) -1L else nowMs - lastBytesMs
        longestSilenceMs = 0L
        bytesDuring = 0L
        droppedAtStart = droppedFrames
    }

    /**
     * Le lecteur est prêt (STATE_READY). Rend la pause qui vient de finir, ou
     * `null` s'il n'y en avait pas ou si elle était trop courte pour s'entendre.
     */
    @Synchronized
    fun onReady(nowMs: Long, droppedFrames: Int): Stall? {
        played = true
        if (stallStartMs < 0L) return null
        val start = stallStartMs
        stallStartMs = -1L
        val duration = nowMs - start
        if (duration < MIN_REPORTED_MS) return null
        // Silence de la fin de pause : depuis le dernier octet (ou le début).
        val trailing = nowMs - max(lastBytesMs, start)
        val longest = max(longestSilenceMs, trailing)
        count += 1
        totalMs += duration
        val dropped =
            if (droppedFrames < 0 || droppedAtStart < 0) -1 else max(0, droppedFrames - droppedAtStart)
        return Stall(
            number = count,
            durationMs = duration,
            bufferedAtStartMs = bufferedAtStartMs,
            silentBeforeMs = silentBeforeMs,
            longestSilenceMs = longest,
            bytesDuring = bytesDuring,
            droppedFrames = dropped,
            totalStalls = count,
            totalStalledMs = totalMs,
            sinceOpenMs = max(0L, nowMs - openedAtMs),
        )
    }

    companion object {
        /** En dessous, ça ne s'entend pas : ni comptée, ni écrite. */
        const val MIN_REPORTED_MS: Long = 700L

        /** Après un saut, le tampon qui suit est normal. */
        const val SEEK_GRACE_MS: Long = 2_500L
    }
}

/** Texte des pauses pour la boîte noire (français simple, aucune adresse). */
object StallText {

    /** « 3,2 s » — virgule, une décimale, quelle que soit la langue du système. */
    fun seconds(ms: Long): String =
        String.format(Locale.US, "%.1f", ms / 1000.0).replace('.', ',') + " s"

    private fun kilobytes(bytes: Long): String =
        if (bytes < 1024L) "$bytes o" else "${bytes / 1024L} Ko"

    /** Ce que la mesure permet de dire, sans en dire plus. */
    fun verdict(s: PlaybackStallTracker.Stall): String {
        val serverSilent = s.longestSilenceMs >= max(1_000L, s.durationMs * 6 / 10)
        val devicePressure = s.droppedFrames > 0
        return when {
            serverSilent ->
                "→ Le serveur n'envoyait rien pendant la pause : le flux ou le réseau, pas l'appli."
            devicePressure ->
                "→ Des données arrivaient mais ${s.droppedFrames} images ont été perdues : l'appareil ne suit pas."
            s.bytesDuring > 0L && s.longestSilenceMs < 500L -> {
                val kbit = s.bytesDuring * 8L / max(1L, s.durationMs)
                "→ Des données arrivaient pendant toute la pause ($kbit kbit/s) : débit trop faible pour ce flux, ou appareil lent à décoder."
            }
            else ->
                "→ Le serveur envoyait par à-coups (silence le plus long : ${seconds(s.longestSilenceMs)})."
        }
    }

    /** La ligne écrite à chaque pause terminée. [network] : « Wi-Fi (−58 dBm) », « câble »… */
    fun line(s: PlaybackStallTracker.Stall, network: String): String {
        val parts = mutableListOf<String>()
        parts += "Pause n°${s.number} : ${seconds(s.durationMs)}."
        parts += "Réserve au début : ${seconds(s.bufferedAtStartMs)}."
        if (s.silentBeforeMs >= 1_000L) {
            parts += "Rien reçu depuis ${seconds(s.silentBeforeMs)} quand elle a commencé."
        }
        parts += "Silence du serveur pendant la pause : ${seconds(s.longestSilenceMs)}."
        parts += "Reçu pendant la pause : ${kilobytes(s.bytesDuring)}."
        if (s.droppedFrames >= 0) parts += "Images perdues : ${s.droppedFrames}."
        parts += "Réseau : $network."
        val percent = if (s.sinceOpenMs > 0L) min(100L, s.totalStalledMs * 100L / s.sinceOpenMs) else 0L
        parts += "Bilan : ${s.totalStalls} pause${if (s.totalStalls > 1) "s" else ""}, " +
            "${seconds(s.totalStalledMs)} depuis l'ouverture ($percent %)."
        parts += verdict(s)
        return parts.joinToString(" ")
    }
}

/**
 * COUSSIN ANTI-COUPURE (réglage facultatif, coupé par défaut).
 *
 * Après une coupure, le lecteur repart dès 2 s de réserve (réglage d'origine,
 * inchangé depuis septembre). Sur un flux qui a des trous, ça donne des
 * coupures fréquentes. Allumé, le coussin exige 5 s avant de repartir :
 * moins de coupures, mais chacune plus longue.
 *
 * Garde-fous (leçon v99–v101 : une reprise allongée avait laissé des chaînes
 * bloquées sur le logo) :
 *  - il n'AJOUTE qu'une attente : il ne permet jamais de repartir plus tôt ;
 *  - il ne joue qu'après une COUPURE (jamais au démarrage, jamais après un saut) ;
 *  - il respecte la fenêtre du direct (la moitié du retard visé) ;
 *  - au bout de [MAX_WAIT_MS] d'attente il laisse repartir quand même.
 */
object ResumeCushion {
    const val DEFAULT_MS: Long = 2_000L
    const val CUSHION_MS: Long = 5_000L
    const val MAX_WAIT_MS: Long = 10_000L

    /** Même valeur que androidx.media3.common.C.TIME_UNSET. */
    private const val TIME_UNSET: Long = Long.MIN_VALUE + 1

    @Volatile
    var enabled: Boolean = false

    /**
     * [baseOk] : ce que Media3 a décidé avec ses 2 s. [bufferedPlayoutUs] : la
     * réserve, à la vitesse de lecture. [waitedMs] : depuis combien de temps on
     * attend cette reprise.
     */
    fun shouldResume(
        baseOk: Boolean,
        rebuffering: Boolean,
        bufferedPlayoutUs: Long,
        targetLiveOffsetUs: Long,
        waitedMs: Long,
        enabled: Boolean,
    ): Boolean {
        if (!baseOk) return false
        if (!enabled || !rebuffering) return true
        if (waitedMs >= MAX_WAIT_MS) return true
        var needUs = CUSHION_MS * 1_000L
        if (targetLiveOffsetUs != TIME_UNSET) needUs = min(targetLiveOffsetUs / 2L, needUs)
        return bufferedPlayoutUs >= needUs
    }
}
