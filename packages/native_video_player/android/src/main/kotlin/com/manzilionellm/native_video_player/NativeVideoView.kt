package com.manzilionellm.native_video_player

import android.content.Context
import android.media.MediaCodecList
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.SurfaceView
import android.view.View
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

/**
 * LE cœur du correctif « son OK / image noire » + le moteur « qui ne s'arrête
 * jamais » (façon YouTube / Netflix).
 *
 * RENDU : la vidéo est dessinée dans une vraie [SurfaceView] Android pilotée
 * par Media3 (ExoPlayer). MediaCodec décode le HEVC en matériel et écrit
 * directement sur la Surface : la trame ne passe JAMAIS par une texture Flutter
 * (le chemin qui restait noir avec mpv et libVLC sur cette box).
 *
 * DÉMARRAGE RAPIDE : tampon de lecture court (≈1 s) + priorité au temps plutôt
 * qu'à la taille → la 1re image arrive le plus vite possible.
 *
 * AUTO-RECONNEXION SILENCIEUSE : si le serveur coupe / le réseau hoquette,
 * ExoPlayer ré-essaie d'abord seul (LoadErrorHandlingPolicy), et en cas
 * d'erreur fatale on RE-PREPARE automatiquement avec un back-off (1→2→4→8 s)
 * SANS rien dire à l'UI (juste « buffering »). On ne remonte une vraie erreur
 * à Dart qu'après plusieurs échecs d'affilée (filet de sécurité ultime).
 *
 * Communication avec Dart via un MethodChannel dédié (`native_video_player/<id>`).
 */
