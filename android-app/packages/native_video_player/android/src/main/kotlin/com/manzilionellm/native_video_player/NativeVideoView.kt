package com.manzilionellm.native_video_player

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.graphics.Rect
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.AudioPlaybackConfiguration
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import android.view.PixelCopy
import android.view.Surface
import android.view.SurfaceView
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.decoder.ffmpeg.ExperimentalFfmpegVideoRenderer
import androidx.media3.decoder.ffmpeg.FfmpegAudioRenderer
import androidx.media3.decoder.ffmpeg.FfmpegLibrary
import androidx.media3.exoplayer.DecoderReuseEvaluation
import androidx.media3.exoplayer.DefaultLivePlaybackSpeedControl
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlaybackException
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.audio.AudioCapabilities
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.AdaptiveTrackSelection
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.video.VideoFrameMetadataListener
import androidx.media3.exoplayer.video.VideoRendererEventListener
import com.manzilionellm.native_video_player.logic.AudioDiagnosis
import com.manzilionellm.native_video_player.logic.AudioGate
import com.manzilionellm.native_video_player.logic.AudioHandoff
import com.manzilionellm.native_video_player.logic.AudioFocusPolicy
import com.manzilionellm.native_video_player.logic.AudioFixes
import com.manzilionellm.native_video_player.logic.AudioModeGuard
import com.manzilionellm.native_video_player.logic.AudioRouteState
import com.manzilionellm.native_video_player.logic.AudioSnapshot
import com.manzilionellm.native_video_player.logic.AudioSpectrum
import com.manzilionellm.native_video_player.logic.AudioStages
import com.manzilionellm.native_video_player.logic.AudioTrackBuffer
import com.manzilionellm.native_video_player.logic.AacRoute
import com.manzilionellm.native_video_player.logic.CodecOrder
import com.manzilionellm.native_video_player.logic.DecoderFallback
import com.manzilionellm.native_video_player.logic.DisplayModeOption
import com.manzilionellm.native_video_player.logic.ExclusiveAudio
import com.manzilionellm.native_video_player.logic.FrameRateMatch
import com.manzilionellm.native_video_player.logic.NamedCodec
import com.manzilionellm.native_video_player.logic.PictureHealth
import com.manzilionellm.native_video_player.logic.PictureSignal
import com.manzilionellm.native_video_player.logic.PictureTune
import com.manzilionellm.native_video_player.logic.PlaybackSession
import com.manzilionellm.native_video_player.logic.PlayerCensus
import com.manzilionellm.native_video_player.logic.ProbeAttach
import com.manzilionellm.native_video_player.logic.VolumeTrace
import com.manzilionellm.native_video_player.logic.ReconnectGate
import com.manzilionellm.native_video_player.logic.ReconnectPlan
import com.manzilionellm.native_video_player.logic.SpokenCandidate
import com.manzilionellm.native_video_player.logic.SpokenTrackChoice
import com.manzilionellm.native_video_player.logic.VideoCandidate
import com.manzilionellm.native_video_player.logic.VideoEngine
import com.manzilionellm.native_video_player.logic.VideoTrackChoice
import java.util.concurrent.atomic.AtomicInteger
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
 * qu'à la taille → la 1re image arrive le plus vite possible. Ces durées ne
 * sont PAS modifiées : les allonger (reprise à 5 s, v99) a laissé des chaînes
 * sur le logo de chargement.
 *
 * IMAGE (box bas de gamme) : décodeur vidéo matériel uniquement, surface
 * opaque, pas de changement de fréquence HDMI, pas de « jointure » de
 * résolution qui fige l'image, qualité HLS qui change sans jeter les images
 * déjà reçues, et libération du codec AVANT la chaîne suivante (sinon image
 * verte / noire / figée, ou chaîne refusée si une seule connexion est permise).
 * Le décodeur VIDÉO FFmpeg n'est construit QUE si la bibliothèque native
 * déclare un décodeur vidéo (H.264, HEVC ou MPEG-2). Le binaire audio
 * Jellyfin de la v104 n'en a pas : on ne le construit donc pas, le chemin
 * qui avait bloqué des chaînes sur le logo (v99–v101) reste fermé.
 * Si MediaCodec échoue ou reste noir, on passe au décodeur logiciel
 * Android, puis à FFmpeg seulement s'il est vraiment là.
 *
 * AUTO-RECONNEXION SILENCIEUSE : si le serveur coupe / le réseau hoquette,
 * ExoPlayer ré-essaie d'abord seul (LoadErrorHandlingPolicy), et en cas
 * d'erreur fatale on RE-PREPARE avec un back-off (1→2→4→8 s, plafond 8 s,
 * 8 essais). Un second essai n'est pas programmé tant que le premier
 * attend (deux prepare = deux sons). Le volume reste à 0 jusqu'à la
 * nouvelle image ou le nouveau « je joue ». Si une image a déjà été
 * vue, on la garde (petite copie) au lieu d'un panneau opaque : stop()
 * vide souvent la surface, et le panneau Flutter par-dessus faisait
 * un écran noir. Sans copie (coupure dans les premières secondes),
 * on montre le panneau avec le nom de la chaîne. On ne remonte une
 * vraie erreur à Dart qu'après les 8 essais. Un direct « en retard »
 * (hors fenêtre) rejoint le direct tout de suite : ce n'est pas une
 * panne, et ça ne compte pas dans le budget d'échecs.
 *
 * MODE FILM / ÉPISODE (« vod », 26/09/2026) : pour un fichier fini on
 * ajoute ce qu'un lecteur façon Netflix exige — démarrage à une position
 * (reprise), avance/retour (seekTo), durée totale, pistes AUDIO et
 * SOUS-TITRES (liste + choix), texte des sous-titres envoyé à Dart (affiché
 * par Flutter par-dessus la vidéo, la SurfaceView ne dessine pas le texte),
 * et une reconnexion qui REPREND À LA MÊME SECONDE au lieu de repartir du
 * début. Le direct (vod = false) garde EXACTEMENT son comportement.
 *
 * UN SEUL SON (30/09/2026, v104). Cause du « deux chaînes en même temps » :
 *  1. handleAudioFocus était false : l'aperçu et le plein écran (deux
 *     ExoPlayer) parlaient ensemble, Android ne coupait ni l'un ni l'autre ;
 *  2. un zap appelait stop() puis prepare() sans mettre le volume à 0 :
 *     le tampon AudioTrack (surtout en passthrough AC-3) continuait
 *     l'ancienne chaîne pendant que la nouvelle démarrait ;
 *  3. des callbacks tardifs (reconnexion, repli FFmpeg) rappelaient
 *     prepare()/play() sans jeton : une session déjà quittée repartait.
 *  Avant de démarrer, on prend le bail [owners] (tous les autres lecteurs
 *  passent volume 0 + stop), on invalide l'ancienne [sessions], et seulement
 *  ensuite on prépare. Le focus audio Android est demandé (true).
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
 *     « radio » qu'une chaîne bloquée. Ce repli ne touche PAS la vidéo.
 *
 * Communication avec Dart via un MethodChannel dédié (`native_video_player/<id>`).
 */
