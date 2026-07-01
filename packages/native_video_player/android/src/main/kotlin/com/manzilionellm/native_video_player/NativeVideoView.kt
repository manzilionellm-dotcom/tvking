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
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.AdaptiveTrackSelection
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
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

    companion object {
        // Toutes les vues VIVANTES (accès main-thread uniquement : création /
        // dispose des PlatformViews et callbacks de cycle de vie arrivent tous
        // sur le main thread). Sert au « couvre-feu » ci-dessous.
        private val instances = mutableSetOf<NativeVideoView>()

        /**
         * Coupe TOUS les lecteurs — appelé par le plugin quand l'ACTIVITÉ passe
         * en arrière-plan (Home / veille / autre app). GARANTIE NATIVE « zéro
         * son en arrière-plan » : elle ne dépend PAS de l'écran Flutter affiché
         * (le lecteur plein écran gère déjà son cycle de vie côté Dart, mais la
         * multi-vue ou tout futur écran pouvait laisser le son tourner). La
         * pause remonte à Dart via onIsPlayingChanged → l'UI reste cohérente.
         */
        fun pauseAll() {
            for (v in instances) v.player.pause()
        }
    }

    private val surfaceView = SurfaceView(context)
    private val channel = MethodChannel(messenger, "native_video_player/$id")
    private val player: ExoPlayer
    private val handler = Handler(Looper.getMainLooper())

    private var currentUrl: String? = null

    // Reconnexion auto silencieuse. Peu d'essais et RAPIDES : au-delà, on rend
    // la main à Dart qui, lui, sait basculer sur une VARIANTE d'URL du même
    // flux (.ts ⇄ .m3u8) — rester à marteler une URL morte retarde la bascule.
    private var retryCount = 0
    private var pendingRetry: Runnable? = null
    private val maxSilentRetries = 3

    private val positionPump = object : Runnable {
        override fun run() {
            if (player.isPlaying) {
                channel.invokeMethod("position", player.currentPosition)
            }
            handler.postDelayed(this, 500)
        }
    }

    init {
        instances.add(this)
        channel.setMethodCallHandler(this)

        // La SurfaceView ne doit PAS être focusable (sinon elle capte le D-pad
        // qui doit revenir au Focus Flutter) ; on garde l'écran allumé.
        surfaceView.isFocusable = false
        surfaceView.isFocusableInTouchMode = false
        surfaceView.keepScreenOn = true

        // Tampons anti-coupure MAIS PRUDENTS EN MÉMOIRE (box à RAM limitée).
        // ⚠️ LEÇON : un buffer trop gros (90 s / 64 Mo) faisait planter les box
        // par MANQUE DE MÉMOIRE (OOM → l'OS tue l'app → boucle de redémarrage).
        // On garde donc une résilience RÉELLE mais un plafond mémoire SÛR :
        //   • minBuffer = 15 s, maxBuffer = 40 s : de l'avance pour absorber les
        //     hoquets, sans exploser la RAM (avant : 30 s → on améliore un peu).
        //   • bufferForPlayback = 2 s : 1re image rapide.
        //   • bufferForPlaybackAfterRebuffer = 4 s : après une coupure, on attend
        //     4 s de réserve avant de repartir (on ne se re-bloque pas aussitôt).
        // Plafond MÉMOIRE à 24 Mo (setTargetBufferBytes + prioritize=false) :
        // c'est LA garde anti-OOM. Sur une connexion lente (débit bas), 24 Mo =
        // déjà beaucoup de secondes d'avance ; sur un flux haut débit, on borne
        // la RAM → plus de crash sur box.
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(15_000, 40_000, 2_000, 4_000)
            .setTargetBufferBytes(24 * 1024 * 1024)
            .setPrioritizeTimeOverSizeThresholds(false)
            .build()

        // Décodage matériel (MediaCodec) avec repli logiciel si l'init échoue.
        val renderersFactory = DefaultRenderersFactory(context)
            .setEnableDecoderFallback(true)

        // User-Agent type lecteur connu + redirections cross-protocole : des
        // panels Xtream ne servent le vrai flux qu'aux signatures connues.
        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent("VLC/3.0.20 LibVLC/3.0.20")
            .setAllowCrossProtocolRedirects(true)
            .setKeepPostFor302Redirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(15_000)

        // DefaultDataSource délègue le http(s) au httpFactory ci-dessus (donc
        // MÊME User-Agent / redirections pour le DIRECT) MAIS sait AUSSI ouvrir
        // les sources LOCALES (file://, content://). Indispensable pour LIRE un
        // enregistrement .ts DANS l'app : avant, la lecture était déléguée à un
        // lecteur externe (open_filex) qui, sur cette box, tombait sur la Galerie
        // → FATAL EXCEPTION (gallery3d) qui tuait l'app. Le direct reste 100 %
        // inchangé (http passe toujours par le même httpFactory).
        val dataSourceFactory = DefaultDataSource.Factory(context, httpFactory)

        // Politique de ré-essai réseau : 3 tentatives par chargement (délais
        // croissants ≈ 0/1/2 s). Assez pour absorber un hoquet bref, assez
        // COURT pour qu'une URL vraiment morte remonte vite en erreur → la
        // couche Dart bascule alors sur la variante .m3u8/.ts du même flux
        // (failover silencieux) au lieu d'attendre ~15 s de retries inutiles.
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)
            .setLoadErrorHandlingPolicy(DefaultLoadErrorHandlingPolicy(3))

        // ADAPTATION AUTOMATIQUE DE LA QUALITÉ (« façon Netflix »), réglée pour
        // les réseaux FAIBLES / INSTABLES (ex. Afrique). Ne s'applique QUE si le
        // flux propose PLUSIEURS qualités (HLS/DASH multi-débit) — un flux à
        // débit unique ne peut pas être allégé (c'est le fournisseur qui décide).
        //   • bandwidthFraction 0.6 : on n'utilise que 60 % du débit MESURÉ pour
        //     choisir la qualité → marge de sécurité, beaucoup moins de coupures.
        //   • on DESCEND vite quand la connexion faiblit (maxDurationFor
        //     QualityDecrease court) et on REMONTE prudemment (minDurationFor
        //     QualityIncrease long) → pas de yo-yo, image stable.
        // Aucun plafond fixe : sur bonne connexion, la HD revient toute seule.
        val trackSelector = DefaultTrackSelector(
            context,
            AdaptiveTrackSelection.Factory(
                15_000, // minDurationForQualityIncreaseMs (remonte prudemment)
                18_000, // maxDurationForQualityDecreaseMs (descend vite)
                20_000, // minDurationToRetainAfterDiscardMs
                0.6f,   // bandwidthFraction (marge de sécurité réseau)
            ),
        )

        player = ExoPlayer.Builder(context, renderersFactory)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(mediaSourceFactory)
            .setTrackSelector(trackSelector)
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
        when (call.method) {
            "setUrl" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrEmpty()) {
                    result.error("no_url", "setUrl appelé sans url", null)
                    return
                }
                cancelRetry()
                // On ne remet le budget de reconnexion silencieuse à zéro QUE
                // pour une VRAIE nouvelle chaîne (URL différente). Si Dart
                // ré-ouvre la MÊME URL (recover sur flux gelé), on CONSERVE le
                // compteur → après maxSilentRetries on remonte enfin l'erreur à
                // Dart au lieu de relancer 8 essais à l'infini (boucle CPU/réseau).
                if (url != currentUrl) retryCount = 0
                currentUrl = url
                player.setMediaItem(buildMediaItem(url))
                player.prepare()
                player.playWhenReady = true
                result.success(null)
            }
            "play" -> {
                player.play()
                result.success(null)
            }
            "setVolume" -> {
                // Multi-vue : on coupe le son des tuiles inactives (volume 0) et
                // on ne laisse le son QUE sur la tuile active (volume 1).
                val v = (call.argument<Double>("volume") ?: 1.0).toFloat()
                player.volume = v.coerceIn(0f, 1f)
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

    override fun onRenderedFirstFrame() {
        retryCount = 0
        channel.invokeMethod("firstFrame", null)
    }

    override fun onPlayerError(error: PlaybackException) {
        // SORTIE DE LA FENÊTRE LIVE (réseau trop lent, le serveur a « avancé »
        // sans nous) : ce n'est PAS une panne — on ressaute au direct
        // IMMÉDIATEMENT, sans compter d'essai ni montrer quoi que ce soit.
        // C'est la recommandation officielle Media3 pour les flux live.
        if (error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
            channel.invokeMethod("buffering", true)
            scheduleRetry(0L)
            return
        }
        // RECONNEXION SILENCIEUSE : on ne montre PAS d'erreur au client tant
        // qu'on n'a pas épuisé les essais. Back-off court (0,5 → 1 → 2 s) :
        // un flux flaky repart vite, un flux mort passe vite la main à Dart
        // (qui bascule sur la variante d'URL du même flux).
        if (retryCount < maxSilentRetries) {
            retryCount++
            channel.invokeMethod("buffering", true)
            val delay = (500L * (1 shl (retryCount - 1))).coerceAtMost(3_000L)
            scheduleRetry(delay)
        } else {
            // Trop d'échecs d'affilée → on laisse Dart faire un reset complet.
            channel.invokeMethod("error", error.message)
        }
    }

    /**
     * Construit l'élément à lire. Pour un DIRECT (HLS live), on demande à jouer
     * ~15 s DERRIÈRE le bord du direct (targetOffset). Ce petit retard crée une
     * réserve qui absorbe les coupures réseau sans geler l'image. On autorise
     * une accélération imperceptible (1.03×) pour rattraper doucement le direct
     * sans à-coup. Sur un flux NON-live (VOD / .ts local), cette configuration
     * est tout simplement ignorée par Media3.
     */
    private fun buildMediaItem(url: String): MediaItem =
        MediaItem.Builder()
            .setUri(url)
            .setLiveConfiguration(
                MediaItem.LiveConfiguration.Builder()
                    .setTargetOffsetMs(15_000)
                    .setMinOffsetMs(8_000)
                    .setMaxPlaybackSpeed(1.03f)
                    .build(),
            )
            .build()

    private fun scheduleRetry(delayMs: Long) {
        cancelRetry()
        val r = Runnable {
            val url = currentUrl
            if (url != null) {
                player.setMediaItem(buildMediaItem(url))
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

    // ---- cycle de vie -------------------------------------------------------

    override fun dispose() {
        instances.remove(this)
        cancelRetry()
        handler.removeCallbacks(positionPump)
        player.removeListener(this)
        player.release()
        channel.setMethodCallHandler(null)
    }
}
