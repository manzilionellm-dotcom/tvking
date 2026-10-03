package com.manzilionellm.native_video_player.logic

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Les compteurs de tampon et de format, sans appareil.
 * On vérifie le TEXTE de la fiche et les classements, pas un son.
 */
class AudioFormatMeterTest {

    private fun quiet(): AudioFormatMeter.Reading = AudioFormatMeter.Reading(
        trackUnderruns = 0,
        latencyMs = 85,
        bufferMs = 170,
        trackHz = 48_000,
        deviceHz = 48_000,
        deviceFrames = 960,
        encoding = "PCM 16 bits",
        speed = 1f,
        pitch = 1f,
        sonicActive = false,
        sonicSpeed = 1f,
        sonicPitch = 1f,
        clippedFraction = 0.0,
        clipSource = "sonde audiotrack",
        latencySeries = listOf(80, 85, 90),
    )

    @Test
    fun memesFrequencesPasDeReechantillonnage() {
        assertEquals(AudioFormatMeter.Resample.SAME, AudioFormatMeter.resample(48_000, 48_000))
        val text = AudioFormatMeter.block(quiet(), media3Underruns = 0)
        assertTrue(text.contains("underruns AudioTrack 0"), text)
        assertTrue(text.contains("rappel Media3 0"), text)
        assertTrue(text.contains("mêmes fréquences"), text)
        assertTrue(text.contains("Sonic inactif"), text)
        assertTrue(text.contains("setPlaybackParams coupé"), text)
        assertTrue(text.contains("Écrêtage : 0,00 %"), text)
        assertTrue(text.contains("latence stable"), text)
        assertTrue(text.contains("pas de dither"), text)
        assertTrue(AudioFormatMeter.notices(quiet()).isEmpty())
    }

    @Test
    fun quaranteHuitVersQuaranteQuatreSignaleLaConversion() {
        val r = quiet().copy(deviceHz = 44_100)
        assertEquals(AudioFormatMeter.Resample.DEVICE_LOWER, AudioFormatMeter.resample(48_000, 44_100))
        val text = AudioFormatMeter.block(r, 0)
        assertTrue(text.contains("44,1 kHz"), text)
        assertTrue(text.contains("vers le bas"), text)
        val notices = AudioFormatMeter.notices(r)
        assertEquals(1, notices.size)
        assertTrue(notices[0].startsWith("FORMAT :"), notices[0])
    }

    @Test
    fun melangeurPlusHautEstAussiUneConversion() {
        assertEquals(
            AudioFormatMeter.Resample.DEVICE_HIGHER,
            AudioFormatMeter.resample(48_000, 96_000),
        )
        assertTrue(AudioFormatMeter.block(quiet().copy(deviceHz = 96_000), 0).contains("vers le haut"))
    }

    @Test
    fun frequenceManquanteNeDevinePas() {
        assertEquals(AudioFormatMeter.Resample.UNKNOWN, AudioFormatMeter.resample(48_000, null))
        assertEquals(AudioFormatMeter.Resample.UNKNOWN, AudioFormatMeter.resample(0, 48_000))
        val text = AudioFormatMeter.block(quiet().copy(trackHz = 0, deviceHz = null), 0)
        assertTrue(text.contains("rééchantillonnage Android inconnu"), text)
        assertTrue(AudioFormatMeter.notices(quiet().copy(deviceHz = null)).isEmpty())
    }

    @Test
    fun underrunsPlateformeEtMedia3SontCitesQuandIlsDivergent() {
        val r = quiet().copy(trackUnderruns = 4)
        val v = AudioDiagnosis.verdicts(AudioSnapshot(underruns = 1, formatMeter = r))
        assertTrue(v.any { it.startsWith("SORTIE : 4 coupure(s)") && it.contains("AudioTrack 4") }, v.toString())
        assertEquals(4, AudioFormatMeter.underrunCount(1, 4))
        assertEquals(3, AudioFormatMeter.underrunCount(3, null))
    }

    @Test
    fun pisteIllisibleNeMetPasZero() {
        val text = AudioFormatMeter.block(quiet().copy(trackUnderruns = null, latencyMs = null), 2)
        assertTrue(text.contains("non lisibles"), text)
        assertTrue(text.contains("latence non lisible"), text)
        assertTrue(text.contains("rappel Media3 2"), text)
        assertFalse(text.contains("underruns AudioTrack 0"), text)
    }

