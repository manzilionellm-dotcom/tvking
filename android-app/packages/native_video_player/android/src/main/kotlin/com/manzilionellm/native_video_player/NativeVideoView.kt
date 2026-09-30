package com.manzilionellm.native_video_player

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.SurfaceView
import android.view.View
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.decoder.ffmpeg.FfmpegAudioRenderer
import androidx.media3.decoder.ffmpeg.FfmpegLibrary
import androidx.media3.exoplayer.DefaultLivePlaybackSpeedControl
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlaybackException
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.audio.AudioSink
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
 * MODE FILM / ÉPISODE (« vod », 26/09/2026) : pour un fichier fini on
 * ajoute ce qu'un lecteur façon Netflix exige — démarrage à une position
 * (reprise), avance/retour (seekTo), durée totale, pistes AUDIO et
 * SOUS-TITRES (liste + choix), texte des sous-titres envoyé à Dart (affiché
 * par Flutter par-dessus la vidéo, la SurfaceView ne dessine pas le texte),
 * et une reconnexion qui REPREND À LA MÊME SECONDE au lieu de repartir du
 * début. Le direct (vod = false) garde EXACTEMENT son comportement.
 *
 * SON « QUALITÉ CINÉMA » (30/09/2026) — correctif du son « vieille radio »,
 * avec filet de sécurité pour ne JAMAIS laisser une chaîne sur la roue :
 *  1. HE-AAC complet : le décodeur AAC de nombreuses box ignore le SBR (les
 *     aigus) et la stéréo paramétrique → son étouffé et mono. L'AAC passe donc
 *     par FFmpeg (décodage de référence), le reste garde le décodeur de la box.
 *  2. AC-3 / E-AC-3 / DTS : envoyés TELS QUELS (passthrough) à la barre de son /
 *     l'ampli quand l'HDMI l'accepte ; sinon décodés par la box ou, à défaut,
 *     par FFmpeg (avant : piste ignorée ou muette).
 *  3. Vitesse du direct figée à 1,0 : Media3 accélère / ralentit un direct HLS
 *     de ±3 % pour tenir la latence, ce qui « étire » le son (effet métallique).
 *  4. Son déclaré « film » au système (post-traitement TV adapté au cinéma).
 *  5. REPLI (leçon v99–v101) : si le moteur FFmpeg échoue, ou s'il est le
 *     décodeur audio actif et que la lecture n'est toujours pas prête 8 s
 *     après l'ouverture, on revient au décodeur de la box pour TOUTE la
 *     session et on re-prépare le flux tout de suite. Mieux vaut un son
 *     « radio » qu'une chaîne bloquée.
 *
 * Communication avec Dart via un MethodChannel dédié (`native_video_player/<id>`).
 */
