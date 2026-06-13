package com.manzilionellm.native_video_player

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.SurfaceView
import android.view.View
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

/**
 * LE cœur du correctif « son OK / image noire ».
 *
 * On rend la vidéo dans une vraie [SurfaceView] Android pilotée par Media3
 * (ExoPlayer). MediaCodec décode le HEVC en matériel et écrit directement sur
 * la Surface de cette SurfaceView : la trame n'est JAMAIS routée par une
 * texture Flutter (le chemin qui restait noir avec mpv et libVLC sur cette box).
 *
 * Communication avec Dart via un MethodChannel dédié à l'instance
 * (`native_video_player/<id>`) :
 *   Dart → natif : setUrl(url), play, pause, dispose
 *   natif → Dart : buffering(bool), playing(bool), position(ms:int),
 *                  firstFrame(), ended(), error(message:String?)
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

    // Pompe de position : envoie la position courante à Dart toutes les 500 ms
    // pour alimenter le chien de garde anti-gel (position qui n'avance plus).
    private val handler = Handler(Looper.getMainLooper())
    private val positionPump = object : Runnable {
        override fun run() {
            if (player.isPlaying) {
                channel.invokeMethod("position", player.currentPosition)
            }
            handler.postDelayed(this, 500)
        }
    }

    init {
        channel.setMethodCallHandler(this)

        // La SurfaceView ne doit PAS être focusable : sinon, sur Android TV,
        // elle capterait les touches D-pad (Haut/Bas/Back) qui doivent revenir
        // au Focus Flutter (zap / quitter). On garde aussi l'écran allumé tant
        // que la vidéo est à l'écran (sinon la box éteint l'écran au bout d'un
        // moment, même en pleine lecture).
        surfaceView.isFocusable = false
        surfaceView.isFocusableInTouchMode = false
        surfaceView.keepScreenOn = true

        // Gros tampons : l'IPTV en direct supporte mal les micro-coupures
        // réseau. minBuffer 5 s, maxBuffer 30 s, démarrage à 1,5 s.
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(5_000, 30_000, 1_500, 3_000)
            .build()

        // Décodage matériel (MediaCodec) avec repli logiciel si le codec
        // matériel échoue à l'init — utile sur des box capricieuses.
        val renderersFactory = DefaultRenderersFactory(context)
            .setEnableDecoderFallback(true)

        // Beaucoup de panels Xtream filtrent sur le User-Agent et renvoient des
        // redirections cross-protocole (http→https). On imite un lecteur connu.
        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent("VLC/3.0.20 LibVLC/3.0.20")
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(15_000)

        // DefaultMediaSourceFactory choisit tout seul la source selon l'URL :
        //   .m3u8 → HlsMediaSource (module media3-exoplayer-hls)
        //   .ts   → ProgressiveMediaSource + TsExtractor (MPEG-TS brut IPTV)
        val mediaSourceFactory = DefaultMediaSourceFactory(httpFactory)

        player = ExoPlayer.Builder(context, renderersFactory)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(mediaSourceFactory)
            .build()

        player.setVideoSurfaceView(surfaceView)
        player.addListener(this)
        player.playWhenReady = true

        handler.postDelayed(positionPump, 500)
    }

    override fun getView(): View = surfaceView

    // ---- Dart → natif -------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setUrl" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrEmpty()) {
                    result.error("no_url", "setUrl appelé sans url", null)
                    return
                }
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
            Player.STATE_READY -> channel.invokeMethod("buffering", false)
            Player.STATE_ENDED -> channel.invokeMethod("ended", null)
            Player.STATE_IDLE -> { /* après une erreur : Dart relance via _recover */ }
        }
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        channel.invokeMethod("playing", isPlaying)
    }

    override fun onRenderedFirstFrame() {
        // 1re trame vidéo RÉELLEMENT dessinée → on peut masquer le logo.
        channel.invokeMethod("firstFrame", null)
    }

    override fun onPlayerError(error: PlaybackException) {
        channel.invokeMethod("error", error.message)
    }

    // ---- cycle de vie -------------------------------------------------------

    override fun dispose() {
        handler.removeCallbacks(positionPump)
        player.removeListener(this)
        player.release()
        channel.setMethodCallHandler(null)
    }
}
