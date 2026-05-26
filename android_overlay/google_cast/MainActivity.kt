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

import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val TAG = "MainActivity"
    }

    private var castApi: GoogleCastApi? = null
    private var galleryExporter: GalleryExporter? = null
    private var recordingService: RecordingServiceBridge? = null

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
    }
}
