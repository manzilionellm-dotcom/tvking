// =========================================================
//  VoiceRelayActivity.kt — phrase déjà reconnue par la box
// =========================================================
//  Le bouton micro de beaucoup de télécommandes ne donne PAS le son
//  à l'application. Android reconnaît la phrase, puis envoie
//  ACTION_SEARCH. Cette activité minuscule :
//    1. range le texte (ZunoVoicePlugin) ;
//    2. ramène Zuno au premier plan SANS recréer le lecteur
//       (CLEAR_TOP sur l'activité déjà ouverte, pas CLEAR_TASK) ;
//    3. se ferme tout de suite.
//  Elle n'a pas d'écran (Theme.NoDisplay) et finish() avant la fin
//  de onCreate, sinon Android ferme l'appli.
// =========================================================

package com.manzilionellm.zuno_voice

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log

class VoiceRelayActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            ZunoVoicePlugin.deliverFromIntent(intent)
            val launch = packageManager.getLaunchIntentForPackage(packageName)
            if (launch != null) {
                launch.addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
                startActivity(launch)
            }
        } catch (t: Throwable) {
            // Même en échec, on ne reste pas à l'écran : une activité
            // invisible qui ne se ferme pas fait planter la box.
            Log.w("ZunoVoice", "relais micro : $t")
        } finally {
            finish()
        }
    }
}
