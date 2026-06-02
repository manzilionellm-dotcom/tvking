// =========================================================
//  ScreenRecordService.kt — Enregistrement par CAPTURE D'ÉCRAN
// =========================================================
//  Pourquoi : sur les serveurs IPTV "1 connexion", impossible
//  d'enregistrer en ouvrant une 2e connexion HTTP pendant qu'on
//  regarde — le fournisseur éjecte une des deux → fichier vide.
//
//  Solution imblocable : on enregistre CE QUI EST AFFICHÉ À L'ÉCRAN
//  (MediaProjection), exactement comme un enregistreur d'écran. Ça
//  marche quel que soit le serveur, et SANS couper la lecture : le
//  client continue de regarder pendant que ça enregistre en fond.
//
//  Pipeline : MediaProjection → VirtualDisplay → MediaRecorder
//  (H264 + MP4). Audio : micro si la permission RECORD_AUDIO est
//  accordée, sinon vidéo seule (jamais de crash — repli automatique).
//
//  La permission de capture (popup système) est demandée côté
//  MainActivity ; ce service reçoit le `resultCode` + `data` et
//  démarre la capture dans un Foreground Service de type
//  `mediaProjection` (obligatoire depuis Android 10/14).
// =========================================================

package com.manzilionellm.tvking

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
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
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_RESULT_DATA = "resultData"
        const val EXTRA_FILE = "file"
        const val EXTRA_TITLE = "title"

        /// `true` tant qu'une capture est en cours (lu best-effort par Dart).
        @Volatile
        var isRecording = false
    }

    private var projection: MediaProjection? = null
    private var recorder: MediaRecorder? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var filePath: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "7 MOTION"
                val resultCode =
                    intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
                val data: Intent? =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(EXTRA_RESULT_DATA)
                    }
                filePath = intent.getStringExtra(EXTRA_FILE)
                createChannelIfNeeded()
                startForeground(NOTIF_ID, buildNotification(title))
                if (resultCode == Activity.RESULT_OK && data != null && filePath != null) {
                    startRecording(resultCode, data, filePath!!)
                } else {
                    Log.w(TAG, "START sans autorisation/data valides — stop")
                    stopSelf()
                }
            }
            ACTION_STOP -> {
                stopRecording()
                stopForegroundCompat()
                stopSelf()
            }
            else -> stopSelf()
        }
        // Pas de redémarrage auto : une capture d'écran n'a pas de sens
        // à reprendre toute seule (l'autorisation système serait perdue).
        return START_NOT_STICKY
    }

    private fun startRecording(resultCode: Int, data: Intent, path: String) {
        try {
            val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                as MediaProjectionManager
            projection = mpm.getMediaProjection(resultCode, data)
            if (projection == null) {
                Log.e(TAG, "MediaProjection null — abandon")
                stopSelf()
                return
            }
            // Depuis Android 14, un callback DOIT être enregistré avant
            // createVirtualDisplay. On arrête proprement si l'utilisateur
            // révoque la capture depuis le système.
            projection!!.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    Log.i(TAG, "MediaProjection.onStop (révoquée) — arrêt")
                    stopRecording()
                    stopForegroundCompat()
                    stopSelf()
                }
            }, null)

            val metrics = resources.displayMetrics
            val dpi = metrics.densityDpi
            // On borne à ~720p pour limiter le débit/CPU tout en gardant
            // le ratio de l'écran. Dimensions paires (exigé par l'encodeur).
            val maxW = 1280
            val maxH = 720
            val scale = minOf(
                1.0,
                maxW.toDouble() / metrics.widthPixels,
                maxH.toDouble() / metrics.heightPixels,
            )
            val width = ((metrics.widthPixels * scale).toInt() / 2) * 2
            val height = ((metrics.heightPixels * scale).toInt() / 2) * 2

            recorder = buildRecorder(path, width, height, withAudio = true)
            val surface = recorder!!.surface
            virtualDisplay = projection!!.createVirtualDisplay(
                "7motion-screenrec",
                width, height, dpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                surface, null, null,
            )
            recorder!!.start()
            isRecording = true
            Log.i(TAG, "capture écran démarrée ${width}x$height → $path")
        } catch (e: Throwable) {
            Log.e(TAG, "startRecording KO: $e", e)
            stopRecording()
            stopSelf()
        }
    }

    /// Construit un MediaRecorder. Si l'audio (micro) échoue (permission
    /// refusée, source indispo), on retombe AUTOMATIQUEMENT sur vidéo
    /// seule — on ne fait jamais planter l'enregistrement pour l'audio.
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
            if (audioOk) {
                rec.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            }
            rec.setVideoSize(width, height)
            rec.setVideoEncodingBitRate(6_000_000)
            rec.setVideoFrameRate(30)
            rec.prepare()
            return rec
        } catch (e: Throwable) {
            // prepare() a échoué (souvent à cause de l'audio sans permission).
            // On libère et on RETENTE en vidéo seule.
            try { rec.reset(); rec.release() } catch (_: Throwable) {}
            if (withAudio) {
                Log.w(TAG, "prepare avec audio KO ($e) — repli vidéo seule")
                return buildRecorder(path, width, height, withAudio = false)
            }
            throw e
        }
    }

    private fun stopRecording() {
        isRecording = false
        try { recorder?.stop() } catch (_: Throwable) {}
        try { recorder?.reset() } catch (_: Throwable) {}
        try { recorder?.release() } catch (_: Throwable) {}
        recorder = null
        try { virtualDisplay?.release() } catch (_: Throwable) {}
        virtualDisplay = null
        try { projection?.stop() } catch (_: Throwable) {}
        projection = null
    }

    override fun onDestroy() {
        stopRecording()
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

    private fun buildNotification(title: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("Enregistrement écran en cours")
            .setContentText(title)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
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
            description = "Notification pendant un enregistrement par capture d'écran"
            setShowBadge(false)
        }
        mgr.createNotificationChannel(channel)
    }
}
