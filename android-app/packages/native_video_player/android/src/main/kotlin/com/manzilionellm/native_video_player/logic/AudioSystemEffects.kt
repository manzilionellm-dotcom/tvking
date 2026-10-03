package com.manzilionellm.native_video_player.logic

/**
 * EFFETS SYSTÈME (03/10/2026) — ce qui peut colorer le son APRÈS
 * l'AudioTrack.
 *
 * Zuno n'attache aucun égaliseur, aucun virtualiseur, aucun Dolby.
 * Le téléphone ou la box, eux, peuvent le faire tout seuls : un effet
 * déclaré dans audio_effects.xml est collé au flux « musique »
 * (USAGE_MEDIA) ou au flux « appel », sans que l'application le
 * demande. Ça se passe après les sondes PCM : un spectre à 2 % ne
 * le voit pas.
 *
 * Ce fichier ne crée JAMAIS d'effet. Créer un Equalizer, un BassBoost
 * ou un Virtualizer sur la session le brancherait (la doc Android le
 * dit) et changerait le son. On ne fait que mettre en phrases des
 * chiffres déjà lus : le catalogue [AudioEffect.queryEffects], les
 * lectures annoncées, la fréquence native, le micro, le spatialiseur.
 *
 * « Présent dans le catalogue » n'est pas « allumé ». On ne les confond
 * pas. Pur Kotlin, testé sans Android.
 */
object AudioSystemEffects {

    /**
     * UUID de type, recopiés depuis android.media.audiofx.AudioEffect
     * (AOSP). Ils nomment la FAMILLE (égaliseur, graves…), pas une
     * marque. Le nom et l'éditeur viennent du descripteur de l'appareil.
     */
    const val TYPE_EQUALIZER = "0bed4300-ddd6-11db-8f34-0002a5d5c51b"
    const val TYPE_BASS_BOOST = "0634f220-ddd4-11db-a0fc-0002a5d5c51b"
    const val TYPE_VIRTUALIZER = "37cc2c00-dddd-11db-8577-0002a5d5c51b"
    const val TYPE_AGC = "0a8abfe0-654c-11e0-ba26-0002a5d5c51b"
    const val TYPE_AEC = "7b491460-8d4d-11e0-bd61-0002a5d5c51b"
    const val TYPE_NS = "58b4b260-8e06-11e0-aa8e-0002a5d5c51b"
    const val TYPE_LOUDNESS = "fe3199be-aed0-413f-87bb-11260eb63cf1"
    const val TYPE_DYNAMICS = "7261676f-6d75-7369-6364-28e2fd3ac39e"
    const val TYPE_PRESET_REVERB = "47382d60-ddd8-11db-bf3a-0002a5d5c51b"
    const val TYPE_ENV_REVERB = "c2e5d5f0-94bd-4763-9cac-4e234d06839e"
    const val TYPE_HAPTIC = "1411e6d6-aecd-4021-a1cf-a6aceb0d71e5"

    /** Modes de branchement, chaînes exactes de AudioEffect (AOSP). */
    const val CONNECT_INSERT = "Insert"
    const val CONNECT_AUXILIARY = "Auxiliary"
    const val CONNECT_PRE = "Pre Processing"
    const val CONNECT_POST = "Post Processing"

    /**
     * Bits de AudioAttributes (AOSP). getFlags() public ne renvoie que
     * les trois premiers « publics ». getAllFlags() (caché) peut en
     * dire plus : SCO = chemin d'appel, « ne pas spatialiser », etc.
     */
    const val FLAG_AUDIBILITY_ENFORCED = 1 shl 0
    const val FLAG_SCO = 1 shl 2
    const val FLAG_HW_AV_SYNC = 1 shl 4
    const val FLAG_LOW_LATENCY = 1 shl 8
    const val FLAG_DEEP_BUFFER = 1 shl 9
    const val FLAG_CONTENT_SPATIALIZED = 1 shl 14
    const val FLAG_NEVER_SPATIALIZE = 1 shl 15

    /** Niveaux Spatializer (API 32). −1 = pas lu. */
    const val SPATIALIZER_NONE = 0
    const val SPATIALIZER_MULTICHANNEL = 1
    const val SPATIALIZER_OTHER = 2

