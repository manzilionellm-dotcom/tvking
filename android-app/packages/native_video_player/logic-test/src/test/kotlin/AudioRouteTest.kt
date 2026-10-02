package com.manzilionellm.native_video_player.logic

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * H1 — l'état du système audio. Une photo « saine » ne doit rien
 * accuser ; une photo « en appel » doit nommer la cause SÛRE et proposer
 * le correctif derrière son interrupteur, coupé par défaut.
 */
class AudioRouteTest {

    private val hdmi = AudioRoute.Device(AudioRoute.TYPE_HDMI, "HDMI")
    private val speaker = AudioRoute.Device(AudioRoute.TYPE_BUILTIN_SPEAKER, "")
    private val earpiece = AudioRoute.Device(AudioRoute.TYPE_BUILTIN_EARPIECE, "")

    private val boxSaine = AudioRoute.Snapshot(
        mode = AudioRoute.MODE_NORMAL,
        speakerphoneOn = false,
        scoOn = false,
        a2dpOn = false,
        wiredHeadsetOn = false,
        musicActive = true,
        outputs = listOf(hdmi),
        mediaRoute = listOf(hdmi),
        communicationDevice = null,
        recordings = emptyList(),
        sdk = 34,
    )

    @Test
    fun uneBoxSaineNeDonneAucuneCause() {
        val f = AudioRoute.findings(boxSaine)
        assertTrue(f.isEmpty(), f.map { it.id }.toString())
        val line = AudioRoute.describe(boxSaine)
        assertTrue(line.contains("mode normal"), line)
        assertTrue(line.contains("route média : HDMI « HDMI »"), line)
        assertTrue(line.contains("micro : aucun enregistrement actif"), line)
        assertFalse(line.contains("http"), line)
        assertTrue(AudioRoute.repairPlan(boxSaine, enabled = true).isEmpty())
    }

    @Test
    fun leModeCommunicationEstUneCauseSureAvecSonInterrupteur() {
        val enAppel = boxSaine.copy(
            mode = AudioRoute.MODE_IN_COMMUNICATION,
            speakerphoneOn = true,
            mediaRoute = listOf(earpiece),
            sdk = 36,
        )
        val f = AudioRoute.findings(enAppel)
        val ids = f.map { it.id }
        assertTrue("mode_appel" in ids, ids.toString())
        assertTrue("sortie_voix" in ids, ids.toString())
        assertTrue("haut_parleur_appel" in ids, ids.toString())
        val mode = f.first { it.id == "mode_appel" }
        assertEquals(AudioDiagnosis.Confidence.HAUTE, mode.confidence)
        assertEquals(AudioDiagnosis.Kind.CAUSE, mode.kind)
        assertEquals(AudioFixes.KEY_MODE_NORMAL, mode.fix.settingKey)
        assertTrue(mode.cause.contains("comme quand on t'appelle"), mode.cause)
        // La fiche complète le dit en tête.
        val snap = AudioSnapshot(
            mime = "audio/mp4a-latm", codecs = "mp4a.40.2", inSampleRate = 48_000, inChannels = 2,
            decoder = "ffmpegLavc60.3.100-aac", outSampleRate = 48_000, outChannels = 2,
            outEncoding = "PCM 16 bits", route = enAppel,
        )
        val verdicts = AudioDiagnosis.verdicts(snap)
        assertTrue(verdicts.first().startsWith("SYSTÈME : Android est en mode COMMUNICATION"), verdicts.toString())
        assertTrue(AudioDiagnosis.sureCauses(snap).any { it.id == "mode_appel" })
        val report = AudioDiagnosis.report(snap)
        assertTrue(report.contains("ÉCOUTEUR du téléphone"), report)
        assertTrue(report.contains("zuno.audio.fix.mode_normal (défaut coupé, non imposé)"), report)
    }

