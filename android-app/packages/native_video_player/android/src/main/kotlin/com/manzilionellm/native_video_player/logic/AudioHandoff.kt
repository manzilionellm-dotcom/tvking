package com.manzilionellm.native_video_player.logic

/**
 * UN SEUL SON AU PASSAGE (01/10/2026).
 *
 * Media3 1.5.1, `DefaultAudioSink.flush()` — appelé par `stop()` du
 * lecteur, donc à chaque zap, à chaque suspend, à chaque libération :
 * l'AudioTrack n'est PAS rendu dans l'appel. `releaseAudioTrackAsync` le
 * programme 20 ms plus tard sur UN fil partagé par tout le processus, et
 * `onAudioTrackReleased` n'arrive qu'APRÈS `AudioTrack.release()`. Si on
 * `prepare()` tout de suite, l'ancienne piste et la nouvelle vivent
 * ensemble. Après beaucoup de zaps, la file s'allonge : la box mélange
 * deux sons (« dans un trou », « vieille radio »). Le décodeur, lui, est
 * rendu dans `stop()` avant que cet événement n'arrive : attendre la piste
 * attend aussi le décodeur.
 *
 * [mayOpenNext] : on n'ouvre la suite que s'il ne reste aucune piste, ou
 * si le réglage de repli [immediate] est allumé (ancien comportement).
 *
 * Le volume décidé ici n'est JAMAIS 0,2 (la baisse de Media3). 0 = silence
 * le temps de vider le tampon HDMI. 1 = lecture.
 *
 * Pur Kotlin : testé dans logic-test sans Android.
 */
object AudioHandoff {
    /** On n'attend pas plus que ça : un événement manquant ne fige pas le zap. */
    const val WAIT_MS: Long = 1_500L

    const val VOLUME_FULL: Float = 1f
    const val VOLUME_SILENT: Float = 0f

    /** Ce que Media3 appliquait sur CAN_DUCK. Interdit dans Zuno. */
    const val VOLUME_DUCK_FORBIDDEN: Float = 0.2f

    data class Open(val openNow: Boolean, val line: String)

    /**
     * Après le stop() du passage. [tracksAlive] = pistes encore comptées
     * dans tout le processus (la nôtre et celles d'une autre vue).
     */
    fun mayOpenNext(tracksAlive: Int, immediate: Boolean): Open {
        if (immediate) {
            return Open(
                openNow = true,
                line = "Zap : passage immédiat (réglage de repli). " +
                    "AudioTrack encore vivants : $tracksAlive.",
            )
        }
        if (tracksAlive <= 0) {
            return Open(
                openNow = true,
                line = "Zap : aucun AudioTrack vivant, la chaîne peut démarrer.",
            )
        }
        return Open(
            openNow = false,
            line = "Zap : on attend que l'AudioTrack précédent soit rendu " +
                "($tracksAlive encore vivant).",
        )
    }

    /** Une piste vient d'être rendue. On ouvre seulement s'il n'en reste plus. */
    fun afterRelease(tracksAliveAfter: Int): Open =
        if (tracksAliveAfter <= 0) {
            Open(true, "Zap : AudioTrack précédent rendu. Un seul va démarrer.")
        } else {
            Open(false, "Zap : AudioTrack rendu, il en reste $tracksAliveAfter.")
        }

    /** L'événement n'est pas venu. On ouvre, et la fiche le dit. */
    fun onWaitTimeout(tracksAlive: Int): Open = Open(
        openNow = true,
        line = "Zap : l'AudioTrack n'a pas été rendu en ${WAIT_MS / 1000} s " +
            "($tracksAlive encore vivant). On ouvre quand même, la fiche le note.",
    )

    /**
     * Volume de sortie. [duckRequested] est ignoré : une demande de baisse
     * ne change pas le chiffre. [handoffMute] vrai = silence de passage
     * (tampon de l'ancienne chaîne), pas une baisse à 20 %.
     */
    fun outputVolume(handoffMute: Boolean, duckRequested: Boolean): Float {
        if (handoffMute) return VOLUME_SILENT
        // duckRequested ne sert qu'à être explicitement ignoré.
        if (duckRequested) return VOLUME_FULL
        return VOLUME_FULL
    }

    data class Resume(val startPositionMs: Long?, val line: String)

    /**
     * Retour au premier plan. Direct : [startPositionMs] null = bord du
     * direct. Film : la position gardée, si elle est connue.
     */
    fun resume(vod: Boolean, lastKnownPos: Long): Resume =
        if (vod && lastKnownPos > 0L) {
            Resume(
                startPositionMs = lastKnownPos,
                line = "Retour : film rouvert à ${lastKnownPos} ms " +
                    "(nouveau décodeur, nouvelle sortie son).",
            )
        } else if (vod) {
            Resume(
                startPositionMs = null,
                line = "Retour : film rouvert au début (nouveau décodeur, nouvelle sortie son).",
            )
        } else {
            Resume(
                startPositionMs = null,
                line = "Retour : direct rouvert au bord du direct " +
                    "(nouveau décodeur, nouvelle sortie son).",
            )
        }

    /**
     * Filet des 8 s. [ffmpegActiveThisSession] doit être celui de CETTE
     * ouverture. Le silence de passage le remet à faux : sinon, au retour
     * dans l'app, le drapeau de la chaîne d'avant faisait croire que
     * FFmpeg avait échoué, et la chaîne passait à la box pour toujours.
     */
    fun watchdogShouldFallback(
        ffmpegActiveThisSession: Boolean,
        readyThisSession: Boolean,
        forceBox: Boolean,
        platformGaveUp: Boolean,
        playbackReady: Boolean,
    ): Boolean =
        ffmpegActiveThisSession &&
            !readyThisSession &&
            !forceBox &&
            !platformGaveUp &&
            !playbackReady
}

/**
 * Une vue qui attend (ou pas) avant d'ouvrir. Le lecteur Android s'en sert ;
 * le test des 50 zaps aussi, pour ne pas réécrire la règle à côté.
 */
class AudioGate(private val immediate: () -> Boolean) {
    var waiting: Boolean = false
        private set

    data class Tick(val prepare: Boolean, val line: String?)

    /** stop() vient d'être demandé. On ouvre tout de suite, ou on attend. */
    fun onStopped(tracksAlive: Int): Tick {
        val d = AudioHandoff.mayOpenNext(tracksAlive, immediate())
        waiting = !d.openNow
        return Tick(d.openNow, d.line)
    }

    /** Le compteur de pistes a bougé. */
    fun onTracksAlive(tracksAlive: Int): Tick {
        if (!waiting) return Tick(prepare = false, line = null)
        val d = AudioHandoff.afterRelease(tracksAlive)
        if (!d.openNow) return Tick(prepare = false, line = null)
        waiting = false
        return Tick(prepare = true, d.line)
    }

    fun onTimeout(tracksAlive: Int): Tick {
        if (!waiting) return Tick(prepare = false, line = null)
        waiting = false
        val d = AudioHandoff.onWaitTimeout(tracksAlive)
        return Tick(prepare = true, d.line)
    }

    /** Un silence (autre lecteur, ou nouveau zap) annule l'attente. */
    fun cancel() {
        waiting = false
    }
}
