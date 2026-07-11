// =========================================================
//  RecordingServiceBridge.kt — Pont Dart → Service
// =========================================================
//  Expose 2 méthodes au code Dart via MethodChannel :
//    - start(title)  → démarre RecordingForegroundService
//    - stop()        → l'arrête proprement
//
//  Les Intent sont préparées ici, le Service lui-même vit dans
//  RecordingForegroundService.kt. Séparation : Bridge = plomberie
//  Dart↔Service, Service = comportement.
// =========================================================

package com.manzilionellm.tvking

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class RecordingServiceBridge(
    messenger: BinaryMessenger,
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "RecSvcBridge"
        private const val CHANNEL = "com.manzilionellm.tvking/recording_service"
    }

    private val channel: MethodChannel =
        MethodChannel(messenger, CHANNEL).apply {
            setMethodCallHandler(this@RecordingServiceBridge)
        }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> {
                    val title = call.argument<String>("title") ?: "7 MOTION"
                    // url + file optionnels : si fournis, le service
                    // enregistre NATIVEMENT (survit a la fermeture app).
                    val url = call.argument<String>("url")
                    val file = call.argument<String>("file")
                    startService(
                        title,
                        url,
                        file,
                        // i18n : libellés localisés fournis par Dart.
                        call.argument<String>("notifTitle"),
                        call.argument<String>("channelName"),
                        call.argument<String>("channelDesc"),
                    )
                    result.success(true)
                }
                "bytes" -> {
                    // Octets ecrits par l'enregistrement natif en cours.
                    result.success(RecordingForegroundService.bytesWritten)
                }
                "stop" -> {
                    stopService()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "method ${call.method} threw: $e")
            result.error("REC_SVC_ERROR", e.message, null)
        }
    }

    private fun startService(
        title: String,
        url: String?,
        file: String?,
        notifTitle: String?,
        channelName: String?,
        channelDesc: String?,
    ) {
        val intent = Intent(context, RecordingForegroundService::class.java).apply {
            action = RecordingForegroundService.ACTION_START
            putExtra(RecordingForegroundService.EXTRA_TITLE, title)
            if (url != null) putExtra(RecordingForegroundService.EXTRA_URL, url)
            if (file != null) putExtra(RecordingForegroundService.EXTRA_FILE, file)
            if (notifTitle != null) {
                putExtra(RecordingForegroundService.EXTRA_NOTIF_TITLE, notifTitle)
            }
            if (channelName != null) {
                putExtra(RecordingForegroundService.EXTRA_CHANNEL_NAME, channelName)
            }
            if (channelDesc != null) {
                putExtra(RecordingForegroundService.EXTRA_CHANNEL_DESC, channelDesc)
            }
        }
        // Sur Android 8+ il faut startForegroundService(), pas startService().
        // ContextCompat fait le bon choix selon l'API level.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ContextCompat.startForegroundService(context, intent)
        } else {
            context.startService(intent)
        }
    }

    private fun stopService() {
        val intent = Intent(context, RecordingForegroundService::class.java).apply {
            action = RecordingForegroundService.ACTION_STOP
        }
        context.startService(intent)
    }
}
