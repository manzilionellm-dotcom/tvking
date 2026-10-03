package com.manzilionellm.native_video_player

import com.manzilionellm.native_video_player.logic.AudioModeGuard
import com.manzilionellm.native_video_player.logic.AudioRouteState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * La garde ne demande MODE_NORMAL que si l'interrupteur est allumé
 * ET que le mode lu est un chemin d'appel. Coupé, même un mode
 * communication ne produit aucune demande.
 */
class AudioModeGuardTest {

    @Test
    fun coupeNeDemandeRienMemeEnCommunication() {
        val plan = AudioModeGuard.plan(
            enabled = false,
            mode = AudioRouteState.MODE_IN_COMMUNICATION,
        )
        assertEquals(AudioModeGuard.Action.LEAVE, plan.action)
        assertFalse(AudioFixesHoldsTheSwitch())
    }

    @Test
    fun allumeEnCommunicationDemandeLeRetour() {
        val modes = listOf(
            AudioRouteState.MODE_IN_CALL,
            AudioRouteState.MODE_IN_COMMUNICATION,
            AudioRouteState.MODE_CALL_SCREENING,
            AudioRouteState.MODE_CALL_REDIRECT,
            AudioRouteState.MODE_COMMUNICATION_REDIRECT,
        )
        for (mode in modes) {
            assertEquals(
                AudioModeGuard.Action.SET_NORMAL,
                AudioModeGuard.plan(enabled = true, mode = mode).action,
                "mode $mode",
            )
        }
    }

    @Test
    fun dejaNormalSonnerieOuInconnuNeTouchePas() {
        val modes = listOf(
            AudioRouteState.MODE_NORMAL,
            AudioRouteState.MODE_RINGTONE,
            -1,
            99,
        )
        for (mode in modes) {
            assertEquals(
                AudioModeGuard.Action.LEAVE,
                AudioModeGuard.plan(enabled = true, mode = mode).action,
                "mode $mode",
            )
        }
    }

    @Test
    fun laPhraseDitLeRetourOuQueCaNaPasPris() {
        val ok = AudioModeGuard.resultLine(
            before = AudioRouteState.MODE_IN_COMMUNICATION,
            after = AudioRouteState.MODE_NORMAL,
            threw = false,
        )
        assertTrue(ok.contains("communication → normal"), ok)

        val stuck = AudioModeGuard.resultLine(
            before = AudioRouteState.MODE_IN_COMMUNICATION,
            after = AudioRouteState.MODE_IN_COMMUNICATION,
            threw = false,
        )
        assertTrue(stuck.contains("toujours"), stuck)
        assertTrue(stuck.contains("autre application"), stuck)

        val refused = AudioModeGuard.resultLine(
            before = AudioRouteState.MODE_IN_CALL,
            after = AudioRouteState.MODE_IN_CALL,
            threw = true,
        )
        assertTrue(refused.contains("refusée"), refused)

        val idle = AudioModeGuard.lookedLine(AudioRouteState.MODE_NORMAL)
        assertTrue(idle.contains("normal"), idle)
        assertTrue(idle.contains("Rien à remettre"), idle)
    }

    /** Le drapeau partiel du processus reste faux : le test ne l'allume pas. */
    private fun AudioFixesHoldsTheSwitch(): Boolean =
        com.manzilionellm.native_video_player.logic.AudioFixes.restoreNormalMode
}