@UnstableApi
class NativeVideoView(
    context: Context,
    messenger: BinaryMessenger,
    id: Int,
) : PlatformView, MethodChannel.MethodCallHandler, Player.Listener {

    private val surfaceView = SurfaceView(context)
    private val channel = MethodChannel(messenger, "native_video_player/$id")
    private val player: ExoPlayer
    private val handler = Handler(Looper.getMainLooper())

    private var currentUrl: String? = null

    // Codec vidéo réellement présent dans le flux en cours (rempli par
    // onTracksChanged). Sert au diagnostic remonté quand le décodage échoue.
    private var currentVideoMime: String? = null

    // GARDES DE CYCLE DE VIE (anti-segfault au zap/retour rapide). Tant que
    // `isReleased` est vrai, plus AUCUN accès au player natif : un appel après
    // release() = accès à de la mémoire libérée = crash brutal du process.
    @Volatile
    private var isReleased = false

    // Reconnexion auto silencieuse.
    private var retryCount = 0
    private var pendingRetry: Runnable? = null
    private val maxSilentRetries = 8 // au-delà → on prévient Dart (reset complet)

    private val positionPump = object : Runnable {
        override fun run() {
            if (isReleased) return
            if (player.isPlaying) {
                channel.invokeMethod("position", player.currentPosition)
            }
            handler.postDelayed(this, 500)
        }
    }

    init {
        channel.setMethodCallHandler(this)

        // La SurfaceView ne doit PAS être focusable (sinon elle capte le D-pad
        // qui doit revenir au Focus Flutter) ; on garde l'écran allumé.
        surfaceView.isFocusable = false
        surfaceView.isFocusableInTouchMode = false
        surfaceView.keepScreenOn = true

        // Tampons orientés DÉMARRAGE RAPIDE + direct : on lance la lecture dès
        // ~1 s de données (bufferForPlayback), on retampe vite après coupure,
        // et on autorise jusqu'à 30 s de tampon pour absorber les hoquets.
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(2_500, 30_000, 1_000, 2_000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

        // Décodage matériel (MediaCodec) avec repli logiciel si l'init échoue.
        //
        // ANTI-CRASH MATCH (HEVC/H.265) : on REFUSE le décodage LOGICIEL des
        // codecs lourds (H.265, AV1, VP9). Sur une box faible sans décodeur
        // matériel, décoder un direct sport haute-définition en logiciel sature
        // la RAM → OOM → segfault → l'app se ferme d'un coup en plein match.
        // En ne gardant QUE les décodeurs matériels pour ces formats, si la box
        // n'en a aucun, ExoPlayer lève proprement DECODER_INIT_FAILED → on
        // affiche « Format non supporté » au lieu de crasher (cf. onPlayerError).
        // Le H.264 (et l'audio) gardent le comportement par défaut : leur
        // décodage logiciel est léger et sûr, on ne bride pas les flux courants.
        val codecSelector = object : MediaCodecSelector {
            override fun getDecoderInfos(
                mimeType: String,
                requiresSecureDecoder: Boolean,
                requiresTunnelingDecoder: Boolean,
            ): List<MediaCodecInfo> {
                val infos = MediaCodecSelector.DEFAULT
                    .getDecoderInfos(mimeType, requiresSecureDecoder, requiresTunnelingDecoder)
                if (mimeType == MimeTypes.VIDEO_H265 ||
                    mimeType == MimeTypes.VIDEO_AV1 ||
                    mimeType == MimeTypes.VIDEO_VP9
                ) {
                    val hardwareOnly = infos.filter { it.hardwareAccelerated }
                    // Aucun décodeur matériel → liste vide → échec PROPRE (pas de
                    // repli logiciel qui ferait planter le process).
                    return if (hardwareOnly.isNotEmpty()) hardwareOnly else emptyList()
                }
                return infos
            }
        }

        val renderersFactory = DefaultRenderersFactory(context)
            .setEnableDecoderFallback(true)
            .setMediaCodecSelector(codecSelector)

        // User-Agent type lecteur connu + redirections cross-protocole : des
        // panels Xtream ne servent le vrai flux qu'aux signatures connues.
        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent("VLC/3.0.20 LibVLC/3.0.20")
            .setAllowCrossProtocolRedirects(true)
            .setKeepPostFor302Redirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(15_000)

        // Politique de ré-essai réseau AGRESSIVE : on retente beaucoup avant
        // d'abandonner un chargement (le direct IPTV coupe souvent brièvement).
        val mediaSourceFactory = DefaultMediaSourceFactory(httpFactory)
            .setLoadErrorHandlingPolicy(DefaultLoadErrorHandlingPolicy(6))

        player = ExoPlayer.Builder(context, renderersFactory)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(mediaSourceFactory)
            .setHandleAudioBecomingNoisy(true)
            .build()

        player.setVideoSurfaceView(surfaceView)
        player.addListener(this)
        player.playWhenReady = true

        handler.postDelayed(positionPump, 500)
    }

    override fun getView(): View = surfaceView

    // ---- Dart → natif -------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // Après dispose(), le player natif est libéré : on ignore tout appel
        // tardif (zap pendant la fermeture) plutôt que de toucher de la mémoire
        // libérée et crasher le process.
        if (isReleased) {
            result.success(null)
            return
        }
        when (call.method) {
            "setUrl" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrEmpty()) {
                    result.error("no_url", "setUrl appelé sans url", null)
                    return
                }
                cancelRetry()
                retryCount = 0
                currentUrl = url
                currentVideoMime = null
                player.setMediaItem(MediaItem.fromUri(url))
                player.prepare()
                player.playWhenReady = true
                result.success(null)
            }
            "play" -> {
                player.play()
                result.success(null)
            }
            "pause" -> {
                player.pause()
                result.success(null)
            }
            "dispose" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    // ---- natif → Dart (Player.Listener) ------------------------------------

    override fun onPlaybackStateChanged(playbackState: Int) {
        when (playbackState) {
            Player.STATE_BUFFERING -> channel.invokeMethod("buffering", true)
            Player.STATE_READY -> {
                retryCount = 0 // lecture OK → on oublie les erreurs passées
                channel.invokeMethod("buffering", false)
            }
            Player.STATE_ENDED -> channel.invokeMethod("ended", null)
            Player.STATE_IDLE -> { /* après erreur : géré par onPlayerError */ }
        }
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        channel.invokeMethod("playing", isPlaying)
    }

    // On retient le codec vidéo réellement présent dans le flux : il sert au
    // diagnostic remonté à Dart si le décodage échoue ensuite (« codec demandé
    // vs disponible »).
    override fun onTracksChanged(tracks: Tracks) {
        for (group in tracks.groups) {
            if (group.type != C.TRACK_TYPE_VIDEO) continue
            for (i in 0 until group.length) {
                val mime = group.getTrackFormat(i).sampleMimeType
                if (mime != null) currentVideoMime = mime
            }
        }
    }

    override fun onRenderedFirstFrame() {
        retryCount = 0
        channel.invokeMethod("firstFrame", null)
    }

    override fun onPlayerError(error: PlaybackException) {
        // ERREUR DE CODEC (décodeur introuvable / format non décodable sur cet
        // appareil) : réessayer ne sert à RIEN (un codec absent ne réapparaît
        // pas). On ne boucle donc PAS en reconnexions ; on remonte tout de suite
        // une erreur « codec non supporté » à Dart, avec le diagnostic complet
        // (modèle, version Android, codec demandé vs décodeurs dispo) → l'écran
        // affiche un message clair + Réessayer au lieu d'un spinner sans fin.
        if (isCodecError(error)) {
            channel.invokeMethod("unsupportedCodec", buildDiagnostics(error))
            return
        }

        // RECONNEXION SILENCIEUSE : on ne montre PAS d'erreur au client tant
        // qu'on n'a pas épuisé les essais. On re-prépare avec un back-off.
        if (retryCount < maxSilentRetries) {
            retryCount++
            channel.invokeMethod("buffering", true)
            val delay = (1_000L * (1 shl (retryCount - 1))).coerceAtMost(8_000L)
            scheduleRetry(delay)
        } else {
            // Trop d'échecs d'affilée → on laisse Dart faire un reset complet.
            channel.invokeMethod("error", error.message)
        }
    }

    private fun scheduleRetry(delayMs: Long) {
        cancelRetry()
        val r = Runnable {
            if (isReleased) return@Runnable // vue détruite entre-temps : on n'y touche plus
            val url = currentUrl
            if (url != null) {
                player.setMediaItem(MediaItem.fromUri(url))
                player.prepare()
                player.playWhenReady = true
            } else {
                player.prepare()
            }
        }
        pendingRetry = r
        handler.postDelayed(r, delayMs)
    }

    private fun cancelRetry() {
        pendingRetry?.let { handler.removeCallbacks(it) }
        pendingRetry = null
    }

    // ---- diagnostic codec ---------------------------------------------------

    /** `true` si l'erreur vient du décodeur / d'un format non décodable. */
    private fun isCodecError(error: PlaybackException): Boolean = when (error.errorCode) {
        PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
        PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED,
        PlaybackException.ERROR_CODE_DECODING_FAILED,
        PlaybackException.ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES,
        PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED -> true
        else -> false
    }

    /** Contexte technique remonté à Dart pour comprendre POURQUOI ça plante. */
    private fun buildDiagnostics(error: PlaybackException): Map<String, Any?> = mapOf(
        "device" to "${Build.MANUFACTURER} ${Build.MODEL}",
        "android" to "${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})",
        "codec" to (currentVideoMime ?: "inconnu"),
        "hardwareDecoders" to hardwareDecodersFor(currentVideoMime),
        "errorCode" to error.errorCodeName,
        "message" to error.message,
    )

    /** Noms des décodeurs MATÉRIELS disponibles pour [mime] sur cet appareil. */
    private fun hardwareDecodersFor(mime: String?): String {
        if (mime == null) return ""
        return try {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
                .filter { !it.isEncoder && it.supportedTypes.any { t -> t.equals(mime, ignoreCase = true) } }
                .filter {
                    // API 29+ : flag fiable ; sinon on déduit du nom (les
                    // décodeurs logiciels commencent par OMX.google. / c2.android.).
                    if (Build.VERSION.SDK_INT >= 29) {
                        it.isHardwareAccelerated
                    } else {
                        !it.name.startsWith("OMX.google.") && !it.name.startsWith("c2.android.")
                    }
                }
                .joinToString(",") { it.name }
        } catch (e: Exception) {
            ""
        }
    }

    // ---- cycle de vie -------------------------------------------------------

    override fun dispose() {
        // ANTI-DOUBLE-RELEASE : Flutter peut appeler dispose() plus d'une fois
        // (recréation de PlatformView, zap rapide). Un second release() = crash.
        if (isReleased) return
        isReleased = true

        cancelRetry()
        handler.removeCallbacks(positionPump)
        try {
            player.removeListener(this)
            // On STOPPE et on DÉTACHE la SurfaceView AVANT de libérer : libérer
            // un player encore attaché à une surface en cours de démontage
            // (l'utilisateur quitte/zappe vite) provoque un segfault natif.
            player.stop()
            player.clearVideoSurface()
            player.release()
        } catch (e: Exception) {
            // Une exception pendant la libération ne doit jamais tuer le process.
        }
        channel.setMethodCallHandler(null)
    }
}
