// =========================================================
//  guarded_main.dart — Filet d'erreurs global PARTAGÉ
// =========================================================
//  « L'app ne se ferme JAMAIS toute seule. » C'est ce que font les applis
//  grand public (Netflix, YouTube…) : aucune exception non rattrapée ne
//  doit tuer le process. On installe ICI, en UN SEUL endroit, les 4 filets
//  — et TOUS les points d'entrée (mobile `main.dart`, `main_prive.dart`,
//  TV `main_tv.dart`) passent par `runGuarded()`. Avant, seul la TV avait
//  ce filet ; le mobile démarrait « à nu » → une exception au boot pouvait
//  fermer l'app sèchement. C'est corrigé : un seul code, partout.
//
//  Les 4 filets :
//    1) ErrorWidget.builder      : un widget qui plante affiche un fond
//       sombre discret (au lieu de l'écran rouge/gris) → le RESTE de l'app
//       continue de tourner.
//    2) FlutterError.onError     : erreurs de build/layout/paint → on LOG,
//       pas de crash (console habituelle en debug).
//    3) PlatformDispatcher.onError : erreurs async/plateforme non rattrapées
//       → déclarées « gérées » (return true) → pas de crash.
//    4) runZonedGuarded          : filet ultime pour toute erreur async de
//       la zone (y compris pendant le boot, AVANT le 1er frame).
//
//  Toutes les erreurs interceptées sont en plus envoyées à `CrashReporting`
//  (journal local + Crashlytics si configuré) — sans jamais bloquer.
// =========================================================
import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../crash/crash_reporting.dart';
import '../crash/crash_reporting_firebase.dart';

/// Lance [body] (la séquence de démarrage d'un flavor) sous les 4 filets.
///
/// `void` et non `Future` : on ne veut PAS que l'appelant `await` — la zone
/// vit aussi longtemps que l'app. Les points d'entrée se contentent de
/// `runGuarded(() async { … });`.
void runGuarded(Future<void> Function() body) {
  // 1) Un sous-arbre qui plante ne casse pas tout l'écran : fond Maison Noir.
  //    NB : on utilise volontairement une couleur LITTÉRALE ici (et non
  //    AppColors) — ce widget de secours ne doit dépendre de RIEN qui
  //    pourrait justement être la cause du plantage (thème non chargé, etc.).
  ErrorWidget.builder = (FlutterErrorDetails details) {
    CrashReporting.instance
        .recordError(details.exception, details.stack, context: 'ErrorWidget');
    return const ColoredBox(color: Color(0xFF070707));
  };

  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // 2) Erreurs Flutter (build/layout/paint).
      final FlutterExceptionHandler? presentError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (kDebugMode) {
          presentError?.call(details); // console habituelle en dev
        } else {
          debugPrint('[FlutterError] ${details.exceptionAsString()}');
        }
        CrashReporting.instance.recordError(details.exception, details.stack,
            context: 'FlutterError');
      };

      // 3) Erreurs async/plateforme non rattrapées → « gérées », pas de crash.
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        CrashReporting.instance
            .recordError(error, stack, context: 'PlatformDispatcher');
        return true;
      };

      // Collecteur prêt AVANT le boot : toute erreur de démarrage est captée.
      await CrashReporting.instance.initialize();

      // Crashlytics si (et seulement si) le projet est configuré. Best-effort,
      // jamais bloquant ni fatal : sans google-services.json, no-op silencieux.
      await attachCrashlytics();

      await body();
    },
    // 4) Filet ultime.
    (Object error, StackTrace stack) {
      CrashReporting.instance.recordError(error, stack, context: 'Zone');
    },
  );
}
