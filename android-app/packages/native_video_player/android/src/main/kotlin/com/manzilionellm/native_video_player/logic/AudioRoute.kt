package com.manzilionellm.native_video_player.logic

/**
 * ÉTAT DU SYSTÈME AUDIO (02/10/2026) — hypothèse H1 : « le son passe par
 * le chemin d'appel ».
 *
 * Quand Android est en mode « communication » (un appel, une app de
 * visio, une reconnaissance vocale mal refermée, un Bluetooth SCO), TOUTE
 * lecture média passe par le chemin voix : bande étroite (≈ 3,4 kHz),
 * traitement d'écho, et sur un téléphone l'écouteur au lieu du
 * haut-parleur. C'est exactement « comme la musique quand on t'appelle »,
 * « vieille radio », « dans un trou ». Ça survit aux zaps, et ça touche
 * TOUS les lecteurs (Media3 ET mpv), ce qui colle au terrain.
 *
 * Ce fichier ne lit pas Android : il reçoit une photo ([Snapshot]) prise
 * par le lecteur et dit, en français, ce qu'elle veut dire. Les constantes
 * d'Android sont recopiées pour rester testable sans SDK.
 *
 * Le CORRECTIF candidat ([repairPlan]) reste derrière l'interrupteur
 * [AudioFixes.KEY_MODE_NORMAL], coupé par défaut : on ne touche pas au
 * mode du système tant que le journal n'a pas montré l'anomalie.
 */
object AudioRoute {

    // ---- android.media.AudioManager.MODE_* -----------------------------------
    const val MODE_NORMAL: Int = 0
    const val MODE_RINGTONE: Int = 1
    const val MODE_IN_CALL: Int = 2
    const val MODE_IN_COMMUNICATION: Int = 3
    const val MODE_CALL_SCREENING: Int = 4
    const val MODE_CALL_REDIRECT: Int = 5
    const val MODE_COMMUNICATION_REDIRECT: Int = 6

    // ---- android.media.AudioDeviceInfo.TYPE_* --------------------------------
    const val TYPE_UNKNOWN: Int = 0
    const val TYPE_BUILTIN_EARPIECE: Int = 1
    const val TYPE_BUILTIN_SPEAKER: Int = 2
    const val TYPE_WIRED_HEADSET: Int = 3
    const val TYPE_WIRED_HEADPHONES: Int = 4
    const val TYPE_LINE_ANALOG: Int = 5
    const val TYPE_LINE_DIGITAL: Int = 6
    const val TYPE_BLUETOOTH_SCO: Int = 7
    const val TYPE_BLUETOOTH_A2DP: Int = 8
    const val TYPE_HDMI: Int = 9
    const val TYPE_HDMI_ARC: Int = 10
    const val TYPE_USB_DEVICE: Int = 11
    const val TYPE_USB_ACCESSORY: Int = 12
    const val TYPE_DOCK: Int = 13
    const val TYPE_FM: Int = 14
    const val TYPE_BUILTIN_MIC: Int = 15
    const val TYPE_FM_TUNER: Int = 16
    const val TYPE_TV_TUNER: Int = 17
    const val TYPE_TELEPHONY: Int = 18
    const val TYPE_AUX_LINE: Int = 19
    const val TYPE_IP: Int = 20
    const val TYPE_BUS: Int = 21
    const val TYPE_USB_HEADSET: Int = 22
    const val TYPE_HEARING_AID: Int = 23
    const val TYPE_BUILTIN_SPEAKER_SAFE: Int = 24
    const val TYPE_REMOTE_SUBMIX: Int = 25
    const val TYPE_BLE_HEADSET: Int = 26
    const val TYPE_BLE_SPEAKER: Int = 27
    const val TYPE_ECHO_REFERENCE: Int = 28
    const val TYPE_HDMI_EARC: Int = 29
    const val TYPE_BLE_BROADCAST: Int = 30
    const val TYPE_DOCK_ANALOG: Int = 31

