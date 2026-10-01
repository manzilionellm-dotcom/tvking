package com.manzilionellm.native_video_player.logic

/**
 * RECENSEMENT DU CYCLE DE VIE (01/10/2026) — pour la fiche « Diagnostic
 * du son » : combien de zaps depuis le démarrage, combien de lecteurs,
 * de décodeurs audio et d'AudioTrack sont VIVANTS en ce moment, et si la
 * chaîne a déjà été ouverte avant.
 *
 * Un seul lecteur par vue, un seul décodeur et un seul AudioTrack par
 * lecteur qui joue : plus d'un vivant = une fuite ou un chevauchement
 * (deux sons mélangés). Les compteurs sont alimentés par les événements
 * Media3 (création / libération) ; ils sont pour TOUT le processus,
 * parce que deux vues (lecteur + sonde du diagnostic) peuvent coexister.
 *
 * On ne garde que `url.hashCode()` pour « déjà vue » : aucune adresse.
 *
 * Pur Kotlin (pas d'Android) → testé dans logic-test/.
 */
object PlayerCensus {

    data class Snapshot(
        /** Numéro du zap en cours (1 = première chaîne depuis le démarrage). */
        val zap: Int,
        /** Combien de fois cette chaîne avait déjà été ouverte avant celle-ci. */
        val seenBefore: Int,
        val playersAlive: Int,
        val audioDecodersAlive: Int,
        val audioTracksAlive: Int,
        /** Repli box actif pour CETTE chaîne (null = FFmpeg). */
        val boxFailure: AacRoute.Failure?,
        /** Chaînes actuellement envoyées vers la box dans le processus. */
        val boxCount: Int,
        /** Ancien mode « une panne → la box pour tout le monde ». */
        val sessionWide: Boolean,
    )

    private var zaps: Int = 0
    private var players: Int = 0
    private var decoders: Int = 0
    private var tracks: Int = 0
    private val seen = HashMap<Int, Int>()

    /** setUrl : un zap de plus. @return le numéro de ce zap. */
    @Synchronized
    fun onZap(urlKey: Int): Int {
        zaps += 1
        seen[urlKey] = (seen[urlKey] ?: 0) + 1
        return zaps
    }

    /** Fois où [urlKey] a été ouverte AVANT l'ouverture en cours. */
    @Synchronized
    fun seenBefore(urlKey: Int): Int = ((seen[urlKey] ?: 0) - 1).coerceAtLeast(0)

    @Synchronized fun playerCreated() { players += 1 }
    @Synchronized fun playerReleased() { players = (players - 1).coerceAtLeast(0) }
    @Synchronized fun audioDecoderOpened() { decoders += 1 }
    @Synchronized fun audioDecoderClosed() { decoders = (decoders - 1).coerceAtLeast(0) }
    @Synchronized fun audioTrackOpened() { tracks += 1 }
    @Synchronized fun audioTrackClosed() { tracks = (tracks - 1).coerceAtLeast(0) }

    @Synchronized
    fun snapshot(urlKey: Int, boxFailure: AacRoute.Failure?): Snapshot = Snapshot(
        zap = zaps,
        seenBefore = seenBefore(urlKey),
        playersAlive = players,
        audioDecodersAlive = decoders,
        audioTracksAlive = tracks,
        boxFailure = boxFailure,
        boxCount = AacRoute.count(),
        sessionWide = AacRoute.sessionWide,
    )

    /** Remise à zéro (tests seulement : le processus de l'app ne redémarre pas). */
    @Synchronized
    fun reset() {
        zaps = 0
        players = 0
        decoders = 0
        tracks = 0
        seen.clear()
    }

    /** Plus d'un lecteur, décodeur ou AudioTrack vivant : chevauchement ou fuite. */
    fun overlapping(s: Snapshot): Boolean =
        s.playersAlive > 1 || s.audioDecodersAlive > 1 || s.audioTracksAlive > 1

    /** Une ligne pour la fiche. */
    fun describe(s: Snapshot): String = buildString {
        append("Cycle : zap n°").append(s.zap)
        append(" · chaîne ")
        append(
            if (s.seenBefore == 0) "ouverte pour la 1re fois"
            else "déjà ouverte avant (${s.seenBefore + 1}e fois)",
        )
        append(" · lecteurs vivants ").append(s.playersAlive)
        append(" · décodeurs audio vivants ").append(s.audioDecodersAlive)
        append(" · AudioTrack vivants ").append(s.audioTracksAlive)
        if (overlapping(s)) append(" ⚠ plus d'un actif : deux sons peuvent se mélanger")
        append(" · repli box : ")
        val f = s.boxFailure
        if (f == null) {
            append("aucun pour cette chaîne")
        } else {
            append("ACTIF pour cette chaîne (").append(f.reason.label)
            append(", au zap n°").append(f.zap).append(')')
        }
        if (s.sessionWide) {
            append(" · mode session entière (ancien comportement)")
        } else if (s.boxCount in 1 until Int.MAX_VALUE) {
            append(" · ").append(s.boxCount).append(" chaîne(s) sur la box dans ce processus")
        }
    }
}