    @Test
    fun vitesseQuiQuitteUnEstUnRythme() {
        val r = quiet().copy(speed = 1.03f, speedMin = 1f, speedMax = 1.03f, speedMoves = 1, sonicActive = true)
        assertTrue(AudioFormatMeter.rhythmMoved(r))
        assertTrue(AudioFormatMeter.notices(r).any { it.startsWith("RYTHME :") })
        val s = AudioSnapshot(
            mime = "audio/mp4a-latm", codecs = "mp4a.40.2",
            decoder = "ffmpeg", outSampleRate = 48_000, outChannels = 2,
            formatMeter = r,
        )
        val f = AudioDiagnosis.findings(s).first { it.id == "rythme_ajuste" }
        assertEquals(AudioDiagnosis.Confidence.HAUTE, f.confidence)
        assertEquals(AudioDiagnosis.Kind.INFO, f.kind)
        assertTrue(AudioDiagnosis.sureCauses(s).none { it.id == "rythme_ajuste" })
    }

    @Test
    fun vitesseUnEtSonicInactifNeSontPasUnRythme() {
        assertFalse(AudioFormatMeter.rhythmMoved(quiet()))
    }

    @Test
    fun deriveDuTampon() {
        assertEquals(
            "latence stable",
            AudioFormatMeter.drift(listOf(80, 90, 100)),
        )
        assertEquals(
            "latence en hausse (tampon qui se remplit, rythme non corrigé)",
            AudioFormatMeter.drift(listOf(40, 80, 120)),
        )
        assertEquals(
            "latence en baisse (tampon qui se vide)",
            AudioFormatMeter.drift(listOf(200, 120, 40)),
        )
        assertEquals(
            "pas assez de latences pour voir une dérive",
            AudioFormatMeter.drift(listOf(10, 20)),
        )
        assertEquals(
            "latence qui oscille",
            AudioFormatMeter.drift(listOf(40, 200, 50)),
        )
    }

    @Test
    fun getLatencyTropGrandRappelleLeDoubleCompte() {
        val text = AudioFormatMeter.block(quiet().copy(latencyMs = 400, bufferMs = 170), 0)
        assertTrue(text.contains("souvent le double du tampon de 170 ms"), text)
    }

    @Test
    fun ecretageSansSondeNeVautPasZero() {
        val clip = AudioFormatMeter.clip(sink = null, decoder = null, probeOn = false)
        assertEquals(null, clip.fraction)
        assertEquals("sonde coupée", clip.source)
        val armed = AudioFormatMeter.clip(sink = null, decoder = null, probeOn = true)
        assertEquals("sonde pas encore pleine", armed.source)
        val sink = AudioFormatMeter.clip(sink = 0.15, decoder = 0.01, probeOn = true)
        assertEquals(0.15, sink.fraction)
        assertEquals("sonde audiotrack", sink.source)
        val text = AudioFormatMeter.block(quiet().copy(clippedFraction = null, clipSource = "sonde coupée"), 0)
        assertTrue(text.contains("Écrêtage : non mesuré (sonde coupée)"), text)
    }

    @Test
    fun ficheNommeLaConversionSansEnFaireUneCauseSure() {
        val s = AudioSnapshot(
            mime = "audio/mp4a-latm", codecs = "mp4a.40.2",
            inSampleRate = 48_000, inChannels = 2,
            decoder = "ffmpeg6.0-aac", outSampleRate = 48_000, outChannels = 2,
            outEncoding = "PCM 16 bits",
            formatMeter = quiet().copy(deviceHz = 44_100),
        )
        val f = AudioDiagnosis.findings(s).first { it.id == "reechantillonnage_android" }
        assertEquals(AudioDiagnosis.Confidence.INCERTAINE, f.confidence)
        assertEquals(AudioDiagnosis.Kind.INFO, f.kind)
        assertEquals(null, f.fix.settingKey)
        assertTrue(AudioDiagnosis.sureCauses(s).none { it.id == "reechantillonnage_android" })
        val report = AudioDiagnosis.report(s)
        assertTrue(report.contains("vers le bas"), report)
        assertTrue(report.contains("aucune cause sûre"), report)
    }

    @Test
    fun sansLectureLeBlocDitQuilNaPasEncoreLu() {
        val report = AudioDiagnosis.report(AudioSnapshot())
        assertTrue(report.contains("Tampon : pas encore lu"), report)
        assertTrue(report.contains("Float coupé"), report)
        assertFalse(report.contains("http"), report)
    }
}
