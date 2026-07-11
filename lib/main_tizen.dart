// =========================================================
//  main_tizen.dart — Point d'entrée The Few sur SAMSUNG TV (Tizen)
// =========================================================
//  App SŒUR des versions Android TV / mobile / Windows : MÊME backend, MÊME
//  panel (licence, activation, sources poussées). On réutilise l'UI « 10-foot »
//  de la TV (features/tv/), navigable à la télécommande Samsung.
//
//  CE QUI CHANGE :
//    1) LECTURE VIDÉO : sur Tizen, le lecteur natif Media3/ExoPlayer (Android)
//       n'existe pas et media_kit n'a pas de backend Tizen. On lit via
//       video_player_avplay (AVPlay/PlusPlayer natif Samsung) — injecté ici.
//    2) STOCKAGE : pas de SQLite système exposé comme sur Android → on initialise
//       le moteur SQLite FFI (comme sur Windows). Si indisponible sur la cible,
//       l'app démarre quand même (le cache se remplira via la source distante).
//    3) On n'appelle PAS les briques 100 % Android (BootGuard natif,
//       notifications, enregistrement par relais). Le filet d'erreurs global
//       (runGuarded) reste partagé.
//
//  Build : `flutter-tizen build tpk --device-profile tv` (cf. build-tizen.yml).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

import 'core/app/app_platform.dart';
import 'core/app/guarded_main.dart';
import 'core/flavor/flavor.dart';
import 'core/i18n/locale_repository.dart';
import 'core/realtime/realtime_sync_service.dart';
import 'features/channels/domain/channel.dart';
import 'features/device/data/device_identity.dart';
import 'features/playlists/data/favorites_repository.dart';
import 'features/playlists/data/playlist_repository.dart';
import 'features/playlists/data/remote_source_repository.dart';
import 'features/subscription/data/subscription_state.dart';
import 'features/theme/data/remote_theme_repository.dart';
import 'features/tv/presentation/player/tizen_player_screen.dart';
import 'features/tv/presentation/tv_app.dart';
import 'features/tv/presentation/tv_player_screen.dart';

void main() => runGuarded(_bootstrap);

Future<void> _bootstrap() async {
  FlavorConfig.setCurrent(FlavorConfig.sevenMotion);

  // C'est une TÉLÉVISION → le panel l'affiche comme 📺 (comme l'Android TV).
  AppPlatform.isTv = true;

  // SQLite : sur Tizen on utilise le plugin NATIF `sqflite_tizen` (ajouté par le
  // workflow CI) — il enregistre tout seul la fabrique de bases, donc le code
  // existant (PlaylistDatabase → openDatabase) fonctionne SANS FFI ni init.

  // INJECTION du lecteur Samsung (AVPlay) comme lecteur plein écran de l'app.
  registerTvPlayer((List<Channel> channels, int startIndex) =>
      TizenPlayerScreen(channels: channels, startIndex: startIndex));

  await LocaleRepository.instance.initialize();

  unawaited(DeviceIdentity.instance.preload());
  unawaited(SubscriptionState.instance.initialize().then((_) {
    SubscriptionState.instance.syncWithBackend();
  }));
  unawaited(RemoteThemeRepository.fetchAndApply());

  await PlaylistRepository.instance
      .initialize()
      .timeout(const Duration(seconds: 6), onTimeout: () {});

  unawaited(FavoritesRepository.instance.initialize());

  runApp(const TvApp());

  unawaited(RemoteSourceRepository.sync());

  // Re-synchro PÉRIODIQUE (5 min) tant que l'app tourne : une source ajoutée/
  // poussée par le revendeur APRÈS l'ouverture de l'app reste sinon invisible
  // jusqu'au redémarrage. Léger (un GET JSON), n'ajoute que ce qui manque.
  Timer.periodic(const Duration(minutes: 5), (_) {
    RemoteSourceRepository.sync();
  });

  // TEMPS RÉEL (WebSocket) : mêmes bénéfices que sur Android TV (< 1 s
  // pour les actions du panel). `dart:io` existe sur Tizen (flutter-tizen) ;
  // le try/catch est une ceinture supplémentaire — le service ne throw
  // jamais et se contente du polling ci-dessus si le socket est indispo.
  try {
    unawaited(RealtimeSyncService.instance.start(platform: 'tv'));
  } catch (e) {
    debugPrint('[main_tizen] realtime start: $e');
  }
}
