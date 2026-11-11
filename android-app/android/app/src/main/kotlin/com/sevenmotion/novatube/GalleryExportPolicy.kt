package com.sevenmotion.novatube

import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.min

/** Décisions pures de l'export : testables sur JVM sans simuler des codecs Android. */
internal object GalleryExportPolicy {
    const val AVC = "video/avc"
    const val AAC = "audio/mp4a-latm"
    const val MAX_SAMPLE_BYTES = 64 * 1024 * 1024
    const val MAX_PENDING_BYTES = 32 * 1024 * 1024
    const val STALL_TIMEOUT_MS = 60_000L

    fun canRemux(videoMime: String?, audioMime: String?, sourceHasAudio: Boolean): Boolean =
        videoMime == AVC && (if (sourceHasAudio) audioMime == AAC else audioMime == null)

    /**
     * MediaMuxer attend des séparateurs AVC de quatre octets. Le TS peut
     * fournir 00 00 01 : MPEG4Writer soustrait pourtant quatre et peut
     * provoquer un abort natif. Seuls les séparateurs sont normalisés.
     * Le contenu des NAL, leur ordre et le tampon source restent intacts.
     */
    fun avcAnnexBForMp4(
        sample: ByteBuffer,
        size: Int,
        maxBytes: Int = MAX_SAMPLE_BYTES,
    ): ByteBuffer {
        require(maxBytes in 4..MAX_SAMPLE_BYTES && size in 4..maxBytes && size <= sample.limit()) {
            "Taille de l'échantillon AVC invalide"
        }
        fun prefixAt(at: Int): Int {
            if (at + 3 < size && sample.get(at).toInt() == 0 && sample.get(at + 1).toInt() == 0 &&
                sample.get(at + 2).toInt() == 0 && sample.get(at + 3).toInt() == 1) return 4
            if (at + 2 < size && sample.get(at).toInt() == 0 && sample.get(at + 1).toInt() == 0 &&
                sample.get(at + 2).toInt() == 1) return 3
            return 0
        }
        fun nextPrefix(from: Int): Int {
            var at = from
            while (at < size && prefixAt(at) == 0) at++
            return at
        }
        var at = 0
        var extra = 0
        while (at < size) {
            val prefix = prefixAt(at)
            require(prefix != 0) { "Échantillon AVC sans séparateur Annex-B" }
            val payload = at + prefix
            val end = nextPrefix(payload)
            require(payload < end) { "NAL AVC vide ou tronqué" }
            val header = sample.get(payload).toInt() and 0xff
            require(header and 0x80 == 0 && (header and 0x1f) in 1..23) { "En-tête NAL AVC invalide" }
            if (prefix == 3) extra++
            at = end
        }
        val expanded = size.toLong() + extra
        require(expanded <= maxBytes.toLong()) { "Échantillon AVC normalisé trop volumineux" }
        if (extra == 0) return sample.duplicate().apply { position(0); limit(size) }
        val result = ByteBuffer.allocate(expanded.toInt())
        at = 0
        while (at < size) {
            val payload = at + prefixAt(at)
            val end = nextPrefix(payload)
            result.put(0.toByte()).put(0.toByte()).put(0.toByte()).put(1.toByte())
            result.put(sample.duplicate().apply { position(payload); limit(end) })
            at = end
        }
        result.flip()
        return result
    }

    fun legacyPermissionRequired(api: Int): Boolean = api in 24..28

    /** Conserve la résolution/cadence ; le codec bornera ensuite à ses capacités réelles. */
    fun videoBitrate(width: Int, height: Int, fps: Double, sourceBitrate: Int = 0): Int {
        require(width > 0 && height > 0 && fps.isFinite() && fps > 0)
        val pixelsPerSecond = width.toDouble() * height * fps
        return max(2_000_000.0, max(pixelsPerSecond * 0.20, sourceBitrate.toDouble() * 1.5))
            .coerceAtMost(Int.MAX_VALUE.toDouble()).toInt()
    }