    /** On ne noie pas la fiche : huit moteurs, le reste est compté. */
    private const val MAX_ENGINES = 8
    private const val MAX_PLAYS = 6

    /**
     * Un moteur installé sur l'appareil. Ce n'est pas un effet allumé.
     * [typeUuid] est en minuscules, ou vide si l'appareil ne l'a pas dit.
     */
    data class Engine(
        val name: String,
        val implementor: String,
        val typeUuid: String,
        val connectMode: String,
    )

    /**
     * Une lecture vue par getActivePlaybackConfigurations.
     * [ours] null = Android n'a pas dit à qui elle est (Android 16).
     * [flagsComplete] faux = seuls les drapeaux publics ont été lus.
     */
    data class Play(
        val usage: Int,
        val contentType: Int,
        val flags: Int,
        val flagsComplete: Boolean,
        val deviceType: Int,
        val deviceName: String,
        val ours: Boolean?,
    )

    /**
     * Spatialiseur Android (pas le Dolby du réglage Samsung, qui peut
     * être un autre moteur). Null dans [Sheet.spatial] = API trop
     * ancienne ou lecture ratée.
     */
    data class Spatial(
        val level: Int,
        val available: Boolean?,
        val enabled: Boolean?,
        val headTracker: Boolean?,
        val stereoMovie: Boolean?,
        val fiveOneMovie: Boolean?,
    )

    /** Tout ce que la fiche a le droit de dire. Aucun champ n'allume un effet. */
    data class Sheet(
        val sessionId: Int = -1,
        val engines: List<Engine> = emptyList(),
        /** Vrai dès qu'on a appelé queryEffects, même si la liste est vide. */
        val catalogRead: Boolean = false,
        /** Vrai si queryEffects a jeté : on ne dit pas « aucun moteur ». */
        val catalogFailed: Boolean = false,
        val outputSampleRate: Int = -1,
        val framesPerBuffer: Int = -1,
        val micMuted: Boolean? = null,
        val spatial: Spatial? = null,
        val plays: List<Play> = emptyList(),
        val mode: Int = -1,
    )

    /** Phrase courte quand un indice mérite une ligne de fiche, sans correctif. */
    data class Suspect(
        val symptom: String,
        val cause: String,
    )

    /** Bloc collé dans le rapport. Une ligne = un fait. */
    fun block(s: Sheet): String {
        val lines = ArrayList<String>(16)
        lines += "Effets système (lecture seule, aucun effet créé par l'app) :"
        lines += sessionLine(s.sessionId)
        lines += catalogLines(s)
        lines += rateLine(s.outputSampleRate, s.framesPerBuffer)
        lines += micLine(s.micMuted)
        lines += spatialLine(s.spatial)
        lines += playLines(s.plays)
        return lines.joinToString("\n")
    }

    /**
     * Indices qui PEUVENT expliquer « comme un appel » ou « deux sons ».
     * Null = rien de notable. Jamais une preuve : le catalogue n'est pas
     * l'état allumé, et un Dolby seulement présent ne suffit pas.
     */
    fun suspect(s: Sheet): Suspect? {
        val bits = ArrayList<String>(4)
        if (AudioRouteState.callPath(s.mode)) {
            bits += "mode ${AudioRouteState.modeLabel(s.mode)} (le traitement d'appel peut colorer le média)"
        }
        if (s.outputSampleRate == 8_000 || s.outputSampleRate == 16_000) {
            bits += "fréquence native ${s.outputSampleRate} Hz, bande de téléphonie"
        }
        val sp = s.spatial
        if (sp != null && sp.enabled == true && sp.stereoMovie == true) {
            bits += "spatialiseur activé, et un film stéréo peut être spatialisé"
        }
        if (s.plays.any { it.flags and FLAG_SCO != 0 }) {
            bits += "drapeau SCO (chemin d'appel) sur une lecture"
        }
        if (s.micMuted == false && AudioRouteState.callPath(s.mode)) {
            bits += "micro ouvert pendant un mode d'appel"
        }
        val others = s.plays.count { it.ours == false }
        if (others > 0) {
            bits += "$others autre(s) lecture(s) : deux sons peuvent se battre"
        }
        if (bits.isEmpty()) return null
        return Suspect(
            symptom = bits.joinToString(" ; ") + ".",
            cause = "Tout ceci est après l'AudioTrack, ou à côté de lui. " +
                "Les quatre sondes PCM ne le voient pas. " +
                "Un moteur seulement listé dans le catalogue n'est pas compté ici : " +
                "présent ne veut pas dire allumé. On ne coupe rien.",
        )
    }

