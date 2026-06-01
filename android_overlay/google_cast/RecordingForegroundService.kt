// =========================================================
//  RecordingForegroundService.kt — Service Android pour
//  enregistrements en arrière-plan
// =========================================================
//  Quand l'utilisateur lance un enregistrement IPTV puis quitte
//  l'app (lit un SMS, prend un appel, etc.), Android peut tuer
//  notre process pour libérer de la mémoire — ce qui interrompt
//  l'enregistrement libmpv et donne un fichier tronqué.
//
//  Ce ForegroundService dit à Android "ne me tue pas, je fais
//  quelque chose d'important". En contrepartie il DOIT afficher
//  une notification persistante (impossible de cacher un foreground
//  service depuis Android 8.0 sans).
//
//  Cycle de vie :
//    1. Dart appelle `start(title)` → MethodChannel → on lance le
//       service avec ACTION_START + le titre du programme.
//    2. Le service appelle startForeground() + crée la notification.
//       Android garantit alors la survie du process tant que le
//       service n'a pas appelé stopForeground/stopSelf.
//    3. Dart appelle `stop()` à la fin de l'enregistrement →
//       MethodChannel → ACTION_STOP → stopForeground + stopSelf.
//
//  Pourquoi pas un plugin Flutter ?
//    - flutter_foreground_task / flutter_background : APIs lourdes,
//      isolate séparé, complexité inutile pour notre cas (un
//      simple "tiens-moi en vie").
//    - Le pattern MethodChannel custom est déjà rodé dans ce projet
//      (Cast SDK, Gallery export), même architecture.
// =========================================================

package com.manzilionellm.tvking

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

class RecordingForegroundService : Service() {

    companion object {
        private const val TAG = "RecForegroundSvc"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "recording_channel"
        private const val WAKE_LOCK_TAG = "7motion:recording_wake_lock"
        private const val WIFI_LOCK_TAG = "7motion:recording_wifi_lock"

        const val ACTION_START = "com.manzilionellm.tvking.recording.START"
        const val ACTION_STOP = "com.manzilionellm.tvking.recording.STOP"
        const val EXTRA_TITLE = "title"
    }

    /// PartialWakeLock = garde le CPU actif même quand l'écran s'éteint.
    /// CRITIQUE pour que le Dart isolate continue de tourner et que
    /// les requêtes HTTP du downloader ne soient pas suspendues quand
    /// l'utilisateur appuie HOME ou ferme l'écran.
    private var wakeLock: PowerManager.WakeLock? = null

    /// WifiLock niveau HIGH_PERF = empêche Android de mettre le WiFi
    /// en mode 'sleep' (économie d'énergie) quand l'écran s'éteint.
    /// Sans ça, en 30 s d'écran éteint, le WiFi peut être suspendu →
    /// les sockets HTTP du downloader sont fermées par le système.
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "7 MOTION"
                Log.i(TAG, "START foreground: $title")
                createChannelIfNeeded()
                startForeground(NOTIFICATION_ID, buildNotification(title))
                acquireLocks()
            }
            ACTION_STOP -> {
                Log.i(TAG, "STOP foreground")
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
                // Service redémarré par le système après un kill mémoire.
                // On ne sait plus quel titre était en cours → on s'arrête.
                Log.w(TAG, "onStartCommand sans action — stop")
                releaseLocks()
                stopSelf()
            }
        }
        // NOT_STICKY = ne pas redémarrer le service si killed. Cohérent
        // car libmpv aussi sera mort → relancer un foreground sans
        // enregistrement actif n'a aucun sens.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        // Sécurité : si le service est détruit sans ACTION_STOP propre
        // (kill par l'OS, crash, etc.), on libère les locks pour ne
        // pas laisser le tel surchauffer / vider la batterie.
        releaseLocks()
        super.onDestroy()
    }

    /// Acquiert PartialWakeLock (CPU) + WifiLock (réseau). À appeler
    /// EXACTEMENT une fois — la flag `referenceCounted = false` côté
    /// PowerManager garantit l'idempotence, mais on évite quand même
    /// les acquisitions multiples par safety.
    private fun acquireLocks() {
        try {
            if (wakeLock == null || !wakeLock!!.isHeld) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    WAKE_LOCK_TAG,
                ).apply {
                    setReferenceCounted(false)
                    acquire(12 * 60 * 60 * 1000L) // 12h max safety timeout
                }
                Log.i(TAG, "WakeLock acquired (CPU stays awake)")
            }
        } catch (e: Throwable) {
            Log.e(TAG, "WakeLock acquire failed: $e", e)
        }

        try {
            if (wifiLock == null || !wifiLock!!.isHeld) {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                // HIGH_PERF garantit pas de WiFi sleep + débit max
                // (vs FULL qui économise plus mais peut couper).
                wifiLock = wm.createWifiLock(
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                    WIFI_LOCK_TAG,
                ).apply {
                    setReferenceCounted(false)
                    acquire()
                }
                Log.i(TAG, "WifiLock acquired (WiFi stays awake)")
            }
        } catch (e: Throwable) {
            Log.e(TAG, "WifiLock acquire failed: $e", e)
        }
    }

    private fun releaseLocks() {
        try {
            wakeLock?.takeIf { it.isHeld }?.release()
            wakeLock = null
            Log.i(TAG, "WakeLock released")
        } catch (e: Throwable) {
            Log.w(TAG, "WakeLock release failed: $e")
        }
        try {
            wifiLock?.takeIf { it.isHeld }?.release()
            wifiLock = null
            Log.i(TAG, "WifiLock released")
        } catch (e: Throwable) {
            Log.w(TAG, "WifiLock release failed: $e")
        }
    }

    private fun buildNotification(title: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("Enregistrement en cours")
            .setContentText(title)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            // Notification "discrete" : pas de son, pas de vibration.
            // L'utilisateur sait qu'un enregistrement tourne sans être
            // interrompu visuellement.
            .setSilent(true)
            .setForegroundServiceBehavior(
                NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE,
            )
            .build()
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (mgr.getNotificationChannel(CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Enregistrements",
            // LOW = pas de son ni de heads-up, juste l'icône dans la
            // barre de statut. Le user n'a pas envie d'être harcelé
            // pendant son match de foot.
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Notification persistante pendant un enregistrement"
            setShowBadge(false)
        }
        mgr.createNotificationChannel(channel)
    }
}
