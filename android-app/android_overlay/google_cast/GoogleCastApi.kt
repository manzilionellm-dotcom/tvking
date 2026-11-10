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
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.fragment.app.FragmentActivity
import androidx.mediarouter.app.MediaRouteChooserDialog
import androidx.mediarouter.media.MediaRouter
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

    private val mainHandler = Handler(Looper.getMainLooper())
    // Une bascule receiver annule ses propres timers, jamais l'attente STOP.
    private val stopHandler = Handler(Looper.getMainLooper())
    private var pendingStopResult: MethodChannel.Result? = null

    // Les commandes et rappels SDK passent par le thread principal. Chaque
    // nouveau chargement invalide les résultats de la chaîne précédente ; un
    // arrêt fait de même, même si le SDK répond après la commande stop.
    private var loadGeneration = 0L
    private var receiverSwitchGeneration = 0L
    private var disposed = false
    private var awaitingLoadResult = false
    private var activeLoadId: String? = null

    /**
     * Bascule de receiver EN COURS (CAST_HANDOFF §6.2) : on a nous-mêmes
     * demandé la fin de la session (changement d'App ID custom ⇄ Default) et
     * on va re-sélectionner la même TV. Tant que ce flag est vrai,
     * onSessionEnded émet "receiver_switching" au lieu de "ended" pour que le
     * CastManager Dart ne détruise pas son état de cast en plein
     * établissement. Remis à false quand la nouvelle session démarre (ou par
     * le filet de sécurité 15 s si la reconnexion n'aboutit jamais).
     */
    @Volatile private var switchingReceiver = false

    /** Route (TV) à re-sélectionner dès que l'ancienne session est fermée. */
    private var pendingSwitchRoute: MediaRouter.RouteInfo? = null

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
    private var callbackClient: RemoteMediaClient? = null
    private var remoteMediaCallback: RemoteMediaClient.Callback? = null
    private var observedSession: CastSession? = null

    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(session: CastSession, sessionId: String) {
            if (disposed || !observeSession(session)) return
            cancelReceiverSwitch()
            attachMediaCallback()
            emitSessionEvent("started")
        }
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            if (disposed || !observeSession(session)) return
            cancelReceiverSwitch()
            attachMediaCallback()
            emitSessionEvent("resumed")
        }
        override fun onSessionEnded(session: CastSession, error: Int) {
            if (disposed || observedSession !== session) return
            detachMediaCallback()
            if (switchingReceiver) {
                // Fin PILOTÉE par setReceiverApplicationId : la route vient
                // d'être libérée → on re-sélectionne la même TV pour rouvrir
                // une session sur le NOUVEAU receiver, sans repasser par le
                // picker. Dart traite "receiver_switching" comme un no-op.
                emitSessionEvent("receiver_switching")
                val route = pendingSwitchRoute
                pendingSwitchRoute = null
                if (route != null) {
                    val generation = receiverSwitchGeneration
                    mainHandler.postDelayed({
                        // Stop, déconnexion ou nouvelle bascule ont pu arriver
                        // pendant les 400 ms. Cette ancienne route ne doit plus
                        // rouvrir une TV, même si le rappel était déjà en file.
                        if (disposed || !switchingReceiver ||
                            generation != receiverSwitchGeneration) return@postDelayed
                        try {
                            MediaRouter.getInstance(activity).selectRoute(route)
                        } catch (e: Exception) {
                            Log.w(TAG, "re-select route après switch receiver: $e")
                        }
                    }, 400)
                }
            } else {
                emitSessionEvent("ended")
            }
        }
        override fun onSessionSuspended(session: CastSession, reason: Int) {
            if (disposed || observedSession !== session) return
            detachMediaCallback()
            emitSessionEvent("suspended")
        }
        override fun onSessionStarting(session: CastSession) {}
        override fun onSessionResuming(session: CastSession, sessionId: String) {}
        override fun onSessionEnding(session: CastSession) {}
        override fun onSessionStartFailed(session: CastSession, error: Int) {
            val current = sessionManager?.currentCastSession
            // Une ancienne tentative ne peut plus faire échouer la TV qui
            // l'a remplacée. Sans session courante, l'échec reste légitime :
            // un démarrage peut échouer avant onSessionStarted.
            if (disposed || (current != null && current !== session)) return
            cancelReceiverSwitch()
            emitSessionEvent("start_failed", error)
        }
        override fun onSessionResumeFailed(session: CastSession, error: Int) {
            val current = sessionManager?.currentCastSession
            if (disposed || (current != null && current !== session)) return
            cancelReceiverSwitch()
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
            observedSession = sessionManager.currentCastSession
            attachMediaCallback()
            // Et on emet un evenement immediat pour que Dart sache
            // qu'on est connecte.
            emitSessionEvent("resumed_at_boot")
        }
    }

    /**
     * Adaptateur du plugin Zuno : l'activité peut être détachée sans arrêter
     * le récepteur. Les commandes Cast ci-dessous restent celles de 7 MOTION.
     * Retirer les listeners et les rappels différés évite qu'une ancienne
     * activité resélectionne une route après sa destruction.
     */
    fun dispose() {
        disposed = true
        invalidateLoad()
        cancelReceiverSwitch()
        detachMediaCallback()
        sessionManager?.removeSessionManagerListener(sessionListener, CastSession::class.java)
        channel.setMethodCallHandler(null)
        observedSession = null
    }

    private fun observeSession(session: CastSession): Boolean {
        // Le SDK peut finir de notifier une ancienne TV après le début de
        // la nouvelle. Un callback de l'ancienne ne doit ni voler sa place,
        // ni désabonner le client média qui appartient à la nouvelle TV.
        val current = sessionManager?.currentCastSession
        if (current != null && current !== session) return false
        observedSession = session
        return true
    }

    /** Annule seulement une reconnexion différée, pas la session déjà active. */
    private fun cancelReceiverSwitch() {
        receiverSwitchGeneration++
        mainHandler.removeCallbacksAndMessages(null)
        switchingReceiver = false
        pendingSwitchRoute = null
    }

    private fun invalidateLoad(): Long {
        pendingStopResult?.let {
            finishStop(it, "STOP_SUPERSEDED", "Arrêt remplacé par une commande plus récente")
        }
        awaitingLoadResult = false
        activeLoadId = null
        return ++loadGeneration
    }

    private fun attachMediaCallback() {
        if (disposed) return
        detachMediaCallback()
        val client = remoteMediaClient() ?: return
        val generation = loadGeneration
        // Identité immuable du LOAD qui a créé ce callback. Un événement
        // déjà envoyé sur le canal ne doit pas être attribué au zap suivant.
        val loadId = activeLoadId
        val callback = object : RemoteMediaClient.Callback() {
            override fun onStatusUpdated() {
                // Un callback déjà placé en file peut survivre à unregister.
                // Il reste lié à son client et au chargement qui l'a créé.
                if (disposed || generation != loadGeneration ||
                    awaitingLoadResult || remoteMediaClient() !== client) return
                emitMediaState(client, loadId)
            }
        }
        callbackClient = client
        remoteMediaCallback = callback
        try {
            client.registerCallback(callback)
            // Emission immediate du state courant pour que Dart se
            // synchronise sans attendre le 1er status update.
            // Pendant un load, cet état appartient encore à l'ancienne
            // chaîne ; on attend l'acceptation du chargement courant.
            if (!awaitingLoadResult) emitMediaState(client, loadId)
        } catch (e: Exception) {
            Log.w(TAG, "registerCallback failed: $e")
        }
    }

    private fun detachMediaCallback() {
        // Après un changement de TV, currentCastSession peut déjà désigner le
        // nouveau client. C'est bien l'ancien qu'il faut désabonner.
        val client = callbackClient
        val callback = remoteMediaCallback
        callbackClient = null
        remoteMediaCallback = null
        if (client == null || callback == null) return
        try {
            client.unregisterCallback(callback)
        } catch (e: Exception) {
            Log.w(TAG, "unregisterCallback failed: $e")
        }
    }

    /**
     * Push un evenement "session.*" vers Dart via invokeMethod
     * (one-way). Dart ignore les evenements inconnus.
     */
    private fun emitSessionEvent(event: String, errorCode: Int = 0, loadId: String? = null) {
        if (disposed) return
        try {
            channel.invokeMethod(
                "onSessionEvent",
                mapOf("event" to event, "errorCode" to errorCode, "loadId" to loadId),
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
    private fun emitMediaState(client: RemoteMediaClient, loadId: String?) {
        if (disposed) return
        try {
            // C'est l'URL réellement décrite par le statut SDK, pas celle
            // demandée au dernier LOAD. Dart compare les deux avant de croire
            // PLAYING : le receiver peut encore décrire l'ancien média.
            // Ce champ privé du canal n'est jamais écrit dans les logs.
            val contentId = client.mediaInfo?.contentId
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
                    "loadId" to loadId,
                    "contentId" to contentId,
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
                "setReceiverApplicationId" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                    setReceiverApplicationId(args["appId"] as? String, result)
                }
                "currentReceiverApplicationId" -> result.success(
                    sessionManager?.currentCastSession
                        ?.takeIf { it.isConnected }
                        ?.applicationMetadata?.applicationId,
                )
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
                "stop" -> stopMedia(result)
                "disconnect" -> {
                    invalidateLoad()
                    cancelReceiverSwitch()
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

    /** Répond une fois : un ancien ACK ne peut terminer un nouveau STOP. */
    private fun finishStop(result: MethodChannel.Result, code: String? = null, message: String? = null) {
        if (pendingStopResult !== result) return
        pendingStopResult = null
        stopHandler.removeCallbacksAndMessages(null)
        if (code == null) result.success(null) else result.error(code, message, null)
    }

    /** Le repli fournisseur attend l'ACK réel du receiver, pas l'envoi local. */
    private fun stopMedia(result: MethodChannel.Result) {
        val generation = invalidateLoad()
        cancelReceiverSwitch()
        val client = remoteMediaClient()
        if (client == null) {
            // Déjà déconnecté : aucune lecture distante à arrêter.
            result.success(null)
            return
        }
        pendingStopResult = result
        stopHandler.postDelayed({
            if (pendingStopResult !== result) return@postDelayed
            if (disposed || generation != loadGeneration || remoteMediaClient() !== client) {
                finishStop(result, "STOP_SUPERSEDED", "Session Cast remplacée pendant l'arrêt")
            } else {
                finishStop(result, "STOP_TIMEOUT", "Confirmation d'arrêt Cast non reçue")
            }
        }, 5_000)
        try {
            client.stop().setResultCallback { mediaChannelResult ->
                if (pendingStopResult !== result) return@setResultCallback
                if (disposed || generation != loadGeneration || remoteMediaClient() !== client) {
                    finishStop(result, "STOP_SUPERSEDED", "Session Cast remplacée pendant l'arrêt")
                } else if (mediaChannelResult.status.isSuccess) {
                    finishStop(result)
                } else {
                    finishStop(result, "STOP_FAILED", "Arrêt refusé par le receiver Cast")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "stopMedia: ${e.javaClass.simpleName}")
            finishStop(result, "STOP_FAILED", "Arrêt Cast impossible")
        }
    }

    /**
     * Bascule dynamique du receiver (CAST_HANDOFF §6.2) : custom `5BDFD969`
     * pour le chemin cast_proxy (mpegts.js décode le TS sur la TV), Default
     * `CC1AD845` pour le relais HLS du téléphone (la page custom HTTPS ne
     * peut pas fetch un relais HTTP — mixed content).
     *
     * Le SDK termine la session courante quand l'App ID change
     * (CastContext.setReceiverApplicationId). Dans ce cas on mémorise la
     * route sélectionnée AVANT le changement et onSessionEnded la
     * re-sélectionne → nouvelle session sur la même TV avec le nouveau
     * receiver, sans repasser par le picker.
     *
     * Répond : "ok" (déjà bon / rien à fermer), "switching" (session fermée,
     * reconnexion auto en cours), "unavailable" (SDK absent ou échec).
     */
    private fun setReceiverApplicationId(appId: String?, result: MethodChannel.Result) {
        if (appId.isNullOrBlank()) {
            result.error("INVALID_ARGS", "appId manquant ou vide", null)
            return
        }
        val ctx = castContext
        if (ctx == null) {
            result.success("unavailable")
            return
        }
        try {
            val session = sessionManager?.currentCastSession
            val connected = session?.isConnected == true
            val currentId = session?.applicationMetadata?.applicationId
            if (connected && currentId == appId) {
                result.success("ok")
                return
            }
            // Une nouvelle stratégie remplace l'ancienne, y compris ses
            // timers et ses résultats de chargement encore en vol.
            invalidateLoad()
            cancelReceiverSwitch()
            val router = MediaRouter.getInstance(activity)
            val route = router.selectedRoute
            val willSwitch = connected && !route.isDefault
            if (willSwitch) {
                // Cette commande ferme précisément la session courante. Même
                // si son callback de reprise n'est pas encore arrivé, sa fin
                // reste légitime pour lancer le repli différé de 400 ms.
                observedSession = session
                switchingReceiver = true
                pendingSwitchRoute = route
                val generation = receiverSwitchGeneration
                // Filet de sécurité : si la reconnexion n'aboutit jamais, on
                // rétablit la sémantique normale de "ended" après 15 s.
                mainHandler.postDelayed({
                    if (!disposed && generation == receiverSwitchGeneration) {
                        cancelReceiverSwitch()
                    }
                }, 15_000)
            }
            ctx.setReceiverApplicationId(appId)
            Log.i(TAG, "receiver app id → $appId (willSwitch=$willSwitch)")
            result.success(if (willSwitch) "switching" else "ok")
        } catch (e: Throwable) {
            // Throwable (et pas Exception) : couvre aussi un NoSuchMethodError
            // si un vieux play-services-cast-framework traîne sur l'appareil.
            cancelReceiverSwitch()
            Log.e(TAG, "setReceiverApplicationId: $e")
            result.success("unavailable")
        }
    }

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
        val generation = invalidateLoad()
        val loadId = args["loadId"] as? String
        activeLoadId = loadId
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

        awaitingLoadResult = true
        attachMediaCallback()

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

            // Diagnostic du format réellement transmis, sans l'URL : celle-ci
            // peut contenir des identifiants de playlist ou un jeton signé.
            // Le MIME et le type LIVE/BUFFERED suffisent ici à vérifier le
            // contrat avec le receiver sans exposer ces secrets dans logcat.
            val streamTypeName =
                if (streamType == MediaInfo.STREAM_TYPE_LIVE) "LIVE" else "BUFFERED"
            Log.i(TAG, "loadMedia → mime=$mime streamType=$streamTypeName")

            // Le resultat du load est ASYNCHRONE : client.load() renvoie
            // tout de suite, mais le recepteur peut rejeter le media
            // (codec non supporte, URL injoignable depuis la TV…)
            // quelques secondes plus tard. On surface ce verdict vers
            // Dart via un evenement de session dedie pour que le
            // diagnostic sache si la TV a ACCEPTE ou REFUSE le flux.
            client.load(loadRequest).setResultCallback { mediaChannelResult ->
                // Un ancien refus ne doit pas faire échouer la nouvelle
                // chaîne. L'identité du client couvre aussi le changement de
                // TV/session, et dispose interdit tout retour vers l'ancien
                // moteur Flutter après le détachement de son activité.
                if (disposed || generation != loadGeneration ||
                    remoteMediaClient() !== client) return@setResultCallback
                awaitingLoadResult = false
                val status = mediaChannelResult.status
                if (status.isSuccess) {
                    Log.i(TAG, "receiver accepted load")
                    emitSessionEvent("load_ok", loadId = loadId)
                    // Le statut a pu changer avant le callback de résultat.
                    // On publie alors son état actuel, sans perdre ce signal.
                    emitMediaState(client, loadId)
                } else {
                    Log.e(
                        TAG,
                        "receiver REJECTED load: code=${status.statusCode}",
                    )
                    emitSessionEvent("load_failed", status.statusCode, loadId)
                }
            }
            result.success(true)
        } catch (e: Exception) {
            if (generation == loadGeneration) awaitingLoadResult = false
            // Une exception SDK peut recopier l'URL en clair. Son type reste
            // utile au diagnostic ; le contenu de son message reste privé.
            Log.e(TAG, "loadMedia: ${e.javaClass.simpleName}")
            result.error("LOAD_FAILED", "Chargement Cast impossible", null)
        }
    }
}