    fun audioBitrate(channels: Int): Int {
        require(channels > 0)
        return min(768_000L, max(128_000L, channels.toLong() * 128_000L)).toInt()
    }

    /** Une sortie PCM peut être plus grande qu'une entrée AAC : jamais la tronquer. */
    fun pcmChunkBytes(remaining: Int, capacity: Int, channels: Int): Int {
        require(remaining >= 0 && channels > 0 && channels <= 32)
        val frameBytes = channels * 2 // PCM signé 16 bits, vérifié au format de sortie.
        require(remaining % frameBytes == 0 && capacity >= frameBytes)
        return min(remaining, capacity) / frameBytes * frameBytes
    }

    fun pcmTimestampUs(base: Long, consumedBytes: Int, sampleRate: Int, channels: Int): Long {
        require(consumedBytes >= 0 && sampleRate > 0 && channels > 0)
        return base + (consumedBytes.toLong() / (channels * 2)) * 1_000_000L / sampleRate
    }

    fun stalled(nowMs: Long, lastProgressMs: Long): Boolean = nowMs - lastProgressMs > STALL_TIMEOUT_MS

    fun displayName(raw: String): String {
        var name = raw.substringAfterLast('/').substringAfterLast('\\')
            .replace(Regex("[\\p{Cntrl}<>:\"|?*]"), "_").trim()
        name = name.substringBeforeLast('.', name)
            .replace(Regex("^(?:7MOTION_|NOVATUBE_)", RegexOption.IGNORE_CASE), "")
            .trim().ifBlank { "enregistrement" }
        return "NOVATUBE_${name.take(160)}.mp4"
    }

    fun isMp4Header(header: ByteArray): Boolean = header.size >= 12 &&
        header[4] == 'f'.code.toByte() && header[5] == 't'.code.toByte() &&
        header[6] == 'y'.code.toByte() && header[7] == 'p'.code.toByte()

    fun transportStreamOffset(bytes: ByteArray): Int? {
        for (offset in 0 until min(188, bytes.size)) {
            if (offset + 376 < bytes.size && bytes[offset] == 0x47.toByte() &&
                bytes[offset + 188] == 0x47.toByte() && bytes[offset + 376] == 0x47.toByte()) return offset
        }
        return null
    }

