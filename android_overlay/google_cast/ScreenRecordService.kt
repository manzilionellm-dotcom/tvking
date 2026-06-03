// =========================================================
//  ScreenRecordService.kt — Enregistrement par CAPTURE D'ÉCRAN
//  (autorisation demandée UNE SEULE FOIS)
// =========================================================
//  Android redemande l'autorisation de capture à CHAQUE nouvelle
//  session MediaProjection. Pour ne la demander qu'UNE FOIS :
//    - on crée la MediaProjection + un VirtualDisplay UNE seule fois
//      (au 1er enregistrement, avec la popup système) ;
//    - on les GARDE en vie entre les enregistrements ;
//    - pour chaque enregistrement on branche/débranche juste un
//      MediaRecorder sur le VirtualDisplay via `setSurface()`.
//  → la popup n'apparaît plus aux enregistrements suivants.
//
//  Contrepartie : tant que la projection est active, une notification
//  persistante (et l'indicateur système de capture) restent affichés.
//  On libère tout via ACTION_RELEASE (fermeture de session).
//
//  Pipeline : MediaProjection → VirtualDisplay (persistant) →
//  MediaRecorder (par enregistrement, H264 + MP4). Audio micro
//  best-effort avec repli vidéo seule.
// =========================================================

package com.manzilionellm.tvking

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

class ScreenRecordService : Service() {

    companion object {
        private const val TAG = "ScreenRecSvc"
        private const val NOTIF_ID = 1002
        private const val CHANNEL_ID = "screen_record_channel"

        const val ACTION_START = "com.manzilionellm.tvking.screenrec.START"
        const val ACTION_STOP = "com.manzilionellm.tvking.screenrec.STOP"
        const val ACTION_RELEASE = "com.manzilionellm.tvking.screenrec.RELEASE"
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_RESULT_DATA = "resultData"
        const val EXTRA_FILE = "file"
        const val EXTRA_TITLE = "title"

        /// `true` tant qu'une projection est ACTIVE (autorisation déjà
        /// accordée). Lu par MainActivity pour savoir s'il faut
        /// re-demander la popup système (non si déjà active).
        @Volatile
        var projectionActive: Boolean = false

        /// `true` pendant qu'un enregistrement écrit réellement un fichier.
        @Volatile
        var isRecording: Boolean = false
    }

    // Persistants (durée de vie de la session de capture) :
    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var dispW = 0
    private var dispH = 0
    private var dispDpi = 0

    // Par enregistrement :
    private var recorder: MediaRecorder? = null
    private var filePath: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "BLACK7 ROYAL"
                val file = intent.getStringExtra(EXTRA_FILE)
                createChannelIfNeeded()
                startForeground(NOTIF_ID, buildNotification(title, recording = true))