@UnstableApi
class NativeVideoView(
    context: Context,
    messenger: BinaryMessenger,
    id: Int,
) : PlatformView, MethodChannel.MethodCallHandler, Player.Listener, AnalyticsListener {

    private val surfaceView = SurfaceView(context)
    private val channel = MethodChannel(messenger, "native_video_player/$id")
    private val player: ExoPlayer
    private val handler = Handler(Looper.getMainLooper())

    private var currentUrl: String? = null

    // Mode film/épisode : la reconnexion reprend à [lastKnownPos].
    private var vodMode = false
    private var lastKnownPos = 0L
    private var lastSentDuration = -1L

    // Reconnexion auto silencieuse.
    private var retryCount = 0
    private var pendingRetry: Runnable? = null
    private val maxSilentRetries = 8 // au-delà → on prévient Dart (reset complet)

    // Son : vrai dès que le décodeur audio créé s'appelle « ffmpeg… »
    // (AnalyticsListener.onAudioDecoderInitialized). Remis à faux à chaque
    // setUrl et dès qu'un décodeur de la box prend la relève.
    @Volatile
    private var ffmpegAudioActive = false

    // Jeton du délai de 8 s : l'incrémenter annule le contrôle précédent
    // (zapping, repli, dispose) sans toucher aux autres callbacks du Handler.
    private var ffmpegWatchToken = 0

    private var released = false

    private val positionPump = object : Runnable {
        override fun run() {
            if (player.isPlaying) {
                val pos = player.currentPosition
                if (vodMode) lastKnownPos = pos
                channel.invokeMethod("position", pos)
            }
            sendDurationIfChanged()
            handler.postDelayed(this, 500)
        }
    }

    /** Durée totale (ms) envoyée UNE fois quand elle est connue / change. */
    private fun sendDurationIfChanged() {
        val d = player.duration
        if (d != C.TIME_UNSET && d > 0 && d != lastSentDuration) {
            lastSentDuration = d
            channel.invokeMethod("duration", d)
        }
    }

    init {
        channel.setMethodCallHandler(this)

        // La SurfaceView ne doit PAS être focusable (sinon elle capte le D-pad
        // qui doit revenir au Focus Flutter) ; on garde l'écran allumé.
        surfaceView.isFocusable = false
        surfaceView.isFocusableInTouchMode = false
        surfaceView.keepScreenOn = true

        // Tampons orientés DÉMARRAGE RAPIDE + fluidité. On lance la lecture dès
        // ~1 s de données (bufferForPlayback INCHANGÉ → ouverture/zapping rapide,
        // déjà plus véloce que le mobile), MAIS on approfondit le matelas
        // anti-coupure : base 5 s, jusqu'à 45 s d'avance (au lieu de 30 s) pour
        // mieux absorber un Wi-Fi qui faiblit (bar, box bas de gamme), façon
        // « démarre vite puis creuse le coussin » du lecteur mobile.
        // Plafond gardé MODÉRÉ (45 s, pas 60 s comme le mobile) car la TV tourne
        // sur les box les plus faibles (1 Go) et prioritizeTimeOverSizeThresholds
        // force le tampon en TEMPS : 45 s reste tenable, 60 s risquerait l'OOM
        // sur un flux 4K.
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(5_000, 45_000, 1_000, 2_000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

        // Décodage matériel (MediaCodec) avec repli logiciel si l'init échoue.
        // + SON : un 2e moteur audio, FFmpeg, placé APRÈS celui de la box. Media3
        // prend le premier moteur qui sait lire la piste : la box garde tout ce
        // qu'elle fait bien (dont le passthrough AC-3 vers l'ampli), FFmpeg prend
        // ce qu'elle ne sait pas lire. On l'ajoute nous-mêmes (et pas par le mode
        // « extension » qui passe par réflexion) pour que R8 ne le retire jamais
        // de l'APK minifié.
        val renderersFactory = object : DefaultRenderersFactory(context) {
            override fun buildAudioRenderers(
                context: Context,
                extensionRendererMode: Int,
                mediaCodecSelector: MediaCodecSelector,
                enableDecoderFallback: Boolean,
                audioSink: AudioSink,
                eventHandler: Handler,
                eventListener: AudioRendererEventListener,
                out: ArrayList<Renderer>,
            ) {
                super.buildAudioRenderers(
                    context, extensionRendererMode, mediaCodecSelector,
                    enableDecoderFallback, audioSink, eventHandler, eventListener, out,
                )
                if (ffmpegReady) {
                    out.add(FfmpegAudioRenderer(eventHandler, eventListener, audioSink))
                }
            }
        }
            .setEnableDecoderFallback(true)
            // AAC → on « cache » le décodeur AAC de la box pour que FFmpeg le
            // lise (HE-AAC complet : aigus + stéréo). Tout le reste (vidéo, AC-3,
            // DTS…) passe par la liste normale. Si FFmpeg n'a pas pu se charger,
            // ou si le repli session est armé, rien ne change : la box garde son
            // décodeur AAC.
            // Le drapeau [forceBoxAacDecoder] est relu À CHAQUE appel : Media3
            // redemande la liste à chaque sélection de pistes (donc à chaque
            // re-prepare), il n'y a pas de copie figée au moment du build.
            .setMediaCodecSelector { mimeType, requiresSecure, requiresTunneling ->
                if (!forceBoxAacDecoder && ffmpegAac && mimeType == MimeTypes.AUDIO_AAC) {
                    emptyList<MediaCodecInfo>()
                } else {
                    MediaCodecSelector.DEFAULT.getDecoderInfos(
                        mimeType, requiresSecure, requiresTunneling,
                    )
                }
            }

        // Direct HLS : Media3 fait varier la vitesse (0,97–1,03) pour tenir la
        // latence ; l'étirement du son qui en résulte s'entend. On la fige à 1,0
        // (l'IPTV n'a pas besoin d'une latence au dixième de seconde).
        val liveSpeed = DefaultLivePlaybackSpeedControl.Builder()
            .setFallbackMinPlaybackSpeed(1f)
            .setFallbackMaxPlaybackSpeed(1f)
            .build()

        // Contenu déclaré « film » : le système applique son profil audio
        // cinéma (et non « voix » / « inconnu »). handleAudioFocus = false : on
        // garde le comportement actuel (aperçu + plein écran ne se coupent pas
        // l'un l'autre).
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
            .build()

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

        // Politique de ré-essai réseau AGRESSIVE : on retente beaucoup avant
        // d'abandonner un chargement (le direct IPTV coupe souvent brièvement).
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)
            .setLoadErrorHandlingPolicy(DefaultLoadErrorHandlingPolicy(6))

        player = ExoPlayer.Builder(context, renderersFactory)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(mediaSourceFactory)
            .setLivePlaybackSpeedControl(liveSpeed)
            .setAudioAttributes(audioAttributes, false)
            .setHandleAudioBecomingNoisy(true)
            .build()

        player.setVideoSurfaceView(surfaceView)
        player.addListener(this)
        // Nom du décodeur audio, erreurs de codec et de sortie son : c'est
        // ici qu'on sait si FFmpeg est vraiment celui qui joue.
        player.addAnalyticsListener(this)
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
                vodMode = call.argument<Boolean>("vod") ?: false
                val startMs = (call.argument<Number>("startMs"))?.toLong() ?: 0L
                lastKnownPos = startMs
                lastSentDuration = -1L
                // Nouveau flux : on ne sait pas encore quel décodeur audio
                // va être créé. Le délai de 8 s ne doit pas hériter du « ffmpeg »
                // de la chaîne précédente.
                ffmpegAudioActive = false
                // Langue audio / sous-titres préférée (langue de l'app) : si le
                // film propose la piste, ExoPlayer la choisit d'office.
                val prefAudio = call.argument<String>("preferredAudio")
                val prefText = call.argument<String>("preferredText")
                if (prefAudio != null || prefText != null) {
                    val b = player.trackSelectionParameters.buildUpon()
                    if (prefAudio != null) b.setPreferredAudioLanguage(prefAudio)
                    if (prefText != null) b.setPreferredTextLanguage(prefText)
                    player.trackSelectionParameters = b.build()
                }
                if (vodMode && startMs > 0) {
                    player.setMediaItem(MediaItem.fromUri(url), startMs)
                } else {
                    player.setMediaItem(MediaItem.fromUri(url))
                }
                player.prepare()
                player.playWhenReady = true
                // 8 s pour que FFmpeg prouve qu'il sait lire CE flux. Sinon on
                // revient à la box (voir [armFfmpegReadyWatchdog]).
                armFfmpegReadyWatchdog()
                result.success(null)
            }
            "seekTo" -> {
                val ms = (call.argument<Number>("ms"))?.toLong() ?: 0L
                val dur = player.duration
                val target = if (dur != C.TIME_UNSET && dur > 0) ms.coerceIn(0L, dur) else ms.coerceAtLeast(0L)
                player.seekTo(target)
                lastKnownPos = target
                channel.invokeMethod("position", target)
                result.success(null)
            }
            "selectTrack" -> {
                // Choix explicite d'une piste audio ou de sous-titres.
                val group = call.argument<Int>("group") ?: -1
                val index = call.argument<Int>("index") ?: -1
                val groups = player.currentTracks.groups
                if (group < 0 || group >= groups.size) {
                    result.error("bad_track", "groupe inconnu", null)
                    return
                }
                val g = groups[group]
                if (index < 0 || index >= g.length) {
                    result.error("bad_track", "piste inconnue", null)
                    return
                }
                player.trackSelectionParameters = player.trackSelectionParameters
                    .buildUpon()
                    .setTrackTypeDisabled(g.type, false)
                    .setOverrideForType(TrackSelectionOverride(g.mediaTrackGroup, index))
                    .build()
                result.success(null)
            }
            "disableText" -> {
                // « Sous-titres : désactivés ».
                player.trackSelectionParameters = player.trackSelectionParameters
                    .buildUpon()
                    .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                    .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                    .build()
                channel.invokeMethod("cues", "")
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

    /** Pistes disponibles → Dart (menu Audio / Sous-titres). */
    override fun onTracksChanged(tracks: Tracks) {
        val out = ArrayList<Map<String, Any?>>()
        tracks.groups.forEachIndexed { gi, g ->
            val type = when (g.type) {
                C.TRACK_TYPE_AUDIO -> "audio"
                C.TRACK_TYPE_TEXT -> "text"
                else -> null
            } ?: return@forEachIndexed
            for (i in 0 until g.length) {
                if (!g.isTrackSupported(i)) continue
                val f = g.getTrackFormat(i)
                out.add(
                    mapOf(
                        "type" to type,
                        "group" to gi,
                        "index" to i,
                        "language" to f.language,
                        "label" to f.label,
                        "channels" to f.channelCount,
                        "selected" to g.isTrackSelected(i),
                    )
                )
            }
        }
        channel.invokeMethod("tracks", out)
    }

    /** Texte des sous-titres courants → Dart (vide = rien à afficher). */
    override fun onCues(cueGroup: CueGroup) {
        val text = cueGroup.cues.mapNotNull { it.text?.toString() }.joinToString("\n")
        channel.invokeMethod("cues", text)
    }

    override fun onRenderedFirstFrame() {
        retryCount = 0
        channel.invokeMethod("firstFrame", null)
    }

    override fun onPlayerError(error: PlaybackException) {
        // Erreur DU MOTEUR FFmpeg (rendererName « FfmpegAudioRenderer ») :
        // retenter le même moteur reproduirait le blocage v99. On bascule
        // sur le décodeur de la box et on re-prépare tout de suite, SANS
        // entrer dans le back-off de reconnexion (qui, lui, ne change pas).
        if (!forceBoxAacDecoder && isFfmpegRendererError(error)) {
            requestBoxAudioFallback()
            return
        }
        // RECONNEXION SILENCIEUSE : on ne montre PAS d'erreur au client tant
        // qu'on n'a pas épuisé les essais. On re-prépare avec un back-off.
        if (retryCount < maxSilentRetries) {
            retryCount++
            // Film : on retient la seconde exacte AVANT de re-préparer.
            if (vodMode && player.currentPosition > 0) lastKnownPos = player.currentPosition
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
            val url = currentUrl
            if (url != null && vodMode) {
                // Film : reprise À LA MÊME SECONDE (jamais depuis le début).
                player.setMediaItem(MediaItem.fromUri(url), lastKnownPos)
                player.prepare()
                player.playWhenReady = true
            } else if (url != null) {
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

    // ---- son : suivi FFmpeg et repli box -----------------------------------

    /**
     * Vrai si l'erreur vient du moteur audio FFmpeg (pas d'un couac réseau).
     * [ExoPlaybackException.TYPE_RENDERER] + nom « Ffmpeg… » : c'est le
     * getName() de [FfmpegAudioRenderer], pas celui d'un décodeur de la box.
     */
    private fun isFfmpegRendererError(error: PlaybackException): Boolean {
        val exo = error as? ExoPlaybackException ?: return false
        return exo.type == ExoPlaybackException.TYPE_RENDERER &&
            exo.rendererName?.contains("Ffmpeg", ignoreCase = true) == true
    }

    /**
     * Arme le filet des 8 s pour le setUrl en cours.
     *
     * Pourquoi 8 s : en v99–v101, certaines chaînes restaient sur la roue
     * SANS erreur, parce que le rendu audio FFmpeg ne devenait jamais prêt
     * et que le lecteur restait donc en BUFFERING. Huit secondes laissent
     * le temps à un flux normal de démarrer, et restent sous les 10 s
     * qu'un téléspectateur accepte avant de zapper.
     *
     * On ne bascule QUE si FFmpeg est vraiment le décodeur audio actif
     * (nom vu dans [onAudioDecoderInitialized]). Un direct lent dont le
     * décodeur n'est pas encore créé n'est pas un échec FFmpeg : la
     * reconnexion réseau existante s'en charge.
     */
    private fun armFfmpegReadyWatchdog() {
        val token = ++ffmpegWatchToken
        handler.postDelayed({
            if (token != ffmpegWatchToken || released) return@postDelayed
            if (!forceBoxAacDecoder &&
                ffmpegAudioActive &&
                player.playbackState != Player.STATE_READY
            ) {
                requestBoxAudioFallback()
            }
        }, FFMPEG_READY_TIMEOUT_MS)
    }

    /**
     * Repli pour toute la session, puis re-préparation IMMÉDIATE du flux.
     *
     * Le drapeau est posé AVANT le re-prepare, et il est dans le companion
     * object : la prochaine sélection de pistes (cette vue, ou une autre
     * ouverte plus tard dans le même processus) relit [forceBoxAacDecoder]
     * et rend l'AAC au décodeur de la box. On ne recrée pas le lecteur :
     * les moteurs sont déjà construits, seul le choix de piste change.
     *
     * Posté sur le thread principal : ces signaux arrivent parfois depuis
     * le thread de lecture, et Media3 n'aime pas un prepare() réentrant
     * au milieu de onPlayerError.
     */
    private fun requestBoxAudioFallback() {
        if (forceBoxAacDecoder || released) return
        forceBoxAacDecoder = true
        ffmpegAudioActive = false
        ffmpegWatchToken++
        handler.post {
            if (released) return@post
            // Un essai réseau déjà armé ne doit pas lancer un SECOND
            // prepare() par-dessus celui-ci (la chaîne clignoterait).
            // On ne touche pas au compteur : ce n'est pas un échec réseau.
            cancelRetry()
            channel.invokeMethod("buffering", true)
            reprepareCurrentItemNow()
        }
    }

    /** Même geste que la reconnexion, sans délai. Film : même seconde. */
    private fun reprepareCurrentItemNow() {
        val url = currentUrl ?: return
        if (vodMode) {
            if (player.currentPosition > 0) lastKnownPos = player.currentPosition
            player.setMediaItem(MediaItem.fromUri(url), lastKnownPos)
        } else {
            player.setMediaItem(MediaItem.fromUri(url))
        }
        player.prepare()
        player.playWhenReady = true
    }

    /**
     * Le nom renvoyé par FFmpeg est « ffmpeg » + version + codec
     * (ex. « ffmpeg6.0-aac »). Un décodeur de box ressemble à
     * « c2.android.aac.decoder » ou « OMX.google.aac.decoder » : il ne
     * contient pas « ffmpeg ».
     */
    override fun onAudioDecoderInitialized(
        eventTime: AnalyticsListener.EventTime,
        decoderName: String,
        initializedTimestampMs: Long,
        initializationDurationMs: Long,
    ) {
        ffmpegAudioActive = decoderName.contains("ffmpeg", ignoreCase = true)
    }

    override fun onAudioDecoderReleased(eventTime: AnalyticsListener.EventTime, decoderName: String) {
        if (decoderName.contains("ffmpeg", ignoreCase = true)) {
            ffmpegAudioActive = false
        }
    }

    /**
     * Erreur de sortie son PENDANT que FFmpeg décode. Media3 précise que
     * ça ne veut pas toujours dire que la lecture a planté : ici on s'en
     * sert quand même comme signal de repli, parce qu'un AudioTrack qui
     * refuse le PCM de FFmpeg laisse la chaîne muette ou bloquée, et que
     * le décodeur de la box, lui, parle le dialecte de l'appareil.
     */
    override fun onAudioSinkError(eventTime: AnalyticsListener.EventTime, audioSinkError: Exception) {
        if (ffmpegAudioActive) requestBoxAudioFallback()
    }

    /** Erreur du décodeur logiciel FFmpeg (DecoderException), même repli. */
    override fun onAudioCodecError(eventTime: AnalyticsListener.EventTime, audioCodecError: Exception) {
        if (ffmpegAudioActive) requestBoxAudioFallback()
    }

    // ---- cycle de vie -------------------------------------------------------

    override fun dispose() {
        released = true
        ffmpegWatchToken++
        cancelRetry()
        handler.removeCallbacks(positionPump)
        player.removeAnalyticsListener(this)
        player.removeListener(this)
        player.release()
        channel.setMethodCallHandler(null)
    }

    companion object {
        /**
         * Délai après setUrl avant de conclure que FFmpeg ne deviendra pas
         * prêt. Voir [armFfmpegReadyWatchdog].
         */
        private const val FFMPEG_READY_TIMEOUT_MS = 8_000L

        /**
         * FFmpeg chargé ? (bibliothèque native, UNE fois par processus). Si le
         * chargement échoue (architecture exotique), on reste sur les décodeurs
         * de la box, exactement comme avant.
         */
        private val ffmpegReady: Boolean by lazy {
            try {
                FfmpegLibrary.isAvailable()
            } catch (t: Throwable) {
                false
            }
        }

        /** FFmpeg sait-il lire l'AAC (HE-AAC compris) ? */
        private val ffmpegAac: Boolean by lazy {
            ffmpegReady && FfmpegLibrary.supportsFormat(MimeTypes.AUDIO_AAC)
        }

        /**
         * Repli session. Une fois vrai, PLUS AUCUNE vue de ce processus ne
         * force l'AAC vers FFmpeg : le sélecteur MediaCodec relit ce champ
         * à chaque piste et rend la liste normale des décodeurs de la box.
         *
         * @Volatile : écrit depuis le thread qui constate l'échec, lu depuis
         * le thread de sélection des décodeurs (pas forcément le même).
         */
        @Volatile
        private var forceBoxAacDecoder: Boolean = false
    }
}
