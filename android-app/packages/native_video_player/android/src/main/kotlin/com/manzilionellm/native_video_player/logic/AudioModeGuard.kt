package com.manzilionellm.native_video_player.logic

/**
 * GARDE DU MODE AUDIO (03/10/2026) — hypothèse « comme la musique
 * quand on t'appelle ».
 *
 * Si Android est resté en mode communication, le mélangeur du
 * téléphone peut traiter le son APRÈS l'AudioTrack : bande étroite,
 * haut-parleur d'appel, annulation d'écho. Les sondes PCM, elles,
 * sont avant cet étage. Elles peuvent donc rester à 1–4 % au-dessus
 * de 4 kHz (une voix) pendant que le haut-parleur sonne « dans un trou ».
 *
 * Ce fichier ne parle pas à Android. Il décide seulement s'il FAUT
 * écrire, et quoi. L'écriture est dans [com.manzilionellm.native_video_player.AudioModeApplier],
 * et seulement quand [touchAudio] est vrai.
 *
 * Coupé par défaut : aucune écriture, quel que soit le mode lu.
 *
 * Allumé, on ne touche pas à un vrai appel (mode appel), à une
 * sonnerie, ni aux modes de renvoi du système. On ne coupe pas le
 * Bluetooth d'appel : un casque réel ne doit pas tomber. On ne
 * démarre jamais un micro.
 *
 * Pur Kotlin.
 */
object AudioModeGuard {

    const val KEY: String = "zuno.audio.mode.normal"

    enum class Action {
        /** AudioManager.setMode(MODE_NORMAL). */
        SET_MODE_NORMAL,

        /** AudioManager.setSpeakerphoneOn(false). */
        SPEAKERPHONE_OFF,
    }

    data class Plan(
        val enabled: Boolean,
        val actions: List<Action>,
        /**
         * Vrai seulement si l'appelant doit écrire dans AudioManager.
         * Faux : on a le droit de lire le mode, pas de le changer.
         */
        val touchAudio: Boolean,
        val line: String,
    )

    /**
     * Décision avant une lecture.
     *
     * [mode] −1 = pas lu. [speakerphone] = haut-parleur d'appel.
     * [bluetoothSco] est seulement raconté : aucune action ne le coupe.
     */
    fun plan(
        enabled: Boolean,
        mode: Int,
        speakerphone: Boolean,
        bluetoothSco: Boolean,
    ): Plan {
        val sco = if (bluetoothSco) {
            "Bluetooth appel allumé, non coupé"
        } else {
            "Bluetooth appel coupé"
        }
        val spk = if (speakerphone) "allumé" else "coupé"
        if (!enabled) {
            return Plan(
                enabled = false,
                actions = emptyList(),
                touchAudio = false,
                line = "Garde mode : coupée. Mode lu « ${AudioRouteState.modeLabel(mode)} », " +
                    "haut-parleur d'appel $spk, $sco. Aucune écriture.",
            )
        }
        if (mode < 0) {
            return Plan(
                enabled = true,
                actions = emptyList(),
                touchAudio = false,
                line = "Garde mode : allumée, mode non lu. On ne touche à rien. $sco.",
            )
        }
        if (leaveAlone(mode)) {
            return Plan(
                enabled = true,
                actions = emptyList(),
                touchAudio = false,
                line = "Garde mode : allumée, mode « ${AudioRouteState.modeLabel(mode)} » laissé tel quel " +
                    "(appel, sonnerie ou renvoi : on ne force pas le mode normal). " +
                    "Haut-parleur d'appel $spk, $sco.",
            )
        }
        val actions = ArrayList<Action>(2)
        if (mode != AudioRouteState.MODE_NORMAL) {
            actions.add(Action.SET_MODE_NORMAL)
        }
        if (speakerphone) {
            actions.add(Action.SPEAKERPHONE_OFF)
        }
        val what = if (actions.isEmpty()) {
            "déjà normal, haut-parleur d'appel déjà coupé. Rien à écrire."
        } else {
            val bits = actions.joinToString(", ") { action ->
                when (action) {
                    Action.SET_MODE_NORMAL ->
                        "demander le mode normal (était ${AudioRouteState.modeLabel(mode)})"
                    Action.SPEAKERPHONE_OFF -> "couper le haut-parleur d'appel"
                }
            }
            "on va $bits."
        }
        return Plan(
            enabled = true,
            actions = actions,
            touchAudio = actions.isNotEmpty(),
            line = "Garde mode : allumée. $what $sco.",
        )
    }

    /**
     * Phrase APRÈS une écriture. On compare ce qu'on a lu avant et
     * après : Android peut refuser, ou un autre programme peut garder
     * le mode communication.
     */
    fun resultLine(
        beforeMode: Int,
        afterMode: Int,
        beforeSpeaker: Boolean,
        afterSpeaker: Boolean,
        modeRefused: Boolean,
        speakerRefused: Boolean,
    ): String {
        val modeBit = when {
            modeRefused -> "Android a refusé setMode"
            beforeMode == afterMode -> "mode resté « ${AudioRouteState.modeLabel(afterMode)} »"
            else -> "mode « ${AudioRouteState.modeLabel(beforeMode)} » → « ${AudioRouteState.modeLabel(afterMode)} »"
        }
        val spkBit = when {
            speakerRefused -> "haut-parleur d'appel refusé"
            beforeSpeaker == afterSpeaker && afterSpeaker -> "haut-parleur d'appel toujours allumé"
            beforeSpeaker == afterSpeaker -> "haut-parleur d'appel toujours coupé"
            afterSpeaker -> "haut-parleur d'appel coupé → allumé"
            else -> "haut-parleur d'appel allumé → coupé"
        }
        return "Garde mode : après écriture, $modeBit, $spkBit."
    }

    /**
     * Faut-il écrire une ligne quand on ne change rien ?
     *
     * Coupé, mode normal, haut-parleur d'appel coupé, Bluetooth coupé :
     * non. Sinon chaque aperçu de chaîne ajouterait une ligne.
     * Dès que le mode n'est pas normal, ou que l'interrupteur est allumé,
     * on le dit.
     */
    fun shouldLog(
        enabled: Boolean,
        mode: Int,
        speakerphone: Boolean,
        bluetoothSco: Boolean,
    ): Boolean {
        if (enabled) return true
        if (mode != AudioRouteState.MODE_NORMAL) return true
        if (speakerphone || bluetoothSco) return true
        return false
    }

    /**
     * Ces modes appartiennent à la téléphonie ou au système.
     * Les forcer couperait un vrai appel. On les nomme, on n'écrit pas.
     */
    private fun leaveAlone(mode: Int): Boolean = when (mode) {
        AudioRouteState.MODE_IN_CALL,
        AudioRouteState.MODE_RINGTONE,
        AudioRouteState.MODE_CALL_SCREENING,
        AudioRouteState.MODE_CALL_REDIRECT,
        AudioRouteState.MODE_COMMUNICATION_REDIRECT,
        -> true
        else -> false
    }
}
