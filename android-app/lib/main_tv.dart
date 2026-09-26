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
import 'core/blackbox/black_box.dart';
import 'core/update/update_service.dart';
import 'core/app/boot_guard.dart';
import 'core/app/guarded_main.dart';
import 'core/flavor/flavor.dart';
import 'core/i18n/locale_repository.dart';
import 'features/tv/core/tv_back_guard.dart';
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
import 'features/tv/core/tv_activity.dart';
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
  // RETOUR « UN À UN » : un appui Retour ne recule que d'UN écran (voir
  // tv_back_guard.dart). Inscrit avant runApp → consulté avant le Navigator.
  TvBackGuard.install();

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

  // MISE À JOUR IN-APP : la TV ne regarde QUE sa propre release (zuno-tv),
  // publiée par build-zuno-tv.yml (version.json + zuno-tv.apk). Même clé de
  // signature à chaque build → l'installateur met à jour PAR-DESSUS, sans
  // désinstaller (favoris, listes, licence conservés).
  UpdateService.manifestUrl =
      'https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-tv/version.json';
  UpdateService.apkPrefix = 'zuno-tv';

  // BOÎTE NOIRE (enregistreur de vol) : le plus tôt possible, pour que tout le
  // démarrage soit journalisé et que la raison de la DERNIÈRE fermeture soit
  // lue (Android 11+). Best-effort : ne bloque jamais le boot.
  await BlackBox.instance.initialize(flavor: 'Zuno TV');
  if (BootGuard.instance.safeMode) {
    BlackBox.instance.warn('BOOT', 'MODE SANS ÉCHEC : boucle de redémarrage détectée → ré-imports sautés');
  }

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
  //    TV = TOUTES les listes fusionnées (Xtream + M3U, jusqu'à 4-5 sources
  //    posées par le client ou le panel) affichées ensemble, façon TiviMate.
  PlaylistRepository.mergeAllPlaylists = true;
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

    // SYNCHRONISATION DES LISTES (façon TiviMate, demande du propriétaire
    // 25/09/2026). La TV n'actualisait jamais une M3U/Xtream après l'import.
    //   • 90 s après le démarrage : re-télécharge les listes dont la dernière
    //     synchro date de plus de 24 h ;
    //   • puis toutes les 24 h tant que la box reste allumée.
    // RÈGLE ABSOLUE : jamais pendant que le client est dans Direct ou dans le
    // lecteur (TvActivity.isBusy) — re-télécharger et re-parser 30 000 chaînes
    // pendant qu'il zappe figeait l'écran puis Android tuait l'app. On attend
    // le retour à l'accueil (re-vérification toutes les 60 s, 30 essais max,
    // sinon on réessaie au prochain tick de 24 h).
    unawaited(Future<void>.delayed(const Duration(seconds: 90), () {
      _tvAutoRefresh(onlyStale: true);
    }));
    Timer.periodic(const Duration(hours: 24), (_) {
      RemoteSourceRepository.sync();
      _tvAutoRefresh(onlyStale: false);
    });
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

/// Actualisation des listes quand la box est AU REPOS (cf. TvActivity).
/// Best-effort, silencieuse, une seule passe à la fois (mutex du repo).
Future<void> _tvAutoRefresh({required bool onlyStale}) async {
  if (BootGuard.instance.safeMode) return;
  for (int i = 0; i < 30 && TvActivity.isBusy; i++) {
    await Future<void>.delayed(const Duration(seconds: 60));
  }
  if (TvActivity.isBusy) return; // toujours occupé → prochain tick
  try {
    if (onlyStale) {
      await PlaylistRepository.instance
          .refreshStale(staleness: const Duration(hours: 24));
    } else {
      await PlaylistRepository.instance.refreshAll();
    }
  } catch (_) {
    // silencieux : la synchro est un confort, jamais une cause de panne
  }
}
