package com.manzilionellm.native_video_player.logic

import java.util.Locale
import kotlin.math.max

/**
 * SIGNALISATION DU FLUX AAC — lecture seule (03/10/2026).
 *
 * La fiche disait « AAC-LC » dès que Media3 écrivait `mp4a.40.2`.
 * Ce nom ne suffit pas :
 *
 *   • L'ADTS (le transport le plus courant du direct .ts) n'a que
 *     2 bits de profil. Il sait dire LC, pas HE-AAC (type 5) ni
 *     HE-AAC v2 (type 29). Le SBR, s'il existe, est dans les trames.
 *   • Un HE-AAC v2 implicite s'annonce donc AAC-LC, souvent à
 *     22,05 ou 24 kHz, et souvent mono. Le décodeur qui trouve le
 *     SBR et la stéréo paramétrique sort à 44,1 ou 48 kHz, stéréo.
 *   • Media3 appelle le type MIME `audio/mp4a-latm` pour l'ADTS
 *     ET pour le LATM. Le mot « latm » dans ce nom ne prouve pas
 *     le transport.
 *   • Le débit annoncé est souvent 0 en direct .ts. Sans débit,
 *     un pourcentage bas au-dessus de 4 kHz peut être une parole
 *     (normal) ou un AAC à 32 kb/s (son de téléphone).
 *
 * On lit les octets déjà fournis par le lecteur (initializationData,
 * ou un en-tête ADTS / LOAS s'il est encore là). On ne décode pas,
 * on ne réécrit rien, on ne change pas le son.
 *
 * Objet pur : testé dans logic-test/, sans Android.
 */
object AacSource {

    /** Au-dessus de cette fréquence, la norme ne demande pas de chercher un SBR implicite. */
    const val IMPLICIT_MAX_HZ: Int = 24_000

    /** Débit sous lequel un flux stéréo large bande est déjà coupé par le codeur. */
    const val THIN_BPS: Int = 48_000

    private val RATES = intArrayOf(
        96_000, 88_200, 64_000, 48_000, 44_100, 32_000,
        24_000, 22_050, 16_000, 12_000, 11_025, 8_000, 7_350,
    )

    /**
     * Ce qu'on a pu lire. Les zéros veulent dire « pas dans les octets »,
     * pas « le flux est à 0 Hz ».
     */
    data class Reading(
        /** Nombre d'octets lus. 0 = rien n'est arrivé. */
        val bytes: Int = 0,
        /**
         * « ADTS », « LOAS/LATM », « ASC » (AudioSpecificConfig),
         * ou une phrase si on n'a que le type MIME.
         */
        val container: String = "inconnu",
        /** Premier type d'objet AAC (2 = LC, 5 = SBR, 29 = PS). 0 = inconnu. */
        val audioObjectType: Int = 0,
        /** Nom français du profil lu dans les octets, pas dans la chaîne `codecs`. */
        val profile: String = "inconnu",
        /** Fréquence écrite en premier (le cœur, pour un HE-AAC explicite). */
        val headerHz: Int = 0,
        /** Fréquence d'extension (sortie visée du SBR). 0 = pas écrite. */
        val extensionHz: Int = 0,
        val channels: Int = 0,
        /** SBR écrit dans l'ASC (type 5 / 29, ou extension 0x2b7 avec le bit à 1). */
        val explicitSbr: Boolean = false,
        /** Stéréo paramétrique écrite (type 29). */
        val explicitPs: Boolean = false,
        /**
         * L'extension 0x2b7 est là et son bit SBR vaut 0.
         * FFmpeg ignore alors le SBR des trames.
         */
        val sbrForbidden: Boolean = false,
        /**
         * Type LC (ou équivalent ADTS), fréquence ≤ 24 kHz, SBR non
         * contredit. C'est le cas où il FAUT chercher le SBR dans les trames.
         */
        val implicitCandidate: Boolean = false,
        /** Taille d'une trame ADTS, octets. 0 si on n'a pas l'en-tête. */
        val frameBytes: Int = 0,
        /** Débit calculé : taille de trame × 8 × fréquence / 1024. 0 = pas calculable. */
        val measuredBps: Int = 0,
        val announcedBps: Int = 0,
        val averageBps: Int = 0,
        val peakBps: Int = 0,
        /** Phrase en plus, déjà en français, sans URL. */
        val note: String = "",
    )

    /**
     * Débit d'une trame AAC. [samplesPerFrame] vaut 1024 pour le cœur LC
     * (c'est la durée que l'en-tête ADTS décrit, même en HE-AAC).
     */
    fun bitrateOfFrame(frameBytes: Int, sampleRate: Int, samplesPerFrame: Int = 1024): Int {
        if (frameBytes <= 0 || sampleRate <= 0 || samplesPerFrame <= 0) return 0
        val bps = frameBytes.toLong() * 8L * sampleRate.toLong() / samplesPerFrame.toLong()
        if (bps <= 0L || bps > Int.MAX_VALUE) return 0
        return bps.toInt()
    }

