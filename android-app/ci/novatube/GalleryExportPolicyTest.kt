package com.sevenmotion.novatube

import java.nio.ByteBuffer
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.Test

class GalleryExportPolicyTest {
    private val policy = GalleryExportPolicy

    private fun sampleBytes(buffer: ByteBuffer): ByteArray =
        ByteArray(buffer.remaining()).also { buffer.duplicate().get(it) }

    @Test fun audioBeforeVideoZeroGetsOneSharedTimestampTranslation() {
        // Cas réel de la mire TS : l'AAC précède la première image de 21,333 ms.
        val audio = listOf(-21_333L, 0L, 21_333L)
        val video = listOf(0L, 40_000L, 80_000L)
        val offset = policy.timestampOffsetUs((audio + video).min())
        assertEquals(21_333L, offset)
        val shiftedAudio = audio.map { policy.normalizedTimestampUs(it, offset) }
        val shiftedVideo = video.map { policy.normalizedTimestampUs(it, offset) }
        assertEquals(listOf(0L, 21_333L, 42_666L), shiftedAudio)
        assertEquals(listOf(21_333L, 61_333L, 101_333L), shiftedVideo)
        assertEquals(video.first() - audio.first(), shiftedVideo.first() - shiftedAudio.first())
        assertEquals(audio.zipWithNext { a, b -> b - a }, shiftedAudio.zipWithNext { a, b -> b - a })
        assertEquals(video.zipWithNext { a, b -> b - a }, shiftedVideo.zipWithNext { a, b -> b - a })
    }

    @Test fun timestampTranslationKeepsBFrameOrderAndALaterMinimum() {
        val decodeOrder = listOf(80_000L, 200_000L, -40_000L, 120_000L, -1L)
        val offset = policy.timestampOffsetUs(decodeOrder.min())
        val shifted = decodeOrder.map { policy.normalizedTimestampUs(it, offset) }
        assertEquals(listOf(120_000L, 240_000L, 0L, 160_000L, 39_999L), shifted)
        assertEquals(decodeOrder.zipWithNext { a, b -> b - a }, shifted.zipWithNext { a, b -> b - a })
        assertEquals(decodeOrder.size, shifted.size)
    }

    @Test fun alreadyNonNegativeTimestampsAreNotRebasedPerTrack() {
        val timestamps = listOf(58_666L, 80_000L, 120_000L, Long.MAX_VALUE)
        val offset = policy.timestampOffsetUs(timestamps.min())
        assertEquals(0L, offset)
        assertEquals(timestamps, timestamps.map { policy.normalizedTimestampUs(it, offset) })
        assertEquals(0L, policy.timestampOffsetUs(0L))
    }

    @Test fun timestampTranslationRejectsOverflowAndInvalidOffsets() {
        assertFailsWith<IllegalArgumentException> { policy.timestampOffsetUs(Long.MIN_VALUE) }
        assertFailsWith<ArithmeticException> { policy.normalizedTimestampUs(Long.MAX_VALUE, 1L) }
        assertFailsWith<IllegalArgumentException> { policy.normalizedTimestampUs(0L, -1L) }
        assertFailsWith<IllegalArgumentException> { policy.normalizedTimestampUs(-2L, 1L) }
        assertEquals(Long.MAX_VALUE, policy.normalizedTimestampUs(Long.MAX_VALUE - 1L, 1L))
        assertEquals(0L, policy.normalizedTimestampUs(-1L, policy.timestampOffsetUs(-1L)))
    }

    @Test fun threeByteAvcPrefixIsExpandedWithoutChangingPayloadOrSource() {
        val bytes = byteArrayOf(0, 0, 1, 0x65, 0x11, 0x22)
        val input = ByteBuffer.wrap(bytes).apply { position(2) }
        val result = policy.avcAnnexBForMp4(input, bytes.size)
        assertContentEquals(byteArrayOf(0, 0, 0, 1, 0x65, 0x11, 0x22), sampleBytes(result))
        assertEquals(2, input.position())
        assertEquals(bytes.size, input.limit())
        assertContentEquals(byteArrayOf(0, 0, 1, 0x65, 0x11, 0x22), bytes)
    }

    @Test fun mixedAvcPrefixesKeepNalOrderAndEmulationPreventionBytes() {
        val input = byteArrayOf(0, 0, 0, 1, 0x67, 0x42, 0, 0, 3, 1,
            0, 0, 1, 0x68, 0x11, 0, 0, 1, 0x65, 0x22)
        val expected = byteArrayOf(0, 0, 0, 1, 0x67, 0x42, 0, 0, 3, 1,
            0, 0, 0, 1, 0x68, 0x11, 0, 0, 0, 1, 0x65, 0x22)
        assertContentEquals(expected, sampleBytes(policy.avcAnnexBForMp4(ByteBuffer.wrap(input), input.size)))
        assertContentEquals(expected, sampleBytes(policy.avcAnnexBForMp4(ByteBuffer.wrap(expected), expected.size)))
    }

