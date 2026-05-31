// =========================================================
//  GoogleCastApi.kt — Bridge natif vers Google Cast SDK
// =========================================================
//  Implémentation Kotlin du MethodChannel "com.manzilionellm.tvking/cast"
//  que le code Dart (lib/features/cast/data/google_cast_api.dart) appelle.
//
//  Utilise les VRAIES classes du Google Cast Framework :
//    - CastContext          → singleton du SDK
//    - SessionManager       → gestion des sessions Cast
//    - CastSession          → connexion à UNE TV
//    - RemoteMediaClient    → contrôles play/pause/load/stop
//    - MediaRouteChooserDialog → dialog natif "choose your TV"
//
//  Cycle de vie typique d'un cast Netflix-style :
//    1. user tape Chromecast dans notre picker
//    2. Dart appelle showRoutePicker → on ouvre le dialog natif
//    3. user tape sa TV dans le dialog → le SDK négocie la session
//    4. Dart poll hasActiveSession() jusqu'à true
//    5. Dart appelle loadMedia(url, title) → on construit MediaInfo
//       et on appelle RemoteMediaClient.load() → la TV joue.
// =========================================================

package com.manzilionellm.tvking

import android.app.Activity
import android.content.Context
import android.util.Log
import androidx.fragment.app.FragmentActivity
import androidx.mediarouter.app.MediaRouteChooserDialog
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.SessionManager
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class GoogleCastApi(
    messenger: BinaryMessenger,
    private val activity: Activity,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "GoogleCastApi"
        private const val CHANNEL = "com.manzilionellm.tvking/cast"
    }

    private val channel: MethodChannel = MethodChannel(messenger, CHANNEL).apply {
        setMethodCallHandler(this@GoogleCastApi)
    }

    /**
     * Init lazy du Cast SDK. On wrap en try/catch parce que sur les
     * phones sans Google Play Services (Huawei récents, custom ROMs
     * sans GMS), `getSharedInstance` lève. Dans ce cas castContext
     * reste null et isCastAvailable() renvoie false côté Dart.
     */
    private val castContext: CastContext? = try {
        if (isGmsAvailable(activity)) {
            CastContext.getSharedInstance(activity)
        } else {
            Log.w(TAG, "Google Play Services indisponibles — Cast SDK désactivé")
            null
        }
    } catch (e: Exception) {
        Log.w(TAG, "Cast SDK init failed: ${e.message}")
        null
    }

    private val sessionManager: SessionManager? = castContext?.sessionManager

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isCastAvailable" -> result.success(castContext != null)
                "hasActiveSession" -> result.success(
                    sessionManager?.currentCastSession?.isConnected == true,
                )
                "showRoutePicker" -> showRoutePicker(result)
                "loadMedia" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                    loadMedia(args, result)
                }
                "play" -> {
                    remoteMediaClient()?.play()
                    result.success(null)
                }
                "pause" -> {
                    remoteMediaClient()?.pause()
                    result.success(null)
                }
                "stop" -> {
                    remoteMediaClient()?.stop()
                    result.success(null)
                }
                "disconnect" -> {
                    sessionManager?.endCurrentSession(true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "method ${call.method} threw: $e")
            result.error("CAST_ERROR", e.message, null)
        }
    }

    private fun remoteMediaClient(): RemoteMediaClient? =
        sessionManager?.currentCastSession?.remoteMediaClient

    private fun isGmsAvailable(context: Context): Boolean {
        val availability = GoogleApiAvailability.getInstance()
        return availability.isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS
    }

    /**
     * Ouvre le dialog NATIF Google Cast — celui que YouTube /
     * Netflix utilisent pour montrer les Chromecasts disponibles.
     * L'utilisateur tape une TV, le SDK négocie la session.
     */
    private fun showRoutePicker(result: MethodChannel.Result) {
        val ctx = castContext
        if (ctx == null) {
            result.error("CAST_UNAVAILABLE", "Cast SDK indisponible", null)
            return
        }
        val fragmentActivity = activity as? FragmentActivity
        if (fragmentActivity == null) {
            result.error(
                "ACTIVITY_TYPE",
                "MainActivity doit étendre FlutterFragmentActivity",
                null,
            )
            return
        }
        try {
            // ⚠️ Bug fix Android (constat diagnostic cast 2026-05-31) :
            //
            //   IllegalStateException: background can not be translucent: #0
            //
            // MainActivity Flutter herite par defaut d'un theme qui a
            // android:windowIsTranslucent=true (pour permettre des
            // transitions de demarrage propres). MediaRouteChooserDialog
            // refuse de s'afficher sur un context translucide.
            //
            // Fix : on enveloppe l'activity dans un ContextThemeWrapper
            // avec un theme opaque (Material AppCompat Dialog). Le dialog
            // utilise ce theme pour son rendu et accepte de s'ouvrir.
            // Aucune influence sur MainActivity reelle ni sur les autres
            // dialogs de l'app.
            // Theme AppCompat Light Dialog — opaque, guaranti dispo
            // (androidx.appcompat est deja une dep transitive du Cast SDK).
            // Si on voulait pousser plus loin, on pourrait declarer
            // un theme custom dans styles.xml aux couleurs 7 MOTION,
            // mais le rendering AppCompat suffit pour la liste des TVs.
            val themedContext = androidx.appcompat.view.ContextThemeWrapper(
                fragmentActivity,
                androidx.appcompat.R.style.Theme_AppCompat_Light_Dialog_Alert,
            )
            val dialog = MediaRouteChooserDialog(themedContext)
            dialog.routeSelector = ctx.mergedSelector!!
            dialog.show()
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "showRoutePicker: $e")
            result.error("PICKER_FAILED", e.message, null)
        }
    }

    /**
     * Charge un flux sur la TV connectée via RemoteMediaClient.
     * Le SDK Cast natif s'occupe de tout : transport sécurisé vers
     * la TV, MediaInfo, autoplay, etc.
     */
    private fun loadMedia(args: Map<String, Any?>, result: MethodChannel.Result) {
        val streamUrl = args["streamUrl"] as? String
        val title = args["title"] as? String ?: "7 MOTION"
        val mime = args["mime"] as? String ?: "video/mp2t"
        val imageUrl = args["imageUrl"] as? String
        val subtitle = args["subtitle"] as? String

        if (streamUrl.isNullOrBlank()) {
            result.error("INVALID_ARGS", "streamUrl manquant ou vide", null)
            return
        }

        val client = remoteMediaClient()
        if (client == null) {
            result.success(false)
            return
        }

        try {
            val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_TV_SHOW).apply {
                putString(MediaMetadata.KEY_TITLE, title)
                if (!subtitle.isNullOrBlank()) {
                    putString(MediaMetadata.KEY_SUBTITLE, subtitle)
                }
                if (!imageUrl.isNullOrBlank()) {
                    addImage(com.google.android.gms.common.images.WebImage(android.net.Uri.parse(imageUrl)))
                }
            }

            // LIVE pour IPTV — pas de barre de progression, pas de seek.
            val streamType = if (mime.contains("mpegurl") || mime.contains("mp2t")) {
                MediaInfo.STREAM_TYPE_LIVE
            } else {
                MediaInfo.STREAM_TYPE_BUFFERED
            }

            val mediaInfo = MediaInfo.Builder(streamUrl)
                .setStreamType(streamType)
                .setContentType(mime)
                .setMetadata(metadata)
                .build()

            val loadRequest = MediaLoadRequestData.Builder()
                .setMediaInfo(mediaInfo)
                .setAutoplay(true)
                .build()

            client.load(loadRequest)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "loadMedia: $e")
            result.error("LOAD_FAILED", e.message, null)
        }
    }
}