    // ---- android.media.MediaRecorder.AudioSource.* ---------------------------
    const val SOURCE_DEFAULT: Int = 0
    const val SOURCE_MIC: Int = 1
    const val SOURCE_VOICE_UPLINK: Int = 2
    const val SOURCE_VOICE_DOWNLINK: Int = 3
    const val SOURCE_VOICE_CALL: Int = 4
    const val SOURCE_CAMCORDER: Int = 5
    const val SOURCE_VOICE_RECOGNITION: Int = 6
    const val SOURCE_VOICE_COMMUNICATION: Int = 7
    const val SOURCE_REMOTE_SUBMIX: Int = 8
    const val SOURCE_UNPROCESSED: Int = 9
    const val SOURCE_VOICE_PERFORMANCE: Int = 10

    private const val FILE_VIEW =
        "android-app/packages/native_video_player/android/src/main/kotlin/" +
            "com/manzilionellm/native_video_player/NativeVideoView.kt"

    private const val FILE_ROUTE =
        "android-app/packages/native_video_player/android/src/main/kotlin/" +
            "com/manzilionellm/native_video_player/logic/AudioRoute.kt"

    /** Une sortie (ou une entrée) connue d'Android. [name] est le nom produit, jamais une adresse. */
    data class Device(val type: Int, val name: String)

    /** Un enregistrement micro actif quelque part sur l'appareil. */
    data class Recording(val source: Int, val deviceType: Int?)

    /**
     * Photo du système au moment de l'ouverture (ou de la ligne « Seconde N »).
     * Null = l'API n'existe pas sur cette version d'Android : on le dit,
     * on n'invente pas.
     */
    data class Snapshot(
        val mode: Int,
        val speakerphoneOn: Boolean,
        val scoOn: Boolean,
        val a2dpOn: Boolean,
        val wiredHeadsetOn: Boolean,
        val musicActive: Boolean,
        /** Toutes les sorties que le système connaît (API 23+). */
        val outputs: List<Device>,
        /** Sortie(s) qu'Android choisit pour USAGE_MEDIA (API 33+). */
        val mediaRoute: List<Device>?,
        /** Appareil de communication posé par une app (API 31+). */
        val communicationDevice: Device?,
        /** Micros ouverts sur tout l'appareil (API 24+). */
        val recordings: List<Recording>?,
        val sdk: Int,
    )

    fun modeLabel(mode: Int): String = when (mode) {
        MODE_NORMAL -> "normal"
        MODE_RINGTONE -> "sonnerie"
        MODE_IN_CALL -> "APPEL TÉLÉPHONIQUE"
        MODE_IN_COMMUNICATION -> "COMMUNICATION (appel internet / visio / micro)"
        MODE_CALL_SCREENING -> "FILTRAGE D'APPEL"
        MODE_CALL_REDIRECT -> "APPEL REDIRIGÉ"
        MODE_COMMUNICATION_REDIRECT -> "COMMUNICATION REDIRIGÉE"
        else -> "inconnu ($mode)"
    }

    /** Vrai pour tout mode qui envoie le média par le chemin voix. */
    fun isCallMode(mode: Int): Boolean = when (mode) {
        MODE_IN_CALL, MODE_IN_COMMUNICATION, MODE_CALL_SCREENING,
        MODE_CALL_REDIRECT, MODE_COMMUNICATION_REDIRECT,
        -> true
        else -> false
    }

