package com.manzilionellm.native_video_player.logic

import kotlin.math.PI
import kotlin.math.sin
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * G ≈ D reste ensemble. G ≈ −D est dit opposé. Le son n'est pas modifié :
 * on ne fait que lire un tableau.
 */
class AudioPhaseTest {

    @Test
    fun voiesIdentiquesCorrelationProcheDeUn() {
        val pcm = stereo(48_000) { i ->
            val s = tone(i)
            s to s
        }
        val reading = measure(pcm, 48_000)
        assertTrue(reading.correlation > 0.95, reading.correlation.toString())
        assertTrue(reading.sideToMid < 0.05, reading.sideToMid.toString())
        assertTrue(reading.levelRatio < 0.05, reading.levelRatio.toString())
        assertFalse(reading.opposed)
        assertEquals("+", reading.correlationText().take(1))
    }

    @Test
    fun voiesOpposeesSontDites() {
        val pcm = stereo(48_000) { i ->
            val s = tone(i)
            s to (-s).toShort()
        }
        val reading = measure(pcm, 48_000)
        assertTrue(reading.correlation < -0.95, reading.correlation.toString())
        assertTrue(reading.sideToMid.isInfinite() || reading.sideToMid >= AudioPhase.SIDE_MIN)
        assertTrue(reading.levelRatio.isInfinite() || reading.levelRatio >= 10.0)
        assertTrue(reading.opposed)
        assertEquals("infini", reading.sideText())
        assertTrue(reading.correlationText().startsWith("−") || reading.correlationText().startsWith("-"))
    }

    @Test
    fun monoNeInventepasDopposition() {
        val n = 48_000
        val pcm = ShortArray(n) { tone(it) }
        var acc = AudioPhase.start()
        acc = AudioPhase.push(acc, pcm, 1)
        assertTrue(AudioPhase.ready(acc, 48_000))
        val reading = AudioPhase.judge(acc, 1)
        assertEquals(1, reading.channels)
        assertFalse(reading.opposed)
        assertTrue(reading.correlation.isNaN())
    }

    @Test
    fun fenetreTropCourteNeConclutPas() {
        val pcm = stereo(100) { i -> tone(i) to (-tone(i)).toShort() }
        var acc = AudioPhase.start()
        acc = AudioPhase.push(acc, pcm, 2)
        assertFalse(AudioPhase.ready(acc, 48_000))
        assertFalse(AudioPhase.judge(acc, 2).opposed)
    }

    private fun tone(i: Int): Short =
        (sin(2.0 * PI * 440.0 * i / 48_000.0) * 12_000.0).toInt().toShort()

    private fun stereo(frames: Int, sample: (Int) -> Pair<Short, Short>): ShortArray {
        val pcm = ShortArray(frames * 2)
        for (i in 0 until frames) {
            val (l, r) = sample(i)
            pcm[i * 2] = l
            pcm[i * 2 + 1] = r
        }
        return pcm
    }

    private fun measure(pcm: ShortArray, rate: Int): AudioPhase.Reading {
        val acc = AudioPhase.push(AudioPhase.start(), pcm, 2)
        assertTrue(AudioPhase.ready(acc, rate))
        return AudioPhase.judge(acc, 2)
    }
}