    @Test fun directAndReadOnlyAvcBuffersRespectTheDeclaredSampleBoundary() {
        val bytes = byteArrayOf(0, 0, 1, 0x65, 0x11, 0x22)
        val expected = byteArrayOf(0, 0, 0, 1, 0x65, 0x11, 0x22)
        val heap = ByteBuffer.allocate(bytes.size + 4).apply {
            put(bytes); put(byteArrayOf(0, 0, 1, 0)); position(1); limit(bytes.size)
        }
        val direct = ByteBuffer.allocateDirect(bytes.size + 4).apply {
            put(bytes); put(byteArrayOf(0, 0, 1, 0)); position(1); limit(bytes.size)
        }
        for (input in listOf(heap, heap.asReadOnlyBuffer(), direct, direct.asReadOnlyBuffer())) {
            assertContentEquals(expected, sampleBytes(policy.avcAnnexBForMp4(input, bytes.size)))
            assertEquals(1, input.position())
            assertEquals(bytes.size, input.limit())
            assertFailsWith<IllegalArgumentException> { policy.avcAnnexBForMp4(input, bytes.size + 1) }
        }
    }

    @Test fun emptyOrTruncatedAvcNalNeverReachesTheNativeMuxer() {
        val malformed = listOf(
            byteArrayOf(), byteArrayOf(0, 0, 1), byteArrayOf(0, 0, 0, 1),
            byteArrayOf(0, 0, 1, 0x65, 0, 0, 1),
            byteArrayOf(0, 0, 1, 0, 0, 1, 0x65),
            byteArrayOf(1, 0, 0, 1, 0x65),
            byteArrayOf(0, 0, 1, 0x80.toByte()), byteArrayOf(0, 0, 1, 0),
        )
        for (bytes in malformed) {
            assertFailsWith<IllegalArgumentException> {
                policy.avcAnnexBForMp4(ByteBuffer.wrap(bytes), bytes.size)
            }
        }
    }

    @Test fun avcLimitAlsoAppliesAfterPrefixExpansion() {
        val bytes = byteArrayOf(0, 0, 1, 0x65, 0x11, 0x22)
        assertFailsWith<IllegalArgumentException> {
            policy.avcAnnexBForMp4(ByteBuffer.wrap(bytes), bytes.size, maxBytes = bytes.size)
        }
        assertEquals(bytes.size + 1,
            policy.avcAnnexBForMp4(ByteBuffer.wrap(bytes), bytes.size, maxBytes = bytes.size + 1).remaining())
        assertFailsWith<IllegalArgumentException> {
            policy.avcAnnexBForMp4(ByteBuffer.wrap(bytes), bytes.size, maxBytes = policy.MAX_SAMPLE_BYTES + 1)
        }
    }

    @Test fun remuxRequiresAvcAndAac() {
        assertTrue(policy.canRemux("video/avc", "audio/mp4a-latm", true))
        assertFalse(policy.canRemux("video/hevc", "audio/mp4a-latm", true))
        assertFalse(policy.canRemux("video/mpeg2", "audio/mp4a-latm", true))
        assertFalse(policy.canRemux("video/avc", "audio/ac3", true))
        assertFalse(policy.canRemux(null, "audio/mp4a-latm", true))
    }

    @Test fun audioCannotDisappearDuringRemux() {
        assertFalse(policy.canRemux("video/avc", null, true))
        assertTrue(policy.canRemux("video/avc", null, false))
        assertFalse(policy.canRemux("video/avc", "audio/mp4a-latm", false))
    }

    @Test fun legacyWritePermissionStopsAtAndroidNine() {
        assertTrue(policy.legacyPermissionRequired(24))
        assertTrue(policy.legacyPermissionRequired(28))
        assertFalse(policy.legacyPermissionRequired(29))
        assertFalse(policy.legacyPermissionRequired(36))
    }

    @Test fun highDefinitionBitrateIncludesCadenceAndSourceQuality() {
        assertEquals(12_441_600, policy.videoBitrate(1920, 1080, 30.0))
        assertEquals(24_883_200, policy.videoBitrate(1920, 1080, 60.0))
        assertEquals(99_532_800, policy.videoBitrate(3840, 2160, 60.0))
        assertEquals(60_000_000, policy.videoBitrate(1920, 1080, 30.0, 40_000_000))
        assertEquals(2_000_000, policy.videoBitrate(320, 180, 24.0))
    }

