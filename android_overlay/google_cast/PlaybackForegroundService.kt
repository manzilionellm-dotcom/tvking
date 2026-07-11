// =========================================================
//  PlaybackForegroundService.kt — AUDIO en arrière-plan
// =========================================================
//  Mode « Écouteurs » (façon radio / YouTube Premium) : quand
//  l'utilisateur tape « Écouteurs » dans le player, l'app démarre ce
//  foreground service. Tant qu'il tourne, Android garde le process en
//  vie (foreground + wakelock + wifilock) → le son de media_kit /
//  libmpv continue de jouer ÉCRAN ÉTEINT ou pendant que l'utilisateur
//  est dans une autre app, avec une notification persistante.
//
//  Modelé sur RecordingForegroundService (même projet), en plus simple :
//  PAS de téléchargement ici — la lecture audio reste dans le moteur
//  Flutter (media_kit). Ce service ne fait que « tiens-moi en vie +
//  affiche une notification + garde le CPU/WiFi actifs ».
//
//  Cycle de vie :
//    1. Dart (PipService.startBackgroundAudio(title)) → MainActivity →
//       startForegroundService(ACTION_START). L'app est encore VISIBLE
//       au moment du tap « Écouteurs » → pas de restriction Android 12+
//       sur le démarrage d'un foreground service.
//    2. startForeground() + notification + acquireLocks().
//    3. Dart (stopBackgroundAudio) à la sortie du mode / dispose →
//       ACTION_STOP → releaseLocks + stopForeground + stopSelf.
//    4. Swipe de l'app hors des récents → onTaskRemoved → stopSelf
//       (l'utilisateur a fermé l'app → on coupe le son de fond).
//
//  Ce fichier est CHECKÉ DANS le repo (android_overlay/) et copié par
//  apply_cast_patch.sh vers android/app/src/main/kotlin/... au build CI.
// =========================================================

package com.manzilionellm.tvking

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

class PlaybackForegroundService : Service() {

    companion object {
        private const val TAG = "PlaybackFgSvc"
        private const val NOTIFICATION_ID = 1002
        private const val CHANNEL_ID = "playback_channel"
        private const val WAKE_LOCK_TAG = "7motion:playback_wake_lock"
        private const val WIFI_LOCK_TAG = "7motion:playback_wifi_lock"

        const val ACTION_START = "com.manzilionellm.tvking.playback.START"
        const val ACTION_STOP = "com.manzilionellm.tvking.playback.STOP"
        const val EXTRA_TITLE = "title"

        /// Texte de la 2e ligne de la notification. Par défaut le mode
        /// « Écouteurs » historique ; le CAST RELAIS (le téléphone
        /// alimente la TV, écran éteint possible) passe son propre
        /// libellé — même service, mêmes locks CPU/WiFi.
        const val EXTRA_BODY = "body"
        private const val DEFAULT_BODY = "Lecture audio en arrière-plan"

        /// i18n : libellés localisés fournis par Dart (AppLocalizations,
        /// langue du téléphone ou choix Réglages). Les défauts français
        /// ci-dessous ne servent que de filet si un appelant n'envoie
        /// pas les extras (ancienne version de l'app).
        const val EXTRA_STOP_LABEL = "stopLabel"
        const val EXTRA_CHANNEL_NAME = "channelName"
        const val EXTRA_CHANNEL_DESC = "channelDesc"
        private const val DEFAULT_STOP_LABEL = "Arrêter"
        private const val DEFAULT_CHANNEL_NAME = "Lecture audio"
        private const val DEFAULT_CHANNEL_DESC =
            "Lecture audio en arrière-plan (mode Écouteurs)"
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "7 MOTION"
                val body = intent.getStringExtra(EXTRA_BODY) ?: DEFAULT_BODY
                val stopLabel =
                    intent.getStringExtra(EXTRA_STOP_LABEL) ?: DEFAULT_STOP_LABEL
                Log.i(TAG, "START background keep-alive: $title ($body)")
                createChannelIfNeeded(
                    intent.getStringExtra(EXTRA_CHANNEL_NAME) ?: DEFAULT_CHANNEL_NAME,
                    intent.getStringExtra(EXTRA_CHANNEL_DESC) ?: DEFAULT_CHANNEL_DESC,
                )
                startForeground(
                    NOTIFICATION_ID,
                    buildNotification(title, body, stopLabel),
                )
                acquireLocks()
            }
            ACTION_STOP -> {
                Log.i(TAG, "STOP background audio")
                releaseLocks()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
            }
            else -> {
                // Re-livraison sans action exploitable → on s'arrête.
                releaseLocks()
                stopSelf()
            }
        }
        // NOT_STICKY : si l'OS tue le service, on NE le relance pas tout
        // seul (contrairement à l'enregistrement). L'audio de fond n'a de
        // sens que tant que l'utilisateur le veut ; Dart le relancera au
        // besoin.
        return START_NOT_STICKY
    }

    /// L'utilisateur a "swipe" l'app hors des récents → il a fermé l'app,
    /// donc on COUPE le son de fond (≠ enregistrement qui, lui, survit).
    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "onTaskRemoved — app fermée, on coupe l'audio de fond")
        releaseLocks()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        releaseLocks()
        super.onDestroy()
    }

    private fun buildNotification(
        title: String,
        body: String = DEFAULT_BODY,
        stopLabel: String = DEFAULT_STOP_LABEL,
    ): Notification {
        // Tap sur la notification → ramène l'app au premier plan.
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        }
        val contentPi: PendingIntent? = if (launch != null) {
            PendingIntent.getActivity(
                this,
                0,
                launch,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        } else {
            null
        }

        // Action « Arrêter » → renvoie ACTION_STOP au service (coupe le
        // son de fond + retire la notification).
        val stopIntent = Intent(this, PlaybackForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPi = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                stopLabel,
                stopPi,
            )
        if (contentPi != null) builder.setContentIntent(contentPi)
        return builder.build()
    }

    private fun createChannelIfNeeded(
        name: String = DEFAULT_CHANNEL_NAME,
        desc: String = DEFAULT_CHANNEL_DESC,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            // createNotificationChannel() sur un canal existant met à
            // jour son nom/description (jamais l'importance) → le canal
            // suit la langue de l'app à chaque démarrage du service.
            val ch = NotificationChannel(
                CHANNEL_ID,
                name,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = desc
                setShowBadge(false)
                setSound(null, null)
            }
            mgr.createNotificationChannel(ch)
        }
    }

    /// PartialWakeLock = garde le CPU actif écran éteint (sinon le
    /// décodage audio de libmpv est suspendu). WifiLock HIGH_PERF =
    /// empêche le WiFi de passer en veille (sinon la socket du flux est
    /// coupée après ~30 s d'écran éteint).
    private fun acquireLocks() {
        try {
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
            }
            if (wakeLock?.isHeld != true) {
                // Garde-fou anti-surchauffe : 3 h max, re-acquis si besoin.
                wakeLock?.acquire(3 * 60 * 60 * 1000L)
            }
            if (wifiLock == null) {
                val wm = applicationContext
                    .getSystemService(Context.WIFI_SERVICE) as WifiManager
                wifiLock = wm.createWifiLock(
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                    WIFI_LOCK_TAG,
                )
            }
            if (wifiLock?.isHeld != true) wifiLock?.acquire()
        } catch (e: Throwable) {
            Log.w(TAG, "acquireLocks failed: $e")
        }
    }

    private fun releaseLocks() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Throwable) {
        }
        try {
            if (wifiLock?.isHeld == true) wifiLock?.release()
        } catch (_: Throwable) {
        }
    }
}
