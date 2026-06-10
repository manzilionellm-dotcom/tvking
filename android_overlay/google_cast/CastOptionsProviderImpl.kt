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
            // 2026 — CUSTOM RECEIVER « 7 MOTION TS » (App ID 5BDFD969).
            // C'est le SEUL moyen de lire le MPEG-TS brut (IPTV .ts) sur
            // les appareils Google (Chromecast / Google TV / SHIELD) : ce
            // receiver (cloudflare/cast_receiver.js, URL
            // https://99999.7themotion.com/cast-receiver) embarque
            // mpegts.js qui décode le TS live via MSE. Le Default Media
            // Receiver (CC1AD845) et l'ancien Styled Receiver (46F815A5)
            // ne décodent PAS le .ts → écran « cast » sans image.
            //
            // PRÉREQUIS CONSOLE : 5BDFD969 doit être "Published" pour
            // marcher chez tous les clients. Tant qu'il est "Unpublished",
            // il ne charge QUE sur les appareils inscrits en "test
            // devices" du compte dev (suffisant pour valider sur la SHIELD).
            .setReceiverApplicationId("5BDFD969")
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