    /** Famille lisible. Le nom commercial reste entre guillemets à part. */
    fun family(e: Engine): String {
        val uuid = e.typeUuid.lowercase()
        val blob = "${e.name} ${e.implementor}".lowercase()
        return when (uuid) {
            TYPE_AEC -> "Annulation d'écho"
            TYPE_NS -> "Réduction de bruit"
            TYPE_AGC -> "Gain automatique"
            TYPE_EQUALIZER -> "Égaliseur"
            TYPE_BASS_BOOST -> "Renfort de graves"
            TYPE_VIRTUALIZER -> "Virtualiseur"
            TYPE_LOUDNESS -> "Volume perçu"
            TYPE_DYNAMICS -> "Dynamique"
            TYPE_PRESET_REVERB, TYPE_ENV_REVERB -> "Réverbération"
            TYPE_HAPTIC -> "Vibration"
            else -> if (vendorColor(blob)) "Effet fabricant" else "Autre effet"
        }
    }

    /**
     * Nom commercial qui sent un traitement de voix ou de cinéma
     * (Dolby, SoundAlive, Adapt Sound…). On ne dit pas qu'il est allumé.
     */
    fun vendorColor(blob: String): Boolean {
        val s = blob.lowercase()
        return s.contains("dolby") ||
            s.contains("atmos") ||
            s.contains("soundalive") ||
            s.contains("adapt sound") ||
            s.contains("adaptsound") ||
            s.contains("uhq") ||
            s.contains("dirac")
    }

    fun flagsLabel(flags: Int, complete: Boolean): String {
        if (flags == 0) {
            return if (complete) "aucun" else "aucun (publics seulement)"
        }
        val names = ArrayList<String>(4)
        fun bit(mask: Int, label: String) {
            if (flags and mask != 0) names += label
        }
        bit(FLAG_AUDIBILITY_ENFORCED, "audibilité forcée")
        bit(FLAG_SCO, "SCO appel")
        bit(FLAG_HW_AV_SYNC, "synchro image")
        bit(FLAG_LOW_LATENCY, "faible latence")
        bit(FLAG_DEEP_BUFFER, "tampon profond")
        bit(FLAG_CONTENT_SPATIALIZED, "déjà spatialisé")
        bit(FLAG_NEVER_SPATIALIZE, "ne pas spatialiser")
        val known = FLAG_AUDIBILITY_ENFORCED or FLAG_SCO or FLAG_HW_AV_SYNC or
            FLAG_LOW_LATENCY or FLAG_DEEP_BUFFER or FLAG_CONTENT_SPATIALIZED or
            FLAG_NEVER_SPATIALIZE
        val rest = flags and known.inv()
        if (rest != 0) names += "autre 0x${rest.toString(16)}"
        val core = names.joinToString(", ")
        return if (complete) core else "$core (publics seulement)"
    }

    private fun sessionLine(id: Int): String = when {
        id > 0 ->
            "Session de Zuno n°$id. Les effets déjà collés sur cette session " +
                "ne sont pas listés : en créer un (égaliseur, graves, virtualiseur) " +
                "le brancherait et changerait le son. On n'en crée pas."
        id == 0 ->
            "Session 0. Pour une piste, 0 veut dire « pas encore attribuée ». " +
                "Pour un effet, 0 veut dire le mixage global. On n'en crée pas " +
                "pour voir s'il est allumé."
        else -> "Session de Zuno : pas encore connue. On ne crée pas d'effet."
    }

    private fun catalogLines(s: Sheet): List<String> {
        if (s.catalogFailed) return listOf("Catalogue queryEffects : lecture ratée.")
        if (!s.catalogRead) return listOf("Catalogue queryEffects : pas lu.")
        if (s.engines.isEmpty()) {
            return listOf("Catalogue queryEffects : aucun moteur déclaré.")
        }
        val sorted = s.engines.sortedBy { rank(it) }
        val shown = sorted.take(MAX_ENGINES)
        val lines = ArrayList<String>(shown.size + 2)
        lines += "Catalogue queryEffects : ${s.engines.size} moteur(s) installé(s). " +
            "Présent ne veut pas dire allumé."
        for (e in shown) lines += "- ${engineLine(e)}"
        val rest = s.engines.size - shown.size
        if (rest > 0) lines += "- … et $rest autre(s)."
        return lines
    }

