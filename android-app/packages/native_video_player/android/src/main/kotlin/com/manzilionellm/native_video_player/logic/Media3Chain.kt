package com.manzilionellm.native_video_player.logic

import kotlin.math.abs

/**
 * Chaîne audio Media3 : chemin Zuno, ou essai « Media3 par défaut ».
 *
 * Lu dans Media3 1.5.1 (`DefaultAudioSink`, `DefaultRenderersFactory`,
 * `SonicAudioProcessor`, `SilenceSkippingAudioProcessor`). Pur Kotlin :
 * le lecteur Android ne fait qu'appliquer [useStockFactory].
 *
 * Coupé ([useStockFactory] faux) : rien ici ne change le son. Le lecteur
 * garde la fabrique Zuno (FFmpeg audio ajouté à la main, tampon agrandi,
 * [com.manzilionellm.native_video_player.ZunoAudioChain]).
 *
 * Allumé : `DefaultRenderersFactory` sans aucun réglage. Media3 met alors
 * son propre décodeur de la box et son propre `DefaultAudioSink`. Aucune
 * sonde, aucune voix claire, aucun tampon modifié par Zuno.
 */
object Media3Chain {
    const val KEY: String = "zuno.audio.chain.stock"

    /**
     * Seuil de `SonicAudioProcessor` (Media3 1.5.1, `CLOSE_THRESHOLD`).
     * En dessous, vitesse et hauteur comptent pour 1 : Sonic est inactif.
     */
    const val SONIC_CLOSE_THRESHOLD: Float = 0.0001f

    const val STAGE_PROBE_DECODER: String = "sonde_decodeur"
    const val STAGE_CLEAR: String = "voix_claire"
    const val STAGE_PROBE_VOICE: String = "sonde_voix"
    const val STAGE_SILENCE: String = "silence"
    const val STAGE_PROBE_SILENCE: String = "sonde_silence"
    const val STAGE_SONIC: String = "sonic"
    const val STAGE_PROBE_SINK: String = "sonde_audiotrack"

    /** Vrai : le lecteur doit construire un `DefaultRenderersFactory` nu. */
    fun useStockFactory(pure: Boolean): Boolean = pure

    /**
     * Sonic traite le son seulement si la vitesse, la hauteur, ou la
     * fréquence de sortie s'éloigne. À 1,0 / 1,0 / même fréquence, Media3
     * le laisse inactif : les échantillons ne passent pas dedans.
     */
    fun sonicActive(speed: Float, pitch: Float, sampleRateChanged: Boolean): Boolean {
        return abs(speed - 1f) >= SONIC_CLOSE_THRESHOLD ||
            abs(pitch - 1f) >= SONIC_CLOSE_THRESHOLD ||
            sampleRateChanged
    }

    /**
     * Étages Zuno qui reçoivent vraiment le PCM.
     *
     * [pure] vrai : ils ne sont pas enregistrés, même si Spectre ou la
     * voix claire sont allumés. Sinon, chaque étage n'entre que s'il est
     * actif. Vide = `DefaultAudioSink` écrit le tampon du décodeur tel
     * quel dans l'AudioTrack (pipeline non opérationnel).
     */
    fun activeZunoStages(
        pure: Boolean,
        probe: Boolean,
        clearVoice: Boolean,
        skipSilence: Boolean,
        speed: Float,
        pitch: Float,
        sampleRateChanged: Boolean = false,
    ): List<String> {
        if (pure) return emptyList()
        val sonic = sonicActive(speed, pitch, sampleRateChanged)
        return buildList {
            if (probe) add(STAGE_PROBE_DECODER)
            if (clearVoice) add(STAGE_CLEAR)
            if (probe) add(STAGE_PROBE_VOICE)
            if (skipSilence) add(STAGE_SILENCE)
            if (probe) add(STAGE_PROBE_SILENCE)
            if (sonic) add(STAGE_SONIC)
            if (probe) add(STAGE_PROBE_SINK)
        }
    }

    /**
     * Étages utilisateur du `DefaultAudioProcessorChain` de Media3
     * (silence puis Sonic), une fois les inactifs retirés. ToInt16, le
     * mapping et le trim sont devant, dans le sink, et sont inactifs pour
     * du PCM 16 bits stéréo sans délai d'encodeur.
     */
    fun activeStockUserStages(
        skipSilence: Boolean,
        speed: Float,
        pitch: Float,
        sampleRateChanged: Boolean = false,
    ): List<String> {
        return buildList {
            if (skipSilence) add(STAGE_SILENCE)
            if (sonicActive(speed, pitch, sampleRateChanged)) add(STAGE_SONIC)
        }
    }

    /** Aucun étage actif : le PCM du décodeur va droit à l'AudioTrack. */
    fun straightToAudioTrack(activeStages: List<String>): Boolean = activeStages.isEmpty()

    /** Ligne de la fiche. Pas d'adresse, pas de secret. */
    fun ficheLine(pure: Boolean): String {
        return if (pure) {
            "Chaîne : essai Media3 par défaut. Décodeur de la box, " +
                "DefaultRenderersFactory sans étage Zuno, tampon AudioTrack d'origine. " +
                "La vitesse reste figée à 1,0. Le focus et le volume ne changent pas."
        } else {
            "Chaîne : Zuno (défaut). FFmpeg pour l'AAC si rien ne le cache, " +
                "tampon AudioTrack agrandi. Les étages ajoutés sont inactifs " +
                "quand Spectre, voix claire et saut de silence sont coupés et la vitesse est 1."
        }
    }

    /** Ligne de boîte noire au moment où l'on bascule l'essai. */
    fun switchLine(pure: Boolean): String {
        return if (pure) {
            "Chaîne : essai allumé. On reconstruit le lecteur Media3 par défaut " +
                "(aucun étage Zuno). Recouper pour revenir au son habituel."
        } else {
            "Chaîne : essai coupé. Retour au lecteur Zuno, son habituel."
        }
    }
}