    @Test fun invalidVideoGeometryCannotInventAnExportSize() {
        assertFailsWith<IllegalArgumentException> { policy.videoBitrate(0, 1080, 30.0) }
        assertFailsWith<IllegalArgumentException> { policy.videoBitrate(1920, -1, 30.0) }
        assertFailsWith<IllegalArgumentException> { policy.videoBitrate(1920, 1080, Double.NaN) }
        assertFailsWith<IllegalArgumentException> { policy.videoBitrate(1920, 1080, 0.0) }
    }

    @Test fun aacBitrateRetainsStereoAndSurroundQuality() {
        assertEquals(128_000, policy.audioBitrate(1))
        assertEquals(256_000, policy.audioBitrate(2))
        assertEquals(768_000, policy.audioBitrate(6))
        assertFailsWith<IllegalArgumentException> { policy.audioBitrate(0) }
    }

    @Test fun largePcmOutputIsSplitWithoutDroppingOrOverflowingSamples() {
        val bytes = 6 * 2 * 8192
        var consumed = 0
        var chunks = 0
        while (consumed < bytes) {
            val chunk = policy.pcmChunkBytes(bytes - consumed, 4096, 6)
            assertTrue(chunk in 12..4096)
            assertEquals(0, chunk % 12)
            consumed += chunk
            chunks++
        }
        assertEquals(bytes, consumed)
        assertTrue(chunks > 1)
        assertEquals(0, policy.pcmChunkBytes(0, 4096, 6))
    }

    @Test fun splitPcmTimestampsFollowSamplesRatherThanCodecQueueTime() {
        assertEquals(2_100_000L, policy.pcmTimestampUs(2_000_000, 19_200, 48_000, 2))
        assertEquals(2_000_000L, policy.pcmTimestampUs(2_000_000, 0, 48_000, 2))
    }

    @Test fun invalidPcmCannotBeSilentlyTruncated() {
        assertFailsWith<IllegalArgumentException> { policy.pcmChunkBytes(7, 4096, 2) }
        assertFailsWith<IllegalArgumentException> { policy.pcmChunkBytes(4096, 2, 2) }
        assertFailsWith<IllegalArgumentException> { policy.pcmChunkBytes(0, 4096, 0) }
    }

    @Test fun longRecordingIsAllowedAsLongAsConversionProgresses() {
        assertFalse(policy.stalled(3_600_000, 3_599_999))
        assertFalse(policy.stalled(3_600_000, 3_540_000))
        assertTrue(policy.stalled(3_600_001, 3_540_000))
    }

    @Test fun galleryNameIsSanitizedAndBrandedWithoutOverwritingSourcePath() {
        assertEquals("NOVATUBE_Film.mp4", policy.displayName("/tmp/7MOTION_Film.ts"))
        assertEquals("NOVATUBE_Film.mp4", policy.displayName("C:\\tmp\\NOVATUBE_Film.mp4"))
        assertEquals("NOVATUBE_a_b_.mp4", policy.displayName("a:b?.ts"))
        assertEquals("NOVATUBE_enregistrement.mp4", policy.displayName(".ts"))
        assertEquals(9 + 160 + 4, policy.displayName("x".repeat(300) + ".ts").length)
    }

    @Test fun mp4RequiresRealFtypHeader() {
        assertTrue(policy.isMp4Header(byteArrayOf(0, 0, 0, 24) + "ftypisom".toByteArray()))
        assertFalse(policy.isMp4Header(ByteArray(188) { 0x47 }))
        assertFalse(policy.isMp4Header("ftyp".toByteArray()))
    }

    @Test fun transportStreamAacDeclarationIsAudio() {
        assertEquals(true, policy.declaredTsAudio(ts(pmt(listOf(0x1b to byteArrayOf(), 0x0f to byteArrayOf())))))
    }

    @Test fun ac3DeclarationPreventsAHiddenAudioTrackFromBecomingSilent() {
        assertEquals(true, policy.declaredTsAudio(ts(pmt(listOf(0x1b to byteArrayOf(), 0x81 to byteArrayOf())))))
        assertEquals(true, policy.declaredTsAudio(ts(pmt(listOf(0x1b to byteArrayOf(), 0x06 to byteArrayOf(0x6a, 0))))))
    }

    @Test fun unknownPrivatePesCannotProveThatAudioIsAbsent() {
        assertEquals(true, policy.declaredTsAudio(ts(pmt(listOf(0x1b to byteArrayOf(), 0x06 to byteArrayOf())))))
    }

    @Test fun completeVideoOnlyTransportStreamCanBeExportedWithoutAudio() {
        assertEquals(false, policy.declaredTsAudio(ts(pmt(listOf(0x1b to byteArrayOf())))))
    }

    @Test fun recognizedDvbSubtitlesDoNotInventAnAudioTrack() {
        assertEquals(false, policy.declaredTsAudio(ts(pmt(listOf(0x1b to byteArrayOf(), 0x06 to byteArrayOf(0x59, 0))))))
    }

