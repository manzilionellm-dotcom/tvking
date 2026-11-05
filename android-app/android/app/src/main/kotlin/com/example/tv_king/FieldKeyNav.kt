package com.example.tv_king

import android.view.KeyEvent
import io.flutter.plugin.common.MethodChannel

/**
 * Quand un champ d'une ligne a le focus, Bas / Haut / Entrée
 * doivent changer de champ. La connexion de saisie Android
 * répondrait sinon « traité » sans bouger le curseur
 * (InputConnectionAdaptor.handleVerticalMovement).
 *
 * On consomme la touche ici, avant Flutter, et on demande au
 * cadre de passer au champ suivant. Gauche, Droite et OK
 * restent au curseur ou au clavier.
 */
object FieldKeyNav {
    @Volatile
    var armed: Boolean = false

    var channel: MethodChannel? = null

    fun onKey(event: KeyEvent): Boolean {
        if (!armed) return false
        val direction = direction(event.keyCode) ?: return false
        if (event.action == KeyEvent.ACTION_DOWN) {
            channel?.invokeMethod("move", direction)
        }
        // ACTION_UP aussi : sinon le clavier virtuel reçoit le
        // relâchement et peut encore avaler la touche.
        return true
    }

    private fun direction(code: Int): String? = when (code) {
        KeyEvent.KEYCODE_DPAD_UP,
        KeyEvent.KEYCODE_CHANNEL_UP,
        KeyEvent.KEYCODE_PAGE_UP -> "up"
        KeyEvent.KEYCODE_DPAD_DOWN,
        KeyEvent.KEYCODE_CHANNEL_DOWN,
        KeyEvent.KEYCODE_PAGE_DOWN,
        KeyEvent.KEYCODE_ENTER,
        KeyEvent.KEYCODE_NUMPAD_ENTER -> "down"
        else -> null
    }
}
