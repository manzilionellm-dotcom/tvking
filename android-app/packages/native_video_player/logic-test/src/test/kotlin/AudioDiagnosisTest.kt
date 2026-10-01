import com.manzilionellm.native_video_player.logic.AudioDiagnosis
import com.manzilionellm.native_video_player.logic.AudioFixes
import com.manzilionellm.native_video_player.logic.AudioSnapshot
import com.manzilionellm.native_video_player.logic.AudioSpectrum
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AudioDiagnosisTest {
    private val heAacBox = AudioSnapshot(
        mime = "audio/mp4a-latm", codecs = "mp4a.40.5", inSampleRate = 24_000, inChannels = 2,
        decoder = "OMX.amlogic.aac.decoder", outSampleRate = 24_000, outChannels = 1,
        outEncoding = "PCM 16 bits",
    )

    @Test
    fun vieilleRadioProuveeQuandLaBoxSortA24kHz() {
        val v = AudioDiagnosis.verdicts(heAacBox)
        assertTrue(v[0].startsWith("BOX : son sorti à 24 kHz"), v.toString())
        assertTrue(v.any { it.contains("MONO → stéréo perdue") }, v.toString())
    }

    @Test
    fun ffmpegQuiReconstruitLes48kHzNestPasAccuse() {
        val ok = heAacBox.copy(decoder = "ffmpeg6.0-aac", outSampleRate = 48_000, outChannels = 2)
        val v = AudioDiagnosis.verdicts(ok)
        assertTrue(v.none { it.startsWith("BOX") }, v.toString())
        assertTrue(v.last().startsWith("Rien d'anormal côté app"), v.toString())
    }

    @Test
    fun defautsDeLaSource() {
        val src = AudioSnapshot(
            mime = "audio/mpeg-L2", inSampleRate = 22_050, inChannels = 1, bitrate = 64_000,
            decoder = "ffmpeg6.0-mp2", outSampleRate = 22_050, outChannels = 1, outEncoding = "PCM 16 bits",
        )
        val v = AudioDiagnosis.verdicts(src)
        assertTrue(v.any { it.startsWith("SOURCE : le flux est MONO") }, v.toString())
        assertTrue(v.any { it.startsWith("SOURCE : débit audio faible (64 kb/s)") }, v.toString())
        assertTrue(v.any { it.startsWith("SOURCE : son échantillonné à 22,1 kHz") }, v.toString())
    }

    @Test
    fun coupuresEtPassthrough() {
        val v = AudioDiagnosis.verdicts(
            AudioSnapshot(mime = "audio/ac3", passthrough = true, outEncoding = "AC-3", underruns = 3),
        )
        assertTrue(v.any { it.startsWith("SORTIE : 3 coupure(s)") }, v.toString())
        assertTrue(v.any { it.startsWith("Info : son Dolby/DTS") }, v.toString())
    }

    @Test
    fun ligneFactuelle() {
        assertEquals(
            "reçu : HE-AAC 24 kHz 2 voies · décodé par : box (OMX.amlogic.aac.decoder) · sortie : PCM 16 bits 24 kHz mono",
            AudioDiagnosis.describe(heAacBox),
        )
        assertEquals("HE-AAC v2", AudioDiagnosis.aacProfile("mp4a.40.29"))
        assertEquals("AAC-LC", AudioDiagnosis.aacProfile("mp4a.40.2"))
    }

    @Test
    fun nomsDeCodec() {
        assertEquals("AAC-LC", AudioDiagnosis.codecName(AudioSnapshot(mime = "audio/mp4a-latm", codecs = "mp4a.40.2")))
        assertEquals("HE-AAC/SBR", AudioDiagnosis.codecName(AudioSnapshot(mime = "audio/mp4a-latm", codecs = "mp4a.40.5")))
        assertEquals("HE-AAC v2 (SBR+PS)", AudioDiagnosis.codecName(AudioSnapshot(mime = "audio/mp4a-latm", codecs = "mp4a.40.29")))
        assertEquals("AC-3", AudioDiagnosis.codecName(AudioSnapshot(mime = "audio/ac3")))
        assertEquals("E-AC-3", AudioDiagnosis.codecName(AudioSnapshot(mime = "audio/eac3")))
        assertEquals("MP2", AudioDiagnosis.codecName(AudioSnapshot(mime = "audio/mpeg-L2")))
        assertEquals("MP3", AudioDiagnosis.codecName(AudioSnapshot(mime = "audio/mpeg")))
    }

    @Test
    fun causeSureDecodeurEtCorrectifNomme() {
        val f = AudioDiagnosis.sureCauses(heAacBox)
        assertTrue(f.any { it.id == "decodeur_sans_sbr" }, f.map { it.id }.toString())
        val sbr = f.first { it.id == "decodeur_sans_sbr" }
        assertEquals(AudioFixes.KEY_FFMPEG, sbr.fix.settingKey)
        assertTrue(sbr.fix.symbol.contains("preferFfmpegFor"), sbr.fix.symbol)
        assertTrue(sbr.fix.media3.contains("FfmpegAudioRenderer"), sbr.fix.media3)
        assertTrue(f.any { it.id == "stereo_perdue" })
    }

    @Test
    fun ffmpeg48kHzNaPasDeCauseDecodeurSure() {
        val ok = heAacBox.copy(decoder = "ffmpeg6.0-aac", outSampleRate = 48_000, outChannels = 2)
        assertTrue(AudioDiagnosis.sureCauses(ok).none { it.id == "decodeur_sans_sbr" })
        assertTrue(AudioDiagnosis.findings(ok).none { it.id == "stereo_perdue" })
    }

    @Test
    fun spectreLargeNeDonnePasDeFauxPositifRadio() {
        val wide = AudioSpectrum.Judgement(
            band = AudioSpectrum.Band.WIDE,
            highRatio = 0.82,
            clippedFraction = 0.0,
            peak = 12_000,
            frames = 40_000,
            sampleRate = 48_000,
        )
        val s = AudioSnapshot(
            mime = "audio/mp4a-latm", codecs = "mp4a.40.2",
            inSampleRate = 48_000, inChannels = 2, bitrate = 128_000,
            decoder = "ffmpeg6.0-aac", outSampleRate = 48_000, outChannels = 2,
            outEncoding = "PCM 16 bits", spectrum = wide,
        )
        val findings = AudioDiagnosis.findings(s)
        assertTrue(findings.any { it.id == "spectre_large" && it.confidence == AudioDiagnosis.Confidence.HAUTE })
        assertTrue(findings.none { it.id == "spectre_bas" })
        assertTrue(findings.none { it.id == "decodeur_sans_sbr" })
        assertTrue(AudioDiagnosis.sureCauses(s).isEmpty(), AudioDiagnosis.sureCauses(s).map { it.id }.toString())
    }

    @Test
    fun spectreBasSeulResteIncertain() {
        val low = AudioSpectrum.Judgement(
            band = AudioSpectrum.Band.LOW,
            highRatio = 0.08,
            clippedFraction = 0.0,
            peak = 8000,
            frames = 40_000,
            sampleRate = 48_000,
        )
        val s = AudioSnapshot(
            mime = "audio/mp4a-latm", codecs = "mp4a.40.2",
            inSampleRate = 48_000, inChannels = 2,
            decoder = "ffmpeg6.0-aac", outSampleRate = 48_000, outChannels = 2,
            outEncoding = "PCM 16 bits", spectrum = low,
        )
        val band = AudioDiagnosis.findings(s).first { it.id == "spectre_bas" }
        assertEquals(AudioDiagnosis.Confidence.INCERTAINE, band.confidence)
        assertNull(band.fix.settingKey)
        assertTrue(AudioDiagnosis.sureCauses(s).none { it.id == "spectre_bas" })
        assertTrue(AudioDiagnosis.report(s).contains("aucune cause sûre"))
    }

    @Test
    fun milieuEtHeAacBoxA48kHzNeForcentPasFfmpeg() {
        val mid = AudioSpectrum.Judgement(
            band = AudioSpectrum.Band.MID, highRatio = 0.23,
            clippedFraction = 0.0, peak = 1000, frames = 20_000, sampleRate = 48_000,
        )
        val s = AudioSnapshot(
            mime = "audio/mp4a-latm", codecs = "mp4a.40.5",
            inSampleRate = 24_000, inChannels = 2,
            decoder = "OMX.amlogic.aac.decoder", outSampleRate = 48_000, outChannels = 2,
            spectrum = mid,
        )
        val ids = AudioDiagnosis.findings(s).map { it.id }
        assertTrue("spectre_incertain" in ids, ids.toString())
        assertTrue("heaac_box_freq_haute" in ids, ids.toString())
        assertTrue(AudioDiagnosis.sureCauses(s).isEmpty())
    }

    @Test
    fun spectreLargeInnocenteLeHeAacBoxDejaA48kHz() {
        val wide = AudioSpectrum.Judgement(
            band = AudioSpectrum.Band.WIDE, highRatio = 0.5,
            clippedFraction = 0.0, peak = 1000, frames = 20_000, sampleRate = 48_000,
        )
        val s = AudioSnapshot(
            mime = "audio/mp4a-latm", codecs = "mp4a.40.5",
            decoder = "c2.android.aac.decoder", outSampleRate = 48_000, outChannels = 2,
            inSampleRate = 48_000, inChannels = 2, spectrum = wide,
        )
        assertTrue(AudioDiagnosis.findings(s).none { it.id == "heaac_box_freq_haute" })
    }

    @Test
    fun downmixConstateMaisPasUnCorrectif() {
        val s = AudioSnapshot(
            mime = "audio/ac3", inChannels = 6, outChannels = 2,
            decoder = "OMX.amlogic.ac3.decoder", outSampleRate = 48_000,
            outEncoding = "PCM 16 bits",
        )
        val d = AudioDiagnosis.findings(s).first { it.id == "downmix" }
        assertEquals(AudioDiagnosis.Confidence.HAUTE, d.confidence)
        assertEquals(AudioDiagnosis.Kind.INFO, d.kind)
        assertNull(d.fix.settingKey)
        assertTrue(d.fix.symbol.contains("buildAudioSink"))
    }

    @Test
    fun saturationSureEtSinusIncertain() {
        val slammed = spectrum(clip = 0.15, band = AudioSpectrum.Band.WIDE, ratio = 0.8)
        val sure = AudioDiagnosis.findings(basePcm(slammed)).first { it.id == "saturation" }
        assertEquals(AudioDiagnosis.Confidence.HAUTE, sure.confidence)
        assertNull(sure.fix.settingKey)
        val touch = spectrum(clip = 0.05, band = AudioSpectrum.Band.WIDE, ratio = 0.8)
        val grey = AudioDiagnosis.findings(basePcm(touch)).first { it.id == "saturation" }
        assertEquals(AudioDiagnosis.Confidence.INCERTAINE, grey.confidence)
        val clean = spectrum(clip = 0.0, band = AudioSpectrum.Band.WIDE, ratio = 0.8)
        assertTrue(AudioDiagnosis.findings(basePcm(clean)).none { it.id == "saturation" })
    }

    @Test
    fun decalageTolereSilencieuxEtGrandSigne() {
        assertNull(AudioDiagnosis.delayFinding(null))
        assertNull(AudioDiagnosis.delayFinding(40))
        assertNull(AudioDiagnosis.delayFinding(-80))
        val mid = AudioDiagnosis.delayFinding(120)!!
        assertEquals(AudioDiagnosis.Confidence.INCERTAINE, mid.confidence)
        val big = AudioDiagnosis.delayFinding(-250)!!
        assertEquals(AudioDiagnosis.Confidence.HAUTE, big.confidence)
        assertTrue(big.fix.media3.contains("VIDEO_CHANGE_FRAME_RATE_STRATEGY_OFF"))
        assertNull(big.fix.settingKey)
    }

    @Test
    fun leRapportNeGardeNiUrlNiMotDePasse() {
        val dirty = AudioDiagnosis.redact(
            "vu http://user:s3cret@exemple.test/live/a.ts password=abc token=zzz",
        )
        assertTrue(!dirty.contains("s3cret"), dirty)
        assertTrue(!dirty.contains("http"), dirty)
        assertTrue(!dirty.contains("abc"), dirty)
        assertTrue(!dirty.contains("zzz"), dirty)
        assertTrue(dirty.contains("password=[secret]"), dirty)
        assertTrue(dirty.contains("token=[secret]"), dirty)
    }

    private fun spectrum(clip: Double, band: AudioSpectrum.Band, ratio: Double) = AudioSpectrum.Judgement(
        band = band,
        highRatio = ratio,
        clippedFraction = clip,
        peak = if (clip > 0) 32767 else 1000,
        frames = 40_000,
        sampleRate = 48_000,
    )

    private fun basePcm(spec: AudioSpectrum.Judgement) = AudioSnapshot(
        mime = "audio/mp4a-latm", codecs = "mp4a.40.2",
        inSampleRate = 48_000, inChannels = 2, bitrate = 160_000,
        decoder = "ffmpeg6.0-aac", outSampleRate = 48_000, outChannels = 2,
        outEncoding = "PCM 16 bits", spectrum = spec,
    )
}
