package com.manzilionellm.native_video_player.logic

import kotlin.math.PI
import kotlin.math.sin
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * H3 — opposition de phase G/D. Signaux fabriqués : on vérifie qu'un
 * mono dupliqué, une voix au centre, une stéréo large et une voie
 * inversée sont bien séparés, et qu'un étage qui inverse est nommé.
 */
class StereoImageTest {

    private val rate = 48_000
    private val frames = 24_000

    /** Voix de synthèse : harmoniques d'un 140 Hz, un peu de « souffle ». */
    private fun voice(seed: Int): DoubleArray {
        var r = seed.toLong()
        return DoubleArray(frames) { i ->
            val t = i.toDouble() / rate
            var v = 0.0
            for (h in 1..12) v += sin(2 * PI * 140.0 * h * t) / h
            r = (r * 6364136223846793005L + 1442695040888963407L)
            v * 0.25 + ((r ushr 11).toDouble() / (1L shl 53) - 0.5) * 0.01
        }
    }

    private fun interleave(l: DoubleArray, r: DoubleArray): ShortArray {
        val out = ShortArray(frames * 2)
        for (i in 0 until frames) {
            out[2 * i] = (l[i] * 32767).toInt().coerceIn(-32768, 32767).toShort()
            out[2 * i + 1] = (r[i] * 32767).toInt().coerceIn(-32768, 32767).toShort()
        }
        return out
    }

    @Test
    fun monoDupliqueVoixAuCentreLargeEtInverseeSontSepares() {
        val v = voice(1)
        val identical = StereoImage.measure(interleave(v, v), 2)
        assertEquals(StereoImage.Verdict.IDENTICAL, identical.verdict, identical.toString())
        assertTrue(identical.correlation > 0.999, identical.toString())

        // Voix au centre + ambiance différente à gauche et à droite.
        val amb1 = voice(2).map { it * 0.3 }.toDoubleArray()
        val amb2 = voice(3).map { it * 0.3 }.toDoubleArray()
        val centered = StereoImage.measure(
            interleave(
                DoubleArray(frames) { v[it] + amb1[it] * sin(it * 0.37) },
                DoubleArray(frames) { v[it] + amb2[it] * sin(it * 0.53) },
            ),
            2,
        )
        assertEquals(StereoImage.Verdict.CENTERED, centered.verdict, centered.toString())
        assertTrue(centered.correlation >= StereoImage.CENTERED_MIN, centered.toString())

        // Deux signaux sans rapport : stéréo large.
        val wide = StereoImage.measure(
            interleave(
                DoubleArray(frames) { sin(2 * PI * 440.0 * it / rate) * 0.4 },
                DoubleArray(frames) { sin(2 * PI * 1234.5 * it / rate + 1.0) * 0.4 },
            ),
            2,
        )
        assertEquals(StereoImage.Verdict.WIDE, wide.verdict, wide.toString())
        assertTrue(kotlin.math.abs(wide.correlation) < 0.3, wide.toString())

        // Une voie inversée : la cause « dans un trou ».
        val inverted = StereoImage.measure(interleave(v, DoubleArray(frames) { -v[it] }), 2)
        assertEquals(StereoImage.Verdict.INVERTED, inverted.verdict, inverted.toString())
        assertTrue(inverted.correlation < -0.999, inverted.toString())
        assertTrue(StereoImage.describe(inverted).contains("OPPOSITION DE PHASE"))
        assertTrue(StereoImage.bounded(inverted) && StereoImage.bounded(wide))
    }

    @Test
    fun monoCourtEtSilenceNeJugentPas() {
        val v = voice(4)
        assertEquals(StereoImage.Verdict.NOT_STEREO, StereoImage.measure(ShortArray(frames) { (v[it] * 32767).toInt().toShort() }, 1).verdict)
        val short = StereoImage.measure(interleave(v, v).copyOf(2 * 1000), 2)
        assertEquals(StereoImage.Verdict.SHORT, short.verdict)
        val silence = StereoImage.measure(ShortArray(frames * 2), 2)
        assertEquals(StereoImage.Verdict.SILENCE, silence.verdict)
        // Pousser du 6 voies dans un accumulateur stéréo ne change rien.
        val acc = StereoImage.push(StereoImage.start(2), ShortArray(600), 6)
        assertEquals(0, acc.frames)
    }

    @Test
    fun lEtageQuiInverseEstNommeEtLaFicheLeDit() {
        val v = voice(5)
        val ok = StereoImage.measure(interleave(v, v), 2)
        val bad = StereoImage.measure(interleave(v, DoubleArray(frames) { -v[it] }), 2)
        val spectrum = AudioSpectrum.measure(interleave(v, v), rate, 2)
        val readings = listOf(
            AudioStages.Reading(AudioStages.DECODER, spectrum, ok),
            AudioStages.Reading(AudioStages.VOICE, spectrum, ok),
            AudioStages.Reading(AudioStages.SILENCE, spectrum, bad),
            AudioStages.Reading(AudioStages.SINK, spectrum, bad),
        )
        val drop = AudioStages.firstInversion(readings)
        assertEquals(AudioStages.SILENCE, drop?.id)
        val snap = AudioSnapshot(
            mime = "audio/mp4a-latm", inSampleRate = 48_000, inChannels = 2, decoder = "ffmpeg6.0-aac",
            outSampleRate = 48_000, outChannels = 2, outEncoding = "PCM 16 bits",
            spectrum = spectrum, stages = readings,
        )
        val ids = AudioDiagnosis.findings(snap).map { it.id }
        assertTrue("etage_inverse" in ids, ids.toString())
        assertTrue("phase_inversee" !in ids, ids.toString())
        assertTrue(AudioDiagnosis.verdicts(snap).any { it.startsWith("PHASE :") })
        val report = AudioDiagnosis.report(snap)
        assertTrue(report.contains("silence : "), report)
        assertTrue(report.contains("OPPOSITION DE PHASE"), report)

        // Inversée dès le décodeur : la cause est avant l'app, pas un étage.
        val fromDecoder = snap.copy(stages = readings.map { it.copy(stereo = bad) })
        val ids2 = AudioDiagnosis.findings(fromDecoder).map { it.id }
        assertTrue("phase_inversee" in ids2 && "etage_inverse" !in ids2, ids2.toString())

        // Pas d'inversion : rien de tout ça.
        val sane = snap.copy(stages = readings.map { it.copy(stereo = ok) })
        val ids3 = AudioDiagnosis.findings(sane).map { it.id }
        assertTrue("phase_inversee" !in ids3 && "etage_inverse" !in ids3, ids3.toString())
        assertTrue("voies_identiques" in ids3, ids3.toString())
        assertNull(AudioStages.firstInversion(sane.stages))
    }
}
