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
import com.google.android.gms.cast.MediaStatus
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManager
import com.google.android.gms.cast.framework.SessionManagerListener
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

    /**
     * Phase 1+/G2 — Synchronisation bidirectionnelle.
     *
     * Le RemoteMediaClient.Callback est invoque par le SDK Cast a
     * chaque changement d'etat sur la TV (PLAYING / PAUSED / IDLE /
     * BUFFERING), MEME quand le declencheur est la telecommande
     * physique de la TV ou un autre sender. Sans ce callback, l'app
     * Dart ne savait jamais quand l'utilisateur pausait depuis sa
     * telecommande SHIELD -> l'UI sender affichait toujours
     * "playing" alors que la TV etait en pause. C'est exactement le
     * "l'app ment a l'utilisateur" identifie comme critique.
     *
     * On enregistre le callback :
     *   - quand la session devient active (via SessionManagerListener)
     *   - on le retire quand la session se termine (anti-leak)
     */
    private val remoteMediaCallback = object : RemoteMediaClient.Callback() {
        override fun onStatusUpdated() {
            val client = remoteMediaClient() ?: return
            emitMediaState(client)
        }
    }

    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(session: CastSession, sessionId: String) {
            attachMediaCallback()
            emitSessionEvent("started")
        }
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            attachMediaCallback()
            emitSessionEvent("resumed")
        }
        override fun onSessionEnded(session: CastSession, error: Int) {
            detachMediaCallback()
            emitSessionEvent("ended")
        }
        override fun onSessionSuspended(session: CastSession, reason: Int) {
            detachMediaCallback()
            emitSessionEvent("suspended")
        }
        override fun onSessionStarting(session: CastSession) {}
        override fun onSessionResuming(session: CastSession, sessionId: String) {}
        override fun onSessionEnding(session: CastSession) {}
        override fun onSessionStartFailed(session: CastSession, error: Int) {
            emitSessionEvent("start_failed", error)
        }
        override fun onSessionResumeFailed(session: CastSession, error: Int) {
            emitSessionEvent("resume_failed", error)
        }
    }

    init {
        // Branchement du listener sessions des le construction. Le SDK
        // est responsable de la lifecycle — pas besoin de detacher
        // manuellement, l'Activity Flutter persiste tant que l'app
        // tourne.
        sessionManager?.addSessionManagerListener(
            sessionListener,
            CastSession::class.java,
        )
        // Si une session existait deja (ex. resume apres reboot Dart
        // via setResumeSavedSession), on s'accroche tout de suite.
        if (sessionManager?.currentCastSession?.isConnected == true) {
            attachMediaCallback()
            // Et on emet un evenement immediat pour que Dart sache
            // qu'on est connecte.
            emitSessionEvent("resumed_at_boot")
        }
    }

    private fun attachMediaCallback() {
        val client = remoteMediaClient() ?: return
        try {
            client.registerCallback(remoteMediaCallback)
            // Emission immediate du state courant pour que Dart se
            // synchronise sans attendre le 1er status update.
            emitMediaState(client)
        } catch (e: Exception) {
            Log.w(TAG, "registerCallback failed: $e")
        }
    }

    private fun detachMediaCallback() {
        val client = remoteMediaClient() ?: return
        try {
            client.unregisterCallback(remoteMediaCallback)
        } catch (e: Exception) {
            Log.w(TAG, "unregisterCallback failed: $e")
        }
    }

    /**
     * Push un evenement "session.*" vers Dart via invokeMethod
     * (one-way). Dart ignore les evenements inconnus.
     */
    private fun emitSessionEvent(event: String, errorCode: Int = 0) {
        try {
            channel.invokeMethod(
                "onSessionEvent",
                mapOf("event" to event, "errorCode" to errorCode),
            )
        } catch (e: Exception) {
            Log.w(TAG, "emitSessionEvent: $e")
        }
    }

    /**
     * Push l'etat de lecture courant vers Dart. Le mapping est ce
     * que CastManager attend (cf. _onNativeMediaState dans
     * cast_manager.dart).
     */
    private fun emitMediaState(client: RemoteMediaClient) {
        try {
            val playerState = when (client.playerState) {
                MediaStatus.PLAYER_STATE_PLAYING -> "playing"
                MediaStatus.PLAYER_STATE_PAUSED -> "paused"
                MediaStatus.PLAYER_STATE_BUFFERING -> "buffering"
                MediaStatus.PLAYER_STATE_IDLE -> "idle"
                MediaStatus.PLAYER_STATE_LOADING -> "loading"
                else -> "unknown"
            }
            // idleReason distingue une fin NORMALE (FINISHED) d'un REJET
            // du recepteur (ERROR) — ex. codec/conteneur non supporte par
            // le Default Media Receiver. Sans ca, cote Dart un .ts refuse
            // ressemble a une lecture "terminee" et l'utilisateur n'a
            // aucune piste. Cf. brief cast §4.
            val idleReason = when (client.mediaStatus?.idleReason) {
                MediaStatus.IDLE_REASON_FINISHED -> "finished"
                MediaStatus.IDLE_REASON_CANCELED -> "canceled"
                MediaStatus.IDLE_REASON_INTERRUPTED -> "interrupted"
                MediaStatus.IDLE_REASON_ERROR -> "error"
                else -> "none"
            }
            channel.invokeMethod(
                "onMediaStateChanged",
                mapOf(
                    "playerState" to playerState,
                    "isPlaying" to client.isPlaying,
                    "isPaused" to client.isPaused,
                    "isBuffering" to client.isBuffering,
                    "idleReason" to idleReason,
                ),
            )
        } catch (e: Exception) {
            Log.w(TAG, "emitMediaState: $e")
        }
    }

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
        val debugOverlay = (args["debug"] as? Boolean) ?: false

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

            // Overlay debug du receiver custom : on passe {debug:true} en
            // customData. Le receiver l'active alors (sans effet sur le
            // Default Media Receiver, qui ignore customData inconnu).
            val customData = if (debugOverlay) {
                org.json.JSONObject().apply { put("debug", true) }
            } else {
                null
            }
            val mediaInfo = MediaInfo.Builder(streamUrl)
                .setStreamType(streamType)
                .setContentType(mime)
                .setMetadata(metadata)
                .apply { if (customData != null) setCustomData(customData) }
                .build()

            val loadRequest = MediaLoadRequestData.Builder()
                .setMediaInfo(mediaInfo)
                .setAutoplay(true)
                .build()

            // DIAGNOSTIC (brief cast §4.3) — trace EXACTEMENT ce qu'on
            // pousse au recepteur. C'est le point de verite : si l'URL
            // est un .ts brut en video/mp2t, le Default Media Receiver
            // (CC1AD845) ne la decode pas → ecran noir. On loggue aussi
            // le STREAM_TYPE pour verifier l'alignement LIVE/BUFFERED.
            val streamTypeName =
                if (streamType == MediaInfo.STREAM_TYPE_LIVE) "LIVE" else "BUFFERED"
            Log.i(TAG, "loadMedia → url=$streamUrl mime=$mime streamType=$streamTypeName")

            // Le resultat du load est ASYNCHRONE : client.load() renvoie
            // tout de suite, mais le recepteur peut rejeter le media
            // (codec non supporte, URL injoignable depuis la TV…)
            // quelques secondes plus tard. On surface ce verdict vers
            // Dart via un evenement de session dedie pour que le
            // diagnostic sache si la TV a ACCEPTE ou REFUSE le flux.
            client.load(loadRequest).setResultCallback { mediaChannelResult ->
                val status = mediaChannelResult.status
                if (status.isSuccess) {
                    Log.i(TAG, "receiver accepted load")
                    emitSessionEvent("load_ok")
                } else {
                    Log.e(
                        TAG,
                        "receiver REJECTED load: code=${status.statusCode} " +
                            "msg=${status.statusMessage}",
                    )
                    emitSessionEvent("load_failed", status.statusCode)
                }
            }
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "loadMedia: $e")
            result.error("LOAD_FAILED", e.message, null)
        }
    }
}
