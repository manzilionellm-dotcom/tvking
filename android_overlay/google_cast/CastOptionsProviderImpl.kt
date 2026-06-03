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

    companion object {
        /// Custom Styled Media Receiver "BLACK7 ROYAL" enregistré sur la
        /// Google Cast SDK Developer Console (compte
        /// manzilionel.lm@gmail.com). ⚠️ STATUT "UNPUBLISHED" : tant
        /// qu'il n'est pas PUBLIÉ sur la Console, il ne fonctionne que
        /// sur les Chromecast déclarées comme appareils de test. Sur les
        /// autres TV → découverte OK mais SESSION QUI ÉCHOUE. Pour le
        /// grand public, il FAUT "Publish" cet App ID sur la Console.
        private const val RECEIVER_APP_ID = "46F815A5"

        /// Default Media Receiver de Google — TOUJOURS disponible, sans
        /// branding. Sert de fallback pour ISOLER une panne de receiver
        /// custom (non publié) d'une panne de découverte : si le cast
        /// marche avec celui-ci mais pas avec le custom, le problème est
        /// la publication du receiver, pas le réseau.
        private const val DEFAULT_RECEIVER = "CC1AD845"
    }

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

        // Choix du receiver :
        //   - Build DEBUG  → Default Media Receiver (CC1AD845), TOUJOURS
        //     disponible → le cast MARCHE même si le receiver custom
        //     n'est pas publié. Permet d'isoler les pannes.
        //   - Build RELEASE → receiver custom brandé (RECEIVER_APP_ID).
        // ⚠️ NB : les APK actuels sont buildés en DEBUG (flutter build
        // apk --debug), donc ils utilisent le Default Receiver. Quand le
        // receiver custom sera PUBLIÉ sur la Cast Console, on pourra
        // passer en release ou forcer RECEIVER_APP_ID.
        val isDebuggable = (context.applicationInfo.flags and
            android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
        val appId = if (isDebuggable) DEFAULT_RECEIVER else RECEIVER_APP_ID

        return CastOptions.Builder()
            .setReceiverApplicationId(appId)
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