    private fun engineLine(e: Engine): String {
        val name = AudioRouteState.safeName(e.name)
        val who = AudioRouteState.safeName(e.implementor)
        val quoted = if (name.isEmpty()) "" else " « $name »"
        val by = if (who.isEmpty()) "" else ", $who"
        return "${family(e)}$quoted (${connectLabel(e.connectMode)}$by)"
    }

    private fun connectLabel(mode: String): String = when (mode) {
        CONNECT_INSERT -> "dans la piste"
        CONNECT_AUXILIARY -> "auxiliaire, mixage global"
        CONNECT_PRE -> "avant le micro"
        CONNECT_POST -> "après le mixage"
        else -> {
            val clean = AudioRouteState.safeName(mode)
            if (clean.isEmpty()) "branchement inconnu" else "branchement $clean"
        }
    }

    /** Les traitements de voix et de cinéma d'abord, le reste après. */
    private fun rank(e: Engine): Int = when (family(e)) {
        "Annulation d'écho", "Réduction de bruit", "Gain automatique" -> 0
        "Virtualiseur", "Effet fabricant", "Dynamique" -> 1
        "Égaliseur", "Renfort de graves", "Volume perçu" -> 2
        else -> if (e.connectMode == CONNECT_POST) 3 else 4
    }

    private fun rateLine(hz: Int, frames: Int): String {
        val hzText = if (hz > 0) "$hz Hz" else "inconnue"
        val fr = if (frames > 0) "$frames" else "inconnu"
        val warn = if (hz == 8_000 || hz == 16_000) " ⚠ fréquence de téléphonie" else ""
        return "Sortie native (chemin rapide, pas forcément la piste de Zuno) : " +
            "$hzText$warn, $fr trames par tampon."
    }

    private fun micLine(muted: Boolean?): String = when (muted) {
        true -> "Micro : muet."
        false -> "Micro : ouvert."
        null -> "Micro : état non lu."
    }

    private fun spatialLine(sp: Spatial?): String {
        if (sp == null || sp.level < 0) {
            return "Spatialiseur : pas lu (Android avant 12, ou lecture impossible)."
        }
        val level = when (sp.level) {
            SPATIALIZER_NONE -> "aucun"
            SPATIALIZER_MULTICHANNEL -> "multicanal"
            SPATIALIZER_OTHER -> "autre"
            else -> "niveau ${sp.level}"
        }
        return "Spatialiseur : niveau $level, activé ${yn(sp.enabled)}, " +
            "disponible ${yn(sp.available)}, suivi de tête ${yn(sp.headTracker)}, " +
            "film stéréo spatialisable ${yn(sp.stereoMovie)}, " +
            "film 5.1 spatialisable ${yn(sp.fiveOneMovie)}."
    }

    private fun yn(b: Boolean?): String = when (b) {
        true -> "oui"
        false -> "non"
        null -> "inconnu"
    }

    private fun playLines(plays: List<Play>): List<String> {
        if (plays.isEmpty()) return listOf("Lectures annoncées : aucune pour l'instant.")
        val lines = ArrayList<String>(plays.size + 1)
        lines += "Lectures annoncées : ${plays.size}."
        plays.take(MAX_PLAYS).forEachIndexed { i, p ->
            val who = when (p.ours) {
                true -> "cette app"
                false -> "une autre application"
                null -> "appartenance inconnue"
            }
            val name = AudioRouteState.safeName(p.deviceName)
            val dev = AudioRouteState.deviceLabel(p.deviceType) +
                if (name.isEmpty()) "" else " « $name »"
            lines += "- ${i + 1} $who, ${AudioRouteState.streamLabel(p.usage, p.contentType)}, " +
                "drapeaux ${flagsLabel(p.flags, p.flagsComplete)}, sortie $dev."
        }
        val rest = plays.size - MAX_PLAYS
        if (rest > 0) lines += "- … et $rest autre(s)."
        return lines
    }
}
