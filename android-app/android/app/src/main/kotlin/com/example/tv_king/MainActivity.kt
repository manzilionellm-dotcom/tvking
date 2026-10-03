package com.example.tv_king

import com.manzilionellm.native_video_player.logic.AppForeground
import io.flutter.embedding.android.FlutterActivity

/**
 * Activité TV. Le son s'arrête ici, dans le cycle Android, sans attendre
 * que Flutter envoie « paused » (la surface part avant, l'AudioTrack non).
 *
 * La règle (dialogue / overlay / Home) est dans [AppForeground].
 */
class MainActivity : FlutterActivity() {
    override fun onUserLeaveHint() {
        // Home, avant onPause. Un dialogue système ne passe pas ici.
        AppForeground.onUserLeaveHint()
        super.onUserLeaveHint()
    }

    override fun onPause() {
        AppForeground.onPause()
        super.onPause()
    }

    override fun onStop() {
        // Plus visible (écran éteint, ou Home si la box n'a pas dit « leave »).
        AppForeground.onStop()
        super.onStop()
    }

    override fun onResume() {
        // Avant Flutter : une seule reprise, le message « resumed » en
        // retard ne doit pas en lancer une deuxième.
        AppForeground.onResume()
        super.onResume()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // Focus perdu seul = overlay encore sur l'app. On ne coupe pas.
        AppForeground.onWindowFocus(hasFocus)
    }
}
