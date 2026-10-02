package com.manzilionellm.native_video_player.logic

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * H4 — le son témoin. On rejoue ici les CHIFFRES mesurés hors appareil
 * sur le fichier réel (54,3 % > 4 kHz, corrélation +1,00) et on vérifie
 * que la fiche conclut dans le bon sens, sans accuser l'app quand elle
 * transmet bien.
 */
class WitnessToneTest {

    private fun judgement(ratio: Double) = AudioSpectrum.Judgement(
        band = when {
            ratio >= AudioSpectrum.WIDE_MIN_RATIO -> AudioSpectrum.Band.WIDE
            ratio <= AudioSpectrum.LOW_MAX_RATIO -> AudioSpectrum.Band.LOW
            else -> AudioSpectrum.Band.MID
        },
        highRatio = ratio, clippedFraction = 0.0, peak = 15_368, frames = 500_000, sampleRate = 48_000,
    )

    private val identical = StereoImage.Judgement(StereoImage.Verdict.IDENTICAL, 1.0, 1e-6, 500_000)

    @Test
    fun lUriEstUnFichierDeLApkPasUneAdresse() {
        assertTrue(WitnessTone.isWitness(WitnessTone.ASSET_URI))
        assertFalse(WitnessTone.isWitness(null))
        assertFalse(WitnessTone.ASSET_URI.startsWith("http"))
        assertEquals("[url]", AudioDiagnosis.redact("http://x/y").trim())
        // Le libellé ne porte ni URL ni secret.
        assertEquals(WitnessTone.CHANNEL_LABEL, AudioDiagnosis.redact(WitnessTone.CHANNEL_LABEL))
    }

    @Test
    fun temoinLargeEtEnPhaseInnocenteLApp() {
        val text = WitnessTone.verdict(judgement(WitnessTone.FILE_HIGH_RATIO), identical)
        assertTrue(text.contains("54,3 %"), text)
        assertTrue(text.contains("l'app décode et transmet les aigus"), text)
        assertTrue(text.contains("APRÈS l'app"), text)
        assertTrue(text.contains("aucune inversion dans l'app"), text)
    }

    @Test
    fun temoinBasOuInverseAccuseUnEtageDeLApp() {
        val low = WitnessTone.verdict(judgement(0.02), identical)
        assertTrue(low.contains("un étage de l'app coupe les aigus"), low)
        val inverted = WitnessTone.verdict(
            judgement(0.54),
            StereoImage.Judgement(StereoImage.Verdict.INVERTED, -0.99, 1e6, 500_000),
        )
        assertTrue(inverted.contains("un étage de l'app inverse une voie"), inverted)
        val none = WitnessTone.verdict(null, null)
        assertTrue(none.contains("allumer « Spectre : mesuré »"), none)
    }

    @Test
    fun laFicheDuTemoinPorteSaDescriptionEtSonVerdict() {
        val reading = AudioStages.Reading(AudioStages.DECODER, judgement(0.54), identical)
        val snap = AudioSnapshot(
            mime = "audio/mp4a-latm", codecs = "mp4a.40.2", inSampleRate = 48_000, inChannels = 2,
            bitrate = 120_000, decoder = "ffmpegLavc60.3.100-aac", outSampleRate = 48_000, outChannels = 2,
            outEncoding = "PCM 16 bits", spectrum = reading.judgement, stages = listOf(reading), witness = true,
        )
        val report = AudioDiagnosis.report(snap)
        assertTrue(report.contains("Témoin : fichier AAC-LC 48 kHz"), report)
        assertTrue(report.contains("l'app décode et transmet les aigus"), report)
        // Le témoin est G = D exprès : ce n'est pas le constat « source mono dupliquée ».
        assertFalse(AudioDiagnosis.findings(snap).any { it.id == "voies_identiques" })
        // Une vraie chaîne G = D, elle, reçoit le constat.
        val chaine = snap.copy(witness = false)
        assertTrue(AudioDiagnosis.findings(chaine).any { it.id == "voies_identiques" })
        assertFalse(report.contains("http"))
    }
}
