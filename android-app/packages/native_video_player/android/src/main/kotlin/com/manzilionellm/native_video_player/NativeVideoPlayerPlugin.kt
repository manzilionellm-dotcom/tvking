package com.manzilionellm.native_video_player

import android.os.Handler
import android.os.Looper
import com.manzilionellm.native_video_player.ai.AiPictureEngine
import com.manzilionellm.native_video_player.logic.AiPreflightGate
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.renderer.FlutterRenderer
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener

/**
 * Point d'entrée du plugin. Flutter l'instancie et l'attache automatiquement
 * (GeneratedPluginRegistrant) après `flutter pub get`. On enregistre la
 * fabrique de PlatformView sous le type de vue "native_video_player/view"
 * — c'est le même identifiant que côté Dart.
 */
class NativeVideoPlayerPlugin : FlutterPlugin {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var startupRenderer: FlutterRenderer? = null
    private var startupListener: FlutterUiDisplayListener? = null
    private var startupUi: AiPreflightGate.UiRegistration? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopObservingFirstFrame()
        binding
            .platformViewRegistry
            .registerViewFactory(
                "native_video_player/view",
                NativeVideoViewFactory(binding.binaryMessenger),
            )

        val readiness = AiPictureEngine.get(binding.applicationContext).attachFlutterUi()
        startupUi = readiness
        // Flutter 3.47.7 fournit flutterEngine.getRenderer() comme TextureRegistry
        // dans FlutterEngineConnectionRegistry. L'interface TextureRegistry seule
        // n'expose pas la première image. Le cast sûr évite le getter de moteur
        // déprécié ; un autre registre suspend le préflight, jamais la vidéo native.
        val renderer = binding.textureRegistry as? FlutterRenderer ?: return
        val listener = object : FlutterUiDisplayListener {
            private var firstFramePosted = false
            override fun onFlutterUiDisplayed() {
                if (firstFramePosted) return
                firstFramePosted = true
                // Laisser finir TOUS les listeners du rendu (dont la trace native)
                // avant de donner du travail au GPU. Une session fermée ignore
                // ce callback si le moteur a été détaché entre-temps.
                mainHandler.post { readiness.firstFrameDisplayed() }
            }
            override fun onFlutterUiNoLongerDisplayed() = Unit
        }
        startupRenderer = renderer
        startupListener = listener
        renderer.addIsDisplayingFlutterUiListener(listener)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopObservingFirstFrame()
        // Les vues gardent leur propre cycle de vie et leurs baux de lecture.
    }

    private fun stopObservingFirstFrame() {
        startupListener?.let { startupRenderer?.removeIsDisplayingFlutterUiListener(it) }
        startupListener = null
        startupRenderer = null
        startupUi?.close()
        startupUi = null
    }
}
