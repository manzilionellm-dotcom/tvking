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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Câblage du Cast SDK. GoogleCastApi gère lui-même son
        // MethodChannel — pas besoin de le retenir au-delà de l'init.
        castApi = GoogleCastApi(
            messenger = flutterEngine.dartExecutor.binaryMessenger,
            activity = this,
        )
    }
}
