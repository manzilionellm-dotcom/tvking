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

package com.sevenmotion.novatube

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ResultReceiver
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import java.lang.ref.WeakReference
import java.util.concurrent.atomic.AtomicBoolean

class RecordingServiceBridge(
    messenger: BinaryMessenger,
    private val context: Context,
    engine: FlutterEngine? = null,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "RecSvcBridge"
        private const val CHANNEL = "com.manzilionellm.tvking/recording_service"
        private var playBridge: WeakReference<RecordingServiceBridge>? = null
        fun hasPlayEngine(): Boolean = playBridge?.get() != null

        fun playStopped(sessionId: String, reason: String) {
            if (!BuildConfig.NOVATUBE_PLAY) return
            try {
                playBridge?.get()?.channel?.invokeMethod(
                    "recordingStopped", mapOf("sessionId" to sessionId, "reason" to reason),
                )
            } catch (error: Exception) {
                Log.w(TAG, "Moteur Flutter déjà fermé lors de l'arrêt REC", error)
            }
        }
    }

    private val channel: MethodChannel =
        MethodChannel(messenger, CHANNEL).apply {
            setMethodCallHandler(this@RecordingServiceBridge)
        }

    init {
        if (BuildConfig.NOVATUBE_PLAY && engine != null) {
            playBridge = WeakReference(this)
            engine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
                override fun onPreEngineRestart() {
                    if (playBridge?.get() === this@RecordingServiceBridge) {
                        RecordingForegroundService.stopPlayForEngineLoss()
                    }
                }

                override fun onEngineWillDestroy() {
                    if (playBridge?.get() === this@RecordingServiceBridge) {
                        playBridge = null
                        RecordingForegroundService.stopPlayForEngineLoss()
                    }
                }
            })
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> {
                    val title = call.argument<String>("title") ?: "NOVATUBE"
                    // url + file optionnels : si fournis, le service
                    // enregistre NATIVEMENT (survit a la fermeture app).
                    val url = call.argument<String>("url")
                    val file = call.argument<String>("file")
                    if (BuildConfig.NOVATUBE_PLAY) {
                        startPlayService(title, url, file, call.argument<String>("sessionId"), result)
                    } else {
                        startService(title, url, file)
                        result.success(true)
                    }
                }
                "bytes" -> {
                    // Octets ecrits par l'enregistrement natif en cours.
                    result.success(RecordingForegroundService.bytesWritten)
                }
                "stop" -> {
                    if (BuildConfig.NOVATUBE_PLAY) {
                        RecordingForegroundService.stopPlayFromApp { result.success(true) }
                    } else {
                        stopService()
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "method ${call.method} threw: $e")
            result.error("REC_SVC_ERROR", e.message, null)
        }
    }

    private fun startPlayService(
        title: String, url: String?, file: String?, sessionId: String?,
        result: MethodChannel.Result,
    ) {
        if (sessionId.isNullOrBlank()) {
            result.success(false)
            return
        }
        val replied = AtomicBoolean(false)
        val acknowledgement = object : ResultReceiver(Handler(Looper.getMainLooper())) {
            override fun onReceiveResult(resultCode: Int, resultData: Bundle?) {
                if (replied.compareAndSet(false, true)) result.success(resultCode == 0)
            }
        }
        val intent = Intent(context, RecordingForegroundService::class.java).apply {
            action = RecordingForegroundService.ACTION_START
            putExtra(RecordingForegroundService.EXTRA_TITLE, title)
            putExtra(RecordingForegroundService.EXTRA_SESSION, sessionId)
            putExtra(RecordingForegroundService.EXTRA_START_RESULT, acknowledgement)
            if (url != null) putExtra(RecordingForegroundService.EXTRA_URL, url)
            if (file != null) putExtra(RecordingForegroundService.EXTRA_FILE, file)
        }
        try {
            ContextCompat.startForegroundService(context, intent)
        } catch (error: Exception) {
            if (replied.compareAndSet(false, true)) {
                result.error("REC_SVC_ERROR", error.message, null)
            }
        }
    }

    private fun startService(title: String, url: String?, file: String?) {
        val intent = Intent(context, RecordingForegroundService::class.java).apply {
            action = RecordingForegroundService.ACTION_START
            putExtra(RecordingForegroundService.EXTRA_TITLE, title)
            if (url != null) putExtra(RecordingForegroundService.EXTRA_URL, url)
            if (file != null) putExtra(RecordingForegroundService.EXTRA_FILE, file)
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