    fun deviceLabel(type: Int): String = when (type) {
        TYPE_BUILTIN_EARPIECE -> "ÉCOUTEUR du téléphone (chemin d'appel)"
        TYPE_BUILTIN_SPEAKER -> "haut-parleur intégré"
        TYPE_BUILTIN_SPEAKER_SAFE -> "haut-parleur intégré (volume protégé)"
        TYPE_WIRED_HEADSET -> "casque filaire avec micro"
        TYPE_WIRED_HEADPHONES -> "casque filaire"
        TYPE_LINE_ANALOG -> "sortie ligne analogique"
        TYPE_LINE_DIGITAL -> "sortie ligne numérique"
        TYPE_BLUETOOTH_SCO -> "BLUETOOTH SCO (profil appel, bande étroite)"
        TYPE_BLUETOOTH_A2DP -> "Bluetooth A2DP (profil musique)"
        TYPE_BLE_HEADSET -> "casque Bluetooth LE"
        TYPE_BLE_SPEAKER -> "enceinte Bluetooth LE"
        TYPE_BLE_BROADCAST -> "diffusion Bluetooth LE"
        TYPE_HDMI -> "HDMI"
        TYPE_HDMI_ARC -> "HDMI ARC"
        TYPE_HDMI_EARC -> "HDMI eARC"
        TYPE_USB_DEVICE -> "USB"
        TYPE_USB_ACCESSORY -> "accessoire USB"
        TYPE_USB_HEADSET -> "casque USB"
        TYPE_DOCK, TYPE_DOCK_ANALOG -> "station d'accueil"
        TYPE_TELEPHONY -> "TÉLÉPHONIE (chemin d'appel)"
        TYPE_AUX_LINE -> "ligne auxiliaire"
        TYPE_HEARING_AID -> "appareil auditif"
        TYPE_REMOTE_SUBMIX -> "mixage distant (cast / enregistrement d'écran)"
        TYPE_BUILTIN_MIC -> "micro intégré"
        TYPE_IP -> "réseau (IP)"
        TYPE_BUS -> "bus"
        TYPE_FM, TYPE_FM_TUNER, TYPE_TV_TUNER -> "tuner"
        TYPE_ECHO_REFERENCE -> "référence d'écho"
        TYPE_UNKNOWN -> "inconnu"
        else -> "type $type"
    }

    fun sourceLabel(source: Int): String = when (source) {
        SOURCE_DEFAULT -> "défaut"
        SOURCE_MIC -> "micro"
        SOURCE_VOICE_UPLINK, SOURCE_VOICE_DOWNLINK, SOURCE_VOICE_CALL -> "appel téléphonique"
        SOURCE_CAMCORDER -> "caméra"
        SOURCE_VOICE_RECOGNITION -> "reconnaissance vocale"
        SOURCE_VOICE_COMMUNICATION -> "COMMUNICATION (visio / appel internet)"
        SOURCE_REMOTE_SUBMIX -> "mixage distant"
        SOURCE_UNPROCESSED -> "micro brut"
        SOURCE_VOICE_PERFORMANCE -> "scène"
        else -> "source $source"
    }

    /** Une sortie qui est le chemin « voix » : le média y sort en bande étroite. */
    fun isCallPath(type: Int): Boolean =
        type == TYPE_BUILTIN_EARPIECE || type == TYPE_TELEPHONY || type == TYPE_BLUETOOTH_SCO

    private fun devices(list: List<Device>): String =
        if (list.isEmpty()) "aucune" else list.joinToString(", ") { d ->
            if (d.name.isBlank()) deviceLabel(d.type) else "${deviceLabel(d.type)} « ${d.name} »"
        }

    private fun recordingsText(list: List<Recording>?, sdk: Int): String {
        if (list == null) return "micro : non lisible (Android $sdk < 7.0)"
        if (list.isEmpty()) return "micro : aucun enregistrement actif"
        return "micro : ${list.size} enregistrement(s) ACTIF(S) sur l'appareil (" +
            list.joinToString(", ") { r ->
                sourceLabel(r.source) + (r.deviceType?.let { " via " + deviceLabel(it) } ?: "")
            } + ") — Zuno n'ouvre jamais le micro"
    }

    /** Ligne complète pour la boîte noire et la fiche. */
    fun describe(s: Snapshot): String = buildString {
        append("Système audio : mode ").append(modeLabel(s.mode))
        append(" · haut-parleur d'appel ").append(if (s.speakerphoneOn) "OUI" else "non")
        append(" · Bluetooth SCO ").append(if (s.scoOn) "OUI" else "non")
        append(" · Bluetooth A2DP ").append(if (s.a2dpOn) "oui" else "non")
        append(" · casque filaire ").append(if (s.wiredHeadsetOn) "oui" else "non")
        append(" · musique active ").append(if (s.musicActive) "oui" else "non")
        append(" · route média : ")
        append(
            when {
                s.mediaRoute == null -> "non lisible (Android ${s.sdk} < 13)"
                else -> devices(s.mediaRoute)
            },
        )
        append(" · appareil de communication : ")
        append(
            when {
                s.sdk < 31 -> "non lisible (Android ${s.sdk} < 12)"
                s.communicationDevice == null -> "aucun"
                else -> devices(listOf(s.communicationDevice))
            },
        )
        append(" · sorties connues : ").append(devices(s.outputs))
        append(" · ").append(recordingsText(s.recordings, s.sdk))
    }

