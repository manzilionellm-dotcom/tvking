// =========================================================
//  crash_reporting_firebase.dart — Branchement Firebase Crashlytics
// =========================================================
//  Surcouche OPTIONNELLE de CrashReporting. Tout est « fail-open » : si
//  Firebase n'est pas configuré (pas de google-services.json au build),
//  rien ne plante — Crashlytics reste simplement désactivé et l'app
//  continue avec son journal local.
//
//  Ce que Crashlytics apporte par rapport au journal local :
//    - crashes NATIFS (JNI/NDK, UnsatisfiedLinkError, SIGSEGV…) en plus des
//      exceptions Dart ;
//    - contexte appareil collecté AUTOMATIQUEMENT par le SDK natif : modèle,
//      fabricant, version Android, ABI/architecture CPU, RAM, orientation,
//      état rooté, etc. → la « matrice d'appareils » se remplit toute seule
//      à partir du trafic réel, sans aucun plugin device_info à ajouter.
//
//  Activation : poser le secret CI `GOOGLE_SERVICES_JSON` (contenu du
//  google-services.json du projet Firebase). Le workflow l'écrit dans
//  android/app/ et applique le plugin Gradle google-services. Sans ce
//  secret, ce module ne fait rien (volontairement).
// =========================================================
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'crash_reporting.dart';

/// Tente de brancher Crashlytics. Retourne `true` si actif, `false` sinon.
/// Best-effort : ne lève JAMAIS (toute erreur est avalée et loggée).
Future<bool> attachCrashlytics() async {
  // 1) Init Firebase. Sans google-services.json, ceci lève → on capte et on
  //    abandonne proprement (Crashlytics restera désactivé).
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('[Crashlytics] Firebase non configuré → désactivé ($e)');
    return false;
  }

  // 2) Configure et branche le puits.
  try {
    final FirebaseCrashlytics fc = FirebaseCrashlytics.instance;

    // En debug, on n'envoie rien (on garde la console) ; en release, collecte ON.
    await fc.setCrashlyticsCollectionEnabled(!kDebugMode);

    // Version applicative en clé custom (le SDK fait déjà device/OS/ABI/RAM).
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      await fc.setCustomKey('app_version', '${info.version}+${info.buildNumber}');
    } catch (_) {
      // package_info indisponible : pas grave, Crashlytics garde le reste.
    }

    // Toute erreur signalée à CrashReporting part désormais aussi vers
    // Crashlytics (recordError ajoute le contexte comme « reason »).
    CrashReporting.instance.attachBackend(
      (Object error, StackTrace? stack, {String? context, bool fatal = false}) {
        fc.recordError(error, stack, reason: context, fatal: fatal);
      },
    );

    debugPrint('[Crashlytics] actif.');
    return true;
  } catch (e) {
    debugPrint('[Crashlytics] init partielle échouée → désactivé ($e)');
    return false;
  }
}