@UnstableApi
class NativeVideoView(
    context: Context,
    messenger: BinaryMessenger,
    id: Int,
) : PlatformView, MethodChannel.MethodCallHandler, AnalyticsListener {

    private val appContext: Context = context
    private val surfaceView = SurfaceView(context)

    /**
     * Dernière image, posée PAR-DESSUS la surface pendant une coupure.
     * stop() vide souvent la surface (écran noir). Cette copie, prise
     * pendant que ça jouait, reste visible jusqu'à la nouvelle trame.
     * Une seule image, petite (au plus 1280×720, RGB 565) : pas une
     * file d'images, la box a peu de mémoire.
     */
    private val holdView = ImageView(context).apply {
        visibility = View.GONE
        scaleType = ImageView.ScaleType.CENTER_CROP
        isFocusable = false
        isFocusableInTouchMode = false
    }
    private val root = FrameLayout(context).apply {
        val fill = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        )
        addView(surfaceView, fill)
        addView(
            holdView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
    }
    private val channel = MethodChannel(messenger, "native_video_player/$id")
    private lateinit var player: ExoPlayer
    private val handler = Handler(Looper.getMainLooper())

    private var currentUrl: String? = null

    // Mode film/épisode : la reconnexion reprend à [lastKnownPos].
    private var vodMode = false
    private var lastKnownPos = 0L
    private var lastSentDuration = -1L

    // Reconnexion auto silencieuse. Les délais et le « un seul essai
    // à la fois » sont dans [reconnect] (testé sans ExoPlayer).
    private val reconnect = ReconnectGate()
    private var pendingRetry: Runnable? = null

    // Dernière image copiée. null = on n'a encore rien de montrable.
    private var heldBitmap: Bitmap? = null
    private var copyInFlight = false
    private var lastCopyAt = 0L
    private var sawFrame = false

    // Direct sorti de sa fenêtre (Internet trop lent un moment). On rejoint
    // le direct sans compter une « panne », mais pas à l'infini : au-delà on
    // retombe sur la reconnexion normale, qui finit par prévenir Dart.
    private var behindLiveCount = 0
    private val maxBehindLive = 4

    // Son : vrai dès que le décodeur audio créé s'appelle « ffmpeg… »
    // (AnalyticsListener.onAudioDecoderInitialized). Remis à faux à chaque
    // setUrl et dès qu'un décodeur de la box prend la relève.
    @Volatile
    private var ffmpegAudioActive = false

    /**
     * L'essai « décodeur de la box » a échoué sur CETTE ouverture.
     * On reste sur FFmpeg jusqu'au prochain setUrl. Faux par défaut :
     * le chemin v106 ne le consulte que si le réglage est allumé.
     */
    private var platformAacGaveUp = false

    /**
     * REPLI AAC → BOX, pour CETTE chaîne seulement (voir [AacRoute]).
     * Avant (v103–v106) c'était un seul drapeau pour tout le processus :
     * une panne FFmpeg renvoyait toutes les chaînes AAC à la box, et le
     * son « vieille radio » revenait sur les chaînes déjà vues. Relu par
     * le sélecteur de décodeurs depuis le fil de lecture : @Volatile.
     */
    @Volatile
    private var forceBoxAacDecoder: Boolean = false

    /** Pourquoi cette chaîne est sur la box (null = FFmpeg). Pour la fiche. */
    private var boxFailure: AacRoute.Failure? = null

    // ---- FOCUS AUDIO géré par Zuno (01/10/2026) ----------------------------
    // Media3 (handleAudioFocus = true) baissait le son à 20 % dès qu'une
    // autre app ou un bip demandait le son « avec baisse », et ne le
    // remontait que si le système renvoyait GAIN, ce qui n'arrive pas
    // toujours : son « dans un trou » jusqu'au zap suivant. Ici on demande
    // le focus nous-mêmes et on applique [AudioFocusPolicy] : jamais de
    // baisse, pause seulement sur une vraie perte. [AudioFixes.androidFocus]
    // vrai = ancien comportement (Media3 gère).
    private val audioManager: AudioManager? =
        context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    private var focusRequest: AudioFocusRequest? = null
    private var focusHeld = false
    private var pausedByFocus = false
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        handler.post { onAudioFocusChange(change) }
    }

    /**
     * Lecture arrêtée parce que l'app est passée en arrière-plan (Home) :
     * décodeur et AudioTrack rendus, focus abandonné. « play » ou « resume »
     * rouvre la chaîne au direct (ou le film à sa position).
     */
    private var suspended = false

    /** Autres lectures audio actives sur la box (API 26+), pour la fiche. */
    private var playbackCallback: AudioManager.AudioPlaybackCallback? = null
    private var lastPlaybackLine: String? = null

    /**
     * Vrai dès que le lecteur a été « prêt » une fois dans cette session.
     * Le filet des 8 s ne se déclenche que si FFmpeg n'a JAMAIS rendu la
     * chaîne prête : un simple re-tamponnage réseau à la 8e seconde n'est
     * pas un échec de FFmpeg (c'était l'ancien déclencheur fantôme).
     */
    private var readyThisSession = false

    // Jeton du délai de 8 s : l'incrémenter annule le contrôle précédent
    // (zapping, repli, dispose) sans toucher aux autres callbacks du Handler.
    private var ffmpegWatchToken = 0

    // ---- UN SEUL AudioTrack (01/10/2026) -----------------------------------
    // Media3 1.5.1 rend l'AudioTrack APRÈS stop(), sur un fil, et
    // onAudioTrackReleased n'arrive qu'ensuite. [audioGate] retient le
    // prepare() tant qu'une piste est encore comptée. Les compteurs « ici »
    // sont ceux de CETTE vue. [owedTrackReleases] : on a déjà compté le
    // rendu (délai dépassé) ; le callback en retard ne doit pas décompter
    // la piste suivante.
    private val audioGate = AudioGate { AudioFixes.immediateHandoff }
    private var audioTracksHere = 0
    private var audioDecodersHere = 0
    private var owedTrackReleases = 0
    private var owedDecoderReleases = 0
    private var openDeferred = false
    private var deferredStartMs: Long? = null
    private var deferredToken = 0
    // Zap et libération ont chacun leur jeton : un silence (autre lecteur)
    // pendant le dispose ne doit pas annuler l'attente de la piste.
    private var waitToken = 0
    private var disposeWaitToken = 0
    private var disposeStarted = false
    private var disposeResult: MethodChannel.Result? = null
    private val trackWatcher: (Int) -> Unit = { alive -> onGlobalTracks(alive) }

    // true après releasePlayer : plus aucun appel ExoPlayer (release deux fois
    // fait planter, et un événement en retard ne doit pas parler à Dart).
    private var released = false

    // Jeton de CETTE vue. Un callback n'agit que s'il porte le dernier.
    private val sessions = PlaybackSession()

    // Horodatage du dernier silence / zap. Un événement Analytics plus
    // vieux que ça décrit l'ancienne chaîne : on le jette.
    private var sessionOpenedAt = 0L

    // Epoch Dart du setUrl en cours (accusé). null = pas un setUrl.
    private var dartEpoch: Int? = null

    // Langue audio demandée par l'app pour cette lecture.
    private var prefAudio: String? = null

    // true après le premier choix de piste de cette session.
    // Un second onTracksChanged (le nôtre, ou un choix manuel) ne reforce pas.
    private var audioChosenForSession = false

    // Voix claire. Faux par défaut : le processeur reste inactif.
    private var clearVoiceEnabled = false
    private val clearVoiceProcessor = ClearVoiceProcessor()

    // Quatre sondes. Coupées par défaut : onConfigure renvoie NOT_SET,
    // Media3 ne les insère pas. Allumées, chacune copie le PCM sans le modifier.
    // L'ordre est celui de [ZunoAudioChain] : décodeur, voix, silence, AudioTrack.
    private val probeDecoder = AudioProbeProcessor(AudioStages.DECODER, ::onProbe)
    private val probeVoice = AudioProbeProcessor(AudioStages.VOICE, ::onProbe)
    private val probeSilence = AudioProbeProcessor(AudioStages.SILENCE, ::onProbe)
    private val probeSink = AudioProbeProcessor(AudioStages.SINK, ::onProbe)

    // ---- DIAGNOSTIC DU SON (boîte noire, 01/10/2026) -----------------------
    // Pour chaque chaîne : ce qui ENTRE (format du flux), QUI décode (box ou
    // FFmpeg), ce qui SORT (AudioTrack) et les coupures. Envoyé à Dart
    // (« audioDiag ») qui le range dans la boîte noire (Réglages → Boîte
    // noire). Lecture seule : ne change RIEN à la lecture.
    private var diag = AudioSnapshot()
    private var diagLastUnderrunSentMs = 0L
    private var diagCapsSent = false

    // Trace de volume : une ligne par seconde, 10 s après chaque ouverture.
    // Incrémenté à chaque silence : les lignes de l'ancienne chaîne s'arrêtent.
    private var volumeTraceToken = 0

    // Dernier compteur Android. Vide tant que le rappel n'est pas arrivé.
    // getClientUid est bloqué sur Android 16 : on ne s'en sert que s'il
    // renvoie un vrai uid. Sinon la lecture qui naît avec notre AudioTrack
    // est la nôtre (voir AudioRouteState).
    private data class Heard(
        val usage: Int,
        val contentType: Int,
        val deviceType: Int,
        val deviceName: String,
        val uid: Int,
    )
    private var heard: List<Heard> = emptyList()
    private var heardReady = false
    /** Dernière fiche envoyée : on ne la réécrit pas si rien n'a changé. */
    private var lastDiagText: String? = null

    /** Ce que la sortie son de la box accepte tel quel (HDMI / barre de son). */
    private val outputCaps: String = try {
        val caps = AudioCapabilities.getCapabilities(context)
        fun yn(enc: Int) = if (caps.supportsEncoding(enc)) "oui" else "non"
        "Sortie de la box : AC-3 ${yn(C.ENCODING_AC3)}, E-AC-3 ${yn(C.ENCODING_E_AC3)}, " +
            "DTS ${yn(C.ENCODING_DTS)}, ${caps.maxChannelCount} voies max"
    } catch (_: Throwable) {
        "Sortie de la box : inconnue"
    }

    // Identifiant dans [owners]. -1 tant que le lecteur n'est pas inscrit.
    private var playerKey: Int = -1

    // Moteur vidéo. [preferredEngine] est le choix de la personne (matériel
    // par défaut). [videoEngine] est celui de la chaîne en cours : un repli
    // ne change pas le choix, la chaîne suivante repart du choix.
    private var preferredEngine: VideoEngine = VideoEngine.HARDWARE
    private var videoEngine: VideoEngine = VideoEngine.HARDWARE

    // Vrai seulement pendant la construction d'un lecteur qui doit mettre
    // FFmpeg vidéo EN PREMIER. Faux au démarrage : même liste qu'en v104.
    private var installFfmpegVideo: Boolean = false
    private var ffmpegRendererInstalled: Boolean = false

    // Relu à chaque demande de décodeur. Le logiciel passe devant seulement
    // quand [videoEngine] est SOFTWARE.
    @Volatile
    private var preferSoftwareVideo: Boolean = false

    private val triedEngines = HashSet<VideoEngine>()
    private var videoGaveUp: Boolean = false
    private var videoFallbackPosted: Boolean = false

    // Trames vraiment envoyées à l'écran. Le compteur est touché sur le
    // fil de lecture, lu sur le fil principal.
    private val renderedFrames = AtomicInteger(0)

    @Volatile
    private var lastFrameAtMs: Long = 0L

    /**
     * Une seule instance : Media3 n'accepte pas null, et
     * [ExoPlayer.clearVideoFrameMetadataListener] ne retire le
     * compteur que si on lui rend le même objet.
     */
    private val frameClock = VideoFrameMetadataListener { _, _, _, _ ->
        renderedFrames.incrementAndGet()
        lastFrameAtMs = SystemClock.elapsedRealtime()
    }
    private var videoDecoderReady: Boolean = false
    private var decoderReadyAtMs: Long = 0L
    private var contentFps: Float = 0f
    private var frameRateMatchEnabled: Boolean = false
    private var frameRateModeApplied: Boolean = false
    private var bytesLoaded: Long = 0L
    private var bitrateEstimate: Long = 0L
    private var videoChosenForSession: Boolean = false

    private val positionPump = object : Runnable {
        override fun run() {
            if (released) return
            if (player.isPlaying) {
                val pos = player.currentPosition
                if (vodMode) lastKnownPos = pos
                emit("position", pos)
                maybeCopyFrame()
            }
            sendDurationIfChanged()
            if (!released) handler.postDelayed(this, 500)
        }
    }

    /**
     * Toutes les 2 s : image noire (décodeur prêt, aucune trame) ou image
     * figée (plus de trame alors que ça joue). Un chargement en cours
     * ne compte pas. Un seul basculement à la fois.
     */
    private val pictureWatch = object : Runnable {
        override fun run() {
            if (!released) {
                considerPictureFallback()
                handler.postDelayed(this, 2_000)
            }
        }
    }

    /** Envoie un événement à Dart, sauf si le lecteur est déjà libéré. */
    private fun emit(method: String, args: Any?) {
        if (released) return
        channel.invokeMethod(method, args)
    }

    /** Durée totale (ms) envoyée UNE fois quand elle est connue / change. */
    private fun sendDurationIfChanged() {
        val d = player.duration
        if (d != C.TIME_UNSET && d > 0 && d != lastSentDuration) {
            lastSentDuration = d
            emit("duration", d)
        }
    }

    init {
        channel.setMethodCallHandler(this)

        // La SurfaceView ne doit PAS être focusable (sinon elle capte le D-pad
        // qui doit revenir au Focus Flutter) ; on garde l'écran allumé.
        surfaceView.isFocusable = false
        surfaceView.isFocusableInTouchMode = false
        surfaceView.keepScreenOn = true
        // OPAQUE : certaines puces (Amlogic & co.) laissent la surface
        // translucide et affichent un écran VERT à la place de la vidéo.
        // Opaque = le décodeur écrit des pixels réels, pas « du vide ».
        surfaceView.holder.setFormat(PixelFormat.OPAQUE)

        player = buildConfiguredPlayer()
        PlayerCensus.playerCreated()
        PlayerCensus.watchTracks(trackWatcher)
        // On NE retire PAS la surface au zap : la retirer fait un flash
        // noir. stop() rend le codec ; la surface, elle, reste. Le logo
        // Flutter couvre l'ancienne image jusqu'à la nouvelle trame.
        attachToSurface(player)
        playerKey = owners.register { silenceForHandoff() }

        handler.postDelayed(positionPump, 500)
        handler.postDelayed(pictureWatch, 2_000)
        handler.post { emitImageCaps() }
        watchOtherPlaybacks()
    }

    // ---- focus audio : demande, abandon, décision ----------------------------

    /**
     * Demande le focus pour nous (sauf si Media3 le gère : réglage de repli).
     * Déjà tenu : on ne redemande pas. API < 26 : l'ancienne méthode, les
     * mêmes codes (1 accordé, 0 refusé). La décision est [AudioFocusPolicy.onRequest].
     */
    private fun requestOwnFocus() {
        if (AudioFocusPolicy.media3HandlesFocus(AudioFixes.androidFocus)) return
        val am = audioManager ?: return
        // Déjà tenu : aucun second appel Android.
        if (!AudioFocusPolicy.onRequest(focusHeld, AudioFocusPolicy.REQUEST_GRANTED).asked) return
        val code = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val attrs = android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                    .setContentType(
                        if (clearVoiceEnabled) android.media.AudioAttributes.CONTENT_TYPE_SPEECH
                        else android.media.AudioAttributes.CONTENT_TYPE_MOVIE,
                    )
                    .build()
                val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(attrs)
                    // Pas de pause automatique sur « baisse demandée » : on décide.
                    .setWillPauseWhenDucked(false)
                    .setAcceptsDelayedFocusGain(false)
                    .setOnAudioFocusChangeListener(focusListener, handler)
                    .build()
                focusRequest = req
                am.requestAudioFocus(req)
            } else {
                @Suppress("DEPRECATION")
                am.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
            }
        } catch (_: RuntimeException) {
            AudioFocusPolicy.REQUEST_FAILED
        }
        val plan = AudioFocusPolicy.onRequest(alreadyHeld = false, systemCode = code)
        focusHeld = plan.held
        // Accordé : on n'est plus en pause à cause d'une perte. Refusé :
        // on ne baisse pas le volume, on le dit, et la lecture part quand
        // même à plein volume (une chaîne muette serait pire).
        if (plan.held) pausedByFocus = false
        plan.line?.let { emit("audioDiag", it) }
    }

    private fun abandonOwnFocus() {
        if (!focusHeld) return
        focusHeld = false
        pausedByFocus = false
        val am = audioManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                focusRequest?.let { am.abandonAudioFocusRequest(it) }
            } else {
                @Suppress("DEPRECATION")
                am.abandonAudioFocus(focusListener)
            }
        } catch (_: RuntimeException) {
            // Un abandon raté ne doit pas bloquer la suite.
        }
        emit("audioDiag", "Focus audio : abandonné.")
    }

    /** Sur le fil principal. Applique [AudioFocusPolicy] et le dit à la boîte noire. */
    private fun onAudioFocusChange(change: Int) {
        if (released) return
        val d = AudioFocusPolicy.decide(change, pausedByFocus, player.isPlaying)
        pausedByFocus = d.pausedByFocus
        emit("audioDiag", d.line)
        when (d.action) {
            AudioFocusPolicy.Action.PAUSE -> try { player.pause() } catch (_: RuntimeException) {}
            AudioFocusPolicy.Action.RESUME -> try {
                // Jamais 0,2 : le volume de lecture est 1, le silence de
                // passage (holdMute) reste 0 jusqu'à la nouvelle image.
                if (!reconnect.holdMute) {
                    player.volume = AudioHandoff.outputVolume(handoffMute = false, duckRequested = false)
                }
                player.play()
            } catch (_: RuntimeException) {}
            AudioFocusPolicy.Action.IGNORE, AudioFocusPolicy.Action.NONE -> Unit
        }
    }

    /**
     * Combien de lectures audio tournent sur la box en même temps que nous
     * (API 26+). Deux sons qui se battent = ce compteur à 2 pendant qu'on joue.
     * Une ligne par changement, jamais plus.
     */
    private fun watchOtherPlaybacks() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val am = audioManager ?: return
        val cb = object : AudioManager.AudioPlaybackCallback() {
            override fun onPlaybackConfigChanged(configs: MutableList<AudioPlaybackConfiguration>?) {
                val list = configs ?: return
                val next = list.map { c ->
                    val dev = routedOf(c)
                    Heard(
                        usage = c.audioAttributes.usage,
                        contentType = c.audioAttributes.contentType,
                        deviceType = dev.first,
                        deviceName = dev.second,
                        uid = playbackClientUid(c),
                    )
                }
                heard = next
                heardReady = true
                val owner = ownerNow()
                val line = "Annonces : Android en compte ${next.size}. " +
                    AudioRouteState.playbackPhrase(owner)
                if (line != lastPlaybackLine) {
                    lastPlaybackLine = line
                    handler.post {
                        if (released) return@post
                        emit("audioDiag", line)
                        // La fiche prend le compteur du moment, pas seulement la ligne.
                        if (diag.decoder != null || diag.outSampleRate > 0) sendAudioDiag()
                    }
                }
            }
        }
        try {
            am.registerAudioPlaybackCallback(cb, handler)
            playbackCallback = cb
        } catch (_: RuntimeException) {
            playbackCallback = null
        }
    }

    /**
     * UID du client de cette lecture. -1 si Android ne le dit pas
     * (avant Android 9, ou méthode absente du SDK de compilation).
     */
    private fun playbackClientUid(config: AudioPlaybackConfiguration): Int {
        if (Build.VERSION.SDK_INT < 28) return -1
        return try {
            val method = AudioPlaybackConfiguration::class.java.getMethod("getClientUid")
            method.invoke(config) as? Int ?: -1
        } catch (_: Exception) {
            // Android 16 bloque cette méthode cachée. -1 = on ne s'en sert pas.
            -1
        }
    }

    /** Sortie réelle de cette lecture. API 31+. (−1, "") si Android ne la dit pas. */
    private fun routedOf(config: AudioPlaybackConfiguration): Pair<Int, String> {
        if (Build.VERSION.SDK_INT < 31) return -1 to ""
        return try {
            val info = config.audioDeviceInfo ?: return -1 to ""
            info.type to AudioRouteState.safeName(info.productName?.toString())
        } catch (_: Throwable) {
            -1 to ""
        }
    }

    /**
     * Appareils qu'Android choisirait pour un son média « film »
     * (ou « parole » si voix claire). API 33+. Vide = pas lu.
     */
    private fun plannedTypes(): List<Int> {
        if (Build.VERSION.SDK_INT < 33) return emptyList()
        val am = audioManager ?: return emptyList()
        return try {
            val content = if (clearVoiceEnabled) {
                android.media.AudioAttributes.CONTENT_TYPE_SPEECH
            } else {
                android.media.AudioAttributes.CONTENT_TYPE_MOVIE
            }
            val attrs = android.media.AudioAttributes.Builder()
                .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                .setContentType(content)
                .build()
            am.getAudioDevicesForAttributes(attrs).map { it.type }
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun ownerNow(): AudioRouteState.Owner {
        val tracks = PlayerCensus.tracksAlive()
        if (!heardReady) return AudioRouteState.Owner.unknown(tracks)
        val real = heard.any { it.uid > 0 }
        val matches = if (real) heard.count { it.uid == Process.myUid() } else null
        return AudioRouteState.attribute(heard.size, matches, tracks)
    }

    /**
     * Dernière phrase de la garde, pour ne pas la répéter chaque seconde.
     * Remise à zéro à chaque ouverture.
     */
    private var lastModeGuardLine: String? = null

    /**
     * Interrupteur allumé ET mode d'appel : demande MODE_NORMAL une fois,
     * puis le dit. Coupé : retour immédiat, setMode n'est pas appelé.
     * La lecture du mode (currentFacts) reste à part : elle ne change rien.
     */
    private fun applyModeGuard() {
        if (!AudioFixes.restoreNormalMode || released) return
        val am = audioManager ?: return
        val before = try {
            am.mode
        } catch (_: RuntimeException) {
            return
        }
        if (AudioModeGuard.plan(enabled = true, mode = before).action !=
            AudioModeGuard.Action.SET_NORMAL
        ) {
            return
        }
        var threw = false
        try {
            am.setMode(AudioManager.MODE_NORMAL)
        } catch (_: RuntimeException) {
            threw = true
        }
        val after = if (threw) {
            before
        } else {
            try {
                am.mode
            } catch (_: RuntimeException) {
                -1
            }
        }
        val line = AudioModeGuard.resultLine(before, after, threw)
        if (line == lastModeGuardLine) return
        lastModeGuardLine = line
        emit("audioDiag", line)
    }

    /** Chiffres du chemin, lus maintenant. Ne change pas le mode Android. */
    private fun currentFacts(): AudioRouteState.Facts {
        val am = audioManager
        val mode = try {
            am?.mode ?: -1
        } catch (_: RuntimeException) {
            -1
        }
        val spk = try {
            am?.isSpeakerphoneOn ?: false
        } catch (_: RuntimeException) {
            false
        }
        val sco = try {
            am?.isBluetoothScoOn ?: false
        } catch (_: RuntimeException) {
            false
        }
        val primary = when {
            heard.size == 1 -> heard.first()
            else -> heard.firstOrNull { it.usage == android.media.AudioAttributes.USAGE_MEDIA }
                ?: heard.firstOrNull()
        }
        return AudioRouteState.Facts(
            mode = mode,
            speakerphone = spk,
            bluetoothSco = sco,
            routedType = primary?.deviceType ?: -1,
            routedName = primary?.deviceName ?: "",
            plannedTypes = plannedTypes(),
            usage = primary?.usage ?: -1,
            contentType = primary?.contentType ?: -1,
        )
    }

    private fun unwatchOtherPlaybacks() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val cb = playbackCallback ?: return
        playbackCallback = null
        try {
            audioManager?.unregisterAudioPlaybackCallback(cb)
        } catch (_: RuntimeException) {
        }
    }

    /**
     * Arrière-plan (Home, multitâche) : on ARRÊTE, on ne met pas en pause.
     * Une pause garde le décodeur, l'AudioTrack et le focus vivants pendant
     * que la box fait autre chose ; au retour, c'est ce qui sonnait faux.
     */
    private fun suspendForBackground() {
        if (released || suspended) return
        suspended = true
        if (vodMode && player.currentPosition > 0) lastKnownPos = player.currentPosition
        silenceForHandoff()
        abandonOwnFocus()
        emit("audioDiag", "Arrière-plan : lecture arrêtée, décodeur et sortie son rendus, focus rendu.")
    }

    /** Retour au premier plan : on rouvre, comme un zap (direct au bord du direct). */
    private fun resumeFromBackground() {
        if (released || !suspended) return
        suspended = false
        if (currentUrl == null) return
        // Ligne d'avant, gardée. La suivante précise film (position) ou direct.
        emit("audioDiag", "Retour : chaîne rouverte proprement (nouveau décodeur, nouvelle sortie son).")
        val plan = AudioHandoff.resume(vodMode, lastKnownPos)
        emit("audioDiag", plan.line)
        if (holdView.visibility != View.VISIBLE) emit("buffering", true)
        openCurrent(plan.startPositionMs)
        armFfmpegReadyWatchdog()
    }

    /**
     * Construit un ExoPlayer. Relu quand on passe à FFmpeg vidéo (rare) :
     * les rendus sont figés à la construction. Le chemin matériel
     * (installFfmpegVideo = false) est celui de la v104.
     */
    private fun buildConfiguredPlayer(): ExoPlayer {
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
        //
        // ON NE TOUCHE PAS À CES CHIFFRES. Preuve (29/09/2026, v99–v101) :
        // passer la reprise après coupure de 2 s à 5 s, en même temps que
        // d'autres réglages, a laissé des chaînes bloquées sur le logo.
        // Le matelas anti-saccade reste celui qui est déjà en production.
        // setBackBuffer(0) est le défaut : on ne garde PAS les images déjà
        // jouées (mémoire, et une vieille image ne peut pas rester à l'écran).
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                5_000,
                45_000,
                ReconnectPlan.BUFFER_FOR_PLAYBACK_MS,
                2_000,
            )
            .setPrioritizeTimeOverSizeThresholds(true)
            .setBackBuffer(0, false)
            .build()

        // DÉCODEUR VIDÉO. Matériel d'abord (MediaCodec Android, le plus
        // compatible sur les box), repli vers le décodeur suivant SEULEMENT
        // si l'init du premier échoue. On ne choisit pas un codec à la main :
        // en écarter un peut laisser une chaîne sans aucun décodeur capable
        // (logo infini). Pas de file asynchrone forcée : cet interrupteur
        // Media3 s'applique aussi au décodeur AUDIO.
        //
        // Joining = 0 : quand le HLS change de résolution, on ne demande PAS
        // au décodeur de « continuer sans coupure » pendant 5 s (le défaut).
        // Sur les puces bas de gamme cette attente se voit comme une image
        // FIGÉE. On recrée le décodeur tout de suite (un flash très court,
        // puis l'image repart). Un flux à une seule qualité (.ts classique)
        // ne change jamais de format : ce réglage ne le ralentit pas.
        //
        // SON : un 2e moteur audio, FFmpeg, placé APRÈS celui de la box. Media3
        // prend le premier moteur qui sait lire la piste : la box garde tout ce
        // qu'elle fait bien (dont le passthrough AC-3 vers l'ampli), FFmpeg prend
        // ce qu'elle ne sait pas lire. On l'ajoute nous-mêmes (et pas par le mode
        // « extension » qui passerait AUSSI par la vidéo) pour que R8 ne le
        // retire jamais, et pour que la vidéo reste sur MediaCodec.
        val renderersFactory = object : TvVideoRenderersFactory(appContext, installFfmpegVideo) {
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

            override fun buildAudioSink(
                context: Context,
                enableFloatOutput: Boolean,
                enableAudioTrackPlaybackParams: Boolean,
            ): AudioSink {
                // Tampon de sortie un peu plus grand (craquements), pas le
                // tampon réseau. Float coupé : certaines box crachent le PCM
                // flottant. Vitesse AudioTrack coupée : on joue à 1,0.
                val base = DefaultAudioSink.AudioTrackBufferSizeProvider.DEFAULT
                return DefaultAudioSink.Builder(appContext)
                    .setEnableFloatOutput(false)
                    .setEnableAudioTrackPlaybackParams(false)
                    // Sondes inactives tant que le réglage est coupé (NOT_SET).
                    // Voix claire coupée, silences non sautés, vitesse 1 :
                    // aucun processeur actif. Le son par défaut ne change pas.
                    .setAudioProcessorChain(
                        ZunoAudioChain(
                            probeDecoder,
                            clearVoiceProcessor,
                            probeVoice,
                            probeSilence,
                            probeSink,
                        ),
                    )
                    .setAudioTrackBufferSizeProvider { min, encoding, mode, frame, rate, bitrate, speed ->
                        val minBytes = base.getBufferSizeInBytes(
                            min, encoding, mode, frame, rate, bitrate, speed,
                        )
                        AudioTrackBuffer.sized(minBytes, frame)
                    }
                    .build()
            }
        }
            .setEnableDecoderFallback(true)
            .setAllowedVideoJoiningTimeMs(0)
            .setEnableAudioFloatOutput(false)
            .setEnableAudioTrackPlaybackParams(false)
            // AAC → on « cache » le décodeur AAC de la box pour que FFmpeg le
            // lise (HE-AAC complet : aigus + stéréo). Tout le reste (vidéo, AC-3,
            // DTS…) passe par la liste normale. Si FFmpeg n'a pas pu se charger,
            // ou si le repli session est armé, rien ne change : la box garde son
            // décodeur AAC.
            // Le drapeau [forceBoxAacDecoder] est relu À CHAQUE appel : Media3
            // redemande la liste à chaque sélection de pistes (donc à chaque
            // re-prepare), il n'y a pas de copie figée au moment du build.
            .setMediaCodecSelector { mimeType, requiresSecure, requiresTunneling ->
                val all = MediaCodecSelector.DEFAULT.getDecoderInfos(
                    mimeType, requiresSecure, requiresTunneling,
                )
                if (mimeType.startsWith("video/")) {
                    // Matériel d'abord, sauf repli / option logiciel. On ne
                    // retire aucun codec : une liste sans logiciel reste
                    // celle de la box.
                    val ordered = CodecOrder.order(
                        all.map { NamedCodec(it.name) },
                        preferSoftwareVideo,
                    )
                    ordered.mapNotNull { want -> all.firstOrNull { it.name == want.name } }
                } else if (preferFfmpegFor(mimeType)) {
                    emptyList<MediaCodecInfo>()
                } else {
                    all
                }
            }

        // Direct HLS : Media3 fait varier la vitesse (0,97–1,03) pour tenir la
        // latence ; l'étirement du son qui en résulte s'entend. On la fige à 1,0
        // (l'IPTV n'a pas besoin d'une latence au dixième de seconde).
        val liveSpeed = DefaultLivePlaybackSpeedControl.Builder()
            .setFallbackMinPlaybackSpeed(1f)
            .setFallbackMaxPlaybackSpeed(1f)
            .build()

        // « film » par défaut. « voix claire » passe en SPEECH le temps
        // de la lecture (le téléviseur peut alors appliquer son propre
        // renfort de dialogue). Le focus audio est VRAI : un second
        // lecteur, ou une autre app, ne se mélange plus au nôtre.
        // L'aperçu est coupé explicitement avant le plein écran (bail),
        // donc il ne reprend pas le focus par-dessus la chaîne.
        val audioAttributes = movieAudioAttributes()

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

        // Politique de ré-essai réseau AGRESSIVE : on retente beaucoup avant
        // d'abandonner un chargement (le direct IPTV coupe souvent brièvement).
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)
            .setLoadErrorHandlingPolicy(DefaultLoadErrorHandlingPolicy(6))

        // QUALITÉ HLS (plusieurs débits dans la même chaîne). On part des
        // défauts Media3 (montée après 10 s de réserve, descente seulement
        // si le matelas tombe sous 25 s, 70 % du débit mesuré). On change
        // UNE chose : on ne JETTE jamais les images déjà en mémoire pour
        // monter plus vite (max largeur/hauteur à jeter = 0). Les jeter
        // faisait un trou noir au moment du changement de résolution.
        //
        // Ce qu'on ne fait PAS (ça a bloqué des chaînes, v99) :
        //   • aucun plafond de débit ou de taille « ou rien » ;
        //   • si aucune qualité ne « rentre » dans l'écran, on joue QUAND
        //     MÊME la piste (exceed = true) — une chaîne 4K sur une TV
        //     1080p doit démarrer, pas rester sur le logo ;
        //   • pas de tunneling audio/vidéo (écran noir fréquent sur ces box) ;
        //   • un changement de qualité non « sans couture » est autorisé :
        //     mieux vaut un bref raccord qu'une image qui ne bouge plus.
        // Un flux à UNE piste (.ts) ignore tout ça : une seule qualité.
        val trackSelector = DefaultTrackSelector(
            appContext,
            AdaptiveTrackSelection.Factory(
                /* minDurationForQualityIncreaseMs = */ 10_000,
                /* maxDurationForQualityDecreaseMs = */ 25_000,
                /* minDurationToRetainAfterDiscardMs = */ 25_000,
                /* maxWidthToDiscard = */ 0,
                /* maxHeightToDiscard = */ 0,
                /* bandwidthFraction = */ 0.7f,
            ),
        )
        trackSelector.setParameters(
            trackSelector.buildUponParameters()
                .setExceedVideoConstraintsIfNecessary(true)
                .setExceedRendererCapabilitiesIfNecessary(true)
                .setAllowVideoNonSeamlessAdaptiveness(true)
                // Un flux qui change de codec vidéo (H.264 → HEVC) ne doit
                // pas rester figé : on autorise le changement. On ne force
                // pas un décodeur à la main (en écarter un a déjà laissé
                // des chaînes sans image).
                .setAllowVideoMixedMimeTypeAdaptiveness(true)
                // La voix « principale », pas le commentaire, quand le
                // flux a mis le drapeau. Sinon le choix fin est dans
                // [SpokenTrackChoice], au moment où les pistes arrivent.
                .setPreferredAudioRoleFlags(C.ROLE_FLAG_MAIN)
                .setTunnelingEnabled(false)
                .build(),
        )

        return ExoPlayer.Builder(appContext, renderersFactory)
            .setTrackSelector(trackSelector)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(mediaSourceFactory)
            .setLivePlaybackSpeedControl(liveSpeed)
            // Focus audio : Zuno le gère lui-même (false), sauf réglage de repli.
            // Relu à chaque ouverture dans openCurrent.
            .setAudioAttributes(
                audioAttributes,
                /* handleAudioFocus = */ AudioFocusPolicy.media3HandlesFocus(AudioFixes.androidFocus),
            )
            // OFF : ne pas demander à la TV de changer de fréquence HDMI
            // (50 Hz ↔ 60 Hz). Sur beaucoup de box ce changement coupe
            // l'image (écran noir de une à plusieurs secondes) et décale
            // l'image par rapport au son. Le décodeur, lui, continue de
            // jeter les images en retard : le son reste le chef d'orchestre,
            // sans qu'on touche au décodeur audio.
            .setVideoChangeFrameRateStrategy(C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_OFF)
            .setHandleAudioBecomingNoisy(true)
            .build()
    }

    /** Profil audio : film, ou parole si la voix claire est allumée. */
    private fun movieAudioAttributes(): AudioAttributes {
        val type = if (clearVoiceEnabled) {
            C.AUDIO_CONTENT_TYPE_SPEECH
        } else {
            C.AUDIO_CONTENT_TYPE_MOVIE
        }
        return AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(type)
            .build()
    }

    /**
     * AAC et MP2 passent par FFmpeg quand il sait les lire. AC-3, E-AC-3
     * et DTS restent sur le décodeur de la box (passthrough HDMI). Le MP2
     * des flux MPEG-TS est souvent mal décodé par les puces bon marché
     * (craquements) ; FFmpeg est le décodeur de référence, avec le même
     * repli « retour à la box » que l'AAC si ça bloque.
     */
    private fun preferFfmpegFor(mimeType: String): Boolean {
        if (!ffmpegReady) return false
        if (mimeType == MimeTypes.AUDIO_AAC) {
            // Défaut : FFmpeg, comme la v106. Le réglage « décodeur de la box »
            // est le seul cas où la liste MediaCodec AAC n'est pas vidée.
            return AudioFixes.ffmpegForAac(
                preferPlatform = AudioFixes.preferPlatformAac,
                gaveUpToFfmpeg = platformAacGaveUp,
                forceBox = forceBoxAacDecoder,
                ffmpegReady = true,
                ffmpegSupports = ffmpegAac,
            )
        }
        if (forceBoxAacDecoder) return false
        return when (mimeType) {
            MimeTypes.AUDIO_MPEG_L2 -> ffmpegMp2
            else -> false
        }
    }

    override fun getView(): View = root

    // ---- Dart → natif -------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setUrl" -> {
                // L'accusé part APRÈS le silence (volume 0 + stop), dans
                // [openCurrent]. Les événements déjà dans le canal (ancienne
                // chaîne) arrivent avant l'ack : Dart les ignore. Un
                // événement né après le silence porte un horodatage neuf.
                val epoch = call.argument<Number>("epoch")?.toInt()
                dartEpoch = epoch
                val url = call.argument<String>("url")
                if (url.isNullOrEmpty()) {
                    result.error("no_url", "setUrl appelé sans url", null)
                    return
                }
                cancelRetry()
                // Budget remis à zéro SEULEMENT pour une autre adresse.
                // La même adresse (gel, coupure) garde le compteur : après
                // 8 essais on prévient Dart, on ne boucle pas sans fin.
                // On annule aussi l'attente en cours : Dart ré-ouvre, le
                // délai natif ne doit pas préparer une seconde fois.
                if (url != currentUrl) {
                    reconnect.onDifferentUrl()
                    discardHeldFrame()
                    sawFrame = false
                } else {
                    reconnect.onExternalReopen()
                }
                behindLiveCount = 0
                currentUrl = url
                vodMode = call.argument<Boolean>("vod") ?: false
                val startMs = (call.argument<Number>("startMs"))?.toLong() ?: 0L
                lastKnownPos = startMs
                lastSentDuration = -1L
                // Nouveau flux : on ne sait pas encore quel décodeur audio
                // va être créé. Le délai de 8 s ne doit pas hériter du « ffmpeg »
                // de la chaîne précédente.
                ffmpegAudioActive = false
                audioChosenForSession = false
                videoChosenForSession = false
                // Nouvelle demande Dart : on repart du moteur choisi, pas
                // du repli de la chaîne d'avant. Le repli automatique, lui,
                // n'appelle pas setUrl : il garde le moteur qui vient de
                // prendre le relais.
                triedEngines.clear()
                videoGaveUp = false
                restorePreferredEngine()
                // Recensement : numéro du zap et « déjà vue ». Aucune URL
                // gardée, seulement son hachage.
                val zapNo = PlayerCensus.onZap(AacRoute.key(url))
                emit("audioDiag", "Zap : n°$zapNo.")
                // Repli AAC → box PAR CHAÎNE : seule une chaîne où FFmpeg a
                // vraiment échoué repasse par la box. « FFmpeg : réessayer »
                // efface d'abord sa mémoire. Le filet des 8 s reste armé plus bas.
                boxFailure = AacRoute.decideForOpen(url, AudioFixes.keepFfmpeg)
                forceBoxAacDecoder = boxFailure != null
                boxFailure?.let { f ->
                    emit(
                        "audioDiag",
                        "Repli : cette chaîne est jouée par le décodeur AAC de la box " +
                            "(${f.reason.label} au zap n°${f.zap} ; zap en cours n°$zapNo).",
                    )
                }
                // Nouvel essai : le repli « box échouée → FFmpeg » ne suit
                // pas la chaîne d'avant.
                platformAacGaveUp = false
                // Diagnostic du son : nouvelle chaîne, compteurs à zéro.
                diag = AudioSnapshot(clearVoice = clearVoiceEnabled)
                diagLastUnderrunSentMs = 0L
                lastDiagText = null
                // Langue audio / sous-titres préférée (langue de l'app) : si le
                // film propose la piste, ExoPlayer la choisit d'office.
                prefAudio = call.argument<String>("preferredAudio")
                val prefText = call.argument<String>("preferredText")
                if (prefAudio != null || prefText != null) {
                    val b = player.trackSelectionParameters.buildUpon()
                    if (prefAudio != null) b.setPreferredAudioLanguage(prefAudio)
                    if (prefText != null) b.setPreferredTextLanguage(prefText)
                    player.trackSelectionParameters = b.build()
                }
                openCurrent(if (vodMode && startMs > 0L) startMs else null)
                // 8 s pour que FFmpeg prouve qu'il sait lire CE flux. Sinon on
                // revient à la box (voir [armFfmpegReadyWatchdog]).
                armFfmpegReadyWatchdog()
                result.success(null)
            }
            "silence" -> {
                // Un autre lecteur a pris le son. On se tait et on invalide
                // la session : un retry déjà posté ne doit pas relancer.
                silenceForHandoff()
                result.success(null)
            }
            "setEngine" -> {
                // Choix manuel. « ffmpeg » sans décodeur vidéo ne rouvre
                // pas la chaîne : on le dit, et on reste où on est.
                val requested = VideoEngine.fromWire(call.arguments as? String)
                if (requested == VideoEngine.FFMPEG && !ffmpegVideoReady) {
                    emitEngine(rejected = "ffmpeg")
                    result.success(null)
                    return
                }
                preferredEngine = requested
                triedEngines.clear()
                videoGaveUp = false
                applyEngine(requested, reopen = currentUrl != null)
                result.success(null)
            }
            "setFrameRateMatch" -> {
                frameRateMatchEnabled = call.arguments == true
                if (!frameRateMatchEnabled) {
                    clearFrameRateMode()
                } else if (contentFps > 0f) {
                    applyFrameRate(contentFps)
                }
                result.success(null)
            }
            "setContrast" -> {
                // Le filtre OpenGL quitterait la Surface. On ne l'allume
                // pas : hardwareAllows reste faux, la fonction testée
                // renvoie donc faux. LIGHT_CONTRAST n'est pas appliqué.
                val requested = call.arguments == true
                val applied = PictureTune.resolve(requested, hardwareAllows = false)
                emit("contrast", applied)
                if (requested && !applied) {
                    emit("contrastReason", "surface")
                }
                result.success(applied)
            }
            "setClearVoice" -> {
                val on = call.arguments == true
                if (on == clearVoiceEnabled) {
                    result.success(null)
                    return
                }
                clearVoiceEnabled = on
                clearVoiceProcessor.enabled = on
                // Le processeur n'est relu qu'à la prochaine configuration
                // du sink. Si une chaîne joue, on la rouvre (même URL) pour
                // que le choix prenne effet. Sinon, le prochain zap suffit.
                if (!released && currentUrl != null &&
                    player.playbackState != Player.STATE_IDLE
                ) {
                    if (vodMode && player.currentPosition > 0) {
                        lastKnownPos = player.currentPosition
                    }
                    openCurrent(if (vodMode) lastKnownPos else null)
                } else if (!released) {
                    player.setAudioAttributes(
                        movieAudioAttributes(),
                        AudioFocusPolicy.media3HandlesFocus(AudioFixes.androidFocus),
                    )
                }
                result.success(null)
            }
            "setAndroidFocus" -> {
                // Repli : vrai = Media3 reprend le focus (avec sa baisse à 20 %).
                // Pris en compte à la prochaine ouverture.
                AudioFixes.androidFocus = call.arguments == true
                result.success(null)
            }
            "suspend" -> {
                suspendForBackground()
                result.success(null)
            }
            "resume" -> {
                resumeFromBackground()
                result.success(null)
            }
            "setAudioProbe" -> {
                val on = call.arguments == true
                val turningOn = on && !AudioFixes.probe
                AudioFixes.probe = on
                setProbeEnabled(AudioFixes.probe)
                // Coupé : on oublie le chiffre du passage précédent. Sinon
                // la fiche affiche encore 0,8 % alors que l'interrupteur est éteint.
                if (!AudioFixes.probe && !released) {
                    diag = diag.copy(
                        spectrum = null,
                        stages = emptyList(),
                        probeRequested = false,
                        probeInChain = false,
                        probeFrames = 0,
                        probeReject = null,
                    )
                    sendAudioDiag()
                } else if (ProbeAttach.shouldReopen(turningOn, probeIsPlaying())) {
                    // Media3 ne rappelle onConfigure que si on reconfigure
                    // le sink. Allumer le drapeau sur une chaîne déjà ouverte
                    // laissait la sonde en NOT_SET jusqu'au zap, et parfois
                    // même après (piste réutilisée, flush sans reconfigure).
                    emit(
                        "audioDiag",
                        "Sonde : allumée. On rouvre la chaîne pour la brancher, sans changer les échantillons.",
                    )
                    if (vodMode && player.currentPosition > 0) lastKnownPos = player.currentPosition
                    openCurrent(if (vodMode) lastKnownPos else null)
                } else if (turningOn && !released) {
                    emit(
                        "audioDiag",
                        "Sonde : allumée. Branchée à la prochaine ouverture, sans changer les échantillons.",
                    )
                }
                result.success(null)
            }
            "setKeepFfmpeg" -> {
                // Pris en compte au prochain setUrl (forceBoxAfterOpen).
                // On ne rouvre pas la chaîne tout seul.
                AudioFixes.keepFfmpeg = call.arguments == true
                result.success(null)
            }
            "setPreferPlatformAac" -> {
                // Pris en compte au prochain setUrl. On ne rouvre pas.
                AudioFixes.preferPlatformAac = call.arguments == true
                result.success(null)
            }
            "setImmediateHandoff" -> {
                // Repli du passage « un seul AudioTrack » : vrai = on n'attend
                // pas le rendu (ancien comportement, deux pistes possibles).
                // Pris en compte au prochain zap. On ne rouvre pas.
                AudioFixes.immediateHandoff = call.arguments == true
                result.success(null)
            }
            "setRestoreNormalMode" -> {
                // Garde mode appel. Faux (le défaut) : on ne touche pas au mode.
                // Vrai : si le mode lu est un appel, on demande le retour à normal.
                val on = call.arguments == true
                AudioFixes.restoreNormalMode = on
                if (on && !released) {
                    lastModeGuardLine = null
                    applyModeGuard()
                }
                result.success(null)
            }
            "setSessionWideFallback" -> {
                // Interrupteur de repli du correctif « repli par chaîne » :
                // vrai = ancien comportement (une panne → la box partout).
                // Pris en compte au prochain setUrl. On ne rouvre pas.
                AacRoute.sessionWide = call.arguments == true
                result.success(null)
            }
            "dispose" -> {
                // Dart attend la réponse : on ne la donne qu'une fois
                // l'AudioTrack vraiment rendu (ou le délai dépassé). Sinon
                // le plein écran en créerait un second par-dessus.
                beginDispose(result)
            }
            "seekTo" -> {
                val ms = (call.argument<Number>("ms"))?.toLong() ?: 0L
                val dur = player.duration
                val target = if (dur != C.TIME_UNSET && dur > 0) ms.coerceIn(0L, dur) else ms.coerceAtLeast(0L)
                player.seekTo(target)
                lastKnownPos = target
                emit("position", target)
                result.success(null)
            }
            "selectTrack" -> {
                // Choix explicite. On ne le réécrase pas au prochain
                // onTracksChanged de cette session.
                audioChosenForSession = true
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
                emit("cues", "")
                result.success(null)
            }
            "play" -> {
                // Un lecteur déjà coupé par un autre ne reprend pas le son
                // (sinon le retour au premier plan relancerait l'ancienne chaîne).
                if (playerKey >= 0 && owners.owner != null && owners.owner != playerKey) {
                    result.success(null)
                    return
                }
                // Lecture arrêtée pour l'arrière-plan : « play » rouvre
                // (film : à sa position). Un simple play() sur un lecteur
                // vidé ne ferait rien.
                if (suspended) {
                    resumeFromBackground()
                    result.success(null)
                    return
                }
                // Pendant une reconnexion le volume reste à 0 : le remettre
                // ici ferait ressortir l'ancien tampon. La nouvelle session
                // le remonte toute seule (unmuteIfThisSession).
                pausedByFocus = false
                requestOwnFocus()
                if (!reconnect.holdMute && !pausedByFocus) {
                    player.volume = AudioHandoff.VOLUME_FULL
                }
                player.play()
                result.success(null)
            }
            "pause" -> {
                pausedByFocus = false
                player.pause()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ---- natif → Dart (AnalyticsListener) ----------------------------------
    //
    // Chaque événement porte l'heure à laquelle il a été PRODUIT, pas
    // l'heure à laquelle on le reçoit. Un zap ou un silence note
    // [sessionOpenedAt] : tout ce qui est plus vieux est l'ancienne
    // chaîne (1re image figée, position, « je joue ») et on le jette.

    private fun fresh(eventTime: AnalyticsListener.EventTime): Boolean {
        if (released) return false
        return eventTime.realtimeMs >= sessionOpenedAt && sessionOpenedAt > 0L
    }

    override fun onPlaybackStateChanged(eventTime: AnalyticsListener.EventTime, state: Int) {
        if (!fresh(eventTime)) return
        when (state) {
            Player.STATE_BUFFERING -> emit("buffering", true)
            Player.STATE_READY -> {
                // On annule une ré-ouverture devenue inutile, MAIS on ne
                // remet pas le budget à zéro ici : « prêt » arrive parfois
                // une fraction de seconde avant un nouvel échec. Le budget
                // repart seulement quand l'image ou le son est vraiment là
                // (voir onRenderedFirstFrame / onIsPlayingChanged).
                // On n'annonce pas « plus en tampon » tant que la copie
                // de la dernière image couvre la surface : sinon Flutter
                // découvrirait le noir avant la nouvelle trame.
                cancelRetry()
                behindLiveCount = 0
                // FFmpeg (ou la box) a rendu cette chaîne prête : le filet
                // des 8 s n'a plus lieu de basculer le décodeur.
                readyThisSession = true
                if (holdView.visibility != View.VISIBLE) {
                    emit("buffering", false)
                }
            }
            Player.STATE_ENDED -> emit("ended", null)
            Player.STATE_IDLE -> { /* après erreur : géré par onPlayerError */ }
        }
    }

    override fun onIsPlayingChanged(eventTime: AnalyticsListener.EventTime, isPlaying: Boolean) {
        if (!fresh(eventTime)) return
        emit("playing", isPlaying)
        // Le son de CETTE session seulement. Avant, le volume remontait
        // juste après prepare() : le tampon HDMI de l'ancienne chaîne
        // (surtout en AC-3) sortait encore pendant que la nouvelle
        // démarrait. Ici on attend que le lecteur dise « je joue ».
        if (isPlaying) {
            reconnect.onRecovered()
            unmuteIfThisSession()
        }
    }

    /** Pistes disponibles → Dart, puis choix de la voix (une fois). */
    override fun onTracksChanged(eventTime: AnalyticsListener.EventTime, tracks: Tracks) {
        if (!fresh(eventTime)) return
        val out = ArrayList<Map<String, Any?>>()
        val audio = ArrayList<SpokenCandidate>()
        tracks.groups.forEachIndexed { gi, g ->
            val type = when (g.type) {
                C.TRACK_TYPE_AUDIO -> "audio"
                C.TRACK_TYPE_TEXT -> "text"
                else -> null
            } ?: return@forEachIndexed
            for (i in 0 until g.length) {
                if (!g.isTrackSupported(i)) continue
                val f = g.getTrackFormat(i)
                val selected = g.isTrackSelected(i)
                out.add(
                    mapOf(
                        "type" to type,
                        "group" to gi,
                        "index" to i,
                        "language" to f.language,
                        "label" to f.label,
                        "channels" to f.channelCount,
                        "selected" to selected,
                        "roleFlags" to f.roleFlags,
                    )
                )
                if (type == "audio") {
                    audio.add(
                        SpokenCandidate(
                            group = gi,
                            index = i,
                            language = f.language,
                            label = f.label,
                            channels = f.channelCount,
                            selected = selected,
                            roleFlags = f.roleFlags,
                        )
                    )
                }
            }
        }
        var audioCount = 0
        var wider = 0
        for (row in out) {
            if (row["type"] != "audio") continue
            audioCount++
            val ch = (row["channels"] as? Int) ?: 0
            val selected = row["selected"] == true
            if (!selected && ch > wider) wider = ch
        }
        diag = diag.copy(audioTrackCount = audioCount, widerTrackChannels = wider)
        if (diag.outSampleRate > 0 || diag.decoder != null) sendAudioDiag()
        emit("tracks", out)
        maybeChooseVideo(tracks)
        if (audioChosenForSession) return
        val pick = SpokenTrackChoice.pick(audio, prefAudio) ?: return
        audioChosenForSession = true
        val token = sessions.generation
        // Posté : on ne change pas la sélection au milieu du callback.
        handler.post {
            if (released || token != sessions.generation) return@post
            val groups = player.currentTracks.groups
            if (pick.group < 0 || pick.group >= groups.size) return@post
            val g = groups[pick.group]
            if (g.type != C.TRACK_TYPE_AUDIO) return@post
            if (pick.index < 0 || pick.index >= g.length) return@post
            player.trackSelectionParameters = player.trackSelectionParameters
                .buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                .setOverrideForType(TrackSelectionOverride(g.mediaTrackGroup, pick.index))
                .build()
        }
    }

    /** Texte des sous-titres courants → Dart (vide = rien à afficher). */
    override fun onCues(eventTime: AnalyticsListener.EventTime, cueGroup: CueGroup) {
        if (!fresh(eventTime)) return
        val text = cueGroup.cues.mapNotNull { it.text?.toString() }.joinToString("\n")
        emit("cues", text)
    }

    override fun onRenderedFirstFrame(
        eventTime: AnalyticsListener.EventTime,
        output: Any,
        renderTimeMs: Long,
    ) {
        // L'heure de l'événement, pas « maintenant » : une trame déjà
        // décodée avant le zap ne retire pas le logo de la nouvelle chaîne.
        if (!fresh(eventTime)) return
        reconnect.onRecovered()
        behindLiveCount = 0
        sawFrame = true
        // La nouvelle trame est à l'écran : on retire la copie.
        hideHeldFrame()
        emit("holdFrame", false)
        emit("reconnecting", false)
        emit("buffering", false)
        unmuteIfThisSession()
        emit("firstFrame", null)
        // Une copie tôt : si la coupure arrive dans les secondes qui
        // suivent, on a déjà une image à montrer.
        handler.postDelayed({
            if (!released) maybeCopyFrame(force = true)
        }, 400)
    }

    override fun onVideoDecoderInitialized(
        eventTime: AnalyticsListener.EventTime,
        decoderName: String,
        initializedTimestampMs: Long,
        initializationDurationMs: Long,
    ) {
        if (!fresh(eventTime)) return
        videoDecoderReady = true
        decoderReadyAtMs = SystemClock.elapsedRealtime()
        emit("videoDecoder", decoderName)
    }

    override fun onVideoInputFormatChanged(
        eventTime: AnalyticsListener.EventTime,
        format: Format,
        decoderReuseEvaluation: DecoderReuseEvaluation?,
    ) {
        if (!fresh(eventTime)) return
        val fps = format.frameRate
        if (fps > 0f) {
            contentFps = fps
            applyFrameRate(fps)
        }
    }

    override fun onBandwidthEstimate(
        eventTime: AnalyticsListener.EventTime,
        totalLoadTimeMs: Int,
        totalBytesLoaded: Long,
        bitrateEstimate: Long,
    ) {
        if (!fresh(eventTime)) return
        bytesLoaded = totalBytesLoaded
        this.bitrateEstimate = bitrateEstimate
    }

    override fun onVideoCodecError(
        eventTime: AnalyticsListener.EventTime,
        videoCodecError: Exception,
    ) {
        // Media3 : cet appel n'est PAS un échec de lecture. Le lecteur
        // peut s'en remettre. Changer de moteur ici couperait une image
        // qui va revenir. L'échec réel arrive par onPlayerError.
    }

    override fun onPlayerError(eventTime: AnalyticsListener.EventTime, error: PlaybackException) {
        if (!fresh(eventTime)) return
        val token = sessions.generation
        val exo = error as? ExoPlaybackException
        val signal = DecoderFallback.classify(error.errorCode, exo?.rendererName)
        // Vidéo seulement. Une erreur audio FFmpeg garde son propre repli
        // (plus bas) et ne doit pas changer le décodeur d'image.
        if (signal == PictureSignal.DECODE && takeVideoFallback(signal)) {
            return
        }
        // Erreur DU MOTEUR FFmpeg (rendererName « FfmpegAudioRenderer ») :
        // retenter le même moteur reproduirait le blocage v99. On bascule
        // sur le décodeur de la box et on re-prépare tout de suite, SANS
        // entrer dans le back-off de reconnexion (qui, lui, ne change pas).
        // Ça ne compte pas comme une panne de chaîne.
        if (!forceBoxAacDecoder && isFfmpegRendererError(error) && signal != PictureSignal.DECODE) {
            requestBoxAudioFallback(AacRoute.Reason.RENDERER_ERROR)
            return
        }
        // DIRECT « EN RETARD » : le lecteur est sorti de la fenêtre du
        // direct. Ce n'est PAS une panne de chaîne (doc Media3). On rouvre
        // au bord du direct (stop + nouveau média), pas un seek par-dessus
        // l'ancien tampon : sinon le son reste en avance sur l'image.
        if (!vodMode &&
            error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW &&
            behindLiveCount < maxBehindLive
        ) {
            behindLiveCount++
            try {
                player.volume = 0f
            } catch (_: RuntimeException) {
                // Même filet que la reconnexion : pas de second son.
            }
            if (sawFrame && heldBitmap != null) {
                showHeldFrame()
                emit("holdFrame", true)
            } else {
                emit("buffering", true)
            }
            handler.post {
                if (released || token != sessions.generation) return@post
                openCurrent(null)
            }
            return
        }
        // RECONNEXION SILENCIEUSE. Délai croissant (1 s, 2 s, 4 s, 8 s).
        // On ne prépare pas une seconde fois si une attente est déjà là
        // (deux prepare = deux sons). Le volume tombe à 0 tout de suite :
        // l'ancienne piste ne continue pas pendant l'attente.
        val delay = reconnect.onFailure()
        if (delay == null) {
            if (!reconnect.retryPending) {
                emit("reconnecting", false)
                emit("holdFrame", false)
                emit("error", error.message)
            }
            return
        }
        try {
            player.volume = 0f
        } catch (_: RuntimeException) {
            // Un volume refusé ne doit pas empêcher la ré-ouverture.
        }
        if (vodMode && player.currentPosition > 0) lastKnownPos = player.currentPosition
        // Image déjà vue : on la montre (copie) et on NE demande PAS
        // à Flutter un panneau opaque. Sans copie, le panneau (numéro
        // de chaîne) vaut mieux qu'une surface vide.
        if (sawFrame && heldBitmap != null) {
            showHeldFrame()
            emit("holdFrame", true)
        } else {
            emit("holdFrame", false)
            emit("buffering", true)
        }
        emit("reconnecting", true)
        scheduleRetry(delay, token)
    }

    /**
     * Coupe CE lecteur sans en démarrer un autre. Volume 0 d'abord :
     * stop() seul laisse parfois le tampon HDMI (AC-3) sortir encore
     * l'ancienne chaîne. Le jeton change : les callbacks déjà postés
     * ne relancent plus cette session.
     */
    private fun silenceForHandoff() {
        if (released) return
        pausedByFocus = false
        sessions.open()
        sessionOpenedAt = SystemClock.elapsedRealtime()
        audioChosenForSession = false
        videoChosenForSession = false
        readyThisSession = false
        // Le drapeau « FFmpeg décode » est celui de CETTE ouverture.
        // Le laisser vrai au retour d'arrière-plan faisait tomber le filet
        // des 8 s sur un direct lent, et la chaîne passait à la box.
        ffmpegAudioActive = false
        // Une attente d'AudioTrack de la session d'avant ne doit pas
        // ouvrir par-dessus celle-ci.
        audioGate.cancel()
        openDeferred = false
        waitToken++
        // Les « Seconde N » de l'ancienne chaîne ne s'écrivent plus.
        volumeTraceToken++
        resetPictureClock()
        ffmpegWatchToken++
        cancelRetry()
        try {
            player.volume = 0f
            player.playWhenReady = false
            player.stop()
            player.clearMediaItems()
        } catch (_: RuntimeException) {
            // Un stop raté ne doit pas empêcher le lecteur suivant de parler.
        }
    }

    /**
     * Ouvre [currentUrl] en rendant d'abord l'ancien décodeur, l'ancienne
     * socket, ET le son des autres lecteurs (aperçu, sonde, film).
     *
     * Ordre, volontaire :
     *  1. les AUTRES passent volume 0 + stop (un seul AudioTrack parle) ;
     *  2. nous aussi, volume 0, avant le nouveau prepare ;
     *  3. accusé Dart (les événements d'avant sont ignorés) ;
     *  4. nouveau média, puis volume 1.
     *
     * On ne détache PAS la surface : la détacher fait un flash noir.
     * [startPositionMs] > 0 : reprise d'un film. Le direct passe null
     * et repart du bord du direct, pas d'une image figée.
     */
    private fun openCurrent(startPositionMs: Long?) {
        if (currentUrl == null || released) return
        // Avant stop() : la copie couvre la surface, qui va se vider.
        if (sawFrame && heldBitmap != null) showHeldFrame()
        if (playerKey >= 0) owners.claim(playerKey)
        silenceForHandoff()
        val token = sessions.generation
        dartEpoch?.let { emit("ack", it) }
        if (holdView.visibility == View.VISIBLE) emit("holdFrame", true)
        if (released || token != sessions.generation || disposeStarted) return
        // Focus : Zuno (défaut) ou Media3 (repli). Relu à chaque ouverture :
        // le réglage arrive après la construction du lecteur.
        player.setAudioAttributes(
            movieAudioAttributes(),
            AudioFocusPolicy.media3HandlesFocus(AudioFixes.androidFocus),
        )
        if (AudioFocusPolicy.media3HandlesFocus(AudioFixes.androidFocus)) abandonOwnFocus()
        else requestOwnFocus()
        suspended = false
        clearVoiceProcessor.enabled = clearVoiceEnabled
        setProbeEnabled(AudioFixes.probe)
        emit("audioDiag", ProbeAttach.armingLine(AudioFixes.probe))
        // Nouvelle ouverture : les pourcentages et le décodeur de la
        // chaîne d'avant ne doivent pas rester affichés.
        diag = AudioSnapshot(clearVoice = clearVoiceEnabled)
        val tick = audioGate.onStopped(PlayerCensus.tracksAlive())
        tick.line?.let { emit("audioDiag", it) }
        if (!tick.prepare) {
            // stop() a programmé le rendu. On n'appelle pas prepare() tant
            // que la piste (la nôtre ou celle d'une autre vue) est vivante.
            openDeferred = true
            deferredStartMs = startPositionMs
            deferredToken = token
            val ticket = ++waitToken
            handler.postDelayed({
                if (ticket != waitToken || released || !openDeferred) return@postDelayed
                val late = audioGate.onTimeout(PlayerCensus.tracksAlive())
                if (!late.prepare) return@postDelayed
                late.line?.let { emit("audioDiag", it) }
                forceCloseOurAudio(
                    "Zap : événement AudioTrack manquant, compté rendu pour ne pas laisser le compteur collé.",
                )
                finishDeferredOpen()
            }, AudioHandoff.WAIT_MS)
            return
        }
        prepareCurrent(startPositionMs)
    }

    /** prepare() de [currentUrl]. Appelé seulement quand aucune piste ne vit. */
    private fun prepareCurrent(startPositionMs: Long?) {
        val url = currentUrl ?: return
        if (released || disposeStarted) return
        val token = sessions.generation
        // L'override audio de la chaîne précédente ne doit pas choisir
        // une piste au hasard sur la nouvelle.
        val params = player.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
            .setPreferredAudioRoleFlags(C.ROLE_FLAG_MAIN)
        val lang = prefAudio
        if (!lang.isNullOrBlank()) params.setPreferredAudioLanguage(lang)
        player.trackSelectionParameters = params.build()
        val item = MediaItem.Builder().setUri(url).setTag(token).build()
        if (startPositionMs != null && startPositionMs > 0L) {
            player.setMediaItem(item, startPositionMs)
        } else {
            player.setMediaItem(item)
        }
        // Volume 0 AVANT prepare. Le remettre juste après laissait
        // l'ancien tampon HDMI (AC-3) parler avec le nouveau flux.
        // On ne remonte qu'au « je joue » ou à la nouvelle trame.
        // Ce 0 n'est pas la baisse à 20 % : c'est le silence de passage.
        reconnect.armMute()
        player.volume = AudioHandoff.VOLUME_SILENT
        player.prepare()
        // Garde mode appel, seulement si l'interrupteur est allumé.
        // Coupé : applyModeGuard sort tout de suite, setMode n'est pas appelé.
        lastModeGuardLine = null
        applyModeGuard()
        // Perte de focus pendant le zap : on ne repart pas tant que GAIN
        // n'est pas revenu (ou qu'un nouveau zap n'a pas redemandé le focus).
        player.playWhenReady = !pausedByFocus
        armVolumeTrace()
    }

    /**
     * Dix lignes, une par seconde. On veut voir SI le volume baisse
     * (« son dans un trou ») et QUAND, pas seulement le spectre.
     * Le jeton annule la série si on zappe avant la fin.
     */
    private fun armVolumeTrace() {
        val token = ++volumeTraceToken
        val session = sessions.generation
        for (sec in 1..VolumeTrace.SECONDS) {
            handler.postDelayed({
                if (released || token != volumeTraceToken || session != sessions.generation) return@postDelayed
                // Si le mode d'appel revient pendant les 10 premières secondes
                // et que l'interrupteur est allumé, on redemande normal.
                // Coupé : aucun appel.
                applyModeGuard()
                val playerVol = try {
                    player.volume
                } catch (_: RuntimeException) {
                    -1f
                }
                val stream = try {
                    val am = audioManager
                    val cur = am?.getStreamVolume(AudioManager.STREAM_MUSIC) ?: -1
                    val max = am?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: -1
                    cur to max
                } catch (_: RuntimeException) {
                    -1 to -1
                }
                emit(
                    "audioDiag",
                    VolumeTrace.line(
                        VolumeTrace.Sample(
                            second = sec,
                            playerVolume = playerVol,
                            // AudioTrack.setVolume n'a pas de lecture en retour.
                            trackVolume = null,
                            streamVolume = stream.first,
                            streamMax = stream.second,
                            focusHeld = focusHeld,
                            media3Focus = AudioFocusPolicy.media3HandlesFocus(AudioFixes.androidFocus),
                            pausedByFocus = pausedByFocus,
                            owner = ownerNow(),
                            path = currentFacts(),
                        ),
                    ),
                )
            }, sec * 1_000L)
        }
    }

    /** Une chaîne est en cours : rouvrir a un sens. Idle = la prochaine ouverture suffit. */
    private fun probeIsPlaying(): Boolean {
        if (released || suspended || currentUrl == null) return false
        return try {
            player.playbackState != Player.STATE_IDLE
        } catch (_: RuntimeException) {
            false
        }
    }

    /** L'attente est finie : on ouvre, si c'est toujours CETTE session. */
    private fun finishDeferredOpen() {
        if (released || !openDeferred) return
        val token = deferredToken
        val start = deferredStartMs
        openDeferred = false
        if (token != sessions.generation) return
        prepareCurrent(start)
    }

    /**
     * Le nombre de pistes du processus a bougé (la nôtre ou une autre vue).
     * Si on attendait et qu'il n'en reste plus, on ouvre.
     */
    private fun onGlobalTracks(alive: Int) {
        if (released || disposeStarted || !openDeferred) return
        val tick = audioGate.onTracksAlive(alive)
        if (!tick.prepare) return
        waitToken++
        tick.line?.let { emit("audioDiag", it) }
        val token = deferredToken
        val start = deferredStartMs
        openDeferred = false
        // Posté : on est souvent DANS le callback AudioTrack de Media3.
        // prepare() réentrant au milieu de ce callback est refusé.
        handler.post {
            if (released || token != sessions.generation) return@post
            prepareCurrent(start)
        }
    }

    /**
     * On a déjà compté le rendu (délai dépassé, ou lecteur qu'on va
     * détruire). Le callback Media3 en retard ne doit pas décompter la
     * piste d'après : il est « dû ».
     */
    private fun forceCloseOurAudio(line: String) {
        val had = audioTracksHere > 0 || audioDecodersHere > 0
        owedTrackReleases += audioTracksHere
        owedDecoderReleases += audioDecodersHere
        while (audioTracksHere > 0) {
            audioTracksHere--
            PlayerCensus.audioTrackClosed()
        }
        while (audioDecodersHere > 0) {
            audioDecodersHere--
            PlayerCensus.audioDecoderClosed()
        }
        if (had) emit("audioDiag", line)
    }

    private fun noteTrackOpened() {
        audioTracksHere++
        PlayerCensus.audioTrackOpened()
        if (audioTracksHere > 1) {
            emit(
                "audioDiag",
                "AudioTrack : une piste de plus sans rendu de la précédente.",
            )
        }
    }

    private fun noteTrackClosed() {
        if (owedTrackReleases > 0) {
            owedTrackReleases--
            return
        }
        if (audioTracksHere <= 0) return
        audioTracksHere--
        PlayerCensus.audioTrackClosed()
        if (disposeStarted && audioTracksHere == 0 && !released) {
            handler.post { if (!released && disposeStarted) finishDispose() }
        }
    }

    private fun noteDecoderOpened() {
        audioDecodersHere++
        PlayerCensus.audioDecoderOpened()
        if (audioDecodersHere > 1) {
            emit(
                "audioDiag",
                "Décodeur audio : un de plus sans rendu du précédent.",
            )
        }
    }

    private fun noteDecoderClosed() {
        if (owedDecoderReleases > 0) {
            owedDecoderReleases--
            return
        }
        if (audioDecodersHere <= 0) return
        audioDecodersHere--
        PlayerCensus.audioDecoderClosed()
    }

    private fun scheduleRetry(delayMs: Long, token: Int) {
        // On retire l'ancien délai SANS effacer le verrou que
        // [ReconnectGate.onFailure] vient de poser : le runnable
        // ci-dessous doit être le seul à pouvoir repartir.
        cancelRetry(clearGate = false)
        val r = Runnable {
            if (released || token != sessions.generation) return@Runnable
            // Un seul feu. Un second callback ne prépare pas encore.
            if (!reconnect.onRetryFired()) return@Runnable
            // L'attente est finie : l'écran peut à nouveau surveiller
            // un gel. La copie, elle, reste jusqu'à la nouvelle trame.
            emit("reconnecting", false)
            // Film : [lastKnownPos] a été figé dans onPlayerError, avant stop().
            openCurrent(if (vodMode) lastKnownPos else null)
        }
        pendingRetry = r
        handler.postDelayed(r, delayMs)
    }

    /** Remonte le volume une fois, et seulement si CE lecteur a le son. */
    private fun unmuteIfThisSession() {
        if (!reconnect.onNewSoundAllowed()) return
        if (released) return
        if (playerKey >= 0 && owners.owner != null && owners.owner != playerKey) return
        // Perte de focus pendant le zap : on ne remonte pas. Le GAIN le fera.
        if (pausedByFocus) return
        try {
            player.volume = AudioHandoff.VOLUME_FULL
        } catch (_: RuntimeException) {
            // Un volume refusé laisse la chaîne muette plutôt que planter.
        }
    }

    private fun showHeldFrame() {
        val bmp = heldBitmap ?: return
        if (bmp.isRecycled) return
        holdView.setImageBitmap(bmp)
        holdView.visibility = View.VISIBLE
        holdView.bringToFront()
    }

    /** Cache la copie sans la jeter : la prochaine coupure la réutilise. */
    private fun hideHeldFrame() {
        holdView.visibility = View.GONE
        holdView.setImageDrawable(null)
    }

    /** Zap : l'ancienne image ne doit pas rester (mauvaise chaîne). */
    private fun discardHeldFrame() {
        hideHeldFrame()
        val bmp = heldBitmap
        heldBitmap = null
        if (bmp != null && !bmp.isRecycled) bmp.recycle()
    }

    private fun stashFrame(bmp: Bitmap) {
        val previous = heldBitmap
        heldBitmap = bmp
        if (holdView.visibility == View.VISIBLE) {
            holdView.setImageBitmap(bmp)
        } else {
            holdView.setImageDrawable(null)
        }
        if (previous != null && previous !== bmp && !previous.isRecycled) {
            previous.recycle()
        }
    }

    /**
     * Copie une petite image de la surface pendant que ça joue.
     * On ne copie pas pendant la coupure : on remplacerait la bonne
     * image par du noir. Au plus une copie à la fois, toutes les 4 s.
     */
    private fun maybeCopyFrame(force: Boolean = false) {
        if (released || copyInFlight || !sawFrame) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        val now = SystemClock.elapsedRealtime()
        if (!force && now - lastCopyAt < 4_000L) return
        val w = surfaceView.width
        val h = surfaceView.height
        if (w < 16 || h < 16) return
        val rw = minOf(w, 1280)
        val rh = minOf(h, 720)
        val left = (w - rw) / 2
        val top = (h - rh) / 2
        val rect = Rect(left, top, left + rw, top + rh)
        val bmp = Bitmap.createBitmap(rw, rh, Bitmap.Config.RGB_565)
        copyInFlight = true
        lastCopyAt = now
        try {
            PixelCopy.request(surfaceView, rect, bmp, { code ->
                copyInFlight = false
                val keep = !released && code == PixelCopy.SUCCESS && sawFrame &&
                    holdView.visibility != View.VISIBLE
                if (!keep) {
                    bmp.recycle()
                    return@request
                }
                stashFrame(bmp)
            }, handler)
        } catch (_: RuntimeException) {
            copyInFlight = false
            if (!bmp.isRecycled) bmp.recycle()
        }
    }

    private fun cancelRetry(clearGate: Boolean = true) {
        pendingRetry?.let { handler.removeCallbacks(it) }
        pendingRetry = null
        if (clearGate) reconnect.cancelWait()
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
        val session = sessions.generation
        handler.postDelayed({
            if (token != ffmpegWatchToken || released || session != sessions.generation) {
                return@postDelayed
            }
            // « jamais prêt » et pas « pas prêt à cet instant » : une chaîne
            // qui a joué puis re-tamponne à la 8e seconde n'a pas un FFmpeg
            // en panne (c'est ce faux déclencheur qui envoyait tout à la box).
            if (AudioHandoff.watchdogShouldFallback(
                    ffmpegActiveThisSession = ffmpegAudioActive,
                    readyThisSession = readyThisSession,
                    forceBox = forceBoxAacDecoder,
                    platformGaveUp = platformAacGaveUp,
                    playbackReady = player.playbackState == Player.STATE_READY,
                )
            ) {
                requestBoxAudioFallback(AacRoute.Reason.TIMEOUT)
            }
        }, FFMPEG_READY_TIMEOUT_MS)
    }

    /**
     * Repli pour CETTE chaîne, puis re-préparation IMMÉDIATE du flux.
     *
     * Le drapeau est posé AVANT le re-prepare : la prochaine sélection de
     * pistes relit [forceBoxAacDecoder] et rend l'AAC au décodeur de la
     * box. [AacRoute] s'en souvient pour cette chaîne (et seulement elle,
     * sauf [AacRoute.sessionWide]) : au retour dessus, pas de 8 s d'attente.
     * On ne recrée pas le lecteur : les moteurs sont déjà construits, seul
     * le choix de piste change. La fiche reçoit une ligne « Repli ».
     *
     * On passe par [openCurrent] : le stop() rend le codec et la socket
     * avant de rouvrir, comme un zap. Sans ça, le second prepare() pouvait
     * laisser l'ancienne connexion ouverte (chaîne refusée).
     *
     * Posté sur le thread principal : ces signaux arrivent parfois depuis
     * le thread de lecture, et Media3 n'aime pas un prepare() réentrant
     * au milieu de onPlayerError.
     */
    private fun requestBoxAudioFallback(reason: AacRoute.Reason) {
        // Déjà revenu de la box vers FFmpeg : ne pas renvoyer vers la box,
        // les deux se relanceraient.
        if (platformAacGaveUp || forceBoxAacDecoder || released) return
        val url = currentUrl
        if (url != null) {
            val zapNo = PlayerCensus.snapshot(AacRoute.key(url), null).zap
            boxFailure = AacRoute.markFailed(url, reason, zapNo)
        }
        forceBoxAacDecoder = true
        ffmpegAudioActive = false
        ffmpegWatchToken++
        emit(
            "audioDiag",
            "Repli : ${reason.label} → l'AAC de cette chaîne passe au décodeur de la box " +
                "(cette chaîne seulement" +
                (if (AacRoute.sessionWide) ", mode session entière" else "") + ").",
        )
        val session = sessions.generation
        handler.post {
            if (released || session != sessions.generation) return@post
            // Un essai réseau déjà armé ne doit pas lancer un SECOND
            // prepare() par-dessus celui-ci (la chaîne clignoterait).
            // On ne touche pas au compteur : ce n'est pas un échec réseau.
            cancelRetry()
            if (vodMode && player.currentPosition > 0) lastKnownPos = player.currentPosition
            emit("buffering", true)
            openCurrent(if (vodMode) lastKnownPos else null)
        }
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
        // Compté AVANT le filtre de session : un décodeur vivant est vivant,
        // même s'il appartient à l'ancienne chaîne.
        noteDecoderOpened()
        if (!fresh(eventTime)) return
        ffmpegAudioActive = decoderName.contains("ffmpeg", ignoreCase = true)
        diag = diag.copy(decoder = decoderName)
    }

    override fun onAudioDecoderReleased(eventTime: AnalyticsListener.EventTime, decoderName: String) {
        noteDecoderClosed()
        if (!fresh(eventTime)) return
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
        if (fresh(eventTime)) emit("audioDiag", "Erreur de la sortie son : ${audioSinkError.javaClass.simpleName}")
        if (!fresh(eventTime)) return
        if (ffmpegAudioActive) requestBoxAudioFallback(AacRoute.Reason.SINK_ERROR)
        else requestFfmpegAfterPlatformFailure()
    }

    /** Erreur du décodeur logiciel FFmpeg (DecoderException), même repli. */
    override fun onAudioCodecError(eventTime: AnalyticsListener.EventTime, audioCodecError: Exception) {
        if (fresh(eventTime)) emit("audioDiag", "Erreur du décodeur son : ${audioCodecError.javaClass.simpleName}")
        if (!fresh(eventTime)) return
        if (ffmpegAudioActive) requestBoxAudioFallback(AacRoute.Reason.CODEC_ERROR)
        else requestFfmpegAfterPlatformFailure()
    }

    /**
     * L'essai « décodeur de la box » a échoué. On revient à FFmpeg pour
     * CETTE ouverture. Le réglage reste allumé : la chaîne suivante
     * réessaiera la box. On ne boucle pas (voir [platformAacGaveUp]).
     */
    private fun requestFfmpegAfterPlatformFailure() {
        if (!AudioFixes.preferPlatformAac || platformAacGaveUp || released) return
        if (ffmpegAudioActive) return
        platformAacGaveUp = true
        ffmpegWatchToken++
        diag = diag.copy(
            routeNote = "Le décodeur AAC de la box a échoué. Repli FFmpeg pour cette ouverture.",
        )
        val session = sessions.generation
        handler.post {
            if (released || session != sessions.generation) return@post
            cancelRetry()
            if (vodMode && player.currentPosition > 0) lastKnownPos = player.currentPosition
            emit("buffering", true)
            openCurrent(if (vodMode) lastKnownPos else null)
        }
    }

    // ---- diagnostic du son (lecture seule) ---------------------------------

    /** Format du flux audio REÇU (avant décodage). */
    override fun onAudioInputFormatChanged(
        eventTime: AnalyticsListener.EventTime,
        format: Format,
        decoderReuseEvaluation: DecoderReuseEvaluation?,
    ) {
        if (!fresh(eventTime)) return
        fun known(v: Int) = if (v == Format.NO_VALUE || v < 0) 0 else v
        diag = diag.copy(
            mime = format.sampleMimeType,
            codecs = format.codecs,
            inSampleRate = known(format.sampleRate),
            inChannels = known(format.channelCount),
            bitrate = known(format.bitrate),
        )
    }

    /** Ce qui part réellement vers la sortie son : on envoie le bilan. */
    override fun onAudioTrackInitialized(
        eventTime: AnalyticsListener.EventTime,
        audioTrackConfig: AudioSink.AudioTrackConfig,
    ) {
        noteTrackOpened()
        if (!fresh(eventTime)) return
        diag = diag.copy(
            outSampleRate = audioTrackConfig.sampleRate,
            outChannels = Integer.bitCount(audioTrackConfig.channelConfig),
            outEncoding = encodingName(audioTrackConfig.encoding),
            passthrough = !Util.isEncodingLinearPcm(audioTrackConfig.encoding),
            clearVoice = clearVoiceEnabled,
        )
        sendAudioDiag()
    }

    /** L'AudioTrack est rendu (stop, zap, libération) : un vivant de moins. */
    override fun onAudioTrackReleased(
        eventTime: AnalyticsListener.EventTime,
        audioTrackConfig: AudioSink.AudioTrackConfig,
    ) {
        noteTrackClosed()
        if (!released) {
            emit(
                "audioDiag",
                "AudioTrack rendu. Pistes encore vivantes : ${PlayerCensus.tracksAlive()}.",
            )
        }
    }

    /** Numéro de session audio Android : un numéro qui change = un AudioTrack neuf. */
    override fun onAudioSessionIdChanged(eventTime: AnalyticsListener.EventTime, audioSessionId: Int) {
        if (!fresh(eventTime)) return
        emit("audioDiag", "Session audio Android n°$audioSessionId")
    }

    /**
     * Media3 (mode repli) retient la lecture sur une perte de focus passagère.
     * On le dit, pour que la fiche montre d'où vient un silence.
     */
    override fun onPlaybackSuppressionReasonChanged(eventTime: AnalyticsListener.EventTime, reason: Int) {
        if (!fresh(eventTime)) return
        if (reason == Player.PLAYBACK_SUPPRESSION_REASON_TRANSIENT_AUDIO_FOCUS_LOSS) {
            emit("audioDiag", "Focus audio (Media3) : perte passagère → lecture retenue par Android.")
        }
    }

    override fun onPlayWhenReadyChanged(eventTime: AnalyticsListener.EventTime, playWhenReady: Boolean, reason: Int) {
        if (!fresh(eventTime)) return
        if (reason == Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_FOCUS_LOSS) {
            emit("audioDiag", "Focus audio (Media3) : PERDU → lecture mise en pause par Android.")
        }
    }

    /** Coupure de la sortie son (craquement / trou). Bilan au plus toutes les 30 s. */
    override fun onAudioUnderrun(
        eventTime: AnalyticsListener.EventTime,
        bufferSize: Int,
        bufferSizeMs: Long,
        elapsedSinceLastFeedMs: Long,
    ) {
        if (!fresh(eventTime)) return
        diag = diag.copy(underruns = diag.underruns + 1)
        val now = SystemClock.elapsedRealtime()
        if (now - diagLastUnderrunSentMs >= 30_000L) {
            diagLastUnderrunSentMs = now
            sendAudioDiag()
        }
    }

    /** Les quatre sondes s'allument ensemble. Coupées, chacune renvoie NOT_SET. */
    private fun setProbeEnabled(on: Boolean) {
        probeDecoder.enabled = on
        probeVoice.enabled = on
        probeSilence.enabled = on
        probeSink.enabled = on
    }

    /**
     * Appelé depuis le fil audio. On ne touche [diag] que sur le fil
     * principal : le lecteur le lit aussi pour envoyer le rapport.
     * [spectrum] reste la sonde décodeur, pour les règles déjà écrites.
     * Les quatre chiffres sont dans [AudioSnapshot.stages].
     */
    private fun onProbe(stage: String, judged: AudioSpectrum.Judgement) {
        handler.post {
            if (released) return@post
            val byId = mutableMapOf<String, AudioStages.Reading>()
            for (existing in diag.stages) byId[existing.id] = existing
            byId[stage] = AudioStages.Reading(stage, judged)
            val ordered = ArrayList<AudioStages.Reading>(AudioStages.ORDER.size)
            for (id in AudioStages.ORDER) {
                val reading = byId[id] ?: continue
                ordered.add(reading)
            }
            val decoder = ordered.firstOrNull { it.id == AudioStages.DECODER }?.judgement
            diag = diag.copy(
                stages = ordered,
                spectrum = decoder ?: ordered.firstOrNull()?.judgement,
            )
            sendAudioDiag()
        }
    }

    private fun sendAudioDiag() {
        val audible = try {
            player.isPlaying
        } catch (_: RuntimeException) {
            false
        }
        val live = diag.copy(
            clearVoice = clearVoiceEnabled,
            skipSilence = player.skipSilenceEnabled,
            playbackSpeed = player.playbackParameters.speed,
            cycle = currentUrl?.let { PlayerCensus.snapshot(AacRoute.key(it), boxFailure) },
            probeRequested = AudioFixes.probe,
            probeInChain = probeDecoder.lastAccepted,
            probeFrames = probeDecoder.usefulFrames,
            probeReject = if (AudioFixes.probe) probeDecoder.lastReject else null,
            playback = ownerNow(),
            routeLine = AudioRouteState.pathLine(currentFacts()),
            playerAudible = audible,
        )
        diag = live
        // Le corps, sans la ligne « sortie de la box » : elle ne change
        // pas, et l'ajouter seulement la première fois faisait croire
        // qu'une deuxième fiche était différente.
        val body = AudioDiagnosis.redact(buildString {
            append(AudioDiagnosis.describe(live))
            for (v in AudioDiagnosis.verdicts(diag)) append("\n→ ").append(v)
            append("\n").append(AudioDiagnosis.report(diag))
        })
        if (body == lastDiagText) return
        lastDiagText = body
        val text = if (!diagCapsSent) {
            diagCapsSent = true
            body + "\n" + outputCaps
        } else {
            body
        }
        emit("audioDiag", text)
    }

    private fun encodingName(encoding: Int): String = when (encoding) {
        C.ENCODING_PCM_16BIT -> "PCM 16 bits"
        C.ENCODING_PCM_FLOAT -> "PCM flottant"
        C.ENCODING_PCM_24BIT -> "PCM 24 bits"
        C.ENCODING_PCM_32BIT -> "PCM 32 bits"
        C.ENCODING_AC3 -> "AC-3"
        C.ENCODING_E_AC3, C.ENCODING_E_AC3_JOC -> "E-AC-3"
        C.ENCODING_DTS -> "DTS"
        C.ENCODING_DTS_HD -> "DTS-HD"
        C.ENCODING_DOLBY_TRUEHD -> "TrueHD"
        else -> "codage $encoding"
    }

    // ---- cycle de vie -------------------------------------------------------

    override fun dispose() {
        beginDispose(null)
    }

    /**
     * Libère le décodeur et la surface, une seule fois. Appelé par Flutter
     * quand la vue part, ET par le message « dispose » de Dart (aperçu qui
     * doit rendre le décodeur avant le plein écran). Le second appel ne
     * fait rien : release() deux fois plante ExoPlayer.
     *
     * On ne retire PAS l'écouteur avant le rendu de l'AudioTrack : Media3
     * 1.5.1 l'envoie après stop(), et le retirer avant faisait croire à
     * la fiche qu'une piste restait vivante pour toujours. Dart n'est
     * prévenu qu'à [finishDispose], donc le lecteur suivant n'est pas
     * créé par-dessus.
     */
    private fun releasePlayer() {
        beginDispose(null)
    }

    private fun beginDispose(result: MethodChannel.Result?) {
        if (released) {
            result?.success(null)
            return
        }
        if (disposeStarted) {
            if (result != null) disposeResult = result
            return
        }
        disposeStarted = true
        disposeResult = result
        audioGate.cancel()
        openDeferred = false
        waitToken++
        abandonOwnFocus()
        unwatchOtherPlaybacks()
        ffmpegWatchToken++
        clearFrameRateMode()
        cancelRetry()
        discardHeldFrame()
        try {
            player.volume = AudioHandoff.VOLUME_SILENT
            player.playWhenReady = false
            // stop() programme le rendu. L'écouteur reste : on compte
            // onAudioTrackReleased. On ne détache la surface qu'à la fin.
            player.stop()
            player.clearMediaItems()
        } catch (_: RuntimeException) {
            // Un stop raté ne doit pas empêcher la destruction.
        }
        if (audioTracksHere == 0) {
            emit("audioDiag", "Libération : aucun AudioTrack vivant, lecteur détruit.")
            finishDispose()
            return
        }
        emit("audioDiag", "Libération : on attend que l'AudioTrack soit vraiment rendu.")
        val ticket = ++disposeWaitToken
        handler.postDelayed({
            if (ticket != disposeWaitToken || released) return@postDelayed
            forceCloseOurAudio(
                "Libération : AudioTrack pas rendu à temps, compté rendu pour ne pas bloquer la chaîne suivante.",
            )
            finishDispose()
        }, AudioHandoff.WAIT_MS)
    }

    private fun finishDispose() {
        if (released) return
        disposeWaitToken++
        PlayerCensus.unwatchTracks(trackWatcher)
        if (audioDecodersHere > 0 || audioTracksHere > 0) {
            forceCloseOurAudio(
                "Libération : décodeur ou AudioTrack encore compté, soldé avant destruction du lecteur.",
            )
        }
        released = true
        handler.removeCallbacksAndMessages(null)
        if (playerKey >= 0) {
            owners.unregister(playerKey)
            playerKey = -1
        }
        try {
            player.removeAnalyticsListener(this)
            player.clearVideoFrameMetadataListener(frameClock)
        } catch (_: RuntimeException) {
            // Déjà détaché : on continue la libération.
        }
        try {
            // stop() avant la surface : le codec arrête d'écrire, puis on
            // détache. L'ordre inverse laisse parfois une image verte et
            // un décodeur qui ne se rend jamais (chaîne suivante noire).
            player.clearVideoSurface()
            player.release()
        } catch (_: RuntimeException) {
            // Une libération ratée ne doit pas tuer l'app : la chaîne
            // suivante doit pouvoir créer SON lecteur.
        }
        PlayerCensus.playerReleased()
        channel.setMethodCallHandler(null)
        val pending = disposeResult
        disposeResult = null
        try {
            pending?.success(null)
        } catch (_: RuntimeException) {
            // Réponse déjà envoyée : on ne plante pas la destruction.
        }
    }

    /**
     * Branche le lecteur sur la surface SANS la détacher entre deux
     * chaînes. Toute l'image, bandes noires si ce n'est pas du 16:9 :
     * on ne rogne pas.
     */
    private fun attachToSurface(target: ExoPlayer) {
        target.setVideoScalingMode(C.VIDEO_SCALING_MODE_SCALE_TO_FIT)
        target.setVideoSurfaceView(surfaceView)
        target.addAnalyticsListener(this)
        target.setVideoFrameMetadataListener(frameClock)
        target.skipSilenceEnabled = false
        target.playWhenReady = true
        ffmpegRendererInstalled = installFfmpegVideo
    }

    private fun emitImageCaps() {
        emit(
            "imageCaps",
            mapOf(
                "ffmpegVideo" to ffmpegVideoReady,
                "engine" to videoEngine.wire,
                "contrastHardware" to false,
            ),
        )
    }

    private fun emitEngine(rejected: String? = null) {
        val payload = HashMap<String, Any?>()
        payload["name"] = videoEngine.wire
        payload["ffmpegVideo"] = ffmpegVideoReady
        if (rejected != null) payload["rejected"] = rejected
        emit("engine", payload)
    }

    /** Revenir au choix de la personne, sans rouvrir (setUrl le fait). */
    private fun restorePreferredEngine() {
        if (videoEngine == preferredEngine &&
            preferSoftwareVideo == (preferredEngine == VideoEngine.SOFTWARE) &&
            ffmpegRendererInstalled == (preferredEngine == VideoEngine.FFMPEG && ffmpegVideoReady)
        ) {
            return
        }
        videoEngine = preferredEngine
        preferSoftwareVideo = preferredEngine == VideoEngine.SOFTWARE
        val wantFfmpeg = preferredEngine == VideoEngine.FFMPEG && ffmpegVideoReady
        if (wantFfmpeg != ffmpegRendererInstalled) {
            installFfmpegVideo = wantFfmpeg
            rebuildPlayer()
        }
        emitEngine()
    }

    /**
     * Change le moteur. [reopen] relance le flux en cours. On prévient
     * Dart (`reopen`) AVANT, pour que le carton de chaîne couvre la
     * surface : pas de flash noir.
     */
    private fun applyEngine(next: VideoEngine, reopen: Boolean) {
        if (next == VideoEngine.FFMPEG && !ffmpegVideoReady) {
            emitEngine(rejected = "ffmpeg")
            return
        }
        val changed = next != videoEngine
        videoEngine = next
        preferSoftwareVideo = next == VideoEngine.SOFTWARE
        val wantFfmpeg = next == VideoEngine.FFMPEG && ffmpegVideoReady
        if (wantFfmpeg != ffmpegRendererInstalled) {
            installFfmpegVideo = wantFfmpeg
            rebuildPlayer()
        }
        emitEngine()
        if (reopen && changed && currentUrl != null && !released) {
            emit("reopen", null)
            if (vodMode && player.currentPosition > 0) lastKnownPos = player.currentPosition
            openCurrent(if (vodMode) lastKnownPos else null)
        }
    }

    /**
     * Nouveau lecteur, MÊME surface. On ne le fait que pour entrer ou
     * sortir de FFmpeg vidéo : le matériel et le logiciel partagent
     * le même lecteur, seul l'ordre des codecs change.
     */
    private fun rebuildPlayer() {
        if (!::player.isInitialized) return
        val old = player
        val next = buildConfiguredPlayer()
        PlayerCensus.playerCreated()
        player = next
        attachToSurface(next)
        // L'ancien lecteur va perdre son écouteur : son onAudioTrackReleased
        // n'arriverait plus. On solde le compteur maintenant. Un callback
        // en retard est ignoré (piste « due »).
        forceCloseOurAudio(
            "Moteur vidéo : AudioTrack de l'ancien lecteur compté rendu.",
        )
        try {
            old.removeAnalyticsListener(this)
            old.clearVideoFrameMetadataListener(frameClock)
        } catch (_: RuntimeException) {
        }
        try {
            old.stop()
            old.clearVideoSurface()
            old.release()
        } catch (_: RuntimeException) {
        }
        PlayerCensus.playerReleased()
    }

    private fun resetPictureClock() {
        renderedFrames.set(0)
        lastFrameAtMs = 0L
        videoDecoderReady = false
        decoderReadyAtMs = 0L
    }

    private fun considerPictureFallback() {
        if (released || videoGaveUp || videoFallbackPosted) return
        if (!::player.isInitialized) return
        val now = SystemClock.elapsedRealtime()
        val ready = player.playbackState == Player.STATE_READY
        val buffering = player.playbackState == Player.STATE_BUFFERING
        val frames = renderedFrames.get()
        val black = PictureHealth.black(
            decoderReady = videoDecoderReady,
            framesRendered = frames,
            playbackReady = ready,
            buffering = buffering,
            elapsedMs = if (decoderReadyAtMs == 0L) 0L else now - decoderReadyAtMs,
        )
        val frozen = PictureHealth.frozen(
            framesRendered = frames,
            playing = player.isPlaying,
            buffering = buffering,
            msSinceLastFrame = if (lastFrameAtMs == 0L) 0L else now - lastFrameAtMs,
        )
        if (black || frozen) takeVideoFallback(PictureSignal.BLACK_OR_FROZEN)
    }

    /**
     * @return true si on a traité l'échec (bascule, ou plus aucun moteur).
     * Le réseau continue alors son chemin habituel seulement si on
     * renvoie false.
     */
    private fun takeVideoFallback(signal: PictureSignal): Boolean {
        if (released || videoGaveUp) return videoGaveUp
        val decision = DecoderFallback.next(
            videoEngine,
            signal,
            ffmpegVideoReady,
            triedEngines,
        )
        if (!decision.reopen) {
            if (decision.giveUp) {
                videoGaveUp = true
                // Pas « error » : Dart rouvrirait l'URL et remettrait le
                // matériel, donc la même panne en boucle. L'écran montre
                // l'échec et attend « Réessayer ».
                emit("engineExhausted", videoEngine.wire)
            }
            return decision.giveUp
        }
        if (videoFallbackPosted) return true
        videoFallbackPosted = true
        triedEngines.add(videoEngine)
        val session = sessions.generation
        val next = decision.engine
        handler.post {
            videoFallbackPosted = false
            if (released || session != sessions.generation) return@post
            cancelRetry()
            applyEngine(next, reopen = true)
        }
        return true
    }

    /**
     * Piste vidéo fixe (pas le ladder HLS). Une fois par chaîne.
     * Le HLS adaptatif reste à Media3 : on ne fige pas un débit.
     */
    private fun maybeChooseVideo(tracks: Tracks) {
        if (videoChosenForSession) return
        val videos = ArrayList<VideoCandidate>()
        tracks.groups.forEachIndexed { gi, g ->
            if (g.type != C.TRACK_TYPE_VIDEO) return@forEachIndexed
            val adaptive = g.length > 1
            for (i in 0 until g.length) {
                if (!g.isTrackSupported(i)) continue
                val f = g.getTrackFormat(i)
                videos.add(
                    VideoCandidate(
                        group = gi,
                        index = i,
                        width = positive(f.width),
                        height = positive(f.height),
                        bitrate = positive(f.bitrate),
                        frameRate = if (f.frameRate > 0f) f.frameRate else 0f,
                        mime = f.sampleMimeType,
                        selected = g.isTrackSelected(i),
                        adaptive = adaptive,
                    ),
                )
            }
        }
        if (videos.isEmpty()) return
        val bandwidth = VideoTrackChoice.bandwidthForChoice(bitrateEstimate, bytesLoaded)
        val pick = VideoTrackChoice.pick(videos, bandwidth, screenHeightPx())
        val fixed = videos.count { !it.adaptive }
        if (pick == null) {
            if (player.playbackState == Player.STATE_READY || fixed < 2) {
                videoChosenForSession = true
            }
            return
        }
        videoChosenForSession = true
        val token = sessions.generation
        handler.post {
            if (released || token != sessions.generation) return@post
            val groups = player.currentTracks.groups
            if (pick.group < 0 || pick.group >= groups.size) return@post
            val g = groups[pick.group]
            if (g.type != C.TRACK_TYPE_VIDEO) return@post
            if (pick.index < 0 || pick.index >= g.length) return@post
            player.trackSelectionParameters = player.trackSelectionParameters
                .buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, false)
                .setOverrideForType(TrackSelectionOverride(g.mediaTrackGroup, pick.index))
                .build()
        }
    }

    private fun positive(value: Int): Int = if (value > 0) value else 0

    private fun screenHeightPx(): Int {
        val fromView = surfaceView.height
        if (fromView > 0) return fromView
        return appContext.resources.displayMetrics.heightPixels
    }

    @Suppress("DEPRECATION") // defaultDisplay : lu seulement pour la liste des modes
    private fun applyFrameRate(fps: Float) {
        if (!frameRateMatchEnabled) return
        val activity = findActivity(appContext) ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val display = surfaceView.display ?: activity.windowManager.defaultDisplay
        val modes = display.supportedModes.map { DisplayModeOption(it.modeId, it.refreshRate) }
        val current = activity.window.attributes.preferredDisplayModeId
        val pick = FrameRateMatch.pick(true, fps, modes, current) ?: return
        try {
            val attrs = activity.window.attributes
            attrs.preferredDisplayModeId = pick.id
            activity.window.attributes = attrs
            frameRateModeApplied = true
        } catch (_: RuntimeException) {
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                surfaceView.holder.surface.setFrameRate(
                    fps,
                    Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE,
                    Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS,
                )
            } catch (_: RuntimeException) {
                // L'indice de cadence est en plus du mode. S'il échoue,
                // le mode d'écran, lui, est déjà posé.
            }
        }
    }

    /** Rend la fréquence à la TV. On ne touche à la fenêtre que si ON l'a changée. */
    private fun clearFrameRateMode() {
        if (!frameRateModeApplied) return
        val activity = findActivity(appContext) ?: return
        try {
            val attrs = activity.window.attributes
            attrs.preferredDisplayModeId = 0
            activity.window.attributes = attrs
        } catch (_: RuntimeException) {
            // On note quand même que ce n'est plus notre mode.
        }
        frameRateModeApplied = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                surfaceView.holder.surface.setFrameRate(
                    0f,
                    Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                    Surface.CHANGE_FRAME_RATE_ALWAYS,
                )
            } catch (_: RuntimeException) {
            }
        }
    }

    private fun findActivity(start: Context): Activity? {
        var current: Context? = start
        while (current is ContextWrapper) {
            if (current is Activity) return current
            current = current.baseContext
        }
        return null
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

        /** FFmpeg sait-il lire le MP2 (MPEG-1 Layer II, très courant en IPTV) ? */
        private val ffmpegMp2: Boolean by lazy {
            ffmpegReady && FfmpegLibrary.supportsFormat(MimeTypes.AUDIO_MPEG_L2)
        }

        /**
         * Vrai seulement si le .so déclare un décodeur VIDÉO. Le binaire
         * Jellyfin 1.5.0+1 (son de la v104) n'a pas h264 / hevc / mpeg2 :
         * cet appel renvoie faux, et on ne construit pas le rendu vidéo.
         */
        val ffmpegVideoReady: Boolean by lazy {
            if (!ffmpegReady) return@lazy false
            try {
                FfmpegLibrary.supportsFormat(MimeTypes.VIDEO_H264) ||
                    FfmpegLibrary.supportsFormat(MimeTypes.VIDEO_H265) ||
                    FfmpegLibrary.supportsFormat(MimeTypes.VIDEO_MPEG2)
            } catch (_: Throwable) {
                false
            }
        }

        /**
         * Tous les lecteurs vivants du processus. [claim] coupe les autres
         * avant qu'un nouveau ne sorte du son.
         */
        val owners: ExclusiveAudio = ExclusiveAudio()

        // Le repli AAC → box n'est PLUS un drapeau de processus : il est
        // par chaîne, dans [AacRoute], et par vue dans `forceBoxAacDecoder`.
    }
}

