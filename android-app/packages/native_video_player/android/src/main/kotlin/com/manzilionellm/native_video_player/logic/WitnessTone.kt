package com.manzilionellm.native_video_player.logic

/**
 * SON TÉMOIN (02/10/2026) — hypothèse H4 : « c'est la source, pas l'app ».
 *
 * Un petit fichier AAC-LC embarqué dans l'APK (`zuno_temoin.m4a`, 48 kHz,
 * stéréo G = D, 128 kb/s, 10,6 s), lu par le MÊME lecteur que les chaînes
 * (mêmes décodeurs, mêmes sondes, même focus, même AudioTrack), SANS réseau.
 *
 *   • Témoin net à l'oreille, chaînes mauvaises → la source ou le réseau.
 *   • Témoin mauvais aussi → l'appareil ou le chemin de sortie (H1 / H2 /
 *     H5) : l'app n'y est pour rien, ou un étage de l'app coupe (les
 *     sondes le diront).
 *
 * Composition (mesurée hors appareil le 02/10/2026 avec le même passe-haut
 * que la sonde, FFmpeg 6.1.1 pour décoder) :
 *   0,0–0,3 s silence ; 0,3–2,8 s bruit blanc (75,0 % > 4 kHz) ;
 *   2,8–6,1 s voix de synthèse « Zuno audio test, one, two, three, four »
 *   (0,2 % > 4 kHz : une voix est pauvre en aigus, c'est normal) ;
 *   6,1–8,6 s balayage 500 Hz → 16 kHz (39,2 %) ; 8,6–10,6 s bruit blanc
 *   (74,5 %). Cumulé sur tout le fichier : 54,3 %. Cumulé à 2,8 s : 74,9 % ;
 *   à 6,1 s : 53,2 %. Corrélation G/D : +1,00 (voies identiques). Pic 15 368
 *   (pas de saturation). La voix est volontairement plus douce que le bruit.
 *
 * Pur Kotlin : l'URI est un fichier de l'APK, pas une adresse de flux.
 */
object WitnessTone {

    /** Fichier dans les assets du plugin (DefaultDataSource sait lire `asset:///`). */
    const val ASSET_URI: String = "asset:///zuno_temoin.m4a"

    /** Nom de la fiche dans « Diagnostic du son » et dans la boîte noire. */
    const val CHANNEL_LABEL: String = "Son témoin (fichier intégré, sans réseau)"

    const val DURATION_MS: Long = 10_590L

    /** Rapport > 4 kHz du fichier entier, mesuré hors appareil. */
    const val FILE_HIGH_RATIO: Double = 0.543

    /** Le témoin est large bande dès la première fenêtre publiable. */
    const val EXPECTED_MIN_RATIO: Double = AudioSpectrum.WIDE_MIN_RATIO

    fun isWitness(url: String?): Boolean = url == ASSET_URI

    fun describe(): String =
        "Témoin : fichier AAC-LC 48 kHz stéréo (G = D) de 10,6 s dans l'APK, lu par le même lecteur, sans réseau. " +
            "Contenu : bruit blanc (2,5 s), voix de synthèse « Zuno audio test, one, two, three, four » (3,3 s, " +
            "volontairement plus douce), balayage grave → aigu (2,5 s), bruit blanc (2 s). " +
            "Attendu aux sondes : > 4 kHz ≥ 40 % (le fichier entier fait 54 %), voies identiques (corrélation +1,00)."

    /**
     * Ce que la mesure du témoin prouve. [spectrum] et [stereo] viennent de
     * la sonde décodeur ; null = Spectre coupé ou pas encore de fenêtre.
     */
    fun verdict(spectrum: AudioSpectrum.Judgement?, stereo: StereoImage.Judgement?): String {
        val lines = ArrayList<String>()
        if (spectrum == null) {
            lines += "Témoin : pas de mesure (allumer « Spectre : mesuré » et rejouer le témoin). " +
                "À l'oreille seulement : si la voix et le « pschh » sonnent « radio » ici aussi, " +
                "le défaut n'est pas la chaîne ni le réseau."
        } else {
            when (AudioSpectrum.effectiveBand(spectrum)) {
                AudioSpectrum.Band.WIDE -> lines +=
                    "Témoin : > 4 kHz = ${spectrum.percent()} (attendu ≥ 40 %) → l'app décode et transmet les aigus " +
                        "jusqu'à l'AudioTrack. Si le témoin sonne quand même « radio » ou « dans un trou » à l'oreille, " +
                        "le défaut est APRÈS l'app : mode du système (voir « Système audio »), sortie, réglages de l'appareil."
                AudioSpectrum.Band.LOW, AudioSpectrum.Band.MID -> lines +=
                    "Témoin : > 4 kHz = ${spectrum.percent()} alors que le fichier en contient 54 % → un étage de l'app " +
                        "coupe les aigus même sans réseau. Lire « Points de mesure » : la première sonde basse nomme l'étage."
                AudioSpectrum.Band.SHORT, AudioSpectrum.Band.SILENCE, AudioSpectrum.Band.RATE -> lines +=
                    "Témoin : fenêtre trop courte ou signal trop faible, pas de conclusion. Rejouer le témoin en entier."
            }
        }
        if (stereo != null) {
            when (stereo.verdict) {
                StereoImage.Verdict.INVERTED -> lines +=
                    "Témoin : OPPOSITION DE PHASE mesurée alors que le fichier a deux voies identiques → " +
                        "un étage de l'app inverse une voie. Lire les sondes : la première inversée nomme l'étage."
                StereoImage.Verdict.IDENTICAL, StereoImage.Verdict.CENTERED -> lines +=
                    "Témoin : voies identiques comme attendu (corrélation " +
                        String.format(java.util.Locale.FRANCE, "%+.2f", stereo.correlation) + ") → aucune inversion dans l'app."
                StereoImage.Verdict.WIDE -> lines +=
                    "Témoin : les voies ne sont plus identiques (corrélation " +
                        String.format(java.util.Locale.FRANCE, "%+.2f", stereo.correlation) +
                        ") alors que le fichier est G = D → un étage mélange ou décale une voie."
                else -> Unit
            }
        }
        return lines.joinToString("\n")
    }
}
