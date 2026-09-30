package com.example.tv_king

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Activité de l'app. Le canal « zuno/voice_search » parle au
 * SpeechRecognizer Android (micro de la télécommande sur une box).
 *
 * Si le micro n'existe pas, si l'autorisation est refusée, ou si
 * la reconnaissance échoue : on répond « pas disponible ». La
 * recherche au clavier, elle, ne change pas. On ne lance aucun flux.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "zuno/voice_search"
    private var recognizer: SpeechRecognizer? = null
    private var pending: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var timeout: Runnable? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "available" -> result.success(SpeechRecognizer.isRecognitionAvailable(this))
                    "listen" -> listen(call.argument<String>("locale"), result)
                    "cancel" -> {
                        finishListen(mapOf("ok" to false, "reason" to "cancel"))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun listen(locale: String?, result: MethodChannel.Result) {
        if (pending != null) {
            result.success(mapOf("ok" to false, "reason" to "busy"))
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            result.success(mapOf("ok" to false, "reason" to "unavailable"))
            return
        }
        if (Build.VERSION.SDK_INT >= 23 &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 4101)
            result.success(mapOf("ok" to false, "reason" to "permission"))
            return
        }
        try {
            pending = result
            val engine = SpeechRecognizer.createSpeechRecognizer(this)
            recognizer = engine
            engine.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onError(error: Int) {
                    finishListen(mapOf("ok" to false, "reason" to "error"))
                }
                override fun onResults(results: Bundle?) {
                    val list = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val text = if (list.isNullOrEmpty()) "" else list[0].trim()
                    if (text.isEmpty()) {
                        finishListen(mapOf("ok" to false, "reason" to "empty"))
                    } else {
                        finishListen(mapOf("ok" to true, "text" to text))
                    }
                }
                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                if (!locale.isNullOrBlank()) {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                }
            }
            engine.startListening(intent)
            val wait = Runnable { finishListen(mapOf("ok" to false, "reason" to "timeout")) }
            timeout = wait
            mainHandler.postDelayed(wait, 8_000L)
        } catch (_: RuntimeException) {
            finishListen(mapOf("ok" to false, "reason" to "unavailable"))
        }
    }

    private fun finishListen(payload: Map<String, Any>) {
        timeout?.let { mainHandler.removeCallbacks(it) }
        timeout = null
        val waiting = pending
        pending = null
        try {
            recognizer?.destroy()
        } catch (_: RuntimeException) {
        }
        recognizer = null
        waiting?.success(payload)
    }

    override fun onDestroy() {
        finishListen(mapOf("ok" to false, "reason" to "cancel"))
        super.onDestroy()
    }
}
