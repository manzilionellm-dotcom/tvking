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

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    private var castApi: GoogleCastApi? = null
    private var galleryExporter: GalleryExporter? = null
    private var recordingService: RecordingServiceBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Cast SDK natif — channel "com.manzilionellm.tvking/cast"
        castApi = GoogleCastApi(
            messenger = flutterEngine.dartExecutor.binaryMessenger,
            activity = this,
        )

        // Export Galerie via MediaStore — channel ".../gallery"
        // Pour que les enregistrements .ts (libmpv stream-record)
        // apparaissent dans la galerie photo du téléphone, pas
        // perdus dans Android/data/...
        galleryExporter = GalleryExporter(
            messenger = flutterEngine.dartExecutor.binaryMessenger,
            context = applicationContext,
        )

        // Service ForegroundService — channel ".../recording_service"
        // Maintient l'app vivante quand l'enregistrement tourne et
        // que l'utilisateur quitte l'app pour lire un SMS / prendre
        // un appel. Sans ça, Android peut tuer le process et l'enregistrement
        // donne un fichier tronqué.
        recordingService = RecordingServiceBridge(
            messenger = flutterEngine.dartExecutor.binaryMessenger,
            context = applicationContext,
        )
    }
}
