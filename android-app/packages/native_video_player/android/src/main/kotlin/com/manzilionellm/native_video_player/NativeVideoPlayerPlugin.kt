package com.manzilionellm.native_video_player

import android.content.Context
import android.media.AudioManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Point d'entrée du plugin. Flutter l'instancie et l'attache automatiquement
 * (GeneratedPluginRegistrant) après `flutter pub get`. On enregistre la
 * fabrique de PlatformView sous le type de vue "native_video_player/view"
 * — c'est le même identifiant que côté Dart.
 *
 * Le canal `audio_mode` sert au téléphone (lecteur mpv), qui n'a pas
 * de vue native. L'argument doit être vrai : un faux ne fait rien
 * écrire. La vue TV, elle, appelle [AudioModeApplier] elle-même.
 */
class NativeVideoPlayerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var appContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(
            binding.binaryMessenger,
            "com.manzilionellm.native_video_player/audio_mode",
        )
        channel?.setMethodCallHandler(this)
        binding
            .platformViewRegistry
            .registerViewFactory(
                "native_video_player/view",
                NativeVideoViewFactory(binding.binaryMessenger),
            )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "apply") {
            result.notImplemented()
            return
        }
        // Porte : Dart n'envoie vrai que si l'interrupteur est allumé.
        // Un faux (ou un argument absent) ne touche pas au mode.
        val enabled = call.arguments == true
        val am = appContext?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val lines = AudioModeApplier.describeAndMaybeApply(am, enabled)
        result.success(lines.joinToString("\n"))
    }
}