    @Test fun corruptProgramTableDoesNotProveThatAudioIsAbsent() {
        val broken = pmt(listOf(0x1b to byteArrayOf()))
        broken[12] = 0x24 // CRC conservé : déclaration corrompue.
        assertNull(policy.declaredTsAudio(ts(broken)))
    }

    @Test fun missingProgramMapCannotHideAudioInAnotherProgram() {
        val data = packet(0, true, byteArrayOf(0) + pat(listOf(0x100, 0x200))) +
            packet(0x100, true, byteArrayOf(0) + pmt(listOf(0x1b to byteArrayOf()))) + nullPacket()
        assertNull(policy.declaredTsAudio(data))
    }

    @Test fun missingPatOrPmtIsUnknownInsteadOfSilent() {
        assertNull(policy.declaredTsAudio(nullPacket() + nullPacket() + nullPacket()))
        assertNull(policy.declaredTsAudio(packet(0, true, byteArrayOf(0) + pat()) + nullPacket() + nullPacket()))
        assertNull(policy.declaredTsAudio(byteArrayOf(1, 2, 3)))
    }

    @Test fun fragmentedProgramMapIsReassembledBeforeAudioDecision() {
        val descriptors = ByteArray(170) { if (it % 2 == 0) 0x52 else 0 }
        val map = pmt(listOf(0x1b to descriptors, 0x0f to byteArrayOf()))
        assertTrue(map.size > 183)
        val data = packet(0, true, byteArrayOf(0) + pat()) +
            packet(0x100, true, byteArrayOf(0) + map.copyOfRange(0, 183)) +
            packet(0x100, false, map.copyOfRange(183, map.size), 1)
        assertEquals(true, policy.declaredTsAudio(data))
    }

    @Test fun unknownStreamTypeCannotProveThereIsNoAudio() {
        assertNull(policy.declaredTsAudio(ts(pmt(listOf(0x1b to byteArrayOf(), 0xea to byteArrayOf())))))
    }

    @Test fun offsetBeforeTsPacketsIsHandledWithoutRenamingItMp4() {
        val data = ByteArray(12) + ts(pmt(listOf(0x1b to byteArrayOf(), 0x0f to byteArrayOf())))
        assertEquals(12, policy.transportStreamOffset(data))
        assertEquals(true, policy.declaredTsAudio(data))
        assertFalse(policy.isMp4Header(data))
    }

    private fun ts(map: ByteArray): ByteArray =
        packet(0, true, byteArrayOf(0) + pat()) + packet(0x100, true, byteArrayOf(0) + map) + nullPacket()

    private fun pat(pids: List<Int> = listOf(0x100)): ByteArray {
        var body = byteArrayOf(0, 1, 0xc1.toByte(), 0, 0)
        for ((index, pid) in pids.withIndex()) {
            body += byteArrayOf(0, (index + 1).toByte(), (0xe0 or (pid ushr 8)).toByte(), pid.toByte())
        }
        return section(0, body)
    }

    private fun pmt(streams: List<Pair<Int, ByteArray>>): ByteArray {
        var body = byteArrayOf(0, 1, 0xc1.toByte(), 0, 0, 0xe1.toByte(), 1, 0xf0.toByte(), 0)
        for ((index, stream) in streams.withIndex()) {
            val (type, descriptors) = stream
            body += byteArrayOf(type.toByte(), 0xe1.toByte(), (index + 1).toByte(),
                (0xf0 or (descriptors.size ushr 8)).toByte(), descriptors.size.toByte()) + descriptors
        }
        return section(2, body)
    }

    private fun section(tableId: Int, body: ByteArray): ByteArray {
        val size = body.size + 4
        val bytes = byteArrayOf(tableId.toByte(), (0xb0 or (size ushr 8)).toByte(), size.toByte()) + body
        var crc = -1
        for (value in bytes) {
            crc = crc xor ((value.toInt() and 255) shl 24)
            repeat(8) { crc = if (crc < 0) (crc shl 1) xor 0x04c11db7 else crc shl 1 }
        }
        return bytes + byteArrayOf((crc ushr 24).toByte(), (crc ushr 16).toByte(), (crc ushr 8).toByte(), crc.toByte())
    }

    private fun packet(pid: Int, starts: Boolean, payload: ByteArray, counter: Int = 0): ByteArray {
        require(payload.size <= 184)
        val packet = ByteArray(188) { 0xff.toByte() }
        packet[0] = 0x47
        packet[1] = ((pid ushr 8) or if (starts) 0x40 else 0).toByte()
        packet[2] = pid.toByte()
        packet[3] = (0x10 or counter).toByte()
        payload.copyInto(packet, 4)
        return packet
    }

    private fun nullPacket() = packet(0x1fff, false, byteArrayOf())
}