    /**
     * Lit les octets de signalisation. [formatHz] et [formatChannels]
     * sont ce que Media3 a déjà mis dans le format : on les compare
     * aux octets, on ne les remplace pas.
     */
    fun read(
        bytes: ByteArray?,
        mime: String? = null,
        announcedBps: Int = 0,
        averageBps: Int = 0,
        peakBps: Int = 0,
        formatHz: Int = 0,
        formatChannels: Int = 0,
    ): Reading {
        val cleanAnnounced = positive(announcedBps)
        val cleanAverage = positive(averageBps)
        val cleanPeak = positive(peakBps)
        val parsed = when {
            bytes == null || bytes.isEmpty() -> empty(mime)
            isAdts(bytes) -> parseAdts(bytes)
            isLoas(bytes) -> loas(bytes)
            else -> parseAsc(bytes) ?: empty(mime).copy(bytes = bytes.size, container = "ASC illisible")
        }
        val withRates = parsed.copy(
            announcedBps = cleanAnnounced,
            averageBps = cleanAverage,
            peakBps = cleanPeak,
        )
        val mismatch = rateMismatch(withRates, formatHz, formatChannels)
        if (mismatch.isEmpty()) return withRates
        val joined = listOf(withRates.note, mismatch).filter { it.isNotBlank() }.joinToString(" ")
        return withRates.copy(note = joined)
    }

    /** Ligne de fiche. Pas d'URL, pas de secret. */
    fun describe(r: Reading): String {
        val head = if (r.bytes <= 0) {
            "Signalisation : pas d'AudioSpecificConfig reçu. " +
                "Transport vu : ${r.container}. " +
                "Le type MIME audio/mp4a-latm sert à Media3 pour l'ADTS et pour le LATM : " +
                "le mot latm dans ce nom ne dit pas lequel des deux c'est."
        } else {
            val who = if (r.audioObjectType > 0) {
                "${r.profile} (AOT ${r.audioObjectType})"
            } else {
                r.profile
            }
            val freq = buildString {
                append(if (r.headerHz > 0) khz(r.headerHz) else "fréquence inconnue")
                if (r.extensionHz > 0 && r.extensionHz != r.headerHz) {
                    append(", extension ")
                    append(khz(r.extensionHz))
                }
            }
            val voices = when (r.channels) {
                0 -> "voies inconnues"
                1 -> "mono"
                else -> "${r.channels} voies"
            }
            val sbr = when {
                r.sbrForbidden ->
                    "SBR explicite : non, l'extension le déclare absent (le décodeur ne doit pas le chercher)."
                r.explicitPs ->
                    "SBR explicite : oui, avec stéréo paramétrique (HE-AAC v2)."
                r.explicitSbr ->
                    "SBR explicite : oui (HE-AAC)."
                r.implicitCandidate ->
                    "SBR explicite : non. SBR implicite à chercher, parce que la fréquence est ≤ 24 kHz " +
                        "et que le profil est LC. Le nom AAC-LC ne prouve pas qu'il n'y a pas de SBR dans les trames."
                else ->
                    "SBR explicite : non. Fréquence au-dessus de 24 kHz : la norme ne demande pas de chercher " +
                        "un SBR implicite. Un HE-AAC classique (cœur à 22 ou 24 kHz) ne s'annonce pas comme ça."
            }
            "Signalisation : $who, $freq, $voices. " +
                "Transport lu : ${r.container} (${r.bytes} octets). $sbr"
        }
        val announced = max(r.announcedBps, r.averageBps)
        val debit = buildString {
            append(" Débit annoncé : ")
            append(if (announced > 0) "${announced / 1000} kb/s" else "inconnu")
            if (r.peakBps > announced && r.peakBps > 0) append(", crête ${r.peakBps / 1000} kb/s")
            append(". Débit mesuré : ")
            if (r.measuredBps > 0) {
                append("${r.measuredBps / 1000} kb/s")
                append(" (taille de trame ${r.frameBytes} octets × 8 × fréquence / 1024).")
            } else {
                append("pas disponible. En direct, Media3 retire l'en-tête ADTS avant le décodeur, ")
                append("et le conteneur .ts n'écrit souvent pas de débit.")
            }
        }
        val extra = if (r.note.isBlank()) "" else " ${r.note}"
        return head + debit + extra
    }

