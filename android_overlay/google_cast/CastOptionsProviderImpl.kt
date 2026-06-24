// =========================================================
//  CastOptionsProviderImpl.kt — Config du Cast SDK
// =========================================================
//  Le Google Cast SDK exige une classe qui implémente
//  `OptionsProvider` et fournit le CAST APP ID — l'identifiant
//  du receiver-side à charger sur le Chromecast.
//
//  Receiver utilisé : DEFAULT MEDIA RECEIVER public de Google
//  (App ID `CC1AD845`). Public et toujours actif → le cast marche
//  sur TOUTES les Chromecast / Google TV, chez n'importe qui.
//
//  Historique : on utilisait le Custom Styled Media Receiver brandé
//  "7 MOTION" (App ID `46F815A5`, compte manzilionel.lm@gmail.com,
//  skin https://99999.7themotion.com/cast-skin.css). Mais il était
//  resté "Unpublished" sur la Console → utilisable UNIQUEMENT sur
//  les Chromecast inscrites comme appareils de test du compte dev.
//  D'où le symptôme "le cast ne marche pas sur la plupart des TV".
//  On bascule donc sur le receiver public par défaut (cf. getCastOptions).
//
//  Pour retrouver le branding : publier `46F815A5` sur la Console
//  ("Published"), puis remettre cet App ID dans getCastOptions().
//
//  Comportement : tap sur la TV depuis le dialog Cast → la TV
//  charge le Default Media Receiver → joue notre stream (lecteur
//  Google standard, sans le logo 7 MOTION sur l'idle screen).
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
        // ⚠️ BASCULEMENT CUSTOM RECEIVER — USE_CUSTOM_RECEIVER (ici) et
        // kCastUseCustomReceiver (lib/features/cast/data/google_cast_transport.dart)
        // DOIVENT TOUJOURS valoir LA MÊME CHOSE. Les désynchroniser = écran
        // noir (le sender enverrait un format que le receiver chargé ne sait
        // pas lire). Les deux sont à `true` ci-dessous → custom receiver actif.
        //
        //   false : Default Media Receiver public CC1AD845 (ne décode pas le
        //     MPEG-TS brut → nécessitait un wrap HLS / VPS).
        //   true  : custom receiver 5BDFD969 (page mpegts.js sur
        //     app.7themotion.com/cast-receiver) → décode le MPEG-TS LUI-MÊME
        //     sur la TV → le sender envoie l'URL .ts DIRECTE, sans VPS.
        private const val USE_CUSTOM_RECEIVER = true

        // Default Media Receiver public de Google (toujours actif).
        private const val DEFAULT_RECEIVER_ID = "CC1AD845"
        // Custom Cast receiver « 7 MOTION TS » (page mpegts.js servie par le
        // Worker à /cast-receiver). DOIT être PUBLISHED dans la Google Cast
        // Developer Console — sinon il ne charge QUE sur les Chromecast/SHIELD
        // inscrites comme appareils de test du compte dev.
        private const val CUSTOM_RECEIVER_ID = "5BDFD969"
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

        return CastOptions.Builder()
            // App ID = DEFAULT MEDIA RECEIVER public de Google
            // (CC1AD845). Choisi volontairement a la place du receiver
            // brande "7 MOTION" (46F815A5) parce que ce dernier est
            // reste "Unpublished" sur la Cast Developer Console : un
            // receiver non publie ne charge QUE sur les Chromecast
            // inscrites comme appareils de test du compte dev. Resultat
            // cote utilisateur : "le cast ne marche pas sur la plupart
            // des TV / telephones". Le Default Media Receiver, lui, est
            // public et toujours actif → le cast fonctionne sur TOUTES
            // les Chromecast / Google TV, sans inscription.
            //
            // Aucune perte de compatibilite de format : le Styled Media
            // Receiver et le Default Media Receiver partagent le MEME
            // moteur de lecture web — seule la peau CSS differe. On perd
            // donc uniquement le branding (logo 7 MOTION sur l'idle
            // screen), pas la lecture HLS/IPTV.
            //
            // POUR RETROUVER LE BRANDING plus tard : publier l'app
            // 46F815A5 dans la Cast Developer Console (statut
            // "Published"), puis remettre cet App ID ci-dessous.
            .setReceiverApplicationId(
                if (USE_CUSTOM_RECEIVER) CUSTOM_RECEIVER_ID else DEFAULT_RECEIVER_ID
            )
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
