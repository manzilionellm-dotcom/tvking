// =========================================================
//  main_tv.dart — Point d'entrée DeFew TV (Android TV / Fire TV)
// =========================================================
//  App SŒUR de la version mobile : MÊME backend, MÊME panel (licence,
//  activation, sources poussées, « regarde », annonces, thème). Seule
//  l'UI change → 10-foot, navigation D-pad (cf. features/tv/).
//
//  Build : `flutter build apk --release --target=lib/main_tv.dart`
//  (un workflow CI dédié + manifest Leanback viendront ensuite).
// =========================================================
import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'core/app/app_platform.dart';
import 'core/flavor/flavor.dart';
import 'core/i18n/locale_repository.dart';
import 'features/device/data/device_identity.dart';
import 'features/playlists/data/playlist_repository.dart';
import 'features/playlists/data/favorites_repository.dart';
import 'features/playlists/data/remote_source_repository.dart';
import 'features/recordings/data/recording_repository.dart';
import 'features/subscription/data/subscription_state.dart';
import 'features/theme/data/remote_theme_repository.dart';
import 'features/tv/presentation/tv_app.dart';

// =========================================================
//  BOUNDARY D'ERREURS GLOBAL — « l'app ne se ferme JAMAIS toute seule »
// =========================================================
//  C'est ce que font les applis grand public (Netflix, YouTube…) : aucune
//  exception non rattrapée ne doit tuer le process. On installe 4 filets :
//    1) ErrorWidget.builder : un widget qui plante affiche un fond sombre
//       discret (au lieu de l'écran rouge/gris) — le RESTE de l'app continue.
//    2) FlutterError.onError : erreurs de build/layout/paint → on LOG, pas de
//       crash.
//    3) PlatformDispatcher.onError : erreurs async/plateforme non rattrapées →
//       on les déclare « gérées » (return true) → pas de crash.
//    4) runZonedGuarded : filet ultime pour toute erreur asynchrone de la zone.
//  En prod on se contente de logguer (debugPrint) ; en debug on garde
//  l'affichage console habituel pour ne pas masquer les bugs pendant le dev.
// =========================================================
void main() {
  // 1) Un sous-arbre qui plante ne casse pas tout l'écran : fond Maison Noir.
  ErrorWidget.builder =
      (FlutterErrorDetails details) => const ColoredBox(color: Color(0xFF070707));

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
      };

      // 3) Erreurs async/plateforme non rattrapées → « gérées », pas de crash.
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        debugPrint('[Uncaught] $error');
        return true;
      };

      await _bootstrap();
    },
    // 4) Filet ultime.
    (Object error, StackTrace stack) {
      debugPrint('[Zone] $error');
    },
  );
}

Future<void> _bootstrap() async {
  // Flavor explicite (un seul produit pour l'instant : The Few).
  FlavorConfig.setCurrent(FlavorConfig.sevenMotion);

  // Cette app est la version TÉLÉVISION → le heartbeat enverra
  // platform='tv' et le panel l'affichera comme 📺 (vs 📱 mobile).
  AppPlatform.isTv = true;

  // Moteur lecteur natif (mpv) — avant runApp, comme côté mobile.
  MediaKit.ensureInitialized();

  // La TV est TOUJOURS en paysage : on verrouille (pas de portrait).
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Langue de l'app : on charge le choix mémorisé (ou « Système » =>
  // l'app suit la langue de la TV). BLOQUANT et rapide : garantit que le
  // 1er rendu est déjà dans la bonne langue (pas de flash en français).
  await LocaleRepository.instance.initialize();

  // --- Briques PARTAGÉES avec le mobile (non bloquant) ---
  // 1) Identité stable (MAC) → le panel reconnaît l'appareil TV.
  unawaited(DeviceIdentity.instance.preload());
  // 2) Licence/abonnement : heartbeat + statut depuis le MÊME worker.
  unawaited(SubscriptionState.instance.initialize().then((_) {
    SubscriptionState.instance.syncWithBackend();
  }));
  // 3) Thème distant piloté par le panel (couleur/nom).
  unawaited(RemoteThemeRepository.fetchAndApply());

  // 4) Chaînes : on charge la base locale, PUIS on synchronise la source
  //    poussée par le panel (Xtream/M3U via /api/device-source/<mac>).
  //    Les écrans écoutent `PlaylistRepository.channelsStream`.
  unawaited(
    PlaylistRepository.instance.initialize().then((_) {
      RemoteSourceRepository.sync();
    }),
  );

  // 5) Enregistrements : on initialise la base et on finalise les
  //    enregistrements « fantômes » (l'app a pu être tuée par l'OS en plein
  //    enregistrement). recoverOrphans est idempotent (no-op s'il n'y a rien).
  unawaited(
    RecordingRepository.instance
        .initialize()
        .then((_) => RecordingRepository.instance.recoverOrphans())
        .then((_) {}),
  );

  // 6) Favoris : on précharge l'ensemble des chaînes favorites pour que le
  //    cœur ❤ du lecteur affiche le bon état dès la 1re ouverture.
  unawaited(FavoritesRepository.instance.initialize());

  runApp(const TvApp());
}