                // 1re fois : on a un resultCode + data → on crée la projection.
                if (projection == null) {
                    val resultCode =
                        intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
                    val data: Intent? =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(EXTRA_RESULT_DATA)
                        }
                    if (resultCode != Activity.RESULT_OK || data == null) {
                        Log.w(TAG, "START sans projection valide — stop")
                        releaseAll()
                        stopSelf()
                        return START_NOT_STICKY
                    }
                    if (!setupProjection(resultCode, data)) {
                        releaseAll()
                        stopSelf()
                        return START_NOT_STICKY
                    }
                }

                // Démarre l'enregistrement (réutilise la projection existante).
                if (file != null) startRecording(file)
            }
            ACTION_STOP -> {
                // Arrête juste l'enregistrement en cours, GARDE la projection
                // vive pour ne pas re-demander l'autorisation au suivant.
                stopRecording()
                // On reste en foreground avec une notif "prêt".
                startForeground(NOTIF_ID, buildNotification("BLACK7 ROYAL", recording = false))
            }
            ACTION_RELEASE -> {
                releaseAll()
                stopForegroundCompat()
                stopSelf()
            }
            else -> {
                releaseAll()
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    /// Crée la MediaProjection + le VirtualDisplay persistant (surface
    /// nulle au repos). Appelé UNE fois par session.
    private fun setupProjection(resultCode: Int, data: Intent): Boolean {
        try {
            val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                as MediaProjectionManager
            projection = mpm.getMediaProjection(resultCode, data) ?: return false
            projection!!.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    Log.i(TAG, "projection révoquée par le système")
                    releaseAll()
                    stopForegroundCompat()
                    stopSelf()
                }
            }, null)

            val metrics = resources.displayMetrics
            dispDpi = metrics.densityDpi
            val maxW = 1280
            val maxH = 720
            val scale = minOf(
                1.0,
                maxW.toDouble() / metrics.widthPixels,
                maxH.toDouble() / metrics.heightPixels,
            )
            dispW = ((metrics.widthPixels * scale).toInt() / 2) * 2
            dispH = ((metrics.heightPixels * scale).toInt() / 2) * 2

            // VirtualDisplay créé SANS surface (on la branchera par
            // enregistrement). Reste vivant toute la session.
            virtualDisplay = projection!!.createVirtualDisplay(
                "black7royal-screenrec",
                dispW, dispH, dispDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                null, null, null,
            )
            projectionActive = true
            Log.i(TAG, "projection prête ${dispW}x$dispH")
            return true
        } catch (e: Throwable) {
            Log.e(TAG, "setupProjection KO: $e", e)
            return false
        }
    }

    private fun startRecording(path: String) {
        if (isRecording) return
        val vd = virtualDisplay ?: return
        try {
            filePath = path
            recorder = buildRecorder(path, dispW, dispH, withAudio = true)
            // On branche la sortie du MediaRecorder sur le VirtualDisplay.
            vd.surface = recorder!!.surface
            recorder!!.start()
            isRecording = true
            Log.i(TAG, "enregistrement démarré → $path")
        } catch (e: Throwable) {
            Log.e(TAG, "startRecording KO: $e", e)
            try { recorder?.reset(); recorder?.release() } catch (_: Throwable) {}
            recorder = null
            try { vd.surface = null } catch (_: Throwable) {}
            isRecording = false
        }
    }

    private fun stopRecording() {
        if (!isRecording && recorder == null) return
        isRecording = false
        // On débranche le MediaRecorder du VirtualDisplay AVANT de
        // l'arrêter (sinon l'encodeur peut crasher).
        try { virtualDisplay?.surface = null } catch (_: Throwable) {}
        try { recorder?.stop() } catch (_: Throwable) {}
        try { recorder?.reset() } catch (_: Throwable) {}
        try { recorder?.release() } catch (_: Throwable) {}
        recorder = null
        Log.i(TAG, "enregistrement arrêté ($filePath)")
    }

    private fun releaseAll() {
        stopRecording()
        try { virtualDisplay?.release() } catch (_: Throwable) {}
        virtualDisplay = null
        try { projection?.stop() } catch (_: Throwable) {}
        projection = null
        projectionActive = false
    }

    /// Construit un MediaRecorder. Audio micro best-effort → repli auto
    /// en vidéo seule si la permission audio manque.
    private fun buildRecorder(
        path: String,
        width: Int,
        height: Int,
        withAudio: Boolean,
    ): MediaRecorder {
        val rec = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(this)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
        try {
            var audioOk = withAudio
            if (audioOk) {
                try {
                    rec.setAudioSource(MediaRecorder.AudioSource.MIC)
                } catch (_: Throwable) {
                    audioOk = false
                }
            }
            rec.setVideoSource(MediaRecorder.VideoSource.SURFACE)
            rec.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            rec.setOutputFile(path)
            rec.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            if (audioOk) rec.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            rec.setVideoSize(width, height)
            rec.setVideoEncodingBitRate(6_000_000)
            rec.setVideoFrameRate(30)
            rec.prepare()
            return rec
        } catch (e: Throwable) {
            try { rec.reset(); rec.release() } catch (_: Throwable) {}
            if (withAudio) {
                Log.w(TAG, "prepare avec audio KO ($e) — repli vidéo seule")
                return buildRecorder(path, width, height, withAudio = false)
            }
            throw e
        }
    }

    override fun onDestroy() {
        releaseAll()
        super.onDestroy()
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun buildNotification(title: String, recording: Boolean): Notification {
        // Bouton discret "Arrêter le partage" DANS la notification : le
        // client coupe l'autorisation de capture en 1 tap, sans aller
        // dans les réglages. (Au prochain enregistrement, la popup
        // redemandera une fois — comportement attendu.)
        val releaseIntent = Intent(this, ScreenRecordService::class.java).apply {
            action = ACTION_RELEASE
        }
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val releasePi = PendingIntent.getService(this, 1, releaseIntent, piFlags)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(
                if (recording) "Enregistrement écran en cours"
                else "Capture d'écran prête",
            )
            .setContentText(title)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Arrêter le partage",
                releasePi,
            )
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
            "Enregistrement écran",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Notification pendant la capture d'écran"
            setShowBadge(false)
        }
        mgr.createNotificationChannel(channel)
    }
}