    /** Version courte pour « Seconde N ». */
    fun short(s: Snapshot): String = buildString {
        append("mode ").append(modeLabel(s.mode))
        if (s.speakerphoneOn) append(", haut-parleur d'appel")
        if (s.scoOn) append(", SCO")
        append(", route ")
        append(
            when {
                s.mediaRoute == null -> "non lisible"
                s.mediaRoute.isEmpty() -> "aucune"
                else -> s.mediaRoute.joinToString("+") { deviceLabel(it.type) }
            },
        )
        append(", micro ")
        append(s.recordings?.size?.toString() ?: "non lisible")
    }

    /**
     * Ce que la photo prouve. Une règle ne s'allume que si sa condition est
     * entière ; les API absentes se taisent (pas de demi-certitude).
     */
    fun findings(s: Snapshot): List<AudioDiagnosis.Finding> {
        val out = ArrayList<AudioDiagnosis.Finding>()
        if (isCallMode(s.mode)) {
            out += AudioDiagnosis.Finding(
                id = "mode_appel",
                confidence = AudioDiagnosis.Confidence.HAUTE,
                kind = AudioDiagnosis.Kind.CAUSE,
                symptom = "Le système est en mode ${modeLabel(s.mode)} pendant la lecture.",
                cause = "Android envoie alors tout le média par le chemin voix : bande étroite (≈ 3,4 kHz), " +
                    "traitement d'écho, écouteur sur un téléphone. C'est le son « comme quand on t'appelle ». " +
                    "Ça survit aux zaps et touche tous les lecteurs (Media3 et mpv). Une autre app (appel, " +
                    "visio, assistant vocal) a laissé ce mode ; Zuno ne l'a jamais mis.",
                fix = AudioDiagnosis.Fix(
                    file = FILE_VIEW,
                    symbol = "NativeVideoView.applyModeRepair / AudioRoute.repairPlan",
                    media3 = "AudioManager.setMode(MODE_NORMAL) avant l'ouverture (hors Media3)",
                    action = "Allumer « Mode : normal forcé » et rouvrir la chaîne. Si le son redevient net, " +
                        "la cause est l'état du système, pas le décodeur. Test sans journal : ouvrir YouTube " +
                        "juste après le mauvais son, sans redémarrer ; s'il est mauvais aussi, c'est le système.",
                    settingKey = AudioFixes.KEY_MODE_NORMAL,
                ),
            )
        } else if (s.mode == MODE_RINGTONE) {
            out += AudioDiagnosis.Finding(
                id = "mode_sonnerie",
                confidence = AudioDiagnosis.Confidence.INCERTAINE,
                kind = AudioDiagnosis.Kind.CAUSE,
                symptom = "Le système est en mode sonnerie pendant la lecture.",
                cause = "Un appel arrive ou un état n'a pas été rendu. Le média peut être baissé ou coupé.",
                fix = AudioDiagnosis.Fix(
                    file = FILE_ROUTE,
                    symbol = "AudioRoute.findings",
                    media3 = "AudioManager.getMode",
                    action = "Rien dans l'app. Relire la fiche une fois l'appel terminé.",
                    settingKey = null,
                ),
            )
        }
        if (s.scoOn) {
            out += AudioDiagnosis.Finding(
                id = "bluetooth_sco",
                confidence = AudioDiagnosis.Confidence.HAUTE,
                kind = AudioDiagnosis.Kind.CAUSE,
                symptom = "Le Bluetooth SCO (profil appel) est actif.",
                cause = "Le SCO est un canal voix 8 ou 16 kHz mono : tout ce qui y passe sonne « téléphone ». " +
                    "Une app d'appel ou un casque l'a ouvert ; Zuno ne l'ouvre jamais.",
                fix = AudioDiagnosis.Fix(
                    file = FILE_VIEW,
                    symbol = "NativeVideoView.applyModeRepair",
                    media3 = "AudioManager.stopBluetoothSco (hors Media3)",
                    action = "Allumer « Mode : normal forcé » (il arrête le SCO avant l'ouverture), ou couper le " +
                        "Bluetooth sur l'appareil et rouvrir.",
                    settingKey = AudioFixes.KEY_MODE_NORMAL,
                ),
            )
        }
        if (s.speakerphoneOn) {
            out += AudioDiagnosis.Finding(
                id = "haut_parleur_appel",
                confidence = AudioDiagnosis.Confidence.INCERTAINE,
                kind = AudioDiagnosis.Kind.CAUSE,
                symptom = "Le « haut-parleur d'appel » (speakerphone) est allumé.",
                cause = "Ce réglage n'a de sens qu'en communication. Allumé en mode normal, il signale qu'une " +
                    "app d'appel n'a pas tout rendu. Il peut forcer un pré-traitement voix sur la sortie.",
                fix = AudioDiagnosis.Fix(
                    file = FILE_VIEW,
                    symbol = "NativeVideoView.applyModeRepair",
                    media3 = "AudioManager.setSpeakerphoneOn(false) / clearCommunicationDevice (hors Media3)",
                    action = "Allumer « Mode : normal forcé » et rouvrir. Comparer à l'oreille.",
                    settingKey = AudioFixes.KEY_MODE_NORMAL,
                ),
            )
        }
        val route = s.mediaRoute
        if (route != null && route.any { isCallPath(it.type) }) {
            out += AudioDiagnosis.Finding(
                id = "sortie_voix",
                confidence = AudioDiagnosis.Confidence.HAUTE,
                kind = AudioDiagnosis.Kind.CAUSE,
                symptom = "Android envoie le média vers : ${devices(route)}.",
                cause = "C'est une sortie d'appel (écouteur, téléphonie ou SCO), pas une sortie média. " +
                    "Le son y est étroit et faible : « dans un trou ». Le décodeur n'y est pour rien.",
                fix = AudioDiagnosis.Fix(
                    file = FILE_VIEW,
                    symbol = "NativeVideoView.applyModeRepair / routeSnapshot",
                    media3 = "AudioManager.getAudioDevicesForAttributes(USAGE_MEDIA) (hors Media3)",
                    action = "Allumer « Mode : normal forcé », rouvrir, relire la route. Si elle reste sur " +
                        "l'écouteur, redémarrer l'appareil et fermer l'app qui tient l'appel.",
                    settingKey = AudioFixes.KEY_MODE_NORMAL,
                ),
            )
        }
        if (s.sdk >= 31 && s.communicationDevice != null && !isCallMode(s.mode)) {
            out += AudioDiagnosis.Finding(
                id = "appareil_communication",
                confidence = AudioDiagnosis.Confidence.INCERTAINE,
                kind = AudioDiagnosis.Kind.INFO,
                symptom = "Un appareil de communication est posé (${devices(listOf(s.communicationDevice))}) alors que le mode est normal.",
                cause = "Une app l'a demandé et ne l'a pas rendu. Hors mode communication il ne devrait pas " +
                    "router le média, mais certains appareils gardent un pré-traitement.",
                fix = AudioDiagnosis.Fix(
                    file = FILE_VIEW,
                    symbol = "NativeVideoView.applyModeRepair",
                    media3 = "AudioManager.clearCommunicationDevice (hors Media3)",
                    action = "« Mode : normal forcé » le retire avant l'ouverture. Sinon, rien dans l'app.",
                    settingKey = AudioFixes.KEY_MODE_NORMAL,
                ),
            )
        }
        val recs = s.recordings
        if (!recs.isNullOrEmpty()) {
            val call = recs.any { it.source == SOURCE_VOICE_COMMUNICATION || it.source == SOURCE_VOICE_CALL }
            out += AudioDiagnosis.Finding(
                id = if (call) "micro_appel" else "micro_ouvert",
                confidence = if (call) AudioDiagnosis.Confidence.HAUTE else AudioDiagnosis.Confidence.INCERTAINE,
                kind = AudioDiagnosis.Kind.CAUSE,
                symptom = "${recs.size} enregistrement(s) micro actif(s) sur l'appareil (" +
                    recs.joinToString(", ") { sourceLabel(it.source) } + ").",
                cause = if (call) {
                    "Une app enregistre en mode communication : Android met tout l'appareil sur le chemin voix " +
                        "(écho, bande étroite) tant que ce micro reste ouvert. Zuno n'ouvre jamais le micro."
                } else {
                    "Une app garde le micro ouvert (assistant, « Relaxing Sounds », reconnaissance vocale). " +
                        "Certains appareils appliquent alors un pré-traitement voix à la sortie. " +
                        "Zuno n'ouvre jamais le micro : la reconnaissance passe par l'écran du système."
                },
                fix = AudioDiagnosis.Fix(
                    file = FILE_ROUTE,
                    symbol = "AudioRoute.findings",
                    media3 = "AudioManager.getActiveRecordingConfigurations (hors Media3)",
                    action = "Fermer (Forcer l'arrêt) l'app qui enregistre, rouvrir la chaîne, relire la fiche. " +
                        "Rien à changer dans Zuno.",
                    settingKey = null,
                ),
            )
        }
        if (route != null && route.any {
                it.type == TYPE_BLUETOOTH_A2DP || it.type == TYPE_BLE_HEADSET ||
                    it.type == TYPE_BLE_SPEAKER || it.type == TYPE_BLE_BROADCAST
            }
        ) {
            out += AudioDiagnosis.Finding(
                id = "sortie_bluetooth",
                confidence = AudioDiagnosis.Confidence.HAUTE,
                kind = AudioDiagnosis.Kind.INFO,
                symptom = "Le média sort en Bluetooth (${devices(route)}).",
                cause = "La qualité dépend alors du codec Bluetooth et de l'enceinte, pas de l'app. " +
                    "Comparer avec le haut-parleur de l'appareil.",
                fix = AudioDiagnosis.Fix(
                    file = FILE_ROUTE,
                    symbol = "AudioRoute.findings",
                    media3 = "AudioManager.getAudioDevicesForAttributes",
                    action = "Aucun correctif dans l'app.",
                    settingKey = null,
                ),
            )
        }
        return out
    }