    private fun empty(mime: String?): Reading {
        val container = when {
            mime.isNullOrBlank() -> "inconnu"
            mime.contains("mp4a", ignoreCase = true) || mime.contains("aac", ignoreCase = true) ->
                "MIME ${mime.trim()} (ADTS et LATM portent le même nom chez Media3)"
            else -> "MIME ${mime.trim()}"
        }
        return Reading(container = container)
    }

    private fun isAdts(bytes: ByteArray): Boolean {
        if (bytes.size < 7) return false
        val b0 = bytes[0].toInt() and 0xFF
        val b1 = bytes[1].toInt() and 0xFF
        // Sync 12 bits à 1, layer à 0 (les 2 bits qui suivent l'identifiant).
        return b0 == 0xFF && (b1 and 0xF0) == 0xF0 && (b1 and 0x06) == 0
    }

    private fun isLoas(bytes: ByteArray): Boolean {
        if (bytes.size < 2) return false
        val b0 = bytes[0].toInt() and 0xFF
        val b1 = bytes[1].toInt() and 0xFF
        // Mot de sync LOAS : 11 bits 0x2B7, donc les deux premiers octets 0x56 0xE?.
        return b0 == 0x56 && (b1 and 0xE0) == 0xE0
    }

    private fun loas(bytes: ByteArray): Reading = Reading(
        bytes = bytes.size,
        container = "LOAS/LATM",
        profile = "AAC en LOAS",
        note = "Les octets commencent par 56 E0, le sync LOAS. " +
            "Le décodeur AAC brut (sans démultiplexeur LATM) refuse ce flux : " +
            "ffmpeg 6.1 renvoie une erreur de données, pas un son sourd. " +
            "Media3 retire le LATM avant le décodeur. Si le son joue, ce n'est pas un LOAS laissé tel quel.",
    )

    private fun parseAdts(bytes: ByteArray): Reading {
        val b2 = bytes[2].toInt() and 0xFF
        val b3 = bytes[3].toInt() and 0xFF
        val b4 = bytes[4].toInt() and 0xFF
        val b5 = bytes[5].toInt() and 0xFF
        // Profil ADTS : 0 Main, 1 LC, 2 SSR, 3 LTP. Le type d'objet vaut profil + 1.
        val profile = (b2 shr 6) and 0x3
        val aot = profile + 1
        val sfi = (b2 shr 2) and 0xF
        val hz = rate(sfi)
        val channels = ((b2 and 0x01) shl 2) or ((b3 shr 6) and 0x3)
        val frameBytes = ((b3 and 0x03) shl 11) or (b4 shl 3) or ((b5 shr 5) and 0x7)
        val measured = bitrateOfFrame(frameBytes, hz)
        val implicit = aot == 2 && hz in 1..IMPLICIT_MAX_HZ
        return Reading(
            bytes = bytes.size.coerceAtMost(7),
            container = "ADTS",
            audioObjectType = aot,
            profile = profileName(aot, explicitSbr = false, explicitPs = false),
            headerHz = hz,
            channels = channels,
            implicitCandidate = implicit,
            frameBytes = frameBytes,
            measuredBps = measured,
            note = "L'ADTS n'a que 2 bits de profil (Main, LC, SSR ou LTP). " +
                "Il ne peut pas écrire HE-AAC. Si du SBR est présent, il est seulement dans les trames, " +
                "et seulement cherché quand la fréquence de cet en-tête est ≤ 24 kHz.",
        )
    }

