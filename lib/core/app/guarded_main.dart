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
import 'dart:io' show Directory, SocketException;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:path_provider/path_provider.dart';

import '../crash/crash_reporting.dart';
import '../crash/crash_reporting_firebase.dart';
import '../crash/remote_error_reporter.dart';
import '../observability/black_box.dart';
import 'device_memory.dart';

/// Ajuste le cache d'images selon la RAM réelle. Le défaut posé au boot est
/// déjà PRUDENT (sûr même à 1 Go) ; ici on l'ÉLARGIT sur les box bien dotées et
/// on le RESSERRE encore sur les box « low RAM ». Best-effort : si l'info n'est
/// pas dispo, on garde le défaut prudent.
///
/// La RAM est lue via [DeviceMemory] (SOURCE UNIQUE, partagée avec le plafond
/// de chaînes en RAM côté PlaylistRepository) → un seul appel natif, une seule
/// vérité « petite box / grande box ».
Future<void> _tuneImageCacheForRam() async {
  try {
    await DeviceMemory.ensureLoaded();
    final int totalMb = DeviceMemory.totalMb;
    final bool lowRam = DeviceMemory.lowRam;
    int imgs;
    int bytes;
    if (lowRam || (totalMb > 0 && totalMb <= 1024)) {
      imgs = 60; // ≤ 1 Go : empreinte minimale
      bytes = 24 << 20;
    } else if (totalMb <= 2048) {
      imgs = 120; // ~1–2 Go : équilibré
      bytes = 48 << 20;
    } else {
      imgs = 220; // > 2 Go : pleine qualité
      bytes = 96 << 20;
    }
    PaintingBinding.instance.imageCache
      ..maximumSize = imgs
      ..maximumSizeBytes = bytes;
  } catch (_) {
    // RAM inconnue (plateforme/échec) → on garde le défaut prudent du boot.
  }
}

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

      // ANTI-OOM IMAGES (P0-6) — PARTAGÉ par tous les flavors (mobile/TV/Privé).
      //  Symptôme : en défilant (D-pad haut/bas) la grille de chaînes, l'app se
      //  FERME toute seule. Cause : le cache d'images Flutter par défaut autorise
      //  jusqu'à 1000 images / ~100 Mo ; en scrollant des milliers de logos
      //  réseau, il enfle et l'OS TUE le process (un kill mémoire natif n'est PAS
      //  rattrapable par les filets Dart → « fermeture brutale »). On PLAFONNE le
      //  cache pour qu'il évince agressivement : la mémoire reste bornée, le
      //  scroll ne crashe plus (les logos hors écran sont relâchés puis re-servis
      //  depuis le cache disque de cached_network_image → toujours fluide).
      // DÉFAUT PRUDENT (sûr même sur une box ~1 Go) posé IMMÉDIATEMENT au boot
      // → protège les petites box dès la 1re image. Puis on ADAPTE selon la RAM
      // réelle (cf. _tuneImageCacheForRam) : on élargit sur les grandes box.
      PaintingBinding.instance.imageCache
        ..maximumSize = 90
        ..maximumSizeBytes = 40 << 20;
      // Ajustement adaptatif (non bloquant) : petite RAM ⇒ resserre, grande
      // RAM ⇒ élargit. Best-effort, ne retarde jamais le démarrage.
      unawaited(_tuneImageCacheForRam());

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
        if (isBenignNetworkNoise(error)) {
          CrashReporting.instance.log('bruit réseau ignoré: $error');
          return true;
        }
        CrashReporting.instance
            .recordError(error, stack, context: 'PlatformDispatcher');
        return true;
      };

      // Collecteur prêt AVANT le boot : toute erreur de démarrage est captée.
      await CrashReporting.instance.initialize();

      // BOÎTE NOIRE (2026-07-09) : enregistreur persistant qui capture
      // StructuredLogger + CrashReporting sur disque (survit aux crashs)
      // et sait produire des constats automatiques. Best-effort : si le
      // disque est indisponible, elle continue en mémoire seule.
      try {
        final dir = await getApplicationSupportDirectory();
        await BlackBox.instance.initialize(directory: dir);
      } catch (e) {
        debugPrint('[BlackBox] dossier support KO, repli temp: $e');
        try {
          await BlackBox.instance.initialize(
            directory: Directory.systemTemp,
          );
        } catch (_) {/* la capture mémoire du logger reste sans disque */}
      }

      // Crashlytics si (et seulement si) le projet est configuré. Best-effort,
      // jamais bloquant ni fatal : sans google-services.json, no-op silencieux.
      await attachCrashlytics();

      // Remontée des erreurs vers le PANEL (POST /api/error-log) : le revendeur
      // voit dans « Journaux d'erreurs » ce qui cloche chez un client, sans le
      // harceler. Anti-spam (1/60 s), RELEASE only, best-effort — cf. classe.
      RemoteErrorReporter.instance.attach();

      await body();
    },
    // 4) Filet ultime.
    (Object error, StackTrace stack) {
      if (isBenignNetworkNoise(error)) {
        // Diag terrain 2026-07-09 : la découverte mDNS/SSDP émet en
        // multicast toutes les 60 s ; quand Android bloque l'émission
        // en arrière-plan (EPERM), le paquet multicast_dns laisse fuir
        // l'exception dans la zone — 5+ « erreurs non rattrapées » par
        // heure dans la boîte noire pour un non-événement. Breadcrumb,
        // pas erreur.
        CrashReporting.instance.log('bruit réseau ignoré: $error');
        return;
      }
      CrashReporting.instance.recordError(error, stack, context: 'Zone');
    },
  );
}

/// « Bruit » réseau attendu et sans gravité : émission UDP multicast
/// refusée par l'OS quand l'app est en arrière-plan (découverte
/// mDNS/SSDP, errno=1 EPERM / réseau coupé). Pur + statique → testé.
@visibleForTesting
bool isBenignNetworkNoise(Object error) {
  if (error is! SocketException) return false;
  final String msg = error.message;
  return msg.contains('Send failed') ||
      error.osError?.errorCode == 1 || // EPERM (multicast bloqué)
      error.osError?.errorCode == 101; // ENETUNREACH (réseau coupé)
}