    /** Ce que le correctif « Mode : normal forcé » a le droit de faire. */
    enum class Repair {
        SET_MODE_NORMAL,
        SPEAKERPHONE_OFF,
        STOP_SCO,
        CLEAR_COMMUNICATION_DEVICE,
    }

    /**
     * Plan de réparation AVANT une ouverture. Vide si l'interrupteur est
     * coupé (le défaut), ou si rien n'est anormal : on ne touche jamais au
     * système pour rien. Le mode sonnerie n'est pas « réparé » : c'est un
     * appel qui arrive, pas un état collé.
     */
    fun repairPlan(s: Snapshot, enabled: Boolean): List<Repair> {
        if (!enabled) return emptyList()
        val out = ArrayList<Repair>()
        if (isCallMode(s.mode)) out += Repair.SET_MODE_NORMAL
        if (s.speakerphoneOn) out += Repair.SPEAKERPHONE_OFF
        if (s.scoOn) out += Repair.STOP_SCO
        if (s.sdk >= 31 && s.communicationDevice != null) out += Repair.CLEAR_COMMUNICATION_DEVICE
        return out
    }

    fun repairLabel(r: Repair): String = when (r) {
        Repair.SET_MODE_NORMAL -> "mode remis à normal"
        Repair.SPEAKERPHONE_OFF -> "haut-parleur d'appel coupé"
        Repair.STOP_SCO -> "Bluetooth SCO arrêté"
        Repair.CLEAR_COMMUNICATION_DEVICE -> "appareil de communication retiré"
    }

    /** Ligne de boîte noire après le plan. */
    fun repairLine(applied: List<Repair>, enabled: Boolean, mode: Int): String = when {
        !enabled -> "Mode système : laissé tel quel (interrupteur « Mode : normal forcé » coupé) — mode ${modeLabel(mode)}."
        applied.isEmpty() -> "Mode système : rien à corriger (mode ${modeLabel(mode)}, pas de SCO, pas de haut-parleur d'appel)."
        else -> "Mode système : CORRIGÉ avant l'ouverture — " + applied.joinToString(", ") { repairLabel(it) } + "."
    }
}