    private fun parseAsc(bytes: ByteArray): Reading? {
        val bits = Bits(bytes)
        val aot = bits.readAot() ?: return null
        val headerHz = bits.readRate() ?: return null
        val channels = bits.read(4) ?: return null
        var explicitSbr = aot == 5 || aot == 29
        var explicitPs = aot == 29
        var extensionHz = 0
        val coreHz = headerHz
        if (explicitSbr) {
            // Après le type 5 ou 29 : fréquence de SORTIE, puis le type du cœur (souvent LC).
            // La première fréquence lue reste celle du cœur, pour la ligne de fiche.
            extensionHz = bits.readRate() ?: 0
            bits.readAot()
        }
        // Extension de synchro 0x2b7, là où FFmpeg la cherche, après la config de base.
        // Media3, pour le nom mp4a.40.x, ne lit pas cette extension : il peut dire
        // AAC-LC alors que le SBR est écrit dans les octets suivants.
        var forbidden = false
        val syncAt = bits.find(0x2B7, 11, bits.position)
        if (syncAt != null && !explicitSbr) {
            bits.position = syncAt + 11
            val extAot = bits.readAot()
            val flag = bits.read(1)
            if (extAot == 5 && flag != null) {
                if (flag == 1) {
                    explicitSbr = true
                    extensionHz = bits.readRate() ?: extensionHz
                    val psFlag = bits.find(0x548, 11, bits.position)
                    if (psFlag != null) {
                        bits.position = psFlag + 11
                        if (bits.read(1) == 1) explicitPs = true
                    }
                } else {
                    forbidden = true
                }
            }
        }
        // SBR implicite : la norme le demande pour un LC à 24 kHz ou moins,
        // tant que personne n'a écrit « SBR absent ».
        val implicit = !explicitSbr && !forbidden && aot == 2 && coreHz in 1..IMPLICIT_MAX_HZ
        val note = buildString {
            if (explicitSbr && aot == 2) {
                append("Le SBR est dans l'extension 0x2b7, après un type LC. ")
                append("Le nom mp4a.40.2 de Media3 ne lit que le premier type : il peut dire AAC-LC quand même. ")
            }
            if (bytes.size <= 2 && aot == 2) {
                append("Deux octets : c'est aussi l'ASC que Media3 fabrique depuis un en-tête ADTS. ")
                append("Avec seulement ces deux octets, on ne sépare pas l'ADTS d'un LATM sans SBR. ")
            }
            if (explicitSbr && channels == 1 && !explicitPs) {
                append("Mono avec SBR : la stéréo paramétrique est souvent seulement dans les trames. ")
            }
        }.trim()
        return Reading(
            bytes = bytes.size,
            container = "ASC",
            audioObjectType = aot,
            profile = profileName(aot, explicitSbr, explicitPs),
            headerHz = if (explicitSbr && aot != 2) coreHz else headerHz,
            extensionHz = extensionHz,
            channels = channels,
            explicitSbr = explicitSbr,
            explicitPs = explicitPs,
            sbrForbidden = forbidden,
            implicitCandidate = implicit,
            note = note,
        )
    }

    private fun profileName(aot: Int, explicitSbr: Boolean, explicitPs: Boolean): String = when {
        explicitPs || aot == 29 -> "HE-AAC v2"
        explicitSbr || aot == 5 -> "HE-AAC"
        aot == 2 -> "AAC-LC"
        aot == 1 -> "AAC Main"
        aot == 3 -> "AAC SSR"
        aot == 4 -> "AAC LTP"
        aot == 23 -> "AAC-LD"
        aot == 42 -> "xHE-AAC"
        else -> "AAC type $aot"
    }

    private fun rateMismatch(r: Reading, formatHz: Int, formatChannels: Int): String {
        if (r.bytes <= 0) return ""
        val known = listOf(r.headerHz, r.extensionHz).filter { it > 0 }
        val freqDiffers = formatHz > 0 && known.isNotEmpty() && known.none { it == formatHz }
        val chanDiffers = formatChannels > 0 && r.channels > 0 && formatChannels != r.channels
        if (!freqDiffers && !chanDiffers) return ""
        return buildString {
            append("Le format du lecteur ne dit pas la même chose que les octets :")
            if (freqDiffers) append(" format ").append(khz(formatHz)).append(", octets ").append(khz(r.headerHz))
            if (r.extensionHz > 0 && freqDiffers) append(" / ").append(khz(r.extensionHz))
            if (chanDiffers) append(", format ").append(formatChannels).append(" voies, octets ").append(r.channels)
            append(".")
        }
    }

    private fun rate(index: Int): Int = RATES.getOrNull(index) ?: 0

    private fun positive(v: Int): Int = if (v > 0) v else 0

    private fun khz(hz: Int): String =
        if (hz % 1000 == 0) "${hz / 1000} kHz"
        else String.format(Locale.FRANCE, "%.2f kHz", hz / 1000.0).replace(",00", "")

    /**
     * Lecteur de bits. On n'avance que si les bits sont vraiment là :
     * un ASC trop court donne null, pas une valeur inventée.
     */
    private class Bits(private val data: ByteArray) {
        var position: Int = 0
        private val end = data.size * 8

        fun read(n: Int): Int? {
            if (n <= 0 || n > 24 || position + n > end) return null
            var v = 0
            repeat(n) {
                val byte = data[position / 8].toInt() and 0xFF
                val bit = (byte shr (7 - (position % 8))) and 1
                v = (v shl 1) or bit
                position++
            }
            return v
        }

        fun readAot(): Int? {
            val aot = read(5) ?: return null
            if (aot != 31) return aot
            val extra = read(6) ?: return null
            return 32 + extra
        }

        fun readRate(): Int? {
            val index = read(4) ?: return null
            if (index == 0xF) return read(24)
            return rate(index)
        }

        /** Premier endroit ≥ [from] où [width] bits valent [value]. N'avance pas pour de bon. */
        fun find(value: Int, width: Int, from: Int): Int? {
            val saved = position
            var i = from
            while (i + width <= end) {
                position = i
                if (read(width) == value) {
                    position = saved
                    return i
                }
                i++
            }
            position = saved
            return null
        }
    }
}
