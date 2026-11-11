import com.manzilionellm.native_video_player.logic.PlaybackMetrics
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PlaybackMetricsTest {
    private fun opened(): PlaybackMetrics = PlaybackMetrics(1, 2, 1_000).also {
        it.activateGeneration(10, 1_010)
    }

    @Test fun premiereImageUtiliseLeJalonNatifEtUneSeuleOrigineMonotone() {
        val m = opened()
        val first = m.firstFrame(10, 1_400, 1_250)!!
        assertEquals(1_250L, first.firstFrameElapsedMs)
        assertEquals(250L, first.startupMs)
        assertEquals(400L, first.elapsedMs)
        assertEquals("android_media3", first.toWire()["origin"])
        assertEquals("first_frame", first.kind)
    }

    @Test fun premiereImageAvantOuvertureOuDansLeFuturEstRejetee() {
        val m = opened()
        assertNull(m.firstFrame(10, 1_400, 999))
        assertNull(m.firstFrame(10, 1_400, 1_005))
        assertNull(m.firstFrame(10, 1_400, 1_401))
        assertNull(m.firstFrame(9, 1_400, 1_250))
        assertEquals(250L, m.firstFrame(10, 1_400, 1_250)?.startupMs)
    }

    @Test fun resetTechniqueNeRedemarrePasLaSessionLogique() {
        val m = opened()
        m.firstFrame(10, 1_400, 1_250)
        m.invalidateGeneration()
        assertFalse(m.accepts(10, 3_000))
        m.activateGeneration(11, 4_000)
        assertNull(m.firstFrame(11, 5_000, 4_800))
        val end = m.finish(PlaybackMetrics.EndReason.DISPOSED, 6_000)!!
        assertEquals(1L, end.sessionId)
        assertEquals(2L, end.mediaId)
        assertEquals(250L, end.startupMs)
        assertEquals(5_000L, end.elapsedMs)
    }

    @Test fun reponseTardiveDeLAncienneGenerationNeModifieRien() {
        val m = opened()
        m.activateGeneration(11, 2_000)
        assertNull(m.firstFrame(10, 3_000, 2_500))
        m.droppedFrames(10, 3_000, 50)
        m.state(10, 3_000, PlaybackMetrics.State.BUFFERING, true)
        val end = m.finish(PlaybackMetrics.EndReason.ENDED, 4_000)!!
        assertNull(end.firstFrameElapsedMs)
        assertNull(end.droppedFrames)
        assertEquals(0L, end.rebufferCount)
    }

    @Test fun changementDeMediaProduitDeuxIdentitesEtDeuxDemarrages() {
        val first = opened()
        first.firstFrame(10, 1_400, 1_250)
        val end = first.finish(PlaybackMetrics.EndReason.MEDIA_CHANGED, 2_000)!!
        val next = PlaybackMetrics(3, 4, 2_000)
        next.activateGeneration(11, 2_010)
        val frame = next.firstFrame(11, 2_500, 2_400)!!
        assertEquals(1L, end.sessionId)
        assertEquals(2L, end.mediaId)
        assertEquals(3L, frame.sessionId)
        assertEquals(4L, frame.mediaId)
        assertEquals(400L, frame.startupMs)
        assertNull(first.firstFrame(10, 3_000, 2_900))
    }

    @Test fun tamponInitialNestPasUnRebuffering() {
        val m = opened()
        m.state(10, 1_100, PlaybackMetrics.State.BUFFERING, true)
        m.state(10, 1_200, PlaybackMetrics.State.READY, true)
        m.firstFrame(10, 1_300, 1_250)
        val end = m.finish(PlaybackMetrics.EndReason.ENDED, 2_000)!!
        assertEquals(0L, end.rebufferCount)
        assertEquals(0L, end.rebufferMs)
    }

    @Test fun transitionsRepeteesNeDoublentPasLaCoupure() {
        val m = opened()
        m.firstFrame(10, 1_300, 1_250)
        m.state(10, 2_000, PlaybackMetrics.State.BUFFERING, true)
        m.state(10, 2_100, PlaybackMetrics.State.BUFFERING, true)
        m.state(10, 2_800, PlaybackMetrics.State.READY, true)
        m.state(10, 3_000, PlaybackMetrics.State.BUFFERING, true)
        val end = m.finish(PlaybackMetrics.EndReason.DISPOSED, 3_500)!!
        assertEquals(2L, end.rebufferCount)
        assertEquals(1_300L, end.rebufferMs)
    }

    @Test fun attenteDeReconnexionEtResetRestentDansLaMemeCoupure() {
        val m = opened()
        m.firstFrame(10, 1_300, 1_250)
        m.state(10, 2_000, PlaybackMetrics.State.BUFFERING, true)
        m.invalidateGeneration()
        m.activateGeneration(11, 4_000)
        m.state(11, 4_100, PlaybackMetrics.State.BUFFERING, true)
        m.state(11, 5_000, PlaybackMetrics.State.READY, true)
        val end = m.finish(PlaybackMetrics.EndReason.ENDED, 6_000)!!
        assertEquals(1L, end.rebufferCount)
        assertEquals(3_000L, end.rebufferMs)
    }

    @Test fun pauseFermeLaCoupureSansCompterLeTempsPasseEnPause() {
        val m = opened()
        m.firstFrame(10, 1_300, 1_250)
        m.state(10, 2_000, PlaybackMetrics.State.BUFFERING, true)
        m.state(10, 2_500, PlaybackMetrics.State.BUFFERING, false)
        m.state(10, 6_000, PlaybackMetrics.State.READY, true)
        assertEquals(500L, m.finish(PlaybackMetrics.EndReason.ENDED, 7_000)?.rebufferMs)
    }

    @Test fun rechercheHomeEtCastPlanifiesNeSontPasDesCoupures() {
        val m = opened()
        m.firstFrame(10, 1_300, 1_250)
        m.plannedInterruption(2_000)
        m.state(10, 2_100, PlaybackMetrics.State.BUFFERING, true)
        m.state(10, 4_000, PlaybackMetrics.State.READY, true)
        m.state(10, 5_000, PlaybackMetrics.State.BUFFERING, true)
        m.state(10, 5_200, PlaybackMetrics.State.READY, true)
        val end = m.finish(PlaybackMetrics.EndReason.ENDED, 6_000)!!
        assertEquals(1L, end.rebufferCount)
        assertEquals(200L, end.rebufferMs)
    }

    @Test fun etatPlusAncienNeFermePasUneCoupureRecente() {
        val m = opened()
        m.firstFrame(10, 1_300, 1_250)
        m.state(10, 3_000, PlaybackMetrics.State.BUFFERING, true)
        m.state(10, 2_000, PlaybackMetrics.State.READY, true)
        assertEquals(1_000L, m.finish(PlaybackMetrics.EndReason.ENDED, 4_000)?.rebufferMs)
    }

    @Test fun commandeSansCoupureNeMasquePasLaProchainePanne() {
        val m = opened()
        m.firstFrame(10, 1_300, 1_250)
        m.plannedInterruption(2_000)
        m.readyObserved(10, 2_100)
        m.state(10, 3_000, PlaybackMetrics.State.BUFFERING, true)
        assertEquals(1L, m.finish(PlaybackMetrics.EndReason.ENDED, 4_000)?.rebufferCount)
    }

    @Test fun compteurCumulatifReluNeDoublePasLesPertes() {
        val m = opened()
        val decoder = Any()
        m.decoderSample(decoder, 5)
        m.decoderSample(decoder, 5)
        m.decoderSample(decoder, 8)
        assertEquals(8L, m.finish(PlaybackMetrics.EndReason.ENDED, 2_000)?.droppedFrames)
    }

    @Test fun ancienCompteurAvantZapEstUneOriginePasDesPertesNouvelles() {
        val m = opened()
        val decoder = Any()
        m.decoderBaseline(decoder, 100)
        m.decoderSample(decoder, 103)
        assertEquals(3L, m.finish(PlaybackMetrics.EndReason.ENDED, 2_000)?.droppedFrames)
    }

    @Test fun nouveauDecodeurEtResetDuCompteurSontAdditionnesUneFois() {
        val m = opened()
        val first = Any()
        val second = Any()
        m.decoderSample(first, 3)
        m.decoderSample(second, 4)
        m.decoderSample(second, 1)
        assertEquals(8L, m.finish(PlaybackMetrics.EndReason.ENDED, 2_000)?.droppedFrames)
    }

    @Test fun notificationEtCompteurNeSontJamaisAdditionnes() {
        val m = opened()
        m.droppedFrames(10, 1_200, 4)
        m.decoderSample(Any(), 4)
        val end = m.finish(PlaybackMetrics.EndReason.ENDED, 2_000)!!
        assertEquals(4L, end.droppedFrames)
        assertEquals("decoder", end.droppedSource)
    }

    @Test fun notificationSeuleResteUnRepliIdentifie() {
        val m = opened()
        m.droppedFrames(10, 1_200, 2)
        m.droppedFrames(10, 1_300, 3)
        val end = m.finish(PlaybackMetrics.EndReason.ENDED, 2_000)!!
        assertEquals(5L, end.droppedFrames)
        assertEquals("listener", end.droppedSource)
    }

    @Test fun indisponibleNestPasZeroEtZeroObserveResteZero() {
        val unknown = opened().finish(PlaybackMetrics.EndReason.ENDED, 2_000)!!
        assertNull(unknown.firstFrameElapsedMs)
        assertNull(unknown.startupMs)
        assertNull(unknown.droppedFrames)
        assertNull(unknown.liveOffsetMs)
        val m = opened()
        m.decoderSample(Any(), 0)
        assertEquals(0L, m.finish(PlaybackMetrics.EndReason.ENDED, 2_000)?.droppedFrames)
    }

    @Test fun retardDirectInconnuEffaceUneAncienneValeur() {
        val m = opened()
        m.liveOffset(4_200)
        m.liveOffset(null)
        assertNull(m.finish(PlaybackMetrics.EndReason.ENDED, 2_000)?.liveOffsetMs)
        val negative = opened()
        negative.liveOffset(-200)
        assertEquals(-200L, negative.finish(PlaybackMetrics.EndReason.ENDED, 2_000)?.liveOffsetMs)
    }

    @Test fun finEstIdempotenteEtLesNotificationsTardivesSontSansEffet() {
        val m = opened()
        assertEquals("disposed", m.finish(PlaybackMetrics.EndReason.DISPOSED, 2_000)?.endReason)
        assertNull(m.finish(PlaybackMetrics.EndReason.DISPOSED, 3_000))
        assertFalse(m.accepts(10, 3_000))
        assertNull(m.firstFrame(10, 3_000, 2_500))
    }

    @Test fun compteursBornesSansDebordementNiListeDeTrames() {
        val m = opened()
        m.decoderSample(Any(), Long.MAX_VALUE)
        m.decoderSample(Any(), Long.MAX_VALUE)
        assertEquals(PlaybackMetrics.MAX_VALUE,
            m.finish(PlaybackMetrics.EndReason.ENDED, 2_000)?.droppedFrames)
    }

    @Test fun bilanNeContientAucuneChaineLibreNiAdresse() {
        val wire = opened().finish(PlaybackMetrics.EndReason.SILENCED, 2_000)!!.toWire()
        assertEquals(16, wire.size)
        assertTrue(wire.keys.none { it.contains("url", true) || it.contains("password", true) })
        assertEquals(setOf("android_media3", "summary", "silenced"),
            wire.values.filterIsInstance<String>().toSet())
    }
}
