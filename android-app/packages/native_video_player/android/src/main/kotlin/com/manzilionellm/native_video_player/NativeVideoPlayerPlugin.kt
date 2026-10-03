package com.manzilionellm.native_video_player

import android.content.Context
import android.media.AudioManager
import com.manzilionellm.native_video_player.logic.AudioFixes
import com.manzilionellm.native_video_player.logic.AudioModeGuard
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

/**
 * Point d'entrée du plugin. Flutter l'instancie et l'attache automatiquement
 * (GeneratedPluginRegistrant) après `flutter pub get`. On enregistre la
 * fabrique de PlatformView sous le type de vue "native_video_player/view"
 * — c'est le même identifiant que côté Dart.
 *
 * Le canal `native_video_player/mode_guard` sert au téléphone (lecteur mpv,
 * pas de vue ExoPlayer). Il ne fait setMode que si l'argument est vrai.
 * Faux, ou pas d'appel : le mode Android n'est pas touché.
 */
class NativeVideoPlayerPlugin : FlutterPlugin {
    private var modeChannel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        binding
            .platformViewRegistry
            .registerViewFactory(
                "native_video_player/view",
                NativeVideoViewFactory(binding.binaryMessenger),
            )
        val channel = MethodChannel(
            binding.binaryMessenger,
            "native_video_player/mode_guard",
        )
        val appContext = binding.applicationContext
        channel.setMethodCallHandler { call, result ->
            if (call.method != "restoreIfStuck") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val enabled = call.arguments == true
            AudioFixes.restoreNormalMode = enabled
            if (!enabled) {
                // Coupé : on mémorise, on n'appelle pas setMode.
                result.success(null)
                return@setMethodCallHandler
            }
            result.success(restoreAudioMode(appContext))
        }
        modeChannel = channel
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        modeChannel?.setMethodCallHandler(null)
        modeChannel = null
    }
}

/**
 * Lit le mode et, s'il est un chemin d'appel, demande MODE_NORMAL.
 * N'est appelé que lorsque l'interrupteur est allumé.
 * Aucune adresse de flux n'entre dans la phrase renvoyée.
 */
internal fun restoreAudioMode(context: Context): String {
    val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        ?: return AudioModeGuard.resultLine(before = -1, after = -1, threw = true)
    val before = try {
        am.mode
    } catch (_: RuntimeException) {
        return AudioModeGuard.resultLine(before = -1, after = -1, threw = true)
    }
    if (AudioModeGuard.plan(enabled = true, mode = before).action !=
        AudioModeGuard.Action.SET_NORMAL
    ) {
        return AudioModeGuard.lookedLine(before)
    }
    var threw = false
    try {
        am.setMode(AudioManager.MODE_NORMAL)
    } catch (_: RuntimeException) {
        threw = true
    }
    val after = if (threw) {
        before
    } else {
        try {
            am.mode
        } catch (_: RuntimeException) {
            -1
        }
    }
    return AudioModeGuard.resultLine(before, after, threw)
}
