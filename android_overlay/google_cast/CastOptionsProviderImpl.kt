// =========================================================
//  CastOptionsProviderImpl.kt — Config du Cast SDK
// =========================================================
//  Le Google Cast SDK exige une classe qui implémente
//  `OptionsProvider` et fournit le CAST APP ID — l'identifiant
//  du receiver-side à charger sur le Chromecast.
//
//  Pour 7 MOTION on utilise le **Default Media Receiver** de
//  Google (App ID `CC1AD845`). C'est un receiver générique qui
//  joue n'importe quel flux HLS / DASH / MP4 / MP2T sans qu'on
//  ait à développer une web app receiver custom (qui exigerait
//  un compte Cast Developer Console + hébergement HTML).
//
//  Comportement : tap sur la TV depuis le dialog Cast → la TV
//  charge l'URL receiver de Google → joue notre stream.
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
            // App ID = Default Media Receiver (CC1AD845)
            // = receiver web officiel de Google, joue HLS/DASH/MP4/MP2T
            // sans dev custom. Idéal pour notre cas IPTV.
            .setReceiverApplicationId("CC1AD845")
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
