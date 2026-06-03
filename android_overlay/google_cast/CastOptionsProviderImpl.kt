// =========================================================
//  CastOptionsProviderImpl.kt — Config du Cast SDK
// =========================================================
//  Le Google Cast SDK exige une classe qui implémente
//  `OptionsProvider` et fournit le CAST APP ID — l'identifiant
//  du receiver-side à charger sur le Chromecast.
//
//  Receiver utilisé : Custom Styled Media Receiver enregistré
//  sur la Google Cast SDK Developer Console (compte
//  manzilionel.lm@gmail.com) sous l'App ID `46F815A5`.
//
//  Le receiver est skinné via le CSS hébergé sur notre Worker
//  Cloudflare :
//    https://99999.7themotion.com/cast-skin.css
//  Couleurs : fond charbon (#0A0A0C), accent ember (#D63A30),
//  logo 7 MOTION en idle / splash.
//
//  Statut : "Unpublished" sur la Console = utilisable uniquement
//  sur les Chromecast enregistrées comme appareils de test sur
//  le compte développeur. Pour distribution grand public, il
//  faudra "Publish" l'application sur la Console (séparément).
//
//  Comportement : tap sur la TV depuis le dialog Cast → la TV
//  charge notre receiver brandé → joue notre stream avec le
//  logo 7 MOTION sur l'idle screen.
//
//  Ce fichier est référencé dans AndroidManifest.xml :
//    <meta-data
//      android:name="com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME"
//      android:value="com.manzilionellm.tvking.CastOptionsProviderImpl"/>
//  Le patch CI ajoute cette ligne après `flutter create`.
// =========================================================

package com.manzilionellm.tvking

import android.content.Context
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider
import com.google.android.gms.cast.framework.media.CastMediaOptions
import com.google.android.gms.cast.framework.media.NotificationOptions

class CastOptionsProviderImpl : OptionsProvider {

    override fun getCastOptions(context: Context): CastOptions {
        // Notification persistante quand un cast est actif. Style
        // YouTube : "Lecture sur Salon LG ⏯".
        val notificationOptions = NotificationOptions.Builder()
            .setActions(
                listOf(
                    com.google.android.gms.cast.framework.media.MediaIntentReceiver.ACTION_TOGGLE_PLAYBACK,
                    com.google.android.gms.cast.framework.media.MediaIntentReceiver.ACTION_STOP_CASTING,
                ),
                intArrayOf(0, 1),
            )
            .build()

        val mediaOptions = CastMediaOptions.Builder()
            .setNotificationOptions(notificationOptions)
            .build()

        return CastOptions.Builder()
            // App ID = Custom Styled Media Receiver "7 MOTION"
            // enregistre sur la Google Cast SDK Developer Console
            // (compte manzilionel.lm@gmail.com, statut Unpublished
            // au 2026-05-31). Skin URL pointe vers
            // https://99999.7themotion.com/cast-skin.css → logo
            // 7 MOTION, fond charbon, accent ember sur la TV.
            .setReceiverApplicationId("46F815A5")
            .setCastMediaOptions(mediaOptions)
            // Resume la session si l'app est tuée puis relancée
            // dans les 30 min — l'utilisateur ne se reconnecte pas
            // à chaque retour, comportement Netflix.
            .setResumeSavedSession(true)
            .setEnableReconnectionService(true)
            .build()
    }

    override fun getAdditionalSessionProviders(context: Context): List<SessionProvider>? =
        null
}
