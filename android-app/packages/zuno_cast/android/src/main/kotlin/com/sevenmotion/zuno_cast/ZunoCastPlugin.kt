package com.sevenmotion.zuno_cast

import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.content.pm.PackageManager
import android.os.Build
import com.manzilionellm.tvking.GoogleCastApi
import com.manzilionellm.tvking.MulticastLockBridge
import com.manzilionellm.tvking.PlaybackForegroundService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel

/** Le téléphone émet ; une box reste un lecteur. Aucun scan au démarrage. */
class ZunoCastPlugin : FlutterPlugin, ActivityAware {
    companion object {
        private const val PIP_CHANNEL = "com.manzilionellm.tvking/pip"
    }

    private var binding: FlutterPlugin.FlutterPluginBinding? = null
    private var capability: MethodChannel? = null
    private var playbackChannel: MethodChannel? = null
    private var cast: GoogleCastApi? = null
    private var multicast: MulticastLockBridge? = null
    private var handset = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        val context = binding.applicationContext
        val mode = context.getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
        handset = mode.currentModeType != Configuration.UI_MODE_TYPE_TELEVISION &&
            !context.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        capability = MethodChannel(binding.binaryMessenger, "com.sevenmotion.zuno/cast-capability").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "isHandset") result.success(handset) else result.notImplemented()
            }
        }
        if (handset) {
            // Ce pont appartient au moteur, pas à l'activité. Rotation,
            // Home et écran éteint ne doivent pas arrêter le relais réseau.
            playbackChannel = MethodChannel(binding.binaryMessenger, PIP_CHANNEL).apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "startBackgroundAudio" -> {
                            val intent = Intent(context, PlaybackForegroundService::class.java).apply {
                                action = PlaybackForegroundService.ACTION_START
                                putExtra(PlaybackForegroundService.EXTRA_TITLE,
                                    call.argument<String>("title") ?: "Zuno")
                                for (extra in listOf(
                                    PlaybackForegroundService.EXTRA_BODY,
                                    PlaybackForegroundService.EXTRA_STOP_LABEL,
                                    PlaybackForegroundService.EXTRA_CHANNEL_NAME,
                                    PlaybackForegroundService.EXTRA_CHANNEL_DESC,
                                )) {
                                    call.argument<String>(extra)?.let { putExtra(extra, it) }
                                }
                            }
                            try {
                                val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                    context.startForegroundService(intent)
                                } else {
                                    context.startService(intent)
                                }
                                // Le Dart de 7 MOTION distingue un refus de
                                // démarrage d'un vrai maintien demandé à l'OS.
                                result.success(started != null)
                            } catch (_: Exception) {
                                result.success(false)
                            }
                        }
                        "stopBackgroundAudio" -> {
                            stopPlaybackService(context)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
        }
    }
    override fun onAttachedToActivity(activity: ActivityPluginBinding) {
        val engine = binding ?: return
        if (!handset) return
        // Le bridge gère lui-même les téléphones sans Google Play Services.
        cast = GoogleCastApi(engine.binaryMessenger, activity.activity)
        multicast = MulticastLockBridge(engine.binaryMessenger, engine.applicationContext)
    }
    private fun detachActivity() {
        cast?.dispose(); cast = null
        multicast?.dispose(); multicast = null
    }
    override fun onDetachedFromActivityForConfigChanges() = detachActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detachActivity()
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detachActivity()
        if (playbackChannel != null) {
            playbackChannel?.setMethodCallHandler(null)
            playbackChannel = null
            stopPlaybackService(binding.applicationContext)
        }
        capability?.setMethodCallHandler(null); capability = null
        this.binding = null
    }

    private fun stopPlaybackService(context: Context) {
        // stopService est idempotent et ne crée jamais un nouveau service
        // en arrière-plan. onDestroy du service partagé libère les verrous.
        try {
            context.stopService(Intent(context, PlaybackForegroundService::class.java))
        } catch (_: Exception) {
            // Le moteur peut être détaché alors que l'OS a déjà tout arrêté.
        }
    }
}