    /**
     * MediaExtractor peut masquer l'audio TS non pris en charge (AC3 notamment).
     * Lire PAT/PMT évite d'annoncer un export muet comme une source sans audio.
     * `null` = déclaration absente/incomplète : on ne prétend pas connaître la source.
     */
    fun declaredTsAudio(bytes: ByteArray): Boolean? {
        val offset = transportStreamOffset(bytes) ?: return null
        val pmtPids = mutableSetOf<Int>()
        val buffers = mutableMapOf<Int, MutableList<Byte>>()
        val programTables = mutableMapOf<Int, Boolean?>()
        val patSections = mutableSetOf<Int>()
        var lastPatSection = -1
        var patVersion = -1
        fun u(value: Byte): Int = value.toInt() and 255
        fun validCrc(section: List<Byte>): Boolean {
            var crc = -1
            for (value in section) {
                crc = crc xor (u(value) shl 24)
                repeat(8) { crc = if (crc < 0) (crc shl 1) xor 0x04c11db7 else crc shl 1 }
            }
            return crc == 0
        }
        fun parse(pid: Int, section: List<Byte>) {
            if (section.size < 12 || (u(section[1]) and 0x80) == 0 ||
                (u(section[5]) and 1) == 0 || !validCrc(section)) return
            val end = section.size - 4 // CRC, pas une entrée élémentaire.
            if (pid == 0 && u(section[0]) == 0) {
                if ((end - 8) % 4 != 0 || u(section[6]) > u(section[7])) return
                val version = (u(section[5]) ushr 1) and 31
                if (patVersion != version) {
                    patVersion = version
                    pmtPids.clear()
                    programTables.clear()
                    patSections.clear()
                }
                lastPatSection = u(section[7])
                patSections.add(u(section[6]))
                var i = 8
                while (i + 3 < end) {
                    val program = (u(section[i]) shl 8) or u(section[i + 1])
                    if (program != 0) pmtPids.add(((u(section[i + 2]) and 31) shl 8) or u(section[i + 3]))
                    i += 4
                }
            } else if (pid in pmtPids && u(section[0]) == 2 && section.size >= 16) {
                // Une PMT fragmentée en plusieurs sections reste inconnue ici.
                if (u(section[6]) != 0 || u(section[7]) != 0) return
                val infoLength = ((u(section[10]) and 15) shl 8) or u(section[11])
                var i = 12 + infoLength
                if (i > end) return
                var valid = true
                var sectionAudio = false
                var unknownStream = false
                while (i < end) {
                    if (i + 5 > end) { valid = false; break }
                    val type = u(section[i])
                    val length = ((u(section[i + 3]) and 15) shl 8) or u(section[i + 4])
                    if (i + 5 + length > end) { valid = false; break }
                    val audioType = type in setOf(0x03, 0x04, 0x0f, 0x11, 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x8a)
                    if (audioType) sectionAudio = true
                    if (type == 0x06) {
                        var d = i + 5
                        var knownNonAudio = false
                        var knownAudio = false
                        while (d + 2 <= i + 5 + length) {
                            val tag = u(section[d]); val size = u(section[d + 1])
                            if (d + 2 + size > i + 5 + length) { valid = false; break }
                            if (tag in setOf(0x6a, 0x7a, 0x7b, 0x7c)) knownAudio = true
                            if (tag in setOf(0x56, 0x59)) knownNonAudio = true // télétexte/sous-titres DVB
                            d += 2 + size
                        }
                        if (d != i + 5 + length) valid = false
                        // Un PES privé inconnu ne doit jamais devenir un « pas de son » certain.
                        if (knownAudio || !knownNonAudio) sectionAudio = true
                    } else if (!audioType && type !in setOf(0x01, 0x02, 0x05, 0x10, 0x1b, 0x24, 0x42)) {
                        unknownStream = true
                    }
                    i += 5 + length
                }
                if (valid) programTables[pid] = if (sectionAudio) true else if (unknownStream) null else false
            }
        }
        fun append(pid: Int, start: Int, end: Int) {
            val buffer = buffers[pid] ?: return
            var pos = start
            while (pos < end) {
                if (buffer.isEmpty() && u(bytes[pos]) == 255) return
                buffer.add(bytes[pos++])
                if (buffer.size >= 3) {
                    val size = 3 + ((u(buffer[1]) and 15) shl 8) + u(buffer[2])
                    if (size !in 12..1024) { buffer.clear(); return }
                    if (buffer.size == size) { parse(pid, buffer); buffer.clear() }
                }
            }
        }
        var packet = offset
        while (packet + 188 <= bytes.size) {
            if (u(bytes[packet]) != 0x47) return null
            val pid = ((u(bytes[packet + 1]) and 31) shl 8) or u(bytes[packet + 2])
            val control = (u(bytes[packet + 3]) ushr 4) and 3
            if ((pid == 0 || pid in pmtPids) && control in 1..3 && control != 2 &&
                (u(bytes[packet + 1]) and 0x80) == 0) {
                var pos = packet + 4
                if (control == 3) pos += 1 + u(bytes[pos])
                val end = packet + 188
                if (pos < end) {
                    val starts = (u(bytes[packet + 1]) and 0x40) != 0
                    if (starts) {
                        val pointer = u(bytes[pos++])
                        if (pos + pointer > end) return null
                        if (pointer > 0) append(pid, pos, pos + pointer)
                        pos += pointer
                        buffers[pid] = mutableListOf()
                    }
                    if (pos < end) append(pid, pos, end)
                }
            }
            packet += 188
        }
        if (programTables.values.any { it == true }) return true
        val completePat = lastPatSection >= 0 && (0..lastPatSection).all { it in patSections }
        return if (completePat && pmtPids.isNotEmpty() &&
            pmtPids.all { programTables.containsKey(it) && programTables[it] == false }) false else null
    }
}