/**
 * Fabrique de rendus : identique à Media3, SAUF pour la vidéo.
 *
 * Par défaut [installFfmpegVideo] est faux : la vidéo reste sur
 * MediaCodec (matériel, puis le logiciel Android si l'init échoue).
 * On n'ajoute le rendu FFmpeg QUE si la bibliothèque a dit qu'elle
 * sait décoder la vidéo. Le mode « extension » de Media3 est forcé
 * à OFF pour qu'il ne glisse pas FFmpeg tout seul devant l'image.
 * L'audio FFmpeg est ajouté à part, dans [NativeVideoView].
 */
@UnstableApi
private open class TvVideoRenderersFactory(
    context: Context,
    private val installFfmpegVideo: Boolean,
) : DefaultRenderersFactory(context) {
    @Suppress("UNUSED_PARAMETER") // le mode extension est forcé à OFF plus bas
    override fun buildVideoRenderers(
        context: Context,
        extensionRendererMode: Int,
        mediaCodecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean,
        eventHandler: Handler,
        eventListener: VideoRendererEventListener,
        allowedVideoJoiningTimeMs: Long,
        out: ArrayList<Renderer>,
    ) {
        if (installFfmpegVideo) {
            out.add(
                ExperimentalFfmpegVideoRenderer(
                    allowedVideoJoiningTimeMs,
                    eventHandler,
                    eventListener,
                    /* maxDroppedFramesToNotify = */ 50,
                ),
            )
        }
        super.buildVideoRenderers(
            context,
            EXTENSION_RENDERER_MODE_OFF,
            mediaCodecSelector,
            enableDecoderFallback,
            eventHandler,
            eventListener,
            allowedVideoJoiningTimeMs,
            out,
        )
    }
}
