package com.manzilionellm.native_video_player.logic

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CastNetworkHandoffTest {
    @Test
    fun stopAttendLaFermetureReelleDeChaqueSource() {
        val gate = CastNetworkHandoff()
        val manifest = assertNotNull(gate.acquireSource())
        val segment = assertNotNull(gate.acquireSource())
        val ticket = gate.beginHold()
        gate.acknowledgeStop(ticket)
        assertEquals(CastNetworkHandoff.StopState.WAITING, gate.stopState(ticket))
        gate.sourceClosed(manifest, true)
        assertEquals(CastNetworkHandoff.StopState.WAITING, gate.stopState(ticket))
        gate.sourceClosed(segment, true)
        assertEquals(CastNetworkHandoff.StopState.READY, gate.stopState(ticket))
    }

    @Test
    fun fermetureSeuleSansBarriereStopNeDonnePasLeCast() {
        val gate = CastNetworkHandoff()
        val source = assertNotNull(gate.acquireSource())
        val ticket = gate.beginHold()
        gate.sourceClosed(source, true)
        assertEquals(CastNetworkHandoff.StopState.WAITING, gate.stopState(ticket))
        assertFalse(gate.resumeAfterHold())
        gate.acknowledgeStop(ticket)
        assertEquals(CastNetworkHandoff.StopState.READY, gate.stopState(ticket))
    }

    @Test
    fun uneOuvertureEnRetardEstRefuseeAvantLeReseau() {
        val gate = CastNetworkHandoff()
        val ticket = gate.beginHold()
        gate.onNewSelection() // Un zap arrivé pendant le Cast ne le lève pas.
        assertNull(gate.acquireSource())
        assertFalse(gate.allowsLocalOpen())
        gate.acknowledgeStop(ticket)
        assertTrue(gate.resumeAfterHold())
        assertNotNull(gate.acquireSource())
    }

    @Test
    fun homeEtRetourNeLeventJamaisLeVerrouCast() {
        val gate = CastNetworkHandoff()
        val background = BackgroundGate()
        val ticket = gate.beginHold()
        gate.acknowledgeStop(ticket)
        background.on(BackgroundGate.Signal.PAUSE)
        background.on(BackgroundGate.Signal.STOP)
        background.on(BackgroundGate.Signal.RESUME)
        assertTrue(background.allowsReopen())
        assertFalse(gate.allowsLocalOpen())
        assertNull(gate.acquireSource())
    }

    @Test
    fun erreurDeCloseNeComptePasUneSourceCommeFermee() {
        val gate = CastNetworkHandoff()
        val source = assertNotNull(gate.acquireSource())
        val ticket = gate.beginHold()
        gate.acknowledgeStop(ticket)
        gate.sourceClosed(source, false)
        assertEquals(CastNetworkHandoff.StopState.FAILED, gate.stopState(ticket))
        assertFalse(gate.resumeAfterHold())
        gate.sourceClosed(source, true)
        assertEquals(CastNetworkHandoff.StopState.READY, gate.stopState(ticket))
    }

    @Test
    fun erreurDeStopBloqueLeCastJusquaUnNouvelArretConfirme() {
        val gate = CastNetworkHandoff()
        val first = gate.beginHold()
        gate.failStop(first)
        gate.acknowledgeStop(first)
        assertEquals(CastNetworkHandoff.StopState.FAILED, gate.stopState(first))
        assertFalse(gate.resumeAfterHold())
        val retry = gate.beginHold()
        gate.acknowledgeStop(first) // Le vieux callback ne confirme pas le réessai.
        assertEquals(CastNetworkHandoff.StopState.WAITING, gate.stopState(retry))
        gate.acknowledgeStop(retry)
        assertEquals(CastNetworkHandoff.StopState.READY, gate.stopState(retry))
    }

    @Test
    fun autreLecteurRevoqueTouteRepriseEnRetard() {
        val gate = CastNetworkHandoff()
        val ticket = gate.beginHold()
        gate.revoke()
        gate.acknowledgeStop(ticket)
        gate.onNewSelection()
        assertEquals(CastNetworkHandoff.StopState.CANCELLED, gate.stopState(ticket))
        assertFalse(gate.resumeAfterHold())
        assertNull(gate.acquireSource())
    }

    @Test
    fun ancienCastRevoqueApresSaRepriseNePeutEtreRelanceParUnZapEnRetard() {
        val gate = CastNetworkHandoff()
        val ticket = gate.beginHold()
        gate.acknowledgeStop(ticket)
        assertTrue(gate.resumeAfterHold())
        gate.revoke()
        gate.onNewSelection()
        assertTrue(gate.isHeld())
        assertFalse(gate.resumeAfterHold())
        assertNull(gate.acquireSource())
    }

    @Test
    fun disposeNePeutEtreContreditNiParUnAckNiParUneFermeture() {
        val gate = CastNetworkHandoff()
        val source = assertNotNull(gate.acquireSource())
        val ticket = gate.beginHold()
        gate.dispose()
        gate.sourceClosed(source, true)
        gate.acknowledgeStop(ticket)
        gate.onNewSelection()
        assertEquals(CastNetworkHandoff.StopState.CANCELLED, gate.stopState(ticket))
        assertFalse(gate.resumeAfterHold())
        assertNull(gate.acquireSource())
    }

    @Test
    fun vueAttacheeSansMediaAttendAussiSaBarriereEtLaRepriseExplicite() {
        val gate = CastNetworkHandoff()
        val ticket = gate.beginHold()
        assertEquals(CastNetworkHandoff.StopState.WAITING, gate.stopState(ticket))
        assertNull(gate.acquireSource())
        gate.acknowledgeStop(ticket)
        assertEquals(CastNetworkHandoff.StopState.READY, gate.stopState(ticket))
        assertTrue(gate.isHeld())
        assertTrue(gate.resumeAfterHold())
        assertFalse(gate.isHeld())
    }
}
