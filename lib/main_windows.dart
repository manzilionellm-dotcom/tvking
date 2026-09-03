// =========================================================
//  main_windows.dart — Point d'entrée The Few sur WINDOWS (PC)
// =========================================================
//  App SŒUR des versions mobile et TV : MÊME backend, MÊME panel (licence,
//  activation, sources poussées). On réutilise l'UI « 10-foot » de la TV
//  (features/tv/) car elle est pensée pleine page, navigable au CLAVIER
//  (flèches = D-pad, Entrée = OK, Échap = Retour) → parfaite pour un PC /
//  mini-PC branché à un écran ou une TV.
//
//  CE QUI CHANGE par rapport à la TV (Android) :
//    1) STOCKAGE : Windows n'a pas de SQLite système. On initialise le moteur
//       SQLite « FFI » (sqflite_common_ffi) AVANT toute ouverture de base, puis
//       on branche `databaseFactory` dessus → tout le code de base existant
//       (PlaylistDatabase…) fonctionne tel quel.
//    2) LECTURE VIDÉO : le lecteur natif Media3/ExoPlayer est Android-uniquement.
//       Sur PC, c'est media_kit (libmpv) qui lira les flux (étape 2 — câblage
//       du lecteur desktop, à tester sur une vraie machine Windows).
//    3) On N'APPELLE PAS les briques 100 % Android (BootGuard natif anti-boucle,
//       notifications/alarmes, enregistrement par relais) : elles s'appuient sur
//       des canaux natifs absents sur PC. Le filet d'erreurs global (runGuarded)
//       reste partagé → l'app ne se ferme jamais toute seule.
//
//  Build : `flutter build windows --release --target=lib/main_windows.dart`
//  (un workflow CI dédié compile et publie un .zip téléchargeable).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/app/app_platform.dart';
import 'core/app/guarded_main.dart';
import 'core/flavor/flavor.dart';
import 'core/i18n/locale_repository.dart';
import 'core/privacy/privacy_shield.dart';
import 'core/realtime/realtime_sync_service.dart';
import 'features/channels/domain/channel.dart';
import 'features/device/data/device_identity.dart';
import 'features/playlists/data/favorites_repository.dart';
import 'features/playlists/data/playlist_repository.dart';
import 'features/playlists/data/remote_source_repository.dart';
import 'features/subscription/data/subscription_state.dart';
import 'features/theme/data/remote_theme_repository.dart';
import 'features/tv/presentation/player/desktop_player_screen.dart';
import 'features/tv/presentation/tv_app.dart';
import 'features/tv/presentation/tv_player_screen.dart';

// Le filet d'erreurs global (« l'app ne se ferme JAMAIS toute seule ») est
// MUTUALISÉ avec le mobile et la TV via runGuarded.
void main() => runGuarded(_bootstrap);

Future<void> _bootstrap() async {
  // Un seul produit pour l'instant : The Few.
  FlavorConfig.setCurrent(FlavorConfig.sevenMotion);

  // Le heartbeat enverra platform='windows' (le panel pourra distinguer PC
  // des box TV et des téléphones ). AppPlatform.isTv reste à false : l'UI
  // TV s'affiche quand même (on l'instancie explicitement via TvApp ci-dessous).
  AppPlatform.isWindows = true;

  // ====================================================================
  //  SQLite DESKTOP : on initialise le moteur FFI et on le pose comme fabrique
  //  GLOBALE de bases AVANT toute ouverture. Dès lors, `openDatabase(...)` du
  //  code existant (PlaylistDatabase) passe par le SQLite embarqué Windows.
  // ====================================================================
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Moteur de lecture desktop (libmpv) : initialisation, puis on INJECTE le
  // lecteur media_kit comme lecteur plein écran de l'app (le défaut natif
  // Android est ainsi remplacé sur PC, sans toucher au code partagé).
  MediaKit.ensureInitialized();
  registerTvPlayer((List<Channel> channels, int startIndex) =>
      DesktopPlayerScreen(channels: channels, startIndex: startIndex));

  // Langue de l'app : choix mémorisé (ou « Système »). Bloquant et rapide pour
  // que le 1er rendu soit déjà dans la bonne langue.
  await LocaleRepository.instance.initialize();

  // --- Briques PARTAGÉES avec mobile/TV (non bloquantes) ---
  // 1) Identité stable (MAC) : sur PC, le canal natif Android est absent →
  //    DeviceIdentity bascule TOUT SEUL sur une MAC locale stable (try/catch
  //    interne). Le panel reconnaît donc aussi le poste Windows.
  unawaited(DeviceIdentity.instance.preload());
  // 2) Licence/abonnement : heartbeat + statut depuis le MÊME worker (HTTP,
  //    100 % multiplateforme).
  unawaited(SubscriptionState.instance.initialize().then((_) {
    SubscriptionState.instance.syncWithBackend();
  }));
  // 3) Thème distant piloté par le panel (couleur/nom).
  unawaited(RemoteThemeRepository.fetchAndApply());

  // 4) Chaînes : on charge la base locale AVANT le 1er rendu (cache SQLite via
  //    FFI), avec un garde-fou de 6 s pour ne jamais bloquer le démarrage.
  await PlaylistRepository.instance
      .initialize()
      .timeout(const Duration(seconds: 6), onTimeout: () {});

  // 5) Favoris : préchargés pour que le cœur reflète le bon état dès l'ouverture.
  unawaited(FavoritesRepository.instance.initialize());

  runApp(const TvApp());

  // IMPORT DISTANT (source poussée par le panel) EN ARRIÈRE-PLAN, après le 1er
  // rendu : c'est l'étape la plus gourmande (fetch + parse). Best-effort, ne
  // throw jamais.
  unawaited(RemoteSourceRepository.sync());

  // Re-synchro PÉRIODIQUE (5 min) tant que l'app tourne : une source ajoutée/
  // poussée par le revendeur APRÈS l'ouverture de l'app reste sinon invisible
  // jusqu'au redémarrage. Léger (un GET JSON), n'ajoute que ce qui manque.
  Timer.periodic(const Duration(minutes: 5), (_) {
    RemoteSourceRepository.sync();
  });

  // TEMPS RÉEL (WebSocket) : les actions du panel arrivent en < 1 s quand
  // le poste est en ligne — les polls ci-dessus restent le filet de
  // sécurité. `dart:io` est disponible sur Windows ; le try/catch est une
  // ceinture supplémentaire (le service, lui, ne throw jamais).
  try {
    // Mode Bouclier : réglages (HTTPS préféré, télémétrie minimale). Sur PC
    // la détection VPN n'existe pas : le coupe-circuit y est sans effet.
    unawaited(PrivacyShield.instance.load());
    unawaited(RealtimeSyncService.instance.start(platform: 'windows'));
  } catch (e) {
    debugPrint('[main_windows] realtime start: $e');
  }
}
