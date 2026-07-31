// =========================================================
//  MainActivity.kt — overlay 7 MOTION pour le Google Cast SDK
// =========================================================
//  Remplace la MainActivity par défaut que `flutter create` génère
//  (qui est juste `class MainActivity : FlutterActivity()`).
//
//  Différences :
//    1. Étend FlutterFragmentActivity (au lieu de FlutterActivity)
//       → nécessaire pour afficher le dialog natif Google Cast
//       (MediaRouteChooserDialog requiert un FragmentManager).
//    2. Câble le MethodChannel "com.manzilionellm.tvking/cast"
//       sur notre `GoogleCastApi` Kotlin via configureFlutterEngine.
//       → le code Dart de `lib/features/cast/data/google_cast_api.dart`
//       peut alors appeler les vraies méthodes du SDK.
//
//  Ce fichier est CHECKÉ DANS le repo (android_overlay/) et copié
//  par `apply_cast_patch.sh` vers `android/app/src/main/kotlin/...`
//  au build CI, AVANT `flutter build apk`.
// =========================================================

package com.manzilionellm.tvking

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.Rational
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val TAG = "MainActivity"

        /// Channel Dart ↔ natif pour le Picture-in-Picture.
        /// Doit matcher EXACTEMENT côté lib/features/player/data/pip_service.dart
        private const val PIP_CHANNEL = "com.manzilionellm.tvking/pip"

        /// Channel pour l'identité STABLE de l'appareil (ANDROID_ID).
        /// Doit matcher lib/features/device/data/device_identity.dart.
        /// Sert à dériver une MAC virtuelle qui SURVIT aux
        /// réinstallations (sinon le client perdrait son abonnement).
        private const val DEVICE_CHANNEL = "com.manzilionellm.tvking/device"

        /// Broadcast interne des boutons de la fenêtre PiP (RemoteActions
        /// façon YouTube : 🎧 Écouteurs + Lecture/Pause). Reçu par
        /// `pipActionReceiver` (NOT_EXPORTED) puis routé vers Dart via
        /// l'event `onPipRemoteAction` du PIP_CHANNEL.
        private const val PIP_ACTION_INTENT = "com.manzilionellm.tvking.PIP_REMOTE_ACTION"
        private const val PIP_EXTRA_ACTION = "pip_action"
        private const val PIP_ACTION_HEADPHONES = "headphones"
        private const val PIP_ACTION_PLAY_PAUSE = "playpause"
    }

    private var castApi: GoogleCastApi? = null
    private var galleryExporter: GalleryExporter? = null
    private var recordingService: RecordingServiceBridge? = null
    private var multicastLock: MulticastLockBridge? = null
    private var pipChannel: MethodChannel? = null

    /// Vrai quand le lecteur vidéo joue actuellement. Mis à jour par
    /// `lib/features/player/data/pip_service.dart` à chaque play/pause.
    /// Sert à décider si on entre auto en PiP quand l'utilisateur
    /// appuie sur HOME (= YouTube Premium-style).
    private var playbackActive: Boolean = false

    /// Aspect ratio courant à appliquer au PiP. Défaut 16:9 (la
    /// majorité des contenus). Mise à jour par Dart si la vidéo
    /// a un ratio différent détecté (4:3, 21:9, etc.).
    private var pipAspectNumer: Int = 16
    private var pipAspectDenom: Int = 9

    /// Vrai quand le mode « Écouteurs » (audio seul) est actif. Mis à
    /// jour par Dart (PipService.setAudioOnlyMode). Quand `true`, on NE
    /// déclenche PAS le PiP vidéo au passage en arrière-plan : c'est le
    /// PlaybackForegroundService qui garde le SON en vie (écran éteint).
    private var audioOnlyMode: Boolean = false

    /// Reçoit les taps sur les boutons de la fenêtre PiP (RemoteActions)
    /// et les route vers Dart, qui agit sur le lecteur (bascule Écouteurs,
    /// play/pause). Enregistré NOT_EXPORTED : seul le PendingIntent de
    /// l'app peut l'atteindre.
    private val pipActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.getStringExtra(PIP_EXTRA_ACTION) ?: return
            Log.i(TAG, "PiP remote action: $action")
            pipChannel?.invokeMethod(
                "onPipRemoteAction",
                mapOf("action" to action),
            )
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Fail-open : sans receiver, la fenêtre PiP garde ses boutons mais
        // les taps ne font rien — jamais de crash au boot pour du PiP.
        try {
            val filter = IntentFilter(PIP_ACTION_INTENT)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(pipActionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(pipActionReceiver, filter)
            }
            Log.i(TAG, "  ✓ PiP action receiver registered")
        } catch (e: Throwable) {
            Log.w(TAG, "  ✗ PiP action receiver failed: $e")
        }
        // Pré-enregistre les boutons PiP dès le démarrage : une entrée en
        // PiP initiée par l'OS trouve toujours 🎧 + ⏯ en place.
        refreshPipActions()
        consumeOpenVideoExtra(intent)
    }

    /// Bouton « Vidéo » de la notification (mode radio) : l'intent de
    /// lancement porte EXTRA_OPEN_VIDEO. On le consomme (une seule fois)
    /// et on demande à Dart de rebasculer Écouteurs → vidéo.
    private fun consumeOpenVideoExtra(intent: Intent?) {
        if (intent?.getBooleanExtra(
                PlaybackForegroundService.EXTRA_OPEN_VIDEO, false,
            ) != true
        ) {
            return
        }
        intent.removeExtra(PlaybackForegroundService.EXTRA_OPEN_VIDEO)
        // Le canal est câblé dans configureFlutterEngine (déjà fait quand
        // l'activité existe — cas normal du mode radio). S'il n'est pas
        // encore prêt (démarrage à froid, audio de toute façon coupé), on
        // laisse tomber en silence : rien à rebasculer.
        pipChannel?.invokeMethod("onNotificationVideo", null)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        consumeOpenVideoExtra(intent)
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(pipActionReceiver)
        } catch (_: Throwable) {
            // Déjà désenregistré / jamais enregistré : silencieux.
        }
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        Log.i(TAG, "configureFlutterEngine — wiring MethodChannels")
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Chaque channel est instancié dans son propre try/catch :
        // si UN handler crash à l'init (ex. dépendance native manquante),
        // les AUTRES restent câblés. Sans ça, une exception dans le 3e
        // wiring empêche le 1er et le 2e d'être disponibles côté Dart →
        // MissingPluginException "Bridge natif manquant" sur tous.

        try {
            castApi = GoogleCastApi(messenger = messenger, activity = this)
            Log.i(TAG, "  ✓ Cast channel wired")
        } catch (e: Throwable) {
            Log.e(TAG, "  ✗ Cast channel failed: $e", e)
        }

        // Identité stable de l'appareil : expose ANDROID_ID à Dart pour
        // dériver une MAC virtuelle DÉTERMINISTE (identique après une
        // réinstallation de l'app), au lieu d'une MAC aléatoire perdue à
        // chaque désinstallation.
        try {
            MethodChannel(messenger, DEVICE_CHANNEL).setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAndroidId" -> {
                        try {
                            val id = android.provider.Settings.Secure.getString(
                                contentResolver,
                                android.provider.Settings.Secure.ANDROID_ID,
                            )
                            result.success(id)
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }
                    // Infos appareil : modèle + fabricant + version Android +
                    // numéro de build. Sert au panel à RECENSER tous les
                    // Android où l'app est installée (même partagée).
                    "getDeviceInfo" -> {
                        try {
                            result.success(
                                hashMapOf(
                                    "model" to Build.MODEL,
                                    "manufacturer" to Build.MANUFACTURER,
                                    "release" to Build.VERSION.RELEASE,
                                    "sdk" to Build.VERSION.SDK_INT.toString(),
                                    "build" to Build.DISPLAY,
                                ),
                            )
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
            Log.i(TAG, "  ✓ Device channel wired")
        } catch (e: Throwable) {
            Log.e(TAG, "  ✗ Device channel failed: $e", e)
        }

        try {
            galleryExporter = GalleryExporter(
                messenger = messenger,
                context = applicationContext,
            )
            Log.i(TAG, "  ✓ Gallery channel wired")
        } catch (e: Throwable) {
            Log.e(TAG, "  ✗ Gallery channel failed: $e", e)
        }

        try {
            recordingService = RecordingServiceBridge(
                messenger = messenger,
                context = applicationContext,
            )
            Log.i(TAG, "  ✓ RecordingService channel wired")
        } catch (e: Throwable) {
            Log.e(TAG, "  ✗ RecordingService channel failed: $e", e)
        }

        // MulticastLock — INDISPENSABLE pour la découverte Chromecast /
        // DLNA. Sans le lock WiFi, la puce filtre les réponses mDNS
        // (224.0.0.251) et SSDP (239.255.255.250) → le picker liste 0
        // appareil. Le côté Dart (mdns_discovery.dart / ssdp_discovery.dart)
        // acquire() au début de chaque scan et release() à la fin.
        try {
            multicastLock = MulticastLockBridge(
                messenger = messenger,
                context = applicationContext,
            )
            Log.i(TAG, "  ✓ MulticastLock channel wired")
        } catch (e: Throwable) {
            Log.e(TAG, "  ✗ MulticastLock channel failed: $e", e)
        }

        // ========================================================
        //  PIP — Picture in Picture (YouTube Premium style)
        // ========================================================
        //  Le côté Dart appelle :
        //    - setPlaybackActive(bool) : true pendant la lecture,
        //      false sur pause / stop / dispose. Sert au natif à
        //      décider si onUserLeaveHint() déclenche le PiP auto.
        //    - setAspectRatio(num, den) : ratio courant de la
        //      vidéo (16:9 par défaut, change pour 4:3 / 21:9).
        //    - enterPip()             : entre en PiP IMMÉDIATEMENT
        //      (bouton manuel dans l'overlay du player).
        //    - isPipSupported()       : retourne true si Android 8+
        //      ET le device supporte PiP (hasSystemFeature).
        try {
            pipChannel = MethodChannel(messenger, PIP_CHANNEL)
            pipChannel!!.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setPlaybackActive" -> {
                        playbackActive = call.argument<Boolean>("active") ?: false
                        // En PiP, l'icône Lecture/Pause doit suivre l'état réel.
                        refreshPipActions()
                        result.success(null)
                    }
                    "setAspectRatio" -> {
                        // Clamp à des ratios PiP-compatibles. Android
                        // refuse les ratios trop extrêmes (<0.4 ou >2.39)
                        // et lèverait IllegalArgumentException — on
                        // borne en amont pour rester silencieux.
                        val num = (call.argument<Int>("num") ?: 16).coerceIn(1, 239)
                        val den = (call.argument<Int>("den") ?: 9).coerceIn(1, 239)
                        pipAspectNumer = num
                        pipAspectDenom = den
                        // Re-pose les params : ratio à jour ET boutons
                        // préservés (une MàJ partielle les effacerait).
                        refreshPipActions()
                        result.success(null)
                    }
                    "enterPip" -> {
                        result.success(enterPipNow())
                    }
                    "isPipSupported" -> {
                        result.success(isPipSupportedNative())
                    }
                    // ----- Mode « Écouteurs » : audio en arrière-plan -----
                    "setAudioOnlyMode" -> {
                        audioOnlyMode = call.argument<Boolean>("active") ?: false
                        Log.i(TAG, "audioOnlyMode = $audioOnlyMode")
                        // En PiP, le bouton 🎧 devient « Vidéo » (et vice-versa).
                        refreshPipActions()
                        result.success(null)
                    }
                    "startBackgroundAudio" -> {
                        val title = call.argument<String>("title") ?: "7 MOTION"
                        val body = call.argument<String>("body")
                        // i18n : libellés localisés (bouton Arrêter + canal
                        // de notification) fournis par Dart, null-safe.
                        // On remonte le VRAI résultat à Dart : avant, un
                        // échec de startForegroundService (ex. démarrage
                        // interdit depuis l'arrière-plan sur Android 12+)
                        // était avalé ici et Dart journalisait un
                        // « keepalive_started » menteur — le diagnostic
                        // « le cast coupe écran éteint » était invisible.
                        val started = startBackgroundAudio(
                            title,
                            body,
                            call.argument<String>("stopLabel"),
                            call.argument<String>("channelName"),
                            call.argument<String>("channelDesc"),
                            call.argument<String>("videoLabel"),
                        )
                        result.success(started)
                    }
                    "stopBackgroundAudio" -> {
                        stopBackgroundAudio()
                        result.success(null)
                    }
                    // Fait DISPARAÎTRE la fenêtre PiP sans tuer la lecture :
                    // la tâche passe en arrière-plan (la mini-fenêtre se
                    // ferme), le son continue via PlaybackForegroundService.
                    // C'est le comportement « radio » du bouton 🎧 : appui →
                    // plus aucune fenêtre, juste la voix (façon YouTube).
                    "dismissPipToBackground" -> {
                        result.success(dismissPipToBackground())
                    }
                    else -> result.notImplemented()
                }
            }
            Log.i(TAG, "  ✓ PiP channel wired")
        } catch (e: Throwable) {
            Log.e(TAG, "  ✗ PiP channel failed: $e", e)
        }
    }

    /// PiP est dispo depuis Android 8.0 (API 26) ET le device doit
    /// avoir le hardware feature `FEATURE_PICTURE_IN_PICTURE`. Toutes
    /// les TVs Android Leanback l'ont, presque tous les smartphones
    /// depuis 2018 aussi. Les vieux téléphones API < 26 ou les
    /// devices customisés qui désactivent PiP retournent false.
    private fun isPipSupportedNative(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return packageManager.hasSystemFeature(
            android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE
        )
    }

    /// `true` sur un téléviseur / box Android TV / Fire TV / Google TV
    /// (leanback ou type télévision). Sert à INTERDIRE le PiP et la lecture
    /// audio de fond sur TV : quitter l'app y coupe le son, point.
    private fun isTvDevice(): Boolean {
        return packageManager.hasSystemFeature(
            android.content.pm.PackageManager.FEATURE_LEANBACK,
        ) || packageManager.hasSystemFeature("android.hardware.type.television")
    }

    /// Boutons affichés DANS la fenêtre PiP (RemoteActions), façon
    /// YouTube : 🎧 Écouteurs (bascule audio seul, l'icône devient
    /// « Vidéo » quand le mode est actif) + Lecture/Pause. Les taps
    /// partent en broadcast NOT_EXPORTED vers `pipActionReceiver`,
    /// qui les route vers Dart (le lecteur agit, puis nous rappelle
    /// setAudioOnlyMode / setPlaybackActive → refreshPipActions()).
    private fun buildPipActions(): List<RemoteAction> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return emptyList()

        fun make(code: Int, iconRes: Int, title: String, value: String): RemoteAction {
            val intent = Intent(PIP_ACTION_INTENT)
                .setPackage(packageName)
                .putExtra(PIP_EXTRA_ACTION, value)
            val pending = PendingIntent.getBroadcast(
                this,
                code,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            return RemoteAction(Icon.createWithResource(this, iconRes), title, title, pending)
        }

        return listOf(
            make(
                1,
                if (audioOnlyMode) R.drawable.ic_pip_video else R.drawable.ic_pip_headphones,
                if (audioOnlyMode) "Vidéo" else "Écouteurs",
                PIP_ACTION_HEADPHONES,
            ),
            make(
                2,
                if (playbackActive) R.drawable.ic_pip_pause else R.drawable.ic_pip_play,
                if (playbackActive) "Pause" else "Lecture",
                PIP_ACTION_PLAY_PAUSE,
            ),
        )
    }

    /// Paramètres PiP courants : aspect ratio + boutons. Une seule
    /// source de vérité pour l'entrée en PiP ET les rafraîchissements.
    private fun pipParams(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(pipAspectNumer, pipAspectDenom))
            .setActions(buildPipActions())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ : entrée en PiP pilotée par l'OS (geste Accueil,
            // navigation gestuelle) — AVEC nos boutons, puisque les params
            // sont pré-enregistrés. Jamais en mode Écouteurs (pas de
            // fenêtre vidéo), jamais à l'arrêt, jamais sur TV.
            builder.setAutoEnterEnabled(
                playbackActive && !audioOnlyMode && !isTvDevice(),
            )
        }
        return builder.build()
    }

    /// Met à jour les boutons de la fenêtre PiP quand l'état change
    /// (play/pause, mode Écouteurs). Sans ça, l'icône resterait figée
    /// sur l'état d'entrée en PiP. No-op hors PiP.
    private fun refreshPipActions() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (isTvDevice()) return // pas de PiP sur TV, aucun param à poser
        try {
            // TOUJOURS poser les params, même HORS PiP : si c'est l'OS
            // (geste Accueil, constructeurs Samsung/Honor…) qui déclenche
            // le PiP, il ouvre la fenêtre avec les DERNIERS params
            // enregistrés. Avant, on ne les posait qu'une fois déjà en
            // PiP → fenêtre système SANS nos boutons 🎧/⏯.
            val params = pipParams() ?: return
            setPictureInPictureParams(params)
        } catch (e: Throwable) {
            Log.w(TAG, "refreshPipActions failed: $e")
        }
    }

    /// Ferme la fenêtre PiP en envoyant la tâche en arrière-plan, SANS
    /// finir l'activité (finish() tuerait le moteur Flutter et donc le
    /// son). Android n'a pas d'API officielle « quitter le PiP sans
    /// revenir au premier plan » — moveTaskToBack est le chemin reconnu :
    /// la mini-fenêtre disparaît, l'activité passe en onStop, et le son
    /// survit grâce au foreground service + wakelock du mode Écouteurs.
    private fun dismissPipToBackground(): Boolean {
        return try {
            moveTaskToBack(true)
        } catch (e: Throwable) {
            Log.w(TAG, "dismissPipToBackground failed: $e")
            false
        }
    }

    /// Entre en PiP MAINTENANT avec le bon aspect ratio. Retourne
    /// true si l'appel a bien été passé à l'OS, false sinon (pas
    /// supporté, exception, etc.).
    private fun enterPipNow(): Boolean {
        if (!isPipSupportedNative()) return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val params = pipParams() ?: return false
                enterPictureInPictureMode(params)
            } else {
                false
            }
        } catch (e: Throwable) {
            Log.w(TAG, "enterPip failed: $e")
            false
        }
    }

    /// Démarre le service audio de fond (mode « Écouteurs » et maintien
    /// éveillé du CAST RELAIS). Appelé le plus souvent pendant que l'app
    /// est VISIBLE (tap utilisateur) → pas de restriction Android 12+ ;
    /// MAIS le watchdog de reconnexion cast peut aussi le rappeler
    /// écran éteint, où Android 12+ peut refuser
    /// (ForegroundServiceStartNotAllowedException). On renvoie donc le
    /// résultat RÉEL au lieu d'avaler l'échec : Dart journalise
    /// keepalive_started / keepalive_failed dans la boîte noire.
    private fun startBackgroundAudio(
        title: String,
        body: String? = null,
        stopLabel: String? = null,
        channelName: String? = null,
        channelDesc: String? = null,
        videoLabel: String? = null,
    ): Boolean {
        return try {
            val intent = Intent(this, PlaybackForegroundService::class.java).apply {
                action = PlaybackForegroundService.ACTION_START
                putExtra(PlaybackForegroundService.EXTRA_TITLE, title)
                if (body != null) {
                    putExtra(PlaybackForegroundService.EXTRA_BODY, body)
                }
                if (stopLabel != null) {
                    putExtra(PlaybackForegroundService.EXTRA_STOP_LABEL, stopLabel)
                }
                if (channelName != null) {
                    putExtra(PlaybackForegroundService.EXTRA_CHANNEL_NAME, channelName)
                }
                if (channelDesc != null) {
                    putExtra(PlaybackForegroundService.EXTRA_CHANNEL_DESC, channelDesc)
                }
                if (videoLabel != null) {
                    putExtra(PlaybackForegroundService.EXTRA_VIDEO_LABEL, videoLabel)
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            true
        } catch (e: Throwable) {
            // Cas réel : ForegroundServiceStartNotAllowedException quand la
            // relance vient de l'arrière-plan (Android 12+). Le `false`
            // remonte jusqu'à la boîte noire côté Dart.
            Log.w(TAG, "startBackgroundAudio failed: $e")
            false
        }
    }

    /// Arrête le service audio de fond.
    private fun stopBackgroundAudio() {
        try {
            val intent = Intent(this, PlaybackForegroundService::class.java).apply {
                action = PlaybackForegroundService.ACTION_STOP
            }
            startService(intent)
        } catch (e: Throwable) {
            Log.w(TAG, "stopBackgroundAudio failed: $e")
        }
    }

    /// Appelé par Android quand l'utilisateur appuie HOME / SWITCH /
    /// fait un swipe pour quitter l'app. C'est LA hook standard
    /// utilisée par YouTube / Netflix pour entrer en PiP juste avant
    /// que l'app passe en background — la vidéo continue en mini-
    /// fenêtre flottante.
    ///
    /// Conditions pour le déclencher :
    ///   - Le PiP est supporté par l'OS et le device.
    ///   - La lecture est ACTUELLEMENT active (sinon afficher une
    ///     mini-fenêtre vide n'a aucun intérêt).
    ///   - On n'est pas DÉJÀ en PiP (paranoia, ne devrait jamais
    ///     arriver mais sécurité).
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // BOX TV : JAMAIS de PiP. Sur un téléviseur, quitter l'app (Home,
        // autre app via la télécommande) doit COUPER le son — la lecture en
        // arrière-plan « façon YouTube » (PiP flottant) n'a aucun sens sur TV
        // et laissait le son parler en fond (plainte terrain). En n'entrant
        // PAS en PiP, l'activité passe en onStop → le couvre-feu audio du
        // plugin natif (NativeVideoView.pauseAll) met tous les lecteurs en
        // pause. Le PiP reste actif sur téléphone/tablette (pas leanback).
        if (isTvDevice()) return
        // Mode « Écouteurs » : PAS de PiP vidéo. L'audio de fond est
        // déjà tenu en vie par PlaybackForegroundService, on ne pose
        // donc pas de mini-fenêtre flottante.
        if (audioOnlyMode) return
        if (playbackActive &&
            isPipSupportedNative() &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
            !isInPictureInPictureMode
        ) {
            enterPipNow()
        }
    }

    /// Notifie Flutter quand on entre/sort du PiP. Côté Dart, ça
    /// permet de cacher l'overlay des contrôles et d'adapter le
    /// layout (vidéo plein cadre, pas de boutons).
    override fun onPictureInPictureModeChanged(
        isInPip: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPip, newConfig)
        // Certaines surcouches constructeur ignorent les actions passées à
        // l'entrée : on les re-pose dès que le PiP est confirmé.
        if (isInPip) refreshPipActions()
        pipChannel?.invokeMethod(
            "onPipModeChanged",
            mapOf("inPip" to isInPip),
        )
    }
}
