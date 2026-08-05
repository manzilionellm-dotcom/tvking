package com.manzilionellm.native_video_player

import android.app.Activity
import android.app.ActivityManager
import android.app.Application
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel

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

    private var infoChannel: MethodChannel? = null

    /**
     * GARDE-MÉMOIRE. Enregistré sur le CONTEXTE D'APPLICATION plutôt que dans
     * une classe Application maison : le CI régénère `android/` à chaque build
     * (`flutter create`), donc tout ce qui vit là-bas est effacé — le plugin,
     * lui, survit. Aucune ligne de manifest à patcher non plus.
     *
     * onLowMemory() ne fait rien de plus : sur les versions qui l'appellent
     * encore, onTrimMemory(TRIM_MEMORY_COMPLETE) le double systématiquement.
     */
    private val memoryCallbacks = object : ComponentCallbacks2 {
        override fun onTrimMemory(level: Int) = NativeVideoView.trimMemory(level)
        override fun onConfigurationChanged(newConfig: Configuration) {}
        @Suppress("OverridingDeprecatedMember")
        override fun onLowMemory() {}
    }

    private var appContextForCallbacks: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        binding
            .platformViewRegistry
            .registerViewFactory(
                "native_video_player/view",
                NativeVideoViewFactory(binding.binaryMessenger),
            )
        // Canal d'INFOS APPAREIL : permet à Dart d'adapter l'app aux PETITES
        // box (Fire TV Stick & co) — 'deviceInfo' renvoie la RAM totale et le
        // drapeau isLowRamDevice d'Android. Utilisé par le garde-mémoire TV.
        infoChannel = MethodChannel(binding.binaryMessenger, "native_video_player/info")
        val appContext = binding.applicationContext
        appContext.registerComponentCallbacks(memoryCallbacks)
        appContextForCallbacks = appContext
        infoChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "deviceInfo" -> {
                    val am = appContext.getSystemService(Context.ACTIVITY_SERVICE)
                        as? ActivityManager
                    val mem = ActivityManager.MemoryInfo()
                    am?.getMemoryInfo(mem)
                    result.success(
                        mapOf(
                            "totalMem" to mem.totalMem,
                            "isLowRamDevice" to (am?.isLowRamDevice == true),
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        infoChannel?.setMethodCallHandler(null)
        infoChannel = null
        appContextForCallbacks?.unregisterComponentCallbacks(memoryCallbacks)
        appContextForCallbacks = null
        // Chaque NativeVideoView gère son propre cycle de vie par ailleurs
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
