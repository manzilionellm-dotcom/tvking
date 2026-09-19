package com.manzilionellm.tvking_miroir

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Le service au premier plan qui « tient » la capture d'écran.
 *
 * POURQUOI IL EXISTE. Depuis Android 10, une projection d'écran n'est
 * autorisée QUE si un service au premier plan tourne — et depuis
 * Android 14 il doit être typé `mediaProjection`. Ce n'est pas nous qui
 * le demandons, c'est le système : sans ce service, `getMediaProjection`
 * jette une SecurityException, point.
 *
 * IL NE CAPTURE RIEN LUI-MÊME. La projection, l'ImageReader et le JPEG
 * vivent dans [TvkingMiroirPlugin], qui a le contexte Flutter. Ce
 * service ne fait que (1) exister, (2) afficher la notification que le
 * système exige, (3) s'arrêter quand on le lui dit.
 *
 * LA NOTIFICATION EST UNE FENÊTRE DE PLUS POUR LE CLIENT. « 7 MOTION
 * partage votre écran avec le support » — sur un téléphone elle est
 * bien visible, et on la garde volontairement lisible. Même règle que
 * le bandeau rouge : ce qui rend une assistance honnête, c'est que la
 * personne VOIE.
 */
class MiroirService : Service() {

    companion object {
        private const val TAG = "MiroirService"
        const val ACTION_START = "com.manzilionellm.tvking.miroir.START"
        const val ACTION_STOP = "com.manzilionellm.tvking.miroir.STOP"
        private const val CHANNEL_ID = "seven_motion_miroir"
        private const val NOTIFICATION_ID = 7317

        /** Démarre le service au premier plan (idempotent). `false` si le
         *  système refuse — Android 12+ interdit de le lancer depuis
         *  l'arrière-plan, mais ici on part toujours d'une session
         *  d'assistance active, donc l'app est au premier plan. */
        fun start(context: Context): Boolean {
            return try {
                val i = Intent(context, MiroirService::class.java).apply { action = ACTION_START }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(i)
                } else {
                    context.startService(i)
                }
                true
            } catch (e: Throwable) {
                Log.w(TAG, "start refusé : $e")
                false
            }
        }

        fun stop(context: Context) {
            try {
                val i = Intent(context, MiroirService::class.java).apply { action = ACTION_STOP }
                context.startService(i)
            } catch (e: Throwable) {
                // Service déjà arrêté : sans conséquence.
                Log.w(TAG, "stop : $e")
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelfProprement()
                return START_NOT_STICKY
            }
            else -> {
                // `startForegroundService` exige un `startForeground()` dans
                // les 5 s, sinon Android tue l'app (ANR). On le fait tout de
                // suite, avant n'importe quoi d'autre.
                try {
                    val notif = construireNotification()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        // Le TYPE est ce qui autorise la projection sur
                        // Android 10+ ; sur 14+ il est obligatoire ET doit
                        // correspondre au manifeste.
                        startForeground(
                            NOTIFICATION_ID,
                            notif,
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
                        )
                    } else {
                        startForeground(NOTIFICATION_ID, notif)
                    }
                    Log.i(TAG, "au premier plan (type mediaProjection)")
                } catch (e: Throwable) {
                    // Permission manquante ou refus système : on ne peut
                    // pas tenir la projection. On s'arrête, et le plugin
                    // verra `getMediaProjection` échouer et le dira.
                    Log.e(TAG, "startForeground a échoué : $e")
                    stopSelfProprement()
                }
                return START_NOT_STICKY
            }
        }
    }

    private fun stopSelfProprement() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Throwable) {
        }
        stopSelf()
    }

    private fun construireNotification(): Notification {
        creerCanal()
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentTitle("7 MOTION partage votre écran")
            .setContentText("Le support voit votre écran pendant l’assistance.")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun creerCanal() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = getSystemService(NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (mgr.getNotificationChannel(CHANNEL_ID) != null) return
        val canal = NotificationChannel(
            CHANNEL_ID,
            "Assistance à distance",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Affichée pendant qu’un support voit votre écran."
            setShowBadge(false)
        }
        mgr.createNotificationChannel(canal)
    }
}
