// =========================================================
//  ZunoVoicePlugin.kt — micro de la télécommande
// =========================================================
//  Deux chemins, les deux optionnels :
//
//   1. L'app demande « écoute » → on ouvre l'écran de reconnaissance
//      d'Android (RecognizerIntent). S'il n'existe pas (box sans micro,
//      Fire TV sans le service), on répond unavailable. On ne demande
//      pas RECORD_AUDIO nous-mêmes : c'est cet écran qui écoute.
//
//   2. La télécommande a DÉJÀ reconnu la phrase et envoie
//      ACTION_SEARCH / VOICE_COMMAND à VoiceRelayActivity. On range
//      le texte et on le donne à Flutter. On ne touche pas au lecteur.
//
//  Toute exception est avalée : une box capricieuse ne doit pas fermer
//  Zuno, et encore moins couper une chaîne (cet appel n'est de toute
//  façon pas fait pendant la lecture — voir VoiceHotkey).
// =========================================================

package com.manzilionellm.zuno_voice

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class ZunoVoicePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.NewIntentListener {

    companion object {
        private const val TAG = "ZunoVoice"
        private const val CHANNEL = "com.manzilionellm.zuno/voice"
        private const val REQUEST = 0x7A10

        /// Phrase reçue par le micro système avant que Flutter ne soit prêt.
        @Volatile
        var pendingQuery: String? = null

        @Volatile
        private var channel: MethodChannel? = null

        /// Appelé par VoiceRelayActivity. N'échoue jamais.
        fun deliverFromIntent(intent: Intent?) {
            val text = sanitize(extractQuery(intent)) ?: return
            pendingQuery = text
            try {
                channel?.invokeMethod("onVoiceQuery", text)
            } catch (t: Throwable) {
                Log.w(TAG, "onVoiceQuery non livré (Flutter pas prêt) : $t")
            }
        }

        fun extractQuery(intent: Intent?): String? {
            if (intent == null) return null
            val direct = intent.getStringExtra(android.app.SearchManager.QUERY)
                ?: intent.getStringExtra(Intent.EXTRA_TEXT)
                ?: intent.getStringExtra("query")
            if (!direct.isNullOrBlank()) return direct
            val list = intent.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
            return list?.firstOrNull()
        }

        fun sanitize(raw: String?): String? {
            if (raw.isNullOrBlank()) return null
            val cleaned = raw.replace(Regex("[\\p{Cntrl}]"), " ").trim()
            if (cleaned.isEmpty()) return null
            return if (cleaned.length > 200) cleaned.substring(0, 200) else cleaned
        }
    }

    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null

    /// Réponse Dart encore ouverte. Une seule à la fois.
    private var pendingResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val ch = MethodChannel(binding.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler(this)
        channel = ch
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        reply(mapOf("status" to "cancelled"))
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        hook(binding)
        // Démarrage à froid : la phrase a pu arriver avant le moteur Flutter.
        deliverFromIntent(binding.activity.intent)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        unhook()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        hook(binding)
    }

    override fun onDetachedFromActivity() {
        reply(mapOf("status" to "cancelled"))
        unhook()
    }

    private fun hook(b: ActivityPluginBinding) {
        binding = b
        activity = b.activity
        b.addActivityResultListener(this)
        b.addOnNewIntentListener(this)
    }

    private fun unhook() {
        binding?.removeActivityResultListener(this)
        binding?.removeOnNewIntentListener(this)
        binding = null
        activity = null
    }

    override fun onNewIntent(intent: Intent): Boolean {
        deliverFromIntent(intent)
        return false // on ne vole pas l'intent aux autres
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "takePending" -> {
                    val q = pendingQuery
                    pendingQuery = null
                    result.success(q)
                }
                "listen" -> startListen(result)
                "availability" -> result.success(canListen())
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            Log.w(TAG, "appel ${call.method} : $t")
            result.success(mapOf("status" to "unavailable"))
        }
    }

    private fun canListen(): Boolean {
        val act = activity ?: return false
        return try {
            val probe = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            probe.resolveActivity(act.packageManager) != null ||
                SpeechRecognizer.isRecognitionAvailable(act)
        } catch (t: Throwable) {
            false
        }
    }

    private fun startListen(result: MethodChannel.Result) {
        val act = activity
        if (act == null || act.isFinishing) {
            result.success(mapOf("status" to "unavailable"))
            return
        }
        if (pendingResult != null) {
            result.success(mapOf("status" to "busy"))
            return
        }
        if (!canListen()) {
            result.success(mapOf("status" to "unavailable"))
            return
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Zuno")
            // On ne reste pas le micro ouvert si personne ne parle.
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 2500L)
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                2000L,
            )
        }
        pendingResult = result
        try {
            act.startActivityForResult(intent, REQUEST)
        } catch (t: Throwable) {
            pendingResult = null
            val status = if (t is ActivityNotFoundException) "unavailable" else "failed"
            Log.w(TAG, "reconnaissance non lancée : $t")
            result.success(mapOf("status" to status))
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) return false
        try {
            if (resultCode != Activity.RESULT_OK || data == null) {
                reply(mapOf("status" to "cancelled"))
                return true
            }
            val text = sanitize(extractQuery(data))
            if (text == null) reply(mapOf("status" to "empty"))
            else reply(mapOf("status" to "ok", "text" to text))
        } catch (t: Throwable) {
            Log.w(TAG, "résultat voix : $t")
            reply(mapOf("status" to "failed"))
        }
        return true
    }

    private fun reply(payload: Map<String, String>) {
        val r = pendingResult ?: return
        pendingResult = null
        try {
            r.success(payload)
        } catch (t: Throwable) {
            Log.w(TAG, "réponse déjà envoyée : $t")
        }
    }
}