    @Test
    fun leCorrectifNeFaitRienTantQueLInterrupteurEstCoupe() {
        val enAppel = boxSaine.copy(mode = AudioRoute.MODE_IN_COMMUNICATION, scoOn = true, speakerphoneOn = true)
        assertTrue(AudioRoute.repairPlan(enAppel, enabled = false).isEmpty())
        val plan = AudioRoute.repairPlan(enAppel, enabled = true)
        assertEquals(
            listOf(AudioRoute.Repair.SET_MODE_NORMAL, AudioRoute.Repair.SPEAKERPHONE_OFF, AudioRoute.Repair.STOP_SCO),
            plan,
        )
        val line = AudioRoute.repairLine(plan, enabled = true, mode = enAppel.mode)
        assertTrue(line.startsWith("Mode système : CORRIGÉ"), line)
        assertTrue(line.contains("mode remis à normal"), line)
        val off = AudioRoute.repairLine(emptyList(), enabled = false, mode = enAppel.mode)
        assertTrue(off.contains("laissé tel quel"), off)
        // Le mode sonnerie n'est pas « réparé » : c'est un appel qui arrive.
        val sonnerie = boxSaine.copy(mode = AudioRoute.MODE_RINGTONE)
        assertTrue(AudioRoute.repairPlan(sonnerie, enabled = true).isEmpty())
        assertTrue(AudioRoute.findings(sonnerie).any { it.id == "mode_sonnerie" && it.confidence == AudioDiagnosis.Confidence.INCERTAINE })
    }

    @Test
    fun unMicroOuvertParUneAutreAppEstSignaleSansAccuserZuno() {
        val visio = boxSaine.copy(
            recordings = listOf(AudioRoute.Recording(AudioRoute.SOURCE_VOICE_COMMUNICATION, AudioRoute.TYPE_BUILTIN_MIC)),
        )
        val f = AudioRoute.findings(visio)
        val mic = f.first { it.id == "micro_appel" }
        assertEquals(AudioDiagnosis.Confidence.HAUTE, mic.confidence)
        assertTrue(mic.cause.contains("Zuno n'ouvre jamais le micro"), mic.cause)
        val assistant = boxSaine.copy(
            recordings = listOf(AudioRoute.Recording(AudioRoute.SOURCE_VOICE_RECOGNITION, null)),
        )
        val g = AudioRoute.findings(assistant)
        assertTrue(g.any { it.id == "micro_ouvert" && it.confidence == AudioDiagnosis.Confidence.INCERTAINE })
        assertTrue(AudioRoute.describe(assistant).contains("1 enregistrement(s) ACTIF(S)"))
    }

    @Test
    fun lesApiAbsentesSeTaisentAuLieuDInventer() {
        val vieilleBox = boxSaine.copy(mediaRoute = null, communicationDevice = null, recordings = null, sdk = 25)
        val f = AudioRoute.findings(vieilleBox)
        assertTrue(f.isEmpty(), f.map { it.id }.toString())
        val line = AudioRoute.describe(vieilleBox)
        assertTrue(line.contains("route média : non lisible (Android 25 < 13)"), line)
        assertTrue(line.contains("micro : non lisible (Android 25 < 7.0)"), line)
        assertTrue(line.contains("appareil de communication : non lisible"), line)
        val short = AudioRoute.short(vieilleBox)
        assertTrue(short.contains("route non lisible"), short)
        assertTrue(short.contains("micro non lisible"), short)
    }

    @Test
    fun laSortieBluetoothEstUneInfoPasUneCause() {
        val bt = boxSaine.copy(
            a2dpOn = true,
            mediaRoute = listOf(AudioRoute.Device(AudioRoute.TYPE_BLUETOOTH_A2DP, "Enceinte")),
        )
        val f = AudioRoute.findings(bt)
        assertEquals(listOf("sortie_bluetooth"), f.map { it.id })
        assertEquals(AudioDiagnosis.Kind.INFO, f.first().kind)
        val sco = boxSaine.copy(scoOn = true, mediaRoute = listOf(AudioRoute.Device(AudioRoute.TYPE_BLUETOOTH_SCO, "Casque")))
        val g = AudioRoute.findings(sco).map { it.id }
        assertTrue("bluetooth_sco" in g && "sortie_voix" in g, g.toString())
        assertTrue(speaker.name.isEmpty())
    }
}
