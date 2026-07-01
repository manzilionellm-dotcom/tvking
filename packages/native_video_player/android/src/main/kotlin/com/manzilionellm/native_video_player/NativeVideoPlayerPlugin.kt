package com.manzilionellm.native_video_player

import android.app.Activity
import android.app.Application
import android.os.Bundle
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

/**
 * Point d'entrée du plugin. Flutter l'instancie et l'attache automatiquement
 * (GeneratedPluginRegistrant) après `flutter pub get`. On enregistre la
 * fabrique de PlatformView sous le type de vue "native_video_player/view"
 * — c'est le même identifiant que côté Dart.
 *
 * COUVRE-FEU AUDIO (garantie « zéro son en arrière-plan ») : le plugin écoute
 * le cycle de vie de l'ACTIVITÉ Android elle-même. Dès qu'elle est STOPPÉE
 * (Home, veille, autre app, fermeture), on met en pause TOUS les lecteurs
 * vivants ([NativeVideoView.pauseAll]). C'est le filet côté OS : il marche
 * même si l'écran Flutter courant a oublié de gérer le cycle de vie (ex.
 * multi-vue) ou si l'événement Dart arrive en retard. La reprise, elle, reste
 * une décision de l'UI Dart (reprendre / rejoindre le direct / rester en pause).
 */
class NativeVideoPlayerPlugin : FlutterPlugin, ActivityAware {

    private var activity: Activity? = null

    private val lifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityStopped(a: Activity) {
            // onStop = l'activité n'est PLUS visible (contrairement à onPause,
            // déclenché aussi par de simples dialogues système) → on coupe.
            if (a === activity) NativeVideoView.pauseAll()
        }

        override fun onActivityCreated(a: Activity, savedInstanceState: Bundle?) {}
        override fun onActivityStarted(a: Activity) {}
        override fun onActivityResumed(a: Activity) {}
        override fun onActivityPaused(a: Activity) {}
        override fun onActivitySaveInstanceState(a: Activity, outState: Bundle) {}
        override fun onActivityDestroyed(a: Activity) {}
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
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

    // ---- ActivityAware : suivi de l'activité hôte ---------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.activity.application.registerActivityLifecycleCallbacks(lifecycleCallbacks)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachFromActivity()

    override fun onDetachedFromActivity() = detachFromActivity()

    private fun detachFromActivity() {
        activity?.application?.unregisterActivityLifecycleCallbacks(lifecycleCallbacks)
        activity = null
    }
}
