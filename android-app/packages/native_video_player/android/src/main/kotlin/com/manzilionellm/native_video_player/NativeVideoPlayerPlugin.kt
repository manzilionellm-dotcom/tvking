package com.manzilionellm.native_video_player

import com.manzilionellm.native_video_player.ai.AiPictureEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * Point d'entrée du plugin. Flutter l'instancie et l'attache automatiquement
 * (GeneratedPluginRegistrant) après `flutter pub get`. On enregistre la
 * fabrique de PlatformView sous le type de vue "native_video_player/view"
 * — c'est le même identifiant que côté Dart.
 */
class NativeVideoPlayerPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Mesures locales pendant l'accueil, avant tout prepare vidéo. Le
        // moteur annule ce travail dès qu'un lecteur prend son bail : une
        // première chaîne n'attend jamais la fin du benchmark.
        AiPictureEngine.get(binding.applicationContext).startPreflight()
        binding
            .platformViewRegistry
            .registerViewFactory(
                "native_video_player/view",
                NativeVideoViewFactory(binding.binaryMessenger),
            )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Rien à libérer : chaque NativeVideoView gère son propre cycle de vie
        // (dispose() appelé par Flutter quand la PlatformView est retirée).
    }
}
