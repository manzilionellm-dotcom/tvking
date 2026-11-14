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

package com.sevenmotion.novatube

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.PowerManager
import android.os.ResultReceiver
import android.util.Log
import androidx.core.app.NotificationCompat

class PlaybackForegroundService : Service() {

    companion object {
        private const val TAG = "PlaybackFgSvc"
        private const val NOTIFICATION_ID = 1002
        private const val CHANNEL_ID = "playback_channel"
        private const val CAST_CHANNEL_ID = "cast_playback_channel"
        private const val WAKE_LOCK_TAG = "7motion:playback_wake_lock"
        private const val WIFI_LOCK_TAG = "7motion:playback_wifi_lock"

        const val ACTION_START = "com.manzilionellm.tvking.playback.START"
        const val ACTION_STOP = "com.manzilionellm.tvking.playback.STOP"
        const val EXTRA_TITLE = "title"
        const val ACTION_STOP_CAST = "com.sevenmotion.novatube.playback.STOP_CAST"
        const val EXTRA_CAST_SESSION = "castSessionId"
        const val EXTRA_CAST_DESCRIPTION = "castDescription"
        const val EXTRA_CAST_STOP_LABEL = "castStopLabel"
        const val EXTRA_CAST_STOP_RECEIVER = "castStopReceiver"
        const val RESULT_CAST_USER_STOP = 1

        // Survit à stopSelf dans le même processus : un START de permission
        // déjà en route ne peut recréer la session que l'utilisateur a arrêtée.
        private val castStops = PlaybackStopSession()
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var castSessionId: String? = null
    private var castStopReceiver: ResultReceiver? = null
    private var castDescription: String? = null
    private var castStopLabel: String? = null
    private var foregroundStarted = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val requestedCast = if (BuildConfig.NOVATUBE_PLAY) {
                    intent.getStringExtra(EXTRA_CAST_SESSION)
                } else null
                if (requestedCast != null) {
                    @Suppress("DEPRECATION")
                    val receiver = intent.getParcelableExtra<ResultReceiver>(EXTRA_CAST_STOP_RECEIVER)
                    if (receiver == null || !castStops.startCast(requestedCast)) {
                        stopIfUnused(startId)
                        return START_NOT_STICKY
                    }
                    castSessionId = requestedCast
                    castStopReceiver = receiver
                    castDescription = intent.getStringExtra(EXTRA_CAST_DESCRIPTION)
                    castStopLabel = intent.getStringExtra(EXTRA_CAST_STOP_LABEL)
                } else {
                    if (BuildConfig.NOVATUBE_PLAY) castStops.startAudio()
                    clearCastNotification()
                }
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "NOVATUBE"
                Log.i(TAG, if (castSessionId != null) "START cast relay" else "START background audio: $title")
                createChannelIfNeeded()
                startForeground(NOTIFICATION_ID, buildNotification(title))
                foregroundStarted = true
                acquireLocks()
            }
            ACTION_STOP -> {
                val requestedCast = intent.getStringExtra(EXTRA_CAST_SESSION)
                if (BuildConfig.NOVATUBE_PLAY && !castStops.stopFromApp(requestedCast)) {
                    stopIfUnused(startId)
                    return START_NOT_STICKY
                }
                Log.i(TAG, "STOP background audio")
                clearCastNotification()
                stopPlayback(startId)
            }
            ACTION_STOP_CAST -> {
                val requestedCast = intent.getStringExtra(EXTRA_CAST_SESSION)
                if (!BuildConfig.NOVATUBE_PLAY || requestedCast != castSessionId ||
                    !castStops.stopFromNotification(requestedCast)) {
                    stopIfUnused(startId)
                    return START_NOT_STICKY
                }
                // Seul CE bouton utilisateur renvoie l'événement à Dart.
                // Le ResultReceiver est fourni par notre activité au service
                // non exporté : aucun broadcast public ou lancement d'écran.
                val receiver = castStopReceiver
                clearCastNotification()
                stopPlayback(startId)
                receiver?.send(RESULT_CAST_USER_STOP, Bundle().apply {
                    putString(EXTRA_CAST_SESSION, requestedCast)
                })
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
        if (BuildConfig.NOVATUBE_PLAY) castStops.release(castSessionId)
        clearCastNotification()
        foregroundStarted = false
        releaseLocks()
        super.onDestroy()
    }

    private fun clearCastNotification() {
        castSessionId = null
        castStopReceiver = null
        castDescription = null
        castStopLabel = null
    }

    private fun stopIfUnused(startId: Int) {
        // Un ancien PendingIntent peut recréer un service sans notification.
        // Le fermer, mais ne jamais toucher au service d'une autre session.
        if (!foregroundStarted) stopSelf(startId)
    }

    private fun stopPlayback(startId: Int) {
        releaseLocks()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        foregroundStarted = false
        if (BuildConfig.NOVATUBE_PLAY) stopSelf(startId) else stopSelf()
    }

    private fun buildNotification(title: String): Notification {
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

        // Le jeton est aussi dans data : Android ne compare pas les extras
        // pour l'identité d'un PendingIntent. Une ancienne notification ne
        // doit donc jamais être mise à jour avec le jeton du nouveau Cast.
        val castId = castSessionId
        val stopIntent = Intent(this, PlaybackForegroundService::class.java).apply {
            action = if (castId != null) ACTION_STOP_CAST else ACTION_STOP
            if (castId != null) {
                data = Uri.Builder().scheme("novatube").authority("cast-stop")
                    .appendPath(castId).build()
                putExtra(EXTRA_CAST_SESSION, castId)
            }
        }
        val stopPi = PendingIntent.getService(
            this,
            if (castId != null) 2 else 1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(this, if (castId != null) CAST_CHANNEL_ID else CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(if (castId != null) {
                castDescription?.takeIf { it.isNotBlank() } ?: "Diffusion sur un écran en cours"
            } else "Lecture audio en arrière-plan")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                if (castId != null) castStopLabel?.takeIf { it.isNotBlank() } ?: "Arrêter le cast" else "Arrêter",
                stopPi,
            )
        if (contentPi != null) builder.setContentIntent(contentPi)
        return builder.build()
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (castSessionId != null) {
                if (mgr.getNotificationChannel(CAST_CHANNEL_ID) == null) {
                    val channel = NotificationChannel(
                        CAST_CHANNEL_ID, "Diffusion Cast", NotificationManager.IMPORTANCE_LOW,
                    ).apply {
                        description = "Lecture envoyée vers un écran"
                        setShowBadge(false)
                        setSound(null, null)
                    }
                    mgr.createNotificationChannel(channel)
                }
                return
            }
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID,
                    "Lecture audio",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Lecture audio en arrière-plan (mode Écouteurs)"
                    setShowBadge(false)
                    setSound(null, null)
                }
                mgr.createNotificationChannel(ch)
            }
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
