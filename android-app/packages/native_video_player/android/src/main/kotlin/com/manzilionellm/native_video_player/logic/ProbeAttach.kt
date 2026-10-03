package com.manzilionellm.native_video_player.logic

/**
 * POURQUOI LA SONDE RESTE « NOT_SET » ALORS QUE SPECTRE EST ALLUMÉ
 * (02/10/2026, lu dans Media3 1.5.1, pas rejoué sur la box).
 *
 * `BaseAudioProcessor.isActive()` ne regarde que le format rendu par le
 * DERNIER `onConfigure`. Allumer [enabled] après coup ne rappelle pas
 * `onConfigure`. `AudioProcessingPipeline.flush()` reconstruit la liste
 * des processeurs actifs à partir de cet `isActive()`. Sans un nouveau
 * `configure` puis `flush`, la sonde reste hors de la chaîne : `queueInput`
 * n'est jamais appelé, aucun PCM n'est mesuré, et la fiche disait
 * « sonde coupée » quand même.
 *
 * Deuxième trou, sur le direct : `DefaultAudioSink` appelle `flush()`
 * quand l'horloge saute de plus de 200 ms (fréquent en IPTV). L'ancienne
 * sonde remettait son compteur à zéro à chaque flush. La fenêtre utile
 * (8 192 trames + mise en route) n'était jamais atteinte, donc rien
 * n'était publié. Le son, lui, n'est pas modifié : on ne fait que garder
 * le compteur de mesure.
 *
 * Pur Kotlin. Le lecteur Android ([com.manzilionellm.native_video_player.AudioProbeProcessor])
 * applique les mêmes décisions.
 */
object ProbeAttach {

    /** Trames à voir avant qu'une bande soit publiable. */
    val NEED_FRAMES: Int = AudioSpectrum.MIN_FRAMES + AudioSpectrum.WARMUP_FRAMES

    const val REJECT_OFF: String =
        "le réglage Spectre était coupé quand Media3 a configuré la chaîne"
    const val REJECT_NOT_PCM: String =
        "le décodeur ne sort pas du PCM 16 bits"
    const val REJECT_BAD_FORMAT: String =
        "fréquence ou nombre de voies illisible"

    data class Decision(val accept: Boolean, val reason: String?)

    data class Absence(
        val symptom: String,
        val cause: String,
        val media3: String,
        val action: String,
    )

    /**
     * Ce que `onConfigure` doit répondre. [accept] faux = NOT_SET :
     * Media3 n'insère pas la sonde, le chemin audio par défaut ne change pas.
     */
    fun onConfigure(enabled: Boolean, pcm16: Boolean, sampleRate: Int, channels: Int): Decision {
        if (!enabled) return Decision(false, REJECT_OFF)
        if (!pcm16) return Decision(false, REJECT_NOT_PCM)
        if (sampleRate < 1 || channels < 1) return Decision(false, REJECT_BAD_FORMAT)
        return Decision(true, null)
    }

    /**
     * Allumer le réglage pendant qu'une chaîne joue : il faut rouvrir.
     * Un simple drapeau ne rappelle pas `onConfigure`.
     */
    fun shouldReopen(turningOn: Boolean, playing: Boolean): Boolean = turningOn && playing

    /** Garder la fenêtre de mesure à travers un flush du même format. */
    fun keepWindowOnFlush(): Boolean = true

    /**
     * Plus grand nombre de trames vues si Media3 flush [chunks] fois,
     * [perChunk] trames entre chaque flush.
     * [keep] faux = l'ancien comportement (compteur remis à zéro).
     */
    fun maxFrames(chunks: Int, perChunk: Int, keep: Boolean): Int {
        var frames = 0
        var max = 0
        repeat(chunks.coerceAtLeast(0)) {
            if (!keep) frames = 0
            frames += perChunk
            if (frames > max) max = frames
        }
        return max
    }

