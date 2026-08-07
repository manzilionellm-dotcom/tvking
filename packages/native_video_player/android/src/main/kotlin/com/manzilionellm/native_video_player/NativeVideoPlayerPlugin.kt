package com.manzilionellm.native_video_player

import android.app.Activity
import android.app.ActivityManager
import android.app.Application
import android.content.Context
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

    // Lecteurs en MODE TEXTURE vivants (créés par « createTexturePlayer »,
    // détruits par « disposeTexturePlayer » ou au détachement du moteur).
    // Accès main-thread uniquement (MethodChannel + détachement du moteur).
    private val texturePlayers = HashMap<Long, NativeVideoView>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        binding
            .platformViewRegistry
            .registerViewFactory(
                "native_video_player/view",
                NativeVideoViewFactory(binding.binaryMessenger),
            )
        // Canal d'INFOS APPAREIL + SERVICE du double chemin de rendu :
        //  - 'deviceInfo' : RAM totale + isLowRamDevice (garde-mémoire TV) ;
        //  - 'createTexturePlayer'/'disposeTexturePlayer' : lecteurs en mode
        //    TEXTURE (la vidéo passe par le pipeline de l'UI Flutter — le
        //    correctif « l'image ne vient pas » des box dont le compositeur
        //    rate les SurfaceView) ;
        //  - 'getRenderMode'/'setRenderMode' : chemin de rendu MÉMORISÉ pour
        //    CETTE box (SharedPreferences natives, survit aux mises à jour).
        infoChannel = MethodChannel(binding.binaryMessenger, "native_video_player/info")
        val appContext = binding.applicationContext
        val messenger = binding.binaryMessenger
        val textureRegistry = binding.textureRegistry
        val prefs = appContext.getSharedPreferences("native_video_player", Context.MODE_PRIVATE)
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
                "createTexturePlayer" -> {
                    val preview = call.argument<Boolean>("preview") == true
                    val entry = textureRegistry.createSurfaceTexture()
                    val id = entry.id()
                    // Canal « t<id> » : espace d'ids distinct des PlatformViews
                    // (les deux compteurs partent de 0 → collision sinon).
                    texturePlayers[id] = NativeVideoView(
                        appContext,
                        messenger,
                        "native_video_player/t$id",
                        preview,
                        entry,
                    )
                    result.success(mapOf("textureId" to id))
                }
                "disposeTexturePlayer" -> {
                    val id = (call.argument<Number>("textureId"))?.toLong()
                    if (id != null) texturePlayers.remove(id)?.dispose()
                    result.success(null)
                }
                "getRenderMode" -> {
                    // Défaut « texture » : la vidéo suit le pipeline de l'UI —
                    // partout où l'app s'affiche, l'image vient. Les box où la
                    // texture échouerait basculent (watchdog Dart) sur
                    // « surface » et la préférence est mémorisée ici.
                    result.success(prefs.getString("render_mode", "texture"))
                }
                "setRenderMode" -> {
                    val mode = call.argument<String>("mode")
                    if (mode == "texture" || mode == "surface") {
                        prefs.edit().putString("render_mode", mode).apply()
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        infoChannel?.setMethodCallHandler(null)
        infoChannel = null
        // Les lecteurs TEXTURE n'ont pas de PlatformView pour les libérer :
        // on les coupe ici (idempotent). Les PlatformViews, elles, sont
        // disposées par Flutter.
        for (v in texturePlayers.values) v.dispose()
        texturePlayers.clear()
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
