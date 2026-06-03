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

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.util.Log
import android.util.Rational
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val TAG = "MainActivity"

        /// Channel Dart ↔ natif pour le Picture-in-Picture.
        /// Doit matcher EXACTEMENT côté lib/features/player/data/pip_service.dart
        private const val PIP_CHANNEL = "com.manzilionellm.tvking/pip"

        /// Channel Dart ↔ natif pour l'enregistrement par capture d'écran.
        /// Doit matcher lib/features/recordings/data/screen_recorder.dart
        private const val SCREENREC_CHANNEL =
            "com.manzilionellm.tvking/screen_recorder"
        private const val REQ_SCREEN_CAPTURE = 7021
        private const val REQ_RECORD_AUDIO = 7022
    }

    private var castApi: GoogleCastApi? = null
    private var galleryExporter: GalleryExporter? = null
    private var recordingService: RecordingServiceBridge? = null
    private var multicastLock: MulticastLockBridge? = null
    private var pipChannel: MethodChannel? = null
    private var screenRecChannel: MethodChannel? = null

    /// Contexte d'une demande de capture d'écran en attente (le temps
    /// que l'utilisateur réponde aux popups système). On mémorise le
    /// fichier de sortie + le titre + la Result Dart à compléter.
    private var pendingScreenRecFile: String? = null
    private var pendingScreenRecTitle: String? = null
    private var pendingScreenRecResult: MethodChannel.Result? = null

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

        // Enregistrement par CAPTURE D'ÉCRAN (MediaProjection).
        // start(title, file) : demande la popup système de capture puis
        //   lance ScreenRecordService (vidéo écran + audio micro best-effort).
        //   La lecture N'est PAS coupée → le client continue de regarder.
        // stop() : arrête le service. isSupported()/isRecording() utilitaires.
        try {
            screenRecChannel = MethodChannel(messenger, SCREENREC_CHANNEL)
            screenRecChannel!!.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP,
                    )
                    "isRecording" -> result.success(ScreenRecordService.isRecording)
                    "start" -> {
                        val file = call.argument<String>("file")
                        val title = call.argument<String>("title") ?: "7 MOTION"
                        if (file == null) {
                            result.error("no_file", "file manquant", null)
                        } else {
                            startScreenCapture(file, title, result)
                        }
                    }
                    "stop" -> {
                        stopScreenCapture()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
            Log.i(TAG, "  ✓ ScreenRecorder channel wired")
        } catch (e: Throwable) {
            Log.e(TAG, "  ✗ ScreenRecorder channel failed: $e", e)
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
                        result.success(null)
                    }
                    "enterPip" -> {
                        result.success(enterPipNow())
                    }
                    "isPipSupported" -> {
                        result.success(isPipSupportedNative())
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

    /// Entre en PiP MAINTENANT avec le bon aspect ratio. Retourne
    /// true si l'appel a bien été passé à l'OS, false sinon (pas
    /// supporté, exception, etc.).
    private fun enterPipNow(): Boolean {
        if (!isPipSupportedNative()) return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(pipAspectNumer, pipAspectDenom))
                    .build()
                enterPictureInPictureMode(params)
            } else {
                false
            }
        } catch (e: Throwable) {
            Log.w(TAG, "enterPip failed: $e")
            false
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
        pipChannel?.invokeMethod(
            "onPipModeChanged",
            mapOf("inPip" to isInPip),
        )
    }

    // =========================================================
    //  Enregistrement par capture d'écran (MediaProjection)
    // =========================================================

    /// Démarre une capture : on demande d'abord l'audio (micro, best
    /// effort), puis la popup système de capture d'écran. Le résultat
    /// revient dans onActivityResult / onRequestPermissionsResult.
    private fun startScreenCapture(
        file: String,
        title: String,
        result: MethodChannel.Result,
    ) {
        pendingScreenRecFile = file
        pendingScreenRecTitle = title
        pendingScreenRecResult = result

        // AUTORISATION DÉJÀ ACCORDÉE (projection vivante) : on ne
        // re-demande PAS la popup système — on réutilise la session de
        // capture existante et on démarre directement l'enregistrement.
        if (ScreenRecordService.projectionActive) {
            startRecordingReusingProjection(file, title)
            pendingScreenRecResult?.success(true)
            clearPendingScreenRec()
            return
        }

        // Audio micro : si pas encore accordé, on le demande AVANT la
        // popup de capture (sinon repli vidéo seule côté service). On
        // enchaîne sur la capture dans onRequestPermissionsResult.
        val micGranted = ContextCompat.checkSelfPermission(
            this, android.Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED
        if (!micGranted && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                requestPermissions(
                    arrayOf(android.Manifest.permission.RECORD_AUDIO),
                    REQ_RECORD_AUDIO,
                )
                return // la suite se fait dans onRequestPermissionsResult
            } catch (_: Throwable) {
                // si la demande échoue, on continue quand même (vidéo seule)
            }
        }
        launchScreenCaptureIntent()
    }

    /// Lance la popup système "Autoriser la capture d'écran ?".
    private fun launchScreenCaptureIntent() {
        try {
            val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                as MediaProjectionManager
            startActivityForResult(
                mpm.createScreenCaptureIntent(),
                REQ_SCREEN_CAPTURE,
            )
        } catch (e: Throwable) {
            Log.e(TAG, "createScreenCaptureIntent KO: $e", e)
            pendingScreenRecResult?.success(false)
            clearPendingScreenRec()
        }
    }

    /// Démarre un enregistrement en RÉUTILISANT la projection déjà
    /// autorisée (pas de popup système). Le service est déjà foreground.
    private fun startRecordingReusingProjection(file: String, title: String) {
        try {
            val intent = Intent(this, ScreenRecordService::class.java).apply {
                action = ScreenRecordService.ACTION_START
                putExtra(ScreenRecordService.EXTRA_FILE, file)
                putExtra(ScreenRecordService.EXTRA_TITLE, title)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Throwable) {
            Log.e(TAG, "reuse projection KO: $e", e)
        }
    }

    private fun stopScreenCapture() {
        try {
            val intent = Intent(this, ScreenRecordService::class.java).apply {
                action = ScreenRecordService.ACTION_STOP
            }
            startService(intent)
        } catch (e: Throwable) {
            Log.w(TAG, "stopScreenCapture: $e")
        }
    }

    private fun clearPendingScreenRec() {
        pendingScreenRecFile = null
        pendingScreenRecTitle = null
        pendingScreenRecResult = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_RECORD_AUDIO) {
            // Qu'il soit accordé ou non, on enchaîne sur la capture
            // (le service fera vidéo seule si l'audio manque).
            launchScreenCaptureIntent()
        }
    }

    @Deprecated("startActivityForResult flow")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_SCREEN_CAPTURE) return
        val file = pendingScreenRecFile
        val title = pendingScreenRecTitle ?: "BLACK7 ROYAL"
        val pending = pendingScreenRecResult
        clearPendingScreenRec()

        if (resultCode == Activity.RESULT_OK && data != null && file != null) {
            try {
                val intent = Intent(this, ScreenRecordService::class.java).apply {
                    action = ScreenRecordService.ACTION_START
                    putExtra(ScreenRecordService.EXTRA_RESULT_CODE, resultCode)
                    putExtra(ScreenRecordService.EXTRA_RESULT_DATA, data)
                    putExtra(ScreenRecordService.EXTRA_FILE, file)
                    putExtra(ScreenRecordService.EXTRA_TITLE, title)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
                pending?.success(true)
            } catch (e: Throwable) {
                Log.e(TAG, "démarrage ScreenRecordService KO: $e", e)
                pending?.success(false)
            }
        } else {
            // L'utilisateur a refusé la capture.
            pending?.success(false)
        }
    }
}
