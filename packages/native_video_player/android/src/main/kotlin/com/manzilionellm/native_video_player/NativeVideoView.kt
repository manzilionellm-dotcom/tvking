package com.manzilionellm.native_video_player

import android.app.ActivityManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.Surface
import android.view.SurfaceView
import android.view.View
import android.widget.FrameLayout
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.SubtitleView
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.TransferListener
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.AdaptiveTrackSelection
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.flutter.view.TextureRegistry

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
    // Nom COMPLET du MethodChannel (« native_video_player/<viewId> » pour une
    // PlatformView, « native_video_player/t<textureId> » pour un lecteur
    // TEXTURE) — les deux espaces d'ids se chevauchent, un suffixe distinct
    // évite toute collision de canal.
    channelName: String,
    // Mode APERÇU (vignette de l'accueil / d'En direct) : tampons réduits —
    // voir le bloc LoadControl dans init{}.
    private val preview: Boolean = false,
    // ==================================================================
    //  DOUBLE CHEMIN DE RENDU (correctif terrain « l'image ne vient pas ») :
    //  certaines box n'affichent JAMAIS une SurfaceView composée en hybrid
    //  composition (fenêtre Android séparée que le compositeur de la box
    //  rate), d'autres n'affichent rien via texture. Aucun chemin unique ne
    //  couvre 100 % du parc.
    //   • surfaceTextureEntry == null → PlatformView + SurfaceView
    //     (chemin historique) ;
    //   • surfaceTextureEntry != null → la vidéo est décodée vers la
    //     SurfaceTexture de Flutter et rendue par le MÊME pipeline que
    //     l'interface : partout où l'UI de l'app s'affiche, l'image vient.
    //  Le choix + la bascule automatique vivent côté Dart (watchdog
    //  « lecture OK mais aucune 1re trame » → on change de chemin et on
    //  MÉMORISE celui qui marche sur cette box).
    // ==================================================================
    private val surfaceTextureEntry: TextureRegistry.SurfaceTextureEntry? = null,
) : PlatformView, MethodChannel.MethodCallHandler, Player.Listener {

    companion object {
        // Toutes les vues VIVANTES (accès main-thread uniquement : création /
        // dispose des PlatformViews et callbacks de cycle de vie arrivent tous
        // sur le main thread). Sert au « couvre-feu » ci-dessous.
        private val instances = mutableSetOf<NativeVideoView>()

        // THREAD PLAYER PARTAGÉ (patron Media3 « threading model » officiel :
        // ExoPlayer.Builder.setLooper). TOUT accès au player passe par lui —
        // surtout release(), qui BLOQUE son appelant jusqu'à ~500 ms (codecs
        // matériels + AudioTrack). Sur le main thread Android, ce blocage
        // tombait pile en fin d'animation de pop : c'était LE « ça accroche
        // en quittant le direct ». Un seul thread pour toutes les vues =
        // les releases/préparations se sérialisent proprement (le codec de
        // l'ancien lecteur est rendu avant que le suivant le réclame), et
        // le main thread ne porte plus jamais une opération lecteur.
        private val playerThread =
            HandlerThread("NativeVideoPlayerOps").apply { start() }

        /**
         * Coupe TOUS les lecteurs — appelé par le plugin quand l'ACTIVITÉ passe
         * en arrière-plan (Home / veille / autre app). GARANTIE NATIVE « zéro
         * son en arrière-plan » : elle ne dépend PAS de l'écran Flutter affiché
         * (le lecteur plein écran gère déjà son cycle de vie côté Dart, mais la
         * multi-vue ou tout futur écran pouvait laisser le son tourner). La
         * pause remonte à Dart via onIsPlayingChanged → l'UI reste cohérente.
         */
        fun pauseAll() {
            for (v in instances) v.playerHandler.post { v.player.pause() }
        }

        /**
         * PRESSION MÉMOIRE (onTrimMemory du plugin). Android TV a peu de RAM :
         * quand l'OS prévient qu'il va commencer à tuer des process, on
         * dégrade en douceur AVANT l'OOM :
         *  • les APERÇUS (vignettes muettes) sont stoppés — leur décodeur et
         *    leurs tampons sont rendus immédiatement, personne ne les regarde
         *    de près ;
         *  • en niveau CRITIQUE, les lecteurs principaux rendent leurs codecs
         *    « chauds » (setForegroundMode(false)) — la lecture EN COURS
         *    continue, seul le confort de zap est sacrifié, et setMedia le
         *    réarme automatiquement à la prochaine chaîne.
         * Mieux vaut un zap 500 ms plus lent qu'une app tuée par l'OS.
         */
        fun onMemoryPressure(critical: Boolean) {
            for (v in instances) {
                v.playerHandler.post {
                    if (v.fsm == Fsm.RELEASED) return@post
                    if (v.preview) {
                        v.player.stop()
                        v.recordEvent("trim_preview_stopped")
                    } else if (critical) {
                        v.player.setForegroundMode(false)
                        v.foregroundReleased = true
                        v.recordEvent("trim_codecs_released")
                    }
                }
            }
        }
    }

    private val surfaceView = SurfaceView(appContext)

    // Rendu des SOUS-TITRES : la vidéo est dessinée par MediaCodec directement
    // sur la Surface (elle ne passe pas par Flutter), donc les sous-titres
    // doivent être dessinés par une vue Android PAR-DESSUS. On empile
    // SurfaceView + SubtitleView dans un FrameLayout.
    private val subtitleView = SubtitleView(appContext)
    private val container = FrameLayout(appContext)

    private val channel = MethodChannel(messenger, channelName)
    private val player: ExoPlayer

    // Surface construite sur la SurfaceTexture Flutter (mode TEXTURE
    // uniquement) — gardée pour être libérée proprement au dispose.
    private var flutterSurface: Surface? = null

    // Garde anti double-dispose : en mode TEXTURE, le teardown est déclenché
    // par le canal (« dispose ») ; en mode PlatformView, par Flutter. Les
    // deux peuvent théoriquement se croiser.
    private var isDisposed = false

    // RÉPARTITION DES THREADS (contrat de ce fichier) :
    //   • `handler` (MAIN)         : MethodChannel (les envois vers Dart
    //     DOIVENT partir du main thread) + vues Android (SubtitleView).
    //   • `playerHandler` (PLAYER) : TOUT accès à `player` (contrat
    //     setLooper), l'état de reconnexion (currentUrl/retryCount/
    //     pendingRetry), la pompe de position et currentTracks.
    // Les callbacks Player.Listener arrivent sur le thread PLAYER (c'est le
    // looper d'application du lecteur) → chaque envoi canal fait un
    // handler.post, chaque toucher de vue aussi.
    private val handler = Handler(Looper.getMainLooper())
    private val playerHandler = Handler(playerThread.looper)

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

    // ==================================================================
    //  FAILOVER MULTI-SOURCES (natif). Dart peut fournir, avec setUrl, une
    //  liste d'URLs de REPLI du même contenu (autre variante, autre
    //  serveur du panel). Quand le budget de reconnexion silencieuse de la
    //  source courante est épuisé, on bascule SANS BRUIT sur la suivante
    //  (l'utilisateur ne voit que « buffering ») ; l'erreur ne remonte à
    //  Dart qu'après épuisement de TOUTES les sources. L'orchestration
    //  reste côté Dart (c'est lui qui choisit et ordonne les sources) —
    //  le natif ne fait qu'exécuter la cascade sans crasher.
    // ==================================================================
    private var sourceUrls: List<String> = emptyList()
    private var sourceIndex = 0

    // ==================================================================
    //  MACHINE À ÉTATS (garde DÉFENSIVE native). L'orchestration vit côté
    //  Dart ; ici on empêche seulement les commandes INCOHÉRENTES de
    //  toucher le lecteur (play sans média, commande après release…).
    //  Une violation n'est JAMAIS un crash : la commande est ignorée et
    //  l'événement journalisé dans la télémétrie (ring buffer ci-dessous).
    //  État confiné au thread PLAYER, comme tout l'état lecteur.
    // ==================================================================
    private enum class Fsm { IDLE, LOADING, BUFFERING, READY, ENDED, FAILED, RELEASED }
    private var fsm = Fsm.IDLE

    // ==================================================================
    //  TÉLÉMÉTRIE SILENCIEUSE : compteurs + ring buffer local (borné, donc
    //  impossible à faire déborder). AUCUN envoi réseau ici — la Boîte
    //  noire Dart draine via « getStats » quand ELLE le décide (connexion
    //  stable), pour ne jamais voler de la bande passante à la vidéo.
    // ==================================================================
    private val telemetryEvents = ArrayDeque<Map<String, Any>>()
    private val telemetryMax = 100
    private var totalDroppedFrames = 0L
    private var totalAudioUnderruns = 0L
    private var totalSilentRetries = 0L
    private var totalFailovers = 0L
    private var totalFsmViolations = 0L

    /** Journalise un événement (thread PLAYER uniquement — comme le reste). */
    private fun recordEvent(name: String, detail: String? = null) {
        if (telemetryEvents.size >= telemetryMax) telemetryEvents.removeFirst()
        telemetryEvents.addLast(
            buildMap<String, Any> {
                put("t", android.os.SystemClock.elapsedRealtime())
                put("e", name)
                if (detail != null) put("d", detail)
            },
        )
    }

    /** Commande refusée par la garde d'états : on journalise, on ne crashe pas. */
    private fun fsmViolation(command: String) {
        totalFsmViolations++
        recordEvent("fsm_violation", "$command@${fsm.name}")
    }

    // ==================================================================
    //  COMPTEUR DE SOCKETS RÉSEAU RÉELLES (enquête « limite 1/1 » du 20/08).
    //  La réponse du canal « stop » prouve que la COMMANDE a été exécutée sur
    //  le thread d'application du lecteur — PAS que la socket est fermée :
    //  dans Media3, stop() est asynchrone en interne (le thread de lecture
    //  interne libère ensuite les chargeurs, et la fermeture réelle —
    //  DataSource.close() — arrive sur le thread de chargement). Ce
    //  TransferListener observe les VRAIES ouvertures/fermetures de sources
    //  réseau : onTransferEnd n'est émis qu'au close() effectif. Quand le
    //  compte de transferts réseau actifs touche zéro, on le signale à Dart
    //  (« netActive » false) — c'est LA preuve mesurable que ce lecteur ne
    //  tient plus aucune connexion, celle que le scénario « je quitte le
    //  film, je lance une chaîne » doit attendre avant d'ouvrir la suivante.
    // ==================================================================
    private val activeNetTransfers = java.util.concurrent.atomic.AtomicInteger(0)

    private val netTransferListener = object : TransferListener {
        override fun onTransferInitializing(
            source: DataSource, dataSpec: DataSpec, isNetwork: Boolean,
        ) = Unit

        override fun onTransferStart(
            source: DataSource, dataSpec: DataSpec, isNetwork: Boolean,
        ) {
            if (!isNetwork) return // fichier local : aucune connexion consommée
            if (activeNetTransfers.incrementAndGet() == 1) notifyNetActive(true)
        }

        override fun onBytesTransferred(
            source: DataSource, dataSpec: DataSpec, isNetwork: Boolean, bytesTransferred: Int,
        ) = Unit

        override fun onTransferEnd(
            source: DataSource, dataSpec: DataSpec, isNetwork: Boolean,
        ) {
            if (!isNetwork) return
            if (activeNetTransfers.decrementAndGet() == 0) notifyNetActive(false)
        }
    }

    /**
     * Publie la transition « au moins une socket ↔ plus aucune socket ».
     * Appelé depuis les threads de CHARGEMENT (contrat TransferListener) :
     * le journal natif se remplit sur le thread PLAYER (comme tout l'état
     * lecteur) et le canal s'invoque depuis le main (contrat MethodChannel).
     * En cas de transitions quasi simultanées (segments HLS), Dart reçoit la
     * VALEUR booléenne, pas un delta : le dernier message reflète l'état réel.
     */
    private fun notifyNetActive(active: Boolean) {
        playerHandler.post { recordEvent(if (active) "net_active" else "net_idle") }
        handler.post {
            if (!isDisposed) channel.invokeMethod("netActive", active)
        }
    }

    // REPRISE RÉSEAU INSTANTANÉE (façon Netflix) : pendant qu'un retry
    // attend son back-off (jusqu'à 8 s), si Android annonce que le réseau
    // par défaut est REVENU (Wi-Fi raccroché, 4G rétablie), on relance
    // IMMÉDIATEMENT au lieu de finir d'attendre. Sur une box dont le Wi-Fi
    // hoquette, c'est plusieurs secondes d'écran figé économisées à chaque
    // micro-coupure. Permission requise : ACCESS_NETWORK_STATE (normale,
    // déclarée dans le manifest du plugin).
    // AUDIO FOCUS système — attributs « contenu vidéo » partagés par les deux
    // appels setAudioAttributes (création du lecteur + setVolume multivue).
    // Règle : seul un lecteur AUDIBLE demande le focus (une autre app audio se
    // met en pause, et nous rendons la main si on nous le prend). Un aperçu
    // muet ne le demande JAMAIS : sinon chaque vignette volerait le focus de
    // la lecture principale et la mettrait en pause.
    private val mediaAudioAttributes = AudioAttributes.Builder()
        .setUsage(C.USAGE_MEDIA)
        .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
        .build()

    private val connectivityManager =
        appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
    private var networkCallbackRegistered = false
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            // Callback hors thread → on repasse par le thread PLAYER (l'état
            // de retry et setMedia y sont confinés).
            playerHandler.post {
                val retry = pendingRetry ?: return@post
                playerHandler.removeCallbacks(retry)
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
            // Tourne sur le thread PLAYER (les getters ExoPlayer exigent le
            // looper d'application) ; chaque envoi canal repasse par le main.
            if (player.isPlaying) {
                val pos = player.currentPosition
                handler.post { channel.invokeMethod("position", pos) }
            }
            // DURÉE : connue uniquement pour un contenu SEEKABLE (film / VOD /
            // catch-up). Un DIRECT renvoie TIME_UNSET → on émet 0 (= pas de
            // barre, pas de seek côté UI). On n'émet que sur changement.
            val rawDur = player.duration // ms, ou C.TIME_UNSET
            val durMs = if (rawDur != androidx.media3.common.C.TIME_UNSET && rawDur > 0) rawDur else 0L
            if (durMs != lastDurationMs) {
                lastDurationMs = durMs
                handler.post { channel.invokeMethod("duration", durMs) }
            }
            // AVANCE CHARGÉE (façon YouTube) : jusqu'où le tampon est déjà
            // rempli EN AVANT de la lecture. Sert à dessiner la « ligne grise »
            // sur la barre de progression VOD. Émis uniquement pour un média
            // seekable (film) — inutile sur un direct.
            if (durMs > 0) {
                val buffered = player.bufferedPosition
                handler.post { channel.invokeMethod("buffered", buffered) }
            }
            playerHandler.postDelayed(this, 500)
        }
    }

    init {
        instances.add(this)
        channel.setMethodCallHandler(this)

        // La SurfaceView ne doit PAS être focusable (sinon elle capte le D-pad
        // qui doit revenir au Focus Flutter).
        surfaceView.isFocusable = false
        surfaceView.isFocusableInTouchMode = false

        //  ⚠ CORRECTION DE COMMENTAIRE (28/08/2026). Cette ligne portait
        //  « on garde l'écran allumé ». C'ÉTAIT FAUX dans le mode de rendu
        //  par DÉFAUT, et ça a coûté un bug terrain : « la box part en
        //  veille après 15 minutes », y compris pendant la lecture.
        //
        //  `keepScreenOn` ne fait remonter la demande à la fenêtre que si
        //  la vue est ATTACHÉE à la hiérarchie. En mode « surface »
        //  (hybrid composition) elle l'est, et la ligne fonctionne. En
        //  mode « texture » — le défaut, voir getRenderMode() — la vue
        //  est créée HORS hiérarchie pour rendre dans une texture : elle
        //  n'atteint jamais ViewRootImpl, et la demande est ignorée
        //  silencieusement.
        //
        //  On la GARDE (elle sert dans le mode « surface » et ne coûte
        //  rien), mais elle ne doit plus être considérée comme la
        //  garantie anti-veille. Cette garantie vit désormais côté Dart,
        //  au niveau de l'APPLICATION : lib/core/tv/screen_awake.dart.
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
        //
        // « Connection: close » (recherche du 21/08, cause RACINE du
        // « limite de connexions » après la sortie d'un film) : les panels
        // Xtream/XUI ne libèrent le créneau QU'À LA FERMETURE DU SOCKET TCP
        // (aucun signal applicatif de stop — documenté chez Dispatcharr
        // #451/#1033). Or les sockets keep-alive retournent au pool JVM
        // ENCORE OUVERTS après release() → le panel voyait le film « en
        // cours » de longues secondes et refusait le live (458). En
        // désactivant le keep-alive, la fin de lecture ferme le socket →
        // le panel libère le créneau tout de suite. Coût : une poignée de
        // mains TCP par segment HLS (les panels sont en HTTP nu → minime) ;
        // le direct .ts (UNE longue requête) ne paie rien.
        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent("VLC/3.0.20 LibVLC/3.0.20")
            .setDefaultRequestProperties(mapOf("Connection" to "close"))
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
            // Compteur de sockets réelles (cf. netTransferListener) : chaque
            // source créée signale ses ouvertures/fermetures effectives.
            .setTransferListener(netTransferListener)

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
            // Looper d'application = thread PLAYER partagé (cf. companion) :
            // les appels au lecteur — release() en tête — ne bloquent plus
            // JAMAIS le main thread. build() depuis le main est le patron
            // documenté (« Threading model » Media3).
            .setLooper(playerThread.looper)
            .build()

        // Toute la configuration du lecteur bascule sur SON thread (contrat
        // setLooper). Postée d'un bloc : elle s'exécute avant tout setUrl
        // (même file, ordre FIFO).
        playerHandler.post {
            val entry = surfaceTextureEntry
            if (entry != null) {
                // Mode TEXTURE : MediaCodec décode vers la SurfaceTexture de
                // Flutter — la trame rejoint le compositeur de l'app, pas une
                // fenêtre Android séparée. (MediaCodec fixe lui-même la taille
                // des buffers, pas besoin de setDefaultBufferSize.)
                val s = Surface(entry.surfaceTexture())
                flutterSurface = s
                player.setVideoSurface(s)
            } else {
                player.setVideoSurfaceView(surfaceView)
            }
            player.addListener(this)
            // TÉLÉMÉTRIE SILENCIEUSE : frames perdues et underruns audio sont
            // les DEUX signaux avancés d'une box qui souffre (GPU saturé,
            // réseau limite) — on les compte AVANT que le client ne voie quoi
            // que ce soit. Callbacks sur le looper du lecteur = même
            // confinement que le reste de l'état (aucun verrou nécessaire).
            player.addAnalyticsListener(object : AnalyticsListener {
                override fun onDroppedVideoFrames(
                    eventTime: AnalyticsListener.EventTime,
                    droppedFrames: Int,
                    elapsedMs: Long,
                ) {
                    totalDroppedFrames += droppedFrames
                    // Seuls les paquets notables entrent au journal (le
                    // compteur, lui, additionne tout) : le ring buffer reste
                    // réservé aux événements exploitables.
                    if (droppedFrames >= 30) {
                        recordEvent("dropped_frames", droppedFrames.toString())
                    }
                }

                override fun onAudioUnderrun(
                    eventTime: AnalyticsListener.EventTime,
                    bufferSize: Int,
                    bufferSizeMs: Long,
                    elapsedSinceLastFeedMs: Long,
                ) {
                    totalAudioUnderruns++
                    recordEvent("audio_underrun", "${bufferSizeMs}ms")
                }
            })
            // Focus audio demandé UNIQUEMENT par un lecteur non-aperçu (voir
            // mediaAudioAttributes) ; setVolume le ré-aligne ensuite en multivue.
            player.setAudioAttributes(mediaAudioAttributes, !preview)
            player.playWhenReady = true
            // ZAP FLUIDE : garde les décodeurs MediaCodec « chauds » entre deux
            // préparations (setUrl au zap, retry silencieux). Sans ça, ExoPlayer
            // relâche le codec matériel à chaque stop/prepare et la box (surtout
            // à faible RAM) paie ~300-800 ms de ré-initialisation par chaîne.
            player.setForegroundMode(true)

            // SOUS-TITRES DÉSACTIVÉS par défaut (comportement historique : rien
            // n'était rendu). L'utilisateur les active via le bouton Sous-titres.
            //
            // AUDIO « QUALITÉ CINÉMA » (demande client, façon Netflix) : quand un
            // film/une chaîne propose PLUSIEURS pistes audio, on préfère la
            // MEILLEURE que l'appareil sait restituer, dans cet ordre :
            //   1. E-AC-3 JOC  (Dolby Atmos sur base Dolby Digital Plus)
            //   2. E-AC-3      (Dolby Digital Plus, 5.1/7.1)
            //   3. AC-3        (Dolby Digital 5.1)
            //   4. AAC         (stéréo — le repli universel)
            // POINTS CLÉS :
            //   • C'est une PRÉFÉRENCE, pas un filtre : DefaultTrackSelector ne
            //     retient une piste que si l'appareil peut la DÉCODER ou la
            //     BITSTREAMER (passthrough HDMI). Un téléphone sans décodeur
            //     Dolby retombe automatiquement sur l'AAC — jamais de silence.
            //   • Le PASSTHROUGH est déjà automatique : DefaultAudioSink
            //     interroge les AudioCapabilities (HDMI/eARC) et envoie le
            //     bitstream AC-3/E-AC-3 TEL QUEL à l'ampli quand il l'annonce —
            //     aucun décodage/downmix PCM forcé de notre part. Quand le
            //     matériel ne le supporte pas, Android décode et fait le
            //     downmix standard (centre préservé, dialogues intacts).
            //   • TUNNELING volontairement ABSENT : notre vidéo sort sur une
            //     SurfaceTexture Flutter (mode texture), incompatible avec le
            //     tunneled playback ; et le tunneling est notoirement bogué sur
            //     les box low-cost (image noire). L'A/V sync standard suffit.
            //   • Le FOCUS AUDIO (pause si une autre app parle, ducking) est
            //     déjà géré plus haut via setAudioAttributes(..., !preview).
            //   • La sélection MANUELLE (menu pistes audio → setAudioTrack)
            //     garde le dernier mot : un override écrase la préférence.
            player.trackSelectionParameters = player.trackSelectionParameters
                .buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                .setPreferredAudioMimeTypes(
                    MimeTypes.AUDIO_E_AC3_JOC,
                    MimeTypes.AUDIO_E_AC3,
                    MimeTypes.AUDIO_AC3,
                    MimeTypes.AUDIO_AAC,
                )
                .build()
        }

        // Reprise réseau instantanée : actif toute la vie du lecteur (un
        // callback réseau enregistré est quasi gratuit ; il ne FAIT quelque
        // chose que si un retry attend son back-off).
        registerNetworkCallback()

        // Empilement vidéo + sous-titres (style par défaut de l'appareil).
        val match = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        )
        container.addView(surfaceView, match)
        subtitleView.setUserDefaultStyle()
        subtitleView.setUserDefaultTextSize()
        container.addView(subtitleView, match)

        playerHandler.postDelayed(positionPump, 500)
    }

    override fun getView(): View = container

    // ---- Dart → natif -------------------------------------------------------

    // Arrive sur le MAIN thread (MethodChannel). Chaque opération lecteur est
    // POSTÉE sur le thread player puis on répond tout de suite : Dart ignore
    // les résultats (fire-and-forget), et la file FIFO du thread player
    // garantit l'ordre des commandes (setUrl → play → seekTo…).
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
                // Sources de REPLI optionnelles (failover natif silencieux).
                // Absentes → comportement historique inchangé.
                val fallbacks = call.argument<List<String>>("fallbackUrls")
                    ?.filter { it.isNotBlank() && it != url }
                    ?: emptyList()
                playerHandler.post {
                    if (fsm == Fsm.RELEASED) { fsmViolation("setUrl"); return@post }
                    cancelRetry()
                    // On ne remet le budget de reconnexion silencieuse à zéro QUE
                    // pour une VRAIE nouvelle chaîne (URL différente). Si Dart
                    // ré-ouvre la MÊME URL (recover sur flux gelé), on CONSERVE le
                    // compteur → après maxSilentRetries on remonte enfin l'erreur à
                    // Dart au lieu de relancer 8 essais à l'infini (boucle CPU/réseau).
                    if (url != currentUrl) {
                        retryCount = 0
                        // ZAP vers une AUTRE chaîne : on FERME d'abord la
                        // session en cours (photo client 17/08, « Limite de
                        // connexions atteinte — un autre écran regarde déjà
                        // avec ce compte »).
                        //
                        // `setMediaItem` seul laisse un recouvrement : la
                        // nouvelle source s'ouvre pendant que l'ancienne se
                        // démonte, et la socket HTTP retourne au pool de
                        // keep-alive au lieu de se fermer. Pour le panel, ça
                        // fait DEUX sessions actives — et un abonnement
                        // 1-connexion refuse la seconde. `stop()` +
                        // `clearMediaItems()` libèrent la socket AVANT
                        // d'ouvrir la suivante : une session à la fois, comme
                        // les grandes apps.
                        if (currentUrl != null) {
                            player.stop()
                            player.clearMediaItems()
                        }
                    }
                    sourceUrls = listOf(url) + fallbacks
                    sourceIndex = 0
                    currentUrl = url
                    currentUserAgent = ua
                    fsm = Fsm.LOADING
                    setMedia(url, ua)
                }
                result.success(null)
            }
            "play" -> {
                playerHandler.post {
                    // GARDE FSM : play() sans média chargé ou après release est
                    // une commande zombie (écran quitté, course d'événements) —
                    // on l'ignore proprement au lieu de réveiller un lecteur vide.
                    if (fsm == Fsm.RELEASED || currentUrl == null) {
                        fsmViolation("play")
                    } else {
                        player.play()
                    }
                }
                result.success(null)
            }
            "getStats" -> {
                // TÉLÉMÉTRIE : instantané des compteurs + drain du ring buffer
                // (les événements lus sont consommés). Appelé par la Boîte
                // noire Dart quand la connexion est stable — jamais en continu.
                playerHandler.post {
                    val snapshot = mapOf(
                        "state" to fsm.name,
                        "droppedFrames" to totalDroppedFrames,
                        "audioUnderruns" to totalAudioUnderruns,
                        "silentRetries" to totalSilentRetries,
                        "failovers" to totalFailovers,
                        "fsmViolations" to totalFsmViolations,
                        "sourceIndex" to sourceIndex,
                        "events" to telemetryEvents.toList(),
                    )
                    telemetryEvents.clear()
                    handler.post { result.success(snapshot) }
                }
            }
            "setVolume" -> {
                // Multi-vue : on coupe le son des tuiles inactives (volume 0) et
                // on ne laisse le son QUE sur la tuile active (volume 1).
                val v = (call.argument<Double>("volume") ?: 1.0).toFloat()
                playerHandler.post {
                    player.volume = v.coerceIn(0f, 1f)
                    // Le focus audio suit l'audibilité : la tuile coupée le
                    // REND (une autre app audio peut reprendre), la tuile
                    // active le (re)prend. Jamais pour un aperçu.
                    player.setAudioAttributes(mediaAudioAttributes, !preview && v > 0f)
                }
                result.success(null)
            }
            "pause" -> {
                playerHandler.post { player.pause() }
                result.success(null)
            }
            "stop" -> {
                // LIBÉRATION DE LA CONNEXION sans détruire la vue (Dart peut
                // relancer un setUrl ensuite). Motif terrain : sur un DIRECT,
                // `pause()` garde la session HTTP ouverte vers le panel — un
                // client qui appuie sur Home puis tente de regarder ailleurs
                // se prend « connexion déjà utilisée » sur les abonnements
                // à 1 connexion, alors qu'il ne regarde plus rien.
                // clearMediaItems() ferme réellement la source ; on repasse
                // en IDLE pour que la FSM accepte un nouveau setUrl.
                //
                // ON REPOND APRES COUP (et non tout de suite) : Dart peut donc
                // `await stop()` et n'ouvrir le flux suivant qu'une fois la
                // socket REELLEMENT fermee. C'est ce chainon qui manquait au
                // scenario « je quitte le film, je lance France 2 » : la
                // reponse immediate laissait les deux connexions se croiser.
                playerHandler.post {
                    try {
                        cancelRetry()
                        player.stop()
                        player.clearMediaItems()
                        currentUrl = null
                        fsm = Fsm.IDLE
                        recordEvent("stop")
                    } catch (t: Throwable) {
                        // Lecteur deja detruit / course a la sortie d'ecran :
                        // un arret rate ne doit jamais remonter en crash.
                        recordEvent("stop_error")
                    }
                    // Le resultat d'un MethodChannel se rend sur le thread
                    // plateforme, pas sur le thread player.
                    handler.post { result.success(null) }
                }
            }
            "seekTo" -> {
                // Film / VOD / catch-up : va à une position absolue (ms). Borné
                // à [0, duration] côté Dart ; ici on re-borne par prudence. Sans
                // effet utile sur un direct non-seekable (ExoPlayer l'ignore).
                val ms = (call.argument<Int>("ms") ?: 0).toLong()
                val safe = ms.coerceAtLeast(0L)
                playerHandler.post {
                    if (fsm == Fsm.RELEASED || currentUrl == null) {
                        fsmViolation("seekTo")
                    } else {
                        player.seekTo(safe)
                    }
                }
                result.success(null)
            }
            "setAudioTrack" -> {
                // Sélectionne la N-ième piste AUDIO (index dans la liste envoyée
                // à Dart par onTracksChanged).
                val idx = call.argument<Int>("index") ?: 0
                playerHandler.post {
                    selectTrack(androidx.media3.common.C.TRACK_TYPE_AUDIO, idx)
                }
                result.success(null)
            }
            "setSubtitleTrack" -> {
                // index >= 0 → active la N-ième piste TEXTE ; -1 → sous-titres OFF.
                val idx = call.argument<Int>("index") ?: -1
                if (idx < 0) {
                    playerHandler.post {
                        player.trackSelectionParameters =
                            player.trackSelectionParameters.buildUpon()
                                .setTrackTypeDisabled(
                                    androidx.media3.common.C.TRACK_TYPE_TEXT, true)
                                .clearOverridesOfType(
                                    androidx.media3.common.C.TRACK_TYPE_TEXT)
                                .build()
                    }
                    subtitleView.setCues(null) // vue → main thread (on y est)
                } else {
                    playerHandler.post {
                        selectTrack(androidx.media3.common.C.TRACK_TYPE_TEXT, idx)
                    }
                }
                result.success(null)
            }
            "dispose" -> {
                // Mode PlatformView : no-op (Flutter appelle dispose() sur la
                // vue). Mode TEXTURE : aucune PlatformView n'existe → c'est CE
                // message (envoyé par le controller Dart) qui déclenche le
                // teardown réel. Idempotent (garde isDisposed).
                if (surfaceTextureEntry != null) dispose()
                result.success(null)
            }
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

    // NB threading : ces callbacks arrivent sur le thread PLAYER (looper
    // d'application du lecteur). L'état de retry se manipule ICI même ;
    // chaque envoi vers Dart repasse par le main (contrat MethodChannel).
    override fun onPlaybackStateChanged(playbackState: Int) {
        when (playbackState) {
            Player.STATE_BUFFERING -> {
                if (fsm != Fsm.RELEASED) fsm = Fsm.BUFFERING
                handler.post { channel.invokeMethod("buffering", true) }
            }
            Player.STATE_READY -> {
                retryCount = 0 // lecture OK → on oublie les erreurs passées
                if (fsm != Fsm.RELEASED) fsm = Fsm.READY
                handler.post { channel.invokeMethod("buffering", false) }
            }
            Player.STATE_ENDED -> {
                if (fsm != Fsm.RELEASED) fsm = Fsm.ENDED
                handler.post { channel.invokeMethod("ended", null) }
            }
            Player.STATE_IDLE -> { /* après erreur : géré par onPlayerError */ }
        }
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        handler.post { channel.invokeMethod("playing", isPlaying) }
    }

    override fun onRenderedFirstFrame() {
        retryCount = 0
        handler.post { channel.invokeMethod("firstFrame", null) }
    }

    // Taille réelle de la vidéo → Dart peut proposer les formats d'image
    // (Auto = ratio réel, 16:9, 4:3, Étiré) au lieu du 16:9 figé.
    override fun onVideoSizeChanged(videoSize: VideoSize) {
        if (videoSize.width > 0 && videoSize.height > 0) {
            handler.post {
                channel.invokeMethod(
                    "videoSize",
                    mapOf("width" to videoSize.width, "height" to videoSize.height),
                )
            }
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
        handler.post {
            channel.invokeMethod("tracks", mapOf("audio" to audio, "text" to text))
        }
    }

    // Sous-titres décodés par ExoPlayer. Mode PlatformView : dessinés par la
    // SubtitleView Android par-dessus la SurfaceView. Mode TEXTURE : aucune
    // vue Android n'existe à l'écran → on remonte le TEXTE des cues à Dart
    // (« cueText »), qui les dessine en overlay Flutter. Vue Android → main
    // thread obligatoire (le callback arrive sur le thread player).
    override fun onCues(cueGroup: CueGroup) {
        if (surfaceTextureEntry != null) {
            val txt = cueGroup.cues
                .mapNotNull { it.text?.toString() }
                .filter { it.isNotBlank() }
                .joinToString("\n")
            handler.post { channel.invokeMethod("cueText", txt) }
            return
        }
        val cues = cueGroup.cues
        handler.post { subtitleView.setCues(cues) }
    }

    override fun onPlayerError(error: PlaybackException) {
        // SORTIE DE LA FENÊTRE LIVE (réseau trop lent, le serveur a « avancé »
        // sans nous) : ce n'est PAS une panne — on ressaute au direct
        // IMMÉDIATEMENT, sans compter d'essai ni montrer quoi que ce soit.
        // C'est la recommandation officielle Media3 pour les flux live.
        if (error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
            handler.post { channel.invokeMethod("buffering", true) }
            scheduleRetry(0L)
            return
        }
        // RECONNEXION SILENCIEUSE : on ne montre PAS d'erreur au client tant
        // qu'on n'a pas épuisé les essais. Back-off court (0,5 → 1 → 2 s)
        // AVEC JITTER (±25 %) : sans lui, toutes les box qui perdent le même
        // serveur au même instant re-frappent à la même milliseconde — le
        // panel encaisse un pic synchronisé et retombe (thundering herd). Le
        // jitter étale la reprise, le serveur respire, tout le monde repart.
        if (retryCount < maxSilentRetries) {
            retryCount++
            totalSilentRetries++
            recordEvent("retry", "${error.errorCodeName}#$retryCount")
            handler.post { channel.invokeMethod("buffering", true) }
            val base = (500L * (1 shl (retryCount - 1))).coerceAtMost(3_000L)
            val jittered =
                (base * (0.75 + kotlin.random.Random.nextDouble() * 0.5)).toLong()
            scheduleRetry(jittered)
        } else if (sourceIndex < sourceUrls.size - 1) {
            // CASCADE DE SOURCES : le budget de la source courante est épuisé
            // mais Dart nous a confié des replis → bascule IMMÉDIATE et
            // silencieuse sur la suivante (l'utilisateur ne voit que
            // « buffering »). Budget de retries remis à zéro pour la nouvelle
            // source : chacune a droit à sa chance complète.
            sourceIndex++
            retryCount = 0
            totalFailovers++
            currentUrl = sourceUrls[sourceIndex]
            recordEvent("failover", "source#$sourceIndex")
            handler.post { channel.invokeMethod("buffering", true) }
            scheduleRetry(0L)
        } else {
            // Trop d'échecs d'affilée → on laisse Dart faire un reset complet.
            // Diagnostic terrain : avant, seul `error.message` (souvent vague,
            // ex. "Source error") remontait — impossible de distinguer un
            // codec non supporté d'un timeout réseau sans lire le logcat de
            // la box. `errorCodeName` (constante stable Media3, ex.
            // "ERROR_CODE_IO_BAD_HTTP_STATUS") + le message de la CAUSE racine
            // (souvent plus parlant que le message de façade) donnent au
            // sender de quoi journaliser un diagnostic exploitable à distance.
            fsm = Fsm.FAILED
            recordEvent("fatal", error.errorCodeName)
            handler.post {
                channel.invokeMethod(
                    "error",
                    mapOf(
                        "message" to error.message,
                        "errorCode" to error.errorCode,
                        "errorCodeName" to error.errorCodeName,
                        "causeMessage" to error.cause?.message,
                        // Nombre de sources réellement essayées (cascade
                        // native comprise) : Dart sait qu'il ne sert à rien
                        // de re-proposer les mêmes.
                        "sourcesTried" to (sourceIndex + 1),
                    ),
                )
            }
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
            // Même compteur de sockets que la fabrique de l'init : une lecture
            // sous signature CUSTOM doit compter ses connexions à l'identique.
            .setTransferListener(netTransferListener)
        return DefaultMediaSourceFactory(dataSourceFactory)
            .setLoadErrorHandlingPolicy(DefaultLoadErrorHandlingPolicy(6))
    }

    // Positionné par la pression mémoire (cf. companion onMemoryPressure) :
    // les codecs « chauds » ont été rendus à l'OS ; le prochain setMedia les
    // reprend (le confort de zap revient dès que la pression est retombée).
    private var foregroundReleased = false

    /** Charge [url] avec la signature [userAgent] (`null` = défaut de l'init). */
    private fun setMedia(url: String, userAgent: String?) {
        if (foregroundReleased) {
            player.setForegroundMode(true)
            foregroundReleased = false
        }
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

    // Retry : état et exécution CONFINÉS au thread player (appelé par
    // onPlayerError, setUrl et networkCallback — tous trois y passent).
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
        playerHandler.postDelayed(r, delayMs)
    }

    private fun cancelRetry() {
        pendingRetry?.let { playerHandler.removeCallbacks(it) }
        pendingRetry = null
    }

    // ---- cycle de vie -------------------------------------------------------

    override fun dispose() {
        if (isDisposed) return
        isDisposed = true
        // Main thread : vues, canal, callbacks système — IMMÉDIAT.
        unregisterNetworkCallback()
        instances.remove(this)
        // DÉFENSE ANTI-« TRAME FANTÔME » (terrain 2026-07-16) : une
        // SurfaceView en hybrid composition GARDE sa dernière trame
        // décodée tant qu'elle n'est pas détachée — l'aperçu d'accueil
        // restait incrusté par-dessus l'écran suivant. Retirer les vues
        // ICI, synchrone, détache la SurfaceView de la fenêtre : la
        // couche Android disparaît avec la dispose, pas « plus tard »
        // au bon vouloir du compositeur.
        container.removeAllViews()
        channel.setMethodCallHandler(null)

        // Thread player : l'arrêt RÉEL du lecteur. setForegroundMode(false)
        // et release() BLOQUENT leur appelant (codecs matériels + AudioTrack,
        // jusqu'à ~500 ms) — c'était exécuté sur le main thread Android, en
        // fin d'animation de pop : LE « ça accroche en quittant le direct ».
        // Ici le blocage tombe sur le thread player partagé ; sa file FIFO
        // garantit en prime que le codec est rendu AVANT que le lecteur
        // suivant (aperçu d'accueil, zap) ne le réclame.
        playerHandler.post {
            fsm = Fsm.RELEASED // toute commande ultérieure = violation ignorée
            cancelRetry()
            playerHandler.removeCallbacks(positionPump)
            player.removeListener(this)
            if (surfaceTextureEntry != null) {
                player.clearVideoSurface()
            } else {
                player.clearVideoSurfaceView(surfaceView)
            }
            player.setForegroundMode(false) // relâche les codecs avant release
            player.release()
            // Mode TEXTURE : la Surface puis l'entrée de texture Flutter sont
            // libérées APRÈS le release du lecteur (le codec n'écrit plus
            // dedans) ; l'entrée se libère côté main (contrat TextureRegistry).
            flutterSurface?.release()
            flutterSurface = null
            surfaceTextureEntry?.let { entry ->
                handler.post { entry.release() }
            }
        }
    }
}
