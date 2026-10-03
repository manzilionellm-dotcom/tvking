package com.manzilionellm.native_video_player.logic

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * L'interrupteur coupé n'écrit jamais, même si Android est en mode
 * communication avec le haut-parleur d'appel et le Bluetooth d'appel.
 * Allumé, on ne coupe pas un vrai appel. Le Bluetooth n'est jamais
 * une action.
 */
class AudioModeGuardTest {

    private val everyMode = listOf(
        -1,
        AudioRouteState.MODE_NORMAL,
        AudioRouteState.MODE_RINGTONE,
        AudioRouteState.MODE_IN_CALL,
        AudioRouteState.MODE_IN_COMMUNICATION,
        AudioRouteState.MODE_CALL_SCREENING,
        AudioRouteState.MODE_CALL_REDIRECT,
        AudioRouteState.MODE_COMMUNICATION_REDIRECT,
        99,
    )

    @Test
    fun coupeNeToucheARienMemeEnCommunication() {
        for (mode in everyMode) {
            val plan = AudioModeGuard.plan(
                enabled = false,
                mode = mode,
                speakerphone = true,
                bluetoothSco = true,
            )
            assertFalse(plan.touchAudio, "mode $mode")
            assertTrue(plan.actions.isEmpty(), "mode $mode")
            assertTrue(plan.line.contains("coupée"), plan.line)
            assertTrue(plan.line.contains("Aucune écriture"), plan.line)
            assertTrue(plan.line.contains("non coupé"), plan.line)
            assertFalse(plan.line.contains("on va"), plan.line)
        }
    }

    @Test
    fun allumeEnCommunicationDemandeLeModeNormalEtCoupeLeHautParleur() {
        val plan = AudioModeGuard.plan(
            enabled = true,
            mode = AudioRouteState.MODE_IN_COMMUNICATION,
            speakerphone = true,
            bluetoothSco = true,
        )
        assertTrue(plan.touchAudio)
        assertEquals(
            listOf(
                AudioModeGuard.Action.SET_MODE_NORMAL,
                AudioModeGuard.Action.SPEAKERPHONE_OFF,
            ),
            plan.actions,
        )
        assertTrue(plan.line.contains("mode normal"), plan.line)
        assertTrue(plan.line.contains("communication"), plan.line)
        assertTrue(plan.line.contains("non coupé"), plan.line)
        assertFalse(plan.actions.any { it.name.contains("SCO") || it.name.contains("BLUETOOTH") })
    }

    @Test
    fun allumeDejaNormalSansHautParleurNEcritPas() {
        val plan = AudioModeGuard.plan(
            enabled = true,
            mode = AudioRouteState.MODE_NORMAL,
            speakerphone = false,
            bluetoothSco = false,
        )
        assertFalse(plan.touchAudio)
        assertTrue(plan.actions.isEmpty())
        assertTrue(plan.line.contains("Rien à écrire"), plan.line)
    }

    @Test
    fun allumeModeNormalMaisHautParleurAllumeNeCoupeQueLeHautParleur() {
        val plan = AudioModeGuard.plan(
            enabled = true,
            mode = AudioRouteState.MODE_NORMAL,
            speakerphone = true,
            bluetoothSco = false,
        )
        assertTrue(plan.touchAudio)
        assertEquals(listOf(AudioModeGuard.Action.SPEAKERPHONE_OFF), plan.actions)
    }

    @Test
    fun unVraiAppelUneSonnerieOuUnRenvoiNeSontPasForces() {
        val protected = listOf(
            AudioRouteState.MODE_IN_CALL,
            AudioRouteState.MODE_RINGTONE,
            AudioRouteState.MODE_CALL_SCREENING,
            AudioRouteState.MODE_CALL_REDIRECT,
            AudioRouteState.MODE_COMMUNICATION_REDIRECT,
        )
        for (mode in protected) {
            val plan = AudioModeGuard.plan(
                enabled = true,
                mode = mode,
                speakerphone = true,
                bluetoothSco = true,
            )
            assertFalse(plan.touchAudio, AudioRouteState.modeLabel(mode))
            assertTrue(plan.actions.isEmpty(), AudioRouteState.modeLabel(mode))
            assertTrue(plan.line.contains("laissé tel quel"), plan.line)
        }
    }

    @Test
    fun unModeInconnuEstRameneAuNormal() {
        // 99 n'est pas un appel, une sonnerie, ni un renvoi.
        val plan = AudioModeGuard.plan(
            enabled = true,
            mode = 99,
            speakerphone = false,
            bluetoothSco = false,
        )
        assertEquals(listOf(AudioModeGuard.Action.SET_MODE_NORMAL), plan.actions)
        assertTrue(plan.touchAudio)
    }

    @Test
    fun leCasNormalCoupeNeFaitPasDeLigne() {
        assertFalse(
            AudioModeGuard.shouldLog(
                enabled = false,
                mode = AudioRouteState.MODE_NORMAL,
                speakerphone = false,
                bluetoothSco = false,
            ),
        )
        assertTrue(
            AudioModeGuard.shouldLog(
                enabled = false,
                mode = AudioRouteState.MODE_IN_COMMUNICATION,
                speakerphone = false,
                bluetoothSco = false,
            ),
        )
        assertTrue(
            AudioModeGuard.shouldLog(
                enabled = false,
                mode = AudioRouteState.MODE_NORMAL,
                speakerphone = true,
                bluetoothSco = false,
            ),
        )
        assertTrue(
            AudioModeGuard.shouldLog(
                enabled = true,
                mode = AudioRouteState.MODE_NORMAL,
                speakerphone = false,
                bluetoothSco = false,
            ),
        )
    }

    @Test
    fun modeIllisibleOnNeDevinePas() {
        val plan = AudioModeGuard.plan(
            enabled = true,
            mode = -1,
            speakerphone = true,
            bluetoothSco = false,
        )
        assertFalse(plan.touchAudio)
        assertTrue(plan.line.contains("non lu"), plan.line)
    }

    @Test
    fun laPhraseDApresDitSiAndroidAGardeLeMode() {
        val stayed = AudioModeGuard.resultLine(
            beforeMode = AudioRouteState.MODE_IN_COMMUNICATION,
            afterMode = AudioRouteState.MODE_IN_COMMUNICATION,
            beforeSpeaker = true,
            afterSpeaker = true,
            modeRefused = false,
            speakerRefused = false,
        )
        assertTrue(stayed.contains("resté « communication »"), stayed)
        assertTrue(stayed.contains("toujours allumé"), stayed)

        val changed = AudioModeGuard.resultLine(
            beforeMode = AudioRouteState.MODE_IN_COMMUNICATION,
            afterMode = AudioRouteState.MODE_NORMAL,
            beforeSpeaker = true,
            afterSpeaker = false,
            modeRefused = false,
            speakerRefused = false,
        )
        assertTrue(changed.contains("communication"), changed)
        assertTrue(changed.contains("normal"), changed)
        assertTrue(changed.contains("allumé → coupé"), changed)

        val refused = AudioModeGuard.resultLine(
            beforeMode = AudioRouteState.MODE_IN_COMMUNICATION,
            afterMode = AudioRouteState.MODE_IN_COMMUNICATION,
            beforeSpeaker = false,
            afterSpeaker = false,
            modeRefused = true,
            speakerRefused = true,
        )
        assertTrue(refused.contains("refusé setMode"), refused)
        assertTrue(refused.contains("refusé"), refused)
    }
}