    fun armingLine(enabled: Boolean): String =
        if (enabled) {
            "Sonde : réglage allumé pour cette ouverture. Les échantillons ne sont pas modifiés."
        } else {
            "Sonde : réglage coupé pour cette ouverture."
        }

    fun absence(requested: Boolean, inChain: Boolean, frames: Int, reject: String?): Absence {
        if (!requested) {
            return Absence(
                symptom = "Sonde coupée : le réglage Spectre est éteint.",
                cause = "On ne mesure pas. Media3 reçoit NOT_SET et n'insère pas la sonde. Le son ne change pas.",
                media3 = "AudioProcessor.onConfigure → NOT_SET (réglage coupé)",
                action = "Allumer Spectre. La chaîne se rouvre pour brancher la sonde. Les échantillons ne changent pas.",
            )
        }
        if (!inChain) {
            val why = reject ?: "Media3 a configuré le lecteur avant l'allumage et n'a pas rappelé la sonde"
            return Absence(
                symptom = "Sonde allumée, mais pas branchée : $why.",
                cause = "Le drapeau est vrai, mais le dernier onConfigure a renvoyé NOT_SET. " +
                    "Allumer le réglage ne rappelle pas onConfigure. Tant que la chaîne n'est pas " +
                    "reconfigurée, aucun PCM n'est copié.",
                media3 = "BaseAudioProcessor.isActive reste faux jusqu'au prochain configure + flush",
                action = "Rouvrir la chaîne (l'allumage du réglage le fait si elle joue déjà). Ne pas changer le décodeur.",
            )
        }
        if (frames < NEED_FRAMES) {
            return Absence(
                symptom = "Sonde branchée. Pas encore assez de son : $frames trames sur $NEED_FRAMES.",
                cause = "La sonde est dans la chaîne et copie le PCM sans le modifier. " +
                    "La bande au-dessus de 4 kHz n'est publiée qu'après environ une seconde. " +
                    "Un flush du direct (horloge qui saute) ne remet plus ce compteur à zéro.",
                media3 = "AudioProcessingPipeline.flush ne retire plus la fenêtre de mesure",
                action = "Attendre la ligne suivante de la fiche. Ne rien changer au son.",
            )
        }
        return Absence(
            symptom = "Sonde branchée, $frames trames, bande pas encore publiée.",
            cause = "Assez de son est passé, mais la bande n'a pas été retenue " +
                "(signal trop faible, ou publication pas encore recopiée dans la fiche).",
            media3 = "AudioProbeProcessor.queueInput",
            action = "Relire la fiche une seconde plus tard. Ne pas changer le décodeur sur ce seul état.",
        )
    }

    /**
     * Modèle du sink Media3 1.5.1 : mêmes instances de processeurs,
     * `setEnabled` ne reconfigure pas, `flush` reconstruit la liste active.
     */
    class Sink {
        var probeOn: Boolean = false
        private var pendingAccept: Boolean = false
        var inChain: Boolean = false
            private set
        var frames: Int = 0
            private set
        var lastReject: String? = null
            private set

        /** Allume ou coupe. Ne rappelle pas onConfigure. */
        fun setProbe(on: Boolean) {
            probeOn = on
        }

        fun configure(pcm16: Boolean): Decision {
            val d = onConfigure(probeOn, pcm16, 48_000, 2)
            pendingAccept = d.accept
            lastReject = d.reason
            // Nouvelle ouverture : la fenêtre repart de zéro. Un flush, non.
            frames = 0
            return d
        }

        /**
         * `AudioProcessingPipeline.flush`. [keepWindow] vrai = on ne jette
         * pas les trames déjà vues (correctif). Faux = l'ancien défaut.
         */
        fun flush(keepWindow: Boolean) {
            inChain = pendingAccept
            if (!keepWindow) frames = 0
        }

        fun push(n: Int) {
            if (!inChain || n <= 0) return
            frames += n
        }
    }
}
