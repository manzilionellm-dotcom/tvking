package com.manzilionellm.native_video_player.logic

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Prouve, sans Android, pourquoi la fiche disait « pas de mesure »
 * alors que Spectre était allumé.
 */
class ProbeAttachTest {

    @Test
    fun allumeeApresLaConfigurationResteHorsDeLaChaine() {
        val sink = ProbeAttach.Sink()
        // Première ouverture, réglage encore coupé : NOT_SET.
        val first = sink.configure(pcm16 = true)
        sink.flush(keepWindow = true)
        assertFalse(first.accept)
        assertFalse(sink.inChain)
        assertEquals(ProbeAttach.REJECT_OFF, sink.lastReject)

        // On allume. Media3 ne rappelle pas onConfigure.
        sink.setProbe(true)
        assertFalse(sink.inChain)

        // La réouverture (configure + flush) branche la sonde.
        assertTrue(ProbeAttach.shouldReopen(turningOn = true, playing = true))
        assertFalse(ProbeAttach.shouldReopen(turningOn = true, playing = false))
        val second = sink.configure(pcm16 = true)
        sink.flush(keepWindow = ProbeAttach.keepWindowOnFlush())
        assertTrue(second.accept)
        assertTrue(sink.inChain)
        assertEquals(null, sink.lastReject)
    }

    @Test
    fun cinquanteZapsAvecLaSondeAllumeeAvantConfigureLaLaissentBranchee() {
        val sink = ProbeAttach.Sink()
        sink.setProbe(true)
        repeat(50) { n ->
            val d = sink.configure(pcm16 = true)
            sink.flush(keepWindow = true)
            sink.push(10_000)
            assertTrue(d.accept, "zap $n")
            assertTrue(sink.inChain, "zap $n")
            // Nouvelle ouverture : la fenêtre repart de zéro, puis se remplit.
            assertEquals(10_000, sink.frames, "zap $n")
        }
        // Un format qui n'est pas du PCM 16 : on refuse, sans toucher au son.
        sink.configure(pcm16 = false)
        sink.flush(keepWindow = true)
        assertFalse(sink.inChain)
        assertEquals(ProbeAttach.REJECT_NOT_PCM, sink.lastReject)
    }

    @Test
    fun unFlushDuDirectNeDoitPasEffacerLaFenetre() {
        val tropCourt = ProbeAttach.maxFrames(chunks = 20, perChunk = 1_000, keep = false)
        val assez = ProbeAttach.maxFrames(chunks = 20, perChunk = 1_000, keep = true)
        assertTrue(tropCourt < ProbeAttach.NEED_FRAMES)
        assertTrue(assez >= ProbeAttach.NEED_FRAMES)

        val sink = ProbeAttach.Sink()
        sink.setProbe(true)
        sink.configure(pcm16 = true)
        sink.flush(keepWindow = true)
        sink.push(4_000)
        // Horloge du direct : flush, même format. On garde les trames.
        sink.flush(keepWindow = ProbeAttach.keepWindowOnFlush())
        sink.push(5_000)
        assertEquals(9_000, sink.frames)
        assertTrue(sink.frames >= ProbeAttach.NEED_FRAMES)
    }

    @Test
    fun laFicheDitLaRaisonAuLieuDePasDeMesure() {
        val off = ProbeAttach.absence(requested = false, inChain = false, frames = 0, reject = null)
        assertTrue(off.symptom.contains("réglage Spectre est éteint"))
        assertFalse(off.symptom.contains("Pas de mesure PCM"))

        val tropTot = ProbeAttach.absence(
            requested = true,
            inChain = false,
            frames = 0,
            reject = ProbeAttach.REJECT_OFF,
        )
        assertTrue(tropTot.symptom.contains("pas branchée"))
        assertTrue(tropTot.symptom.contains(ProbeAttach.REJECT_OFF))

        val courte = ProbeAttach.absence(requested = true, inChain = true, frames = 100, reject = null)
        assertTrue(courte.symptom.contains("Pas encore assez de son"))
        assertTrue(courte.symptom.contains("100"))

        val pasPcm = ProbeAttach.absence(
            requested = true,
            inChain = false,
            frames = 0,
            reject = ProbeAttach.REJECT_NOT_PCM,
        )
        assertTrue(pasPcm.symptom.contains("PCM 16 bits"))

        val report = AudioDiagnosis.report(
            AudioSnapshot(
                probeRequested = true,
                probeInChain = false,
                probeReject = ProbeAttach.REJECT_OFF,
                playerAudible = true,
                playbacks = PlaybackCount.Count(0, 0, 0, emptyList(), PlaybackCount.Method.NONE),
                route = null,
            ),
        )
        assertTrue(report.contains("pas branchée"))
        assertFalse(report.contains("Pas de mesure PCM"))
        assertTrue(report.contains("alors que le lecteur joue"))
    }

    @Test
    fun zeroLecturePendantQueCaJoueNestPasUneAbsenceDeSon() {
        val zero = PlaybackCount.Count(0, 0, 0, emptyList(), PlaybackCount.Method.NONE)
        val note = PlaybackCount.note(zero, audible = true)
        assertTrue(note.contains("0"))
        assertTrue(note.contains("avant le rappel"))
        val idle = PlaybackCount.note(null, audible = false)
        assertTrue(idle.contains("pas encore comptées"))
        val one = PlaybackCount.Count(1, 1, 0, emptyList(), PlaybackCount.Method.ATTRIBUTES)
        assertTrue(PlaybackCount.note(one, audible = true).contains("la nôtre seulement"))
    }
}
