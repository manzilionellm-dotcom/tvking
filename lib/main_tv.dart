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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app/app_platform.dart';
import 'core/app/boot_guard.dart';
import 'core/app/guarded_main.dart';
import 'core/flavor/flavor.dart';
import 'core/i18n/locale_repository.dart';
import 'core/notifications/notification_service.dart';
import 'features/channels/data/recently_watched_repository.dart';
import 'features/device/data/device_identity.dart';
import 'features/playlists/data/playlist_repository.dart';
import 'features/playlists/data/favorites_repository.dart';
import 'features/playlists/data/remote_source_repository.dart';
import 'features/recordings/data/recording_repository.dart';
import 'features/security/data/parental_controls.dart';
import 'features/subscription/data/subscription_state.dart';
import 'features/theme/data/remote_theme_repository.dart';
import 'features/tv/presentation/tv_app.dart';

// =========================================================
//  Point d'entrée TV — le filet d'erreurs global (« l'app ne se ferme
//  JAMAIS toute seule ») est désormais MUTUALISÉ avec le mobile dans
//  core/app/guarded_main.dart (`runGuarded`). Avant, ce filet était
//  dupliqué ici ; on le partage maintenant pour garantir un comportement
//  IDENTIQUE sur tous les flavors (mobile, Privé, TV).
// =========================================================
void main() => runGuarded(_bootstrap);

Future<void> _bootstrap() async {
  // Flavor explicite (un seul produit pour l'instant : The Few).
  FlavorConfig.setCurrent(FlavorConfig.sevenMotion);

  // DISJONCTEUR anti-boucle de redémarrage : si la TV s'est relancée
  // plusieurs fois de suite (crash natif type mémoire en ré-important une
  // grosse source), on passe en MODE SANS ÉCHEC et on saute le ré-import
  // distant plus bas → la boucle est cassée. Voir core/app/boot_guard.dart.
  await BootGuard.instance.beginBoot();

  // Cette app est la version TÉLÉVISION → le heartbeat enverra
  // platform='tv' et le panel l'affichera comme 📺 (vs 📱 mobile).
  AppPlatform.isTv = true;

  // ANTI-OOM TV (confirmé par logcat: lowmemorykiller / signal 9) : on N'INITIE
  // PLUS le moteur mpv (media_kit) sur la TV. La TV joue EXCLUSIVEMENT via
  // ExoPlayer (packages/native_video_player) — cf. tv_player_screen.dart. mpv
  // n'y était JAMAIS utilisé : l'initialiser ne faisait que charger libmpv +
  // ses codecs en mémoire pour rien, aggravant la pression mémoire au démarrage
  // sur des box à RAM limitée (SHIELD incluse). Aucune fonctionnalité TV perdue.

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

  // 4) Chaînes : on charge la base locale AVANT le 1er rendu, puis on
  //    synchronise la source poussée par le panel EN ARRIÈRE-PLAN.
  //
  //    POURQUOI bloquant ici : au redémarrage, les chaînes sont DÉJÀ en cache
  //    (SQLite). Si on attend leur chargement avant `runApp`, l'app ouvre
  //    DIRECTEMENT sur les chaînes — fini l'écran « Recherche de tes chaînes… »
  //    qui s'affichait à chaque démarrage le temps que le cache se charge.
  //    Timeout de sécurité : si la base est lente, on n'empêche JAMAIS l'app
  //    de démarrer (au pire, le cache arrivera via le stream juste après).
  await PlaylistRepository.instance
      .initialize()
      .timeout(const Duration(seconds: 6), onTimeout: () {});
  //    La source distante se (re)synchronise après, sans bloquer : si on a
  //    déjà des chaînes en cache, ça reste SILENCIEUX (pas d'écran « Recherche »).
  //    MODE SANS ÉCHEC : on SAUTE ce ré-import — c'est l'étape la plus
  //    gourmande (fetch + parse de toute la source) et le suspect n°1 d'un
  //    crash mémoire en boucle. L'app ouvre sur le cache existant.
  if (!BootGuard.instance.safeMode) {
    unawaited(RemoteSourceRepository.sync());
  } else {
    debugPrint('[main_tv] mode sans échec → ré-import de la source distante sauté.');
  }

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

  // 7) Notifications (alarmes « ton équipe joue bientôt ») : init du plugin +
  //    fuseaux horaires + canal Android. Idempotent, best-effort.
  unawaited(NotificationService.instance.init());

  // 8) Contrôle parental : on charge l'état du Mode Enfants pour que le 1er
  //    rendu du Direct masque déjà l'Adulte si le parent l'a activé.
  unawaited(ParentalControls.instance.load());

  // 9) Historique multi-box : on initialise l'historique local PUIS on le
  //    restaure depuis le serveur si la box est neuve (l'historique « suit »
  //    le client d'une box à l'autre). Best-effort, n'écrase jamais le local.
  unawaited(
    RecentlyWatchedRepository.instance.initialize().then((_) {
      if (!BootGuard.instance.safeMode) RemoteSourceRepository.syncHistory();
    }),
  );

  runApp(const TvApp());

  // L'app est lancée : si elle tient quelques secondes, on efface l'historique
  // de boucle (un démarrage réussi « pardonne » les crashs précédents).
  BootGuard.instance.scheduleStableReset();
}
