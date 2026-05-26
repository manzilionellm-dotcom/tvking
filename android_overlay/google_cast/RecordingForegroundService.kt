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
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

class RecordingForegroundService : Service() {

    companion object {
        private const val TAG = "RecForegroundSvc"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "recording_channel"

        const val ACTION_START = "com.manzilionellm.tvking.recording.START"
        const val ACTION_STOP = "com.manzilionellm.tvking.recording.STOP"
        const val EXTRA_TITLE = "title"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "7 MOTION"
                Log.i(TAG, "START foreground: $title")
                createChannelIfNeeded()
                startForeground(NOTIFICATION_ID, buildNotification(title))
            }
            ACTION_STOP -> {
                Log.i(TAG, "STOP foreground")
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
                stopSelf()
            }
        }
        // NOT_STICKY = ne pas redémarrer le service si killed. Cohérent
        // car libmpv aussi sera mort → relancer un foreground sans
        // enregistrement actif n'a aucun sens.
        return START_NOT_STICKY
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
