package com.manzilionellm.native_video_player

import android.app.ActivityManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.os.Handler
import android.os.Looper
import android.view.SurfaceView
import android.view.View
import android.widget.FrameLayout
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.SubtitleView
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.AdaptiveTrackSelection
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter
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
    private val appContext: Context,
    messenger: BinaryMessenger,
    id: Int,
    // Mode APERÇU (vignette de l'accueil / d'En direct) : tampons réduits —
    // voir le bloc LoadControl dans init{}.
    private val preview: Boolean = false,
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

    private val surfaceView = SurfaceView(appContext)

    // Rendu des SOUS-TITRES : la vidéo est dessinée par MediaCodec directement
    // sur la Surface (elle ne passe pas par Flutter), donc les sous-titres
    // doivent être dessinés par une vue Android PAR-DESSUS. On empile
    // SurfaceView + SubtitleView dans un FrameLayout.
    private val subtitleView = SubtitleView(appContext)
    private val container = FrameLayout(appContext)

    private val channel = MethodChannel(messenger, "native_video_player/$id")
    private val player: ExoPlayer
    private val handler = Handler(Looper.getMainLooper())

    private var currentUrl: String? = null

    // Signature de lecteur CUSTOM pour la chaîne courante (diagnostic
    // multi-UA côté Dart, cf. video_player_screen.dart / tv_player_screen.dart
    // "ça marche sur IBO, pas chez nous" — beaucoup de fournisseurs
    // whitelistent une signature précise). `null` = User-Agent par défaut du
    // httpFactory construit dans init{}. Mémorisée pour que les reconnexions
    // SILENCIEUSES (scheduleRetry) gardent la signature qui a marché.
    private var currentUserAgent: String? = null

    // Dernier état des pistes connu (pour appliquer une sélection par index).
    private var currentTracks: Tracks = Tracks.EMPTY

    // Reconnexion auto silencieuse. Peu d'essais et RAPIDES : au-delà, on rend
    // la main à Dart qui, lui, sait basculer sur une VARIANTE d'URL du même
    // flux (.ts ⇄ .m3u8) — rester à marteler une URL morte retarde la bascule.
    private var retryCount = 0
    private var pendingRetry: Runnable? = null
    private val maxSilentRetries = 3

    // REPRISE RÉSEAU INSTANTANÉE (façon Netflix) : pendant qu'un retry
    // attend son back-off (jusqu'à 8 s), si Android annonce que le réseau
    // par défaut est REVENU (Wi-Fi raccroché, 4G rétablie), on relance
    // IMMÉDIATEMENT au lieu de finir d'attendre. Sur une box dont le Wi-Fi
    // hoquette, c'est plusieurs secondes d'écran figé économisées à chaque
    // micro-coupure. Permission requise : ACCESS_NETWORK_STATE (normale,
    // déclarée dans le manifest du plugin).
    private val connectivityManager =
        appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
    private var networkCallbackRegistered = false
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            // Callback hors thread principal → on repasse par le handler.
            handler.post {
                val retry = pendingRetry ?: return@post
                handler.removeCallbacks(retry)
                pendingRetry = null
                retry.run()
            }
        }
    }

    /** Enregistre le callback réseau (API 24+ ; best-effort, jamais bloquant). */
    private fun registerNetworkCallback() {
        if (networkCallbackRegistered) return
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.N) return
        try {
            connectivityManager?.registerDefaultNetworkCallback(networkCallback)
            networkCallbackRegistered = true
        } catch (_: Exception) {
            // SecurityException (permission absente) / TooManyRequests :
            // on vit sans — le back-off existant reste le filet.
        }
    }

    private fun unregisterNetworkCallback() {
        if (!networkCallbackRegistered) return
        networkCallbackRegistered = false
        try {
            connectivityManager?.unregisterNetworkCallback(networkCallback)
        } catch (_: Exception) {
        }
    }

    // Dernière durée émise à Dart — évite de spammer le canal quand elle ne
    // change pas (elle est stable pour un film, TIME_UNSET pour un direct).
    private var lastDurationMs = -1L

    private val positionPump = object : Runnable {
        override fun run() {
            if (player.isPlaying) {
                channel.invokeMethod("position", player.currentPosition)
            }
            // DURÉE : connue uniquement pour un contenu SEEKABLE (film / VOD /
            // catch-up). Un DIRECT renvoie TIME_UNSET → on émet 0 (= pas de
            // barre, pas de seek côté UI). On n'émet que sur changement.
            val rawDur = player.duration // ms, ou C.TIME_UNSET
            val durMs = if (rawDur != androidx.media3.common.C.TIME_UNSET && rawDur > 0) rawDur else 0L
            if (durMs != lastDurationMs) {
                lastDurationMs = durMs
                channel.invokeMethod("duration", durMs)
            }
            // AVANCE CHARGÉE (façon YouTube) : jusqu'où le tampon est déjà
            // rempli EN AVANT de la lecture. Sert à dessiner la « ligne grise »
            // sur la barre de progression VOD. Émis uniquement pour un média
            // seekable (film) — inutile sur un direct.
            if (durMs > 0) {
                channel.invokeMethod("buffered", player.bufferedPosition)
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
        // ADAPTATION À LA BOX : on lit la RAM réelle de l'appareil et on
        // dimensionne les tampons en conséquence — une box « low RAM »
        // (isLowRamDevice, ou ≤ 1,2 Go de RAM totale) reçoit des tampons plus
        // courts et un plafond mémoire plus bas : moins de pression GC, zap
        // plus réactif, zéro OOM ; une box confortable garde la résilience
        // maximale. Dans les deux cas :
        //   • bufferForPlayback = 1,5 s : 1re image rapide au zap.
        //   • bufferForPlaybackAfterRebuffer : petite réserve avant de
        //     repartir après une coupure (on ne se re-bloque pas aussitôt).
        // Le plafond octets (setTargetBufferBytes + prioritize=false) reste
        // LA garde anti-OOM.
        val activityManager =
            appContext.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        activityManager?.getMemoryInfo(memInfo)
        // STABILITÉ « façon Netflix » : le rebuffering en boucle (« ça tourne »)
        // vient surtout d'un tampon TROP PETIT. Ancien réglage : ≤1,2 Go était
        // classé « faible RAM » → tampon ~10 s (12 Mo) sur des box 1-2 Go
        // COURANTES → sur lien faible, la réserve se vide → rebuffer sans fin.
        // Correctif : le seuil « faible RAM » descend à ~800 Mo (seules les
        // VRAIES petites box gardent le profil serré), et TOUS les tampons
        // grossissent. Le plafond OCTETS (setTargetBufferBytes + prioritize=
        // false) reste LA garde anti-OOM, donc aucune régression mémoire.
        val lowRam = (activityManager?.isLowRamDevice == true) ||
            (memInfo.totalMem in 1..(800L * 1024 * 1024))
        val loadControl = if (preview) {
            // APERÇU (vignette) : tampon MINIMAL — 1re image rapide, ~8 Mo de
            // plafond. Un aperçu muet n'a pas besoin d'absorber 50 s de
            // coupure ; par contre 2 aperçus + l'UI sur une box 1 Go faisaient
            // sortir l'app en OOM (retour terrain « l'app s'est fermée »).
            DefaultLoadControl.Builder()
                // bufferForPlayback (3e param) = 500 ms : l'aperçu démarre dès
                // qu'un demi-tampon est prêt (vignette quasi instantanée).
                .setBufferDurationsMs(8_000, 15_000, 500, 2_000)
                .setTargetBufferBytes(8 * 1024 * 1024)
                .setPrioritizeTimeOverSizeThresholds(false)
                .build()
        } else if (lowRam) {
            // Vraies petites box (≤800 Mo) : profil serré mais un peu plus de
            // réserve qu'avant (15 s / 18 Mo) pour absorber les micro-coupures.
            DefaultLoadControl.Builder()
                // bufferForPlayback 500 ms (au lieu de 1500) : 1re image ~1 s
                // plus tôt au zap. La réserve totale (15-30 s) et le délai
                // après-coupure (4 s) restent inchangés → aucune régression de
                // stabilité, seul le démarrage à froid accélère.
                .setBufferDurationsMs(15_000, 30_000, 500, 4_000)
                .setTargetBufferBytes(18 * 1024 * 1024)
                .setPrioritizeTimeOverSizeThresholds(false)
                .build()
        } else {
            // Box normales (>800 Mo, dont les 1-2 Go) : tampon GÉNÉREUX (~20 s
            // cible, jusqu'à 50 s) pour tenir un lien instable sans rebuffer —
            // et après une coupure on attend 5 s de réserve avant de repartir
            // (on ne se re-bloque pas aussitôt, comme Netflix).
            DefaultLoadControl.Builder()
                // bufferForPlayback 500 ms (au lieu de 2000) : c'était le plus
                // gros délai FIXE avant la 1re image au zap. On démarre dès
                // 0,5 s de réserve ; la cible (20 s) et surtout le délai
                // APRÈS-COUPURE (5 s, 4e param) restent identiques → on garde
                // la stabilité « à la Netflix » sur lien instable.
                .setBufferDurationsMs(20_000, 50_000, 500, 5_000)
                .setTargetBufferBytes(32 * 1024 * 1024)
                .setPrioritizeTimeOverSizeThresholds(false)
                .build()
        }

        // Décodage matériel (MediaCodec) avec repli logiciel si l'init échoue.
        val renderersFactory = DefaultRenderersFactory(appContext)
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
        val dataSourceFactory = DefaultDataSource.Factory(appContext, httpFactory)

        // Politique de ré-essai réseau : 3 tentatives par chargement (délais
        // croissants ≈ 0/1/2 s). Assez pour absorber un hoquet bref, assez
        // COURT pour qu'une URL vraiment morte remonte vite en erreur → la
        // couche Dart bascule alors sur la variante .m3u8/.ts du même flux
        // (failover silencieux) au lieu d'attendre ~15 s de retries inutiles.
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)
            .setLoadErrorHandlingPolicy(DefaultLoadErrorHandlingPolicy(3))

        // ADAPTATION AUTOMATIQUE DE LA QUALITÉ. Ne s'applique QUE si le flux
        // propose PLUSIEURS qualités (HLS/DASH multi-débit, VOD) — un flux à
        // débit unique (.ts live habituel) ne peut PAS être amélioré : c'est
        // le fournisseur qui décide de la netteté.
        //   • NETTETÉ PRIORISÉE (demande client) : bandwidthFraction 0.80 (au
        //     lieu de 0.60) → on exploite 80 % du débit mesuré pour choisir la
        //     MEILLEURE qualité que la connexion supporte. On garde une marge
        //     de 20 % contre les coupures — sharpness maximale SANS yo-yo.
        //   • on MONTE plus vite en HD (minDurationForQualityIncrease 4 s au
        //     lieu de 10) : sur un flux multi-débit, l'image était « molle »
        //     ~10 s avant de passer en HD — désormais ~4 s. On descend
        //     toujours vite si ça faiblit (maxDurationForQualityDecrease 18 s).
        // Aucun plafond de résolution : la HD/4K de la source est utilisée
        // jusqu'à la définition réelle de l'écran (viewport display par défaut).
        val trackSelector = DefaultTrackSelector(
            appContext,
            AdaptiveTrackSelection.Factory(
                4_000,  // minDurationForQualityIncreaseMs (monte vite en HD)
                18_000, // maxDurationForQualityDecreaseMs (descend vite)
                20_000, // minDurationToRetainAfterDiscardMs
                0.80f,  // bandwidthFraction (netteté priorisée, marge 20 %)
            ),
        )

        // ESTIMATION DE DÉBIT INITIALE HAUTE (8 Mb/s). Sans elle, ExoPlayer
        // démarre un flux multi-débit sur son estimation par défaut (~1 Mb/s)
        // → il choisit d'abord la PLUS BASSE qualité (image molle) puis monte.
        // En partant haut, on ouvre directement en HD ; la mesure réelle
        // corrige en quelques secondes. Sans effet sur un flux à débit unique
        // (le .ts live habituel), donc aucun risque de saturation.
        val bandwidthMeter = DefaultBandwidthMeter.Builder(appContext)
            .setInitialBitrateEstimate(8_000_000L)
            .build()

        player = ExoPlayer.Builder(appContext, renderersFactory)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(mediaSourceFactory)
            .setTrackSelector(trackSelector)
            .setBandwidthMeter(bandwidthMeter)
            .setHandleAudioBecomingNoisy(true)
            .build()

        player.setVideoSurfaceView(surfaceView)
        player.addListener(this)
        player.playWhenReady = true
        // ZAP FLUIDE : garde les décodeurs MediaCodec « chauds » entre deux
        // préparations (setUrl au zap, retry silencieux). Sans ça, ExoPlayer
        // relâche le codec matériel à chaque stop/prepare et la box (surtout
        // à faible RAM) paie ~300-800 ms de ré-initialisation par chaîne.
        player.setForegroundMode(true)

        // Reprise réseau instantanée : actif toute la vie du lecteur (un
        // callback réseau enregistré est quasi gratuit ; il ne FAIT quelque
        // chose que si un retry attend son back-off).
        registerNetworkCallback()

        // SOUS-TITRES DÉSACTIVÉS par défaut (comportement historique : rien
        // n'était rendu). L'utilisateur les active via le bouton Sous-titres.
        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
            .build()

        // Empilement vidéo + sous-titres (style par défaut de l'appareil).
        val match = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        )
        container.addView(surfaceView, match)
        subtitleView.setUserDefaultStyle()
        subtitleView.setUserDefaultTextSize()
        container.addView(subtitleView, match)

        handler.postDelayed(positionPump, 500)
    }

    override fun getView(): View = container

    // ---- Dart → natif -------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setUrl" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrEmpty()) {
                    result.error("no_url", "setUrl appelé sans url", null)
                    return
                }
                // Signature de lecteur CUSTOM (diagnostic multi-UA côté Dart,
                // cf. currentUserAgent) — absente/vide = User-Agent par défaut.
                val ua = call.argument<String>("userAgent")?.takeIf { it.isNotBlank() }
                cancelRetry()
                // On ne remet le budget de reconnexion silencieuse à zéro QUE
                // pour une VRAIE nouvelle chaîne (URL différente). Si Dart
                // ré-ouvre la MÊME URL (recover sur flux gelé), on CONSERVE le
                // compteur → après maxSilentRetries on remonte enfin l'erreur à
                // Dart au lieu de relancer 8 essais à l'infini (boucle CPU/réseau).
                if (url != currentUrl) retryCount = 0
                currentUrl = url
                currentUserAgent = ua
                setMedia(url, ua)
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
            "seekTo" -> {
                // Film / VOD / catch-up : va à une position absolue (ms). Borné
                // à [0, duration] côté Dart ; ici on re-borne par prudence. Sans
                // effet utile sur un direct non-seekable (ExoPlayer l'ignore).
                val ms = (call.argument<Int>("ms") ?: 0).toLong()
                val safe = ms.coerceAtLeast(0L)
                player.seekTo(safe)
                result.success(null)
            }
            "setAudioTrack" -> {
                // Sélectionne la N-ième piste AUDIO (index dans la liste envoyée
                // à Dart par onTracksChanged).
                selectTrack(androidx.media3.common.C.TRACK_TYPE_AUDIO,
                    call.argument<Int>("index") ?: 0)
                result.success(null)
            }
            "setSubtitleTrack" -> {
                // index >= 0 → active la N-ième piste TEXTE ; -1 → sous-titres OFF.
                val idx = call.argument<Int>("index") ?: -1
                if (idx < 0) {
                    player.trackSelectionParameters =
                        player.trackSelectionParameters.buildUpon()
                            .setTrackTypeDisabled(
                                androidx.media3.common.C.TRACK_TYPE_TEXT, true)
                            .clearOverridesOfType(
                                androidx.media3.common.C.TRACK_TYPE_TEXT)
                            .build()
                    subtitleView.setCues(null)
                } else {
                    selectTrack(androidx.media3.common.C.TRACK_TYPE_TEXT, idx)
                }
                result.success(null)
            }
            "dispose" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    /// Applique une sélection de piste par (type, index d'affichage). L'index
    /// correspond à l'ordre des groupes de CE type dans onTracksChanged — le
    /// même ordre que la liste montrée côté Dart.
    private fun selectTrack(type: Int, index: Int) {
        var i = 0
        for (group in currentTracks.groups) {
            if (group.type != type) continue
            if (i == index) {
                player.trackSelectionParameters =
                    player.trackSelectionParameters.buildUpon()
                        .setTrackTypeDisabled(type, false)
                        .setOverrideForType(
                            TrackSelectionOverride(group.mediaTrackGroup, 0),
                        )
                        .build()
                return
            }
            i++
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

    // Taille réelle de la vidéo → Dart peut proposer les formats d'image
    // (Auto = ratio réel, 16:9, 4:3, Étiré) au lieu du 16:9 figé.
    override fun onVideoSizeChanged(videoSize: VideoSize) {
        if (videoSize.width > 0 && videoSize.height > 0) {
            channel.invokeMethod(
                "videoSize",
                mapOf("width" to videoSize.width, "height" to videoSize.height),
            )
        }
    }

    // Pistes disponibles (audio + sous-titres) → Dart affiche les boutons
    // Audio / Sous-titres avec les langues. Envoyé à chaque changement de
    // média et à chaque (dé)sélection.
    override fun onTracksChanged(tracks: Tracks) {
        currentTracks = tracks
        val audio = ArrayList<Map<String, Any>>()
        val text = ArrayList<Map<String, Any>>()
        for (group in tracks.groups) {
            if (group.length == 0) continue
            val f = group.getTrackFormat(0)
            val label = f.label
                ?: f.language?.uppercase()
                ?: ""
            when (group.type) {
                C.TRACK_TYPE_AUDIO -> audio.add(
                    mapOf(
                        "label" to (label.ifEmpty { "Piste ${audio.size + 1}" }),
                        // Code langue BRUT (fr/eng/…) : Dart le traduit en
                        // libellé localisé (« Français ») dans la feuille
                        // « Pistes » du lecteur TV.
                        "language" to (f.language ?: ""),
                        "selected" to group.isSelected,
                    ),
                )
                C.TRACK_TYPE_TEXT -> text.add(
                    mapOf(
                        "label" to (label.ifEmpty { "Sous-titres ${text.size + 1}" }),
                        "language" to (f.language ?: ""),
                        "selected" to group.isSelected,
                    ),
                )
            }
        }
        channel.invokeMethod("tracks", mapOf("audio" to audio, "text" to text))
    }

    // Sous-titres décodés par ExoPlayer → dessinés par la SubtitleView.
    override fun onCues(cueGroup: CueGroup) {
        subtitleView.setCues(cueGroup.cues)
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
            // Diagnostic terrain : avant, seul `error.message` (souvent vague,
            // ex. "Source error") remontait — impossible de distinguer un
            // codec non supporté d'un timeout réseau sans lire le logcat de
            // la box. `errorCodeName` (constante stable Media3, ex.
            // "ERROR_CODE_IO_BAD_HTTP_STATUS") + le message de la CAUSE racine
            // (souvent plus parlant que le message de façade) donnent au
            // sender de quoi journaliser un diagnostic exploitable à distance.
            channel.invokeMethod(
                "error",
                mapOf(
                    "message" to error.message,
                    "errorCode" to error.errorCode,
                    "errorCodeName" to error.errorCodeName,
                    "causeMessage" to error.cause?.message,
                ),
            )
        }
    }

    /**
     * Construit l'élément à lire. Pour un DIRECT (HLS live), on demande à jouer
     * ~8 s DERRIÈRE le bord du direct (targetOffset). Ce retard crée une réserve
     * qui absorbe les coupures réseau sans geler l'image. On visait 15 s avant :
     * plus proche du direct (8 s) = moins de latence « télécommande → image »
     * et démarrage plus rapide, tout en gardant une réserve confortable (le
     * LoadControl garde déjà 20-50 s en tampon). On autorise une accélération
     * imperceptible (1.03×) pour rattraper doucement le direct sans à-coup. Sur
     * un flux NON-live (VOD / .ts local), cette configuration est ignorée par
     * Media3.
     */
    private fun buildMediaItem(url: String): MediaItem =
        MediaItem.Builder()
            .setUri(url)
            .setLiveConfiguration(
                MediaItem.LiveConfiguration.Builder()
                    .setTargetOffsetMs(8_000)
                    .setMinOffsetMs(4_000)
                    .setMaxPlaybackSpeed(1.03f)
                    .build(),
            )
            .build()

    /**
     * Construit un [DefaultMediaSourceFactory] à la volée avec la signature
     * [userAgent] demandée. Le httpFactory par défaut (construit dans init{})
     * reste inchangé pour tout appel SANS UA custom — ce factory-ci ne sert
     * QUE le temps d'une lecture avec signature alternative (diagnostic
     * multi-UA "ça marche sur IBO, pas chez nous").
     */
    private fun mediaSourceFactoryFor(userAgent: String): DefaultMediaSourceFactory {
        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setAllowCrossProtocolRedirects(true)
            .setKeepPostFor302Redirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(15_000)
        val dataSourceFactory = DefaultDataSource.Factory(appContext, httpFactory)
        return DefaultMediaSourceFactory(dataSourceFactory)
            .setLoadErrorHandlingPolicy(DefaultLoadErrorHandlingPolicy(6))
    }

    /** Charge [url] avec la signature [userAgent] (`null` = défaut de l'init). */
    private fun setMedia(url: String, userAgent: String?) {
        if (userAgent != null) {
            player.setMediaSource(
                mediaSourceFactoryFor(userAgent).createMediaSource(buildMediaItem(url)),
            )
        } else {
            player.setMediaItem(buildMediaItem(url))
        }
        player.prepare()
        player.playWhenReady = true
    }

    private fun scheduleRetry(delayMs: Long) {
        cancelRetry()
        val r = object : Runnable {
            override fun run() {
                // Un retry ne s'exécute qu'UNE fois : consommé ici, qu'il
                // arrive par le back-off ou par le retour du réseau
                // (networkCallback) — jamais les deux.
                if (pendingRetry === this) pendingRetry = null
                val url = currentUrl
                if (url != null) {
                    // Garde la MÊME signature que la session courante (celle
                    // qui a marché si un diagnostic multi-UA a déjà eu lieu).
                    setMedia(url, currentUserAgent)
                } else {
                    player.prepare()
                }
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
        unregisterNetworkCallback()
        instances.remove(this)
        cancelRetry()
        handler.removeCallbacks(positionPump)
        player.removeListener(this)
        player.setForegroundMode(false) // relâche les codecs avant release
        player.release()
        channel.setMethodCallHandler(null)
    }
}
