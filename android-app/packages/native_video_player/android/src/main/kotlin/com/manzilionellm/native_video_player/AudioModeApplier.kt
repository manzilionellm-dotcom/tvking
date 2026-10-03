package com.manzilionellm.native_video_player

import android.media.AudioManager
import com.manzilionellm.native_video_player.logic.AudioModeGuard

/**
 * Écrit le mode Android seulement si [AudioModeGuard.plan] le demande.
 *
 * Le réglage coupé ([enabled] faux) lit le mode et n'appelle ni
 * setMode, ni setSpeakerphoneOn, ni le Bluetooth. Si tout est déjà
 * normal, on n'écrit même pas de ligne (les aperçus de chaînes
 * seraient noyés). Un mode qui n'est pas normal est noté.
 *
 * Appelé avant chaque ouverture de chaîne (vue TV) et, sur le
 * téléphone, avant que mpv ouvre le flux — dans les deux cas
 * seulement si l'interrupteur est allumé pour l'écriture.
 *
 * On ne restaure pas l'ancien mode en quittant l'app : l'ancien mode
 * peut être justement le mode communication qui fuit. On ne met
 * jamais le mode communication nous-mêmes, donc il n'y a rien à
 * refermer en arrière-plan.
 */
object AudioModeApplier {

    fun describeAndMaybeApply(am: AudioManager?, enabled: Boolean): List<String> {
        if (am == null) {
            return listOf("Garde mode : service audio absent, rien modifié.")
        }
        val beforeMode = readMode(am)
        val beforeSpeaker = readSpeaker(am)
        val sco = readSco(am)
        val plan = AudioModeGuard.plan(enabled, beforeMode, beforeSpeaker, sco)
        if (!plan.touchAudio) {
            val tell = AudioModeGuard.shouldLog(enabled, beforeMode, beforeSpeaker, sco)
            return if (tell) listOf(plan.line) else emptyList()
        }
        var modeRefused = false
        var speakerRefused = false
        for (action in plan.actions) {
            when (action) {
                AudioModeGuard.Action.SET_MODE_NORMAL -> {
                    try {
                        am.mode = AudioManager.MODE_NORMAL
                    } catch (_: SecurityException) {
                        modeRefused = true
                    } catch (_: RuntimeException) {
                        modeRefused = true
                    }
                }
                AudioModeGuard.Action.SPEAKERPHONE_OFF -> {
                    try {
                        @Suppress("DEPRECATION")
                        am.isSpeakerphoneOn = false
                    } catch (_: SecurityException) {
                        speakerRefused = true
                    } catch (_: RuntimeException) {
                        speakerRefused = true
                    }
                }
            }
        }
        val afterMode = readMode(am)
        val afterSpeaker = readSpeaker(am)
        return listOf(
            plan.line,
            AudioModeGuard.resultLine(
                beforeMode = beforeMode,
                afterMode = afterMode,
                beforeSpeaker = beforeSpeaker,
                afterSpeaker = afterSpeaker,
                modeRefused = modeRefused,
                speakerRefused = speakerRefused,
            ),
        )
    }

    private fun readMode(am: AudioManager): Int = try {
        am.mode
    } catch (_: RuntimeException) {
        -1
    }

    private fun readSpeaker(am: AudioManager): Boolean = try {
        @Suppress("DEPRECATION")
        am.isSpeakerphoneOn
    } catch (_: RuntimeException) {
        false
    }

    private fun readSco(am: AudioManager): Boolean = try {
        @Suppress("DEPRECATION")
        am.isBluetoothScoOn
    } catch (_: RuntimeException) {
        false
    }
}
