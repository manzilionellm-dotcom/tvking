// =========================================================
//  main_tv.dart — Point d'entrée DeFew TV (Android TV / Fire TV)
// =========================================================
//  Socle visuel conservé pour NOVATUBE. Les services commerciaux distants
//  sont exclus par une politique immuable propre à cette branche.
//
//  Build : `flutter build apk --release --target=lib/main_tv.dart`
//  (un workflow CI dédié + manifest Leanback viendront ensuite).
// =========================================================
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_video_player/native_video_player.dart';

import 'core/app/novatube_play_policy.dart';
import 'core/app/app_platform.dart';
import 'core/app/zuno_edition.dart';
import 'core/blackbox/black_box.dart';
import 'features/player/data/audio_diag_prefs.dart';
import 'features/player/data/audio_report_store.dart';
import 'features/player/domain/audio_report_book.dart';
import 'core/update/update_service.dart';
import 'core/app/boot_guard.dart';
import 'core/app/guarded_main.dart';
import 'core/app/repair_flags.dart';
import 'core/flavor/flavor.dart';
import 'core/i18n/locale_repository.dart';
import 'features/tv/core/tv_back_guard.dart';
import 'core/notifications/notification_service.dart';
import 'features/channels/data/recently_watched_repository.dart';
import 'features/cast/data/cast_platform.dart';
import 'features/playlists/data/playlist_repository.dart';
import 'features/playlists/data/favorites_repository.dart';
import 'features/recordings/data/recording_repository.dart';
import 'features/profiles/data/profile_repository.dart';
import 'features/security/data/parental_controls.dart';
import 'features/subscription/data/now_playing.dart';
import 'features/subscription/data/subscription_state.dart';
import 'features/tv/core/tv_content_refresh.dart';
import 'features/tv/presentation/tv_app.dart';

// =========================================================
//  Point d'entrée TV — le filet d'erreurs global (« l'app ne se ferme
//  JAMAIS toute seule ») est désormais MUTUALISÉ avec le mobile dans
//  core/app/guarded_main.dart (`runGuarded`). Avant, ce filet était
//  dupliqué ici ; on le partage maintenant pour garantir un comportement
//  IDENTIQUE sur tous les flavors (mobile, Privé, TV).
// =========================================================
void main() => runGuarded(bootstrapZunoTv);

/// « fr » / « en » / … pour le choix de piste. Suit le réglage de l'app,
/// ou la langue de la TV si le réglage est « Système ».
void _syncPlayerLanguage() {
  NativeVideoController.appAudioLanguage =
      LocaleRepository.instance.effectiveLocale.languageCode;
}

/// Diagnostic du son → boîte noire (Réglages → Boîte noire). Une ligne par
/// constat, étiquette « SON », avec la chaîne en cours quand on la connaît.
void _wireAudioDiagnostic() {
  NativeVideoController.onAudioDiagnostic = (String diagnostic) {
    // « Son témoin » : le nom vient de l'écran Diagnostic, pas du
    // heartbeat (NowPlaying reste la chaîne, ou vide).
    final String channel =
        AudioReportStore.channelOverride ?? NowPlaying.instance.current;
    final String safe = redactAudioText(diagnostic);
    bool first = true;
    for (final String raw in safe.split('\n')) {
      final String line = raw.trim();
      if (line.isEmpty) continue;
      BlackBox.instance.info(
        'SON',
        first && channel.isNotEmpty ? '[$channel] $line' : line,
      );
      first = false;
    }
    unawaited(AudioReportStore.instance.record(channel: channel, body: safe));
  };
}

/// Démarrage de Zuno. Partagé avec la version PC (lib/main_windows.dart),
/// qui prépare d'abord SQLite / lecteur / fenêtre puis appelle cette même
/// fonction : MÊME app, même design, mêmes services. [wrap] permet au PC
/// d'ajouter ses raccourcis clavier (Échap = Retour, F11 = plein écran)
/// autour de l'app, sans rien changer sur la box.
Future<void> bootstrapZunoTv({
  ZunoEdition edition = ZunoEdition.television,
  Widget Function(Widget app)? wrap,
}) async {
  // La TV n'instancie aucun service Cast. Les entrées tactile et ordinateur
  // s'identifient ici explicitement, même sur un très grand écran.
  CastPlatform.configureZuno(edition);
  // L'entrée tactile n'a pas encore de canal client propre : même un
  // lancement local sans drapeau de test ne doit pas proposer l'APK TV.
  UpdateService.enabled = NovatubePlayPolicy.allowSelfUpdate;

  // RETOUR « UN À UN » : un appui Retour ne recule que d'UN écran (voir
  // tv_back_guard.dart). Inscrit avant runApp → consulté avant le Navigator.
  TvBackGuard.install();

  // Identité explicite de la nouvelle application, sans modifier les autres produits.
  FlavorConfig.setCurrent(FlavorConfig.novatube);

  // DISJONCTEUR anti-boucle de redémarrage : si la TV s'est relancée
  // plusieurs fois de suite (crash natif type mémoire en ré-important une
  // grosse source), on passe en MODE SANS ÉCHEC et on saute le ré-import
  // distant plus bas → la boucle est cassée. Voir core/app/boot_guard.dart.
  await BootGuard.instance.beginBoot();

  // Identité historique ZUNO pour le panel, partagée avec Windows. Elle
  // ne décide pas des capacités de l'app : celles-ci dépendent d'edition.
  AppPlatform.isTv = true;

  // NOVATUBE n'utilise aucun canal APK des applications historiques.
  // Google Play gère ses mises à jour, avec son propre package/signataire.
  UpdateService.manifestUrl = '';
  UpdateService.apkPrefix = '';
  UpdateService.extraManifestUrls = const <String>[];

  // BOÎTE NOIRE (enregistreur de vol) : le plus tôt possible, pour que tout le
  // démarrage soit journalisé et que la raison de la DERNIÈRE fermeture soit
  // lue (Android 11+). Best-effort : ne bloque jamais le boot.
  await BlackBox.instance.initialize(flavor: 'NOVATUBE');
  _wireAudioDiagnostic();
  // Les diagnostics restent locaux ; aucune MAC ni journal envoyé au panel.
  // Réglages du diagnostic son. Défaut faux : ne change pas le lecteur.
  await AudioDiagPrefs.load();
  // Interrupteurs de repli des correctifs de l'audit (défaut faux).
  await RepairFlags.load();
  if (BootGuard.instance.safeMode) {
    BlackBox.instance.warn(
      'BOOT',
      'MODE SANS ÉCHEC : boucle de redémarrage détectée → ré-imports sautés',
    );
  }

  // ANTI-OOM TV (confirmé par logcat: lowmemorykiller / signal 9) : on N'INITIE
  // PLUS le moteur mpv (media_kit) sur la TV. La TV joue EXCLUSIVEMENT via
  // ExoPlayer (packages/native_video_player) — cf. tv_player_screen.dart. mpv
  // n'y était JAMAIS utilisé : l'initialiser ne faisait que charger libmpv +
  // ses codecs en mémoire pour rien, aggravant la pression mémoire au démarrage
  // sur des box à RAM limitée (SHIELD incluse). Aucune fonctionnalité TV perdue.

  // La TV est TOUJOURS en paysage : on verrouille (pas de portrait).
  // (Le téléphone / la tablette et la fenêtre PC restent libres.)
  if (Platform.isAndroid && edition == ZunoEdition.television) {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  // Langue de l'app : on charge le choix mémorisé (ou « Système » =>
  // l'app suit la langue de la TV). BLOQUANT et rapide : garantit que le
  // 1er rendu est déjà dans la bonne langue (pas de flash en français).
  await LocaleRepository.instance.initialize();
  // Langue des pistes audio (direct, aperçu, film). On la relit si
  // la personne change la langue dans Réglages : le prochain zap
  // prend la nouvelle, sans rouvrir la chaîne en cours.
  _syncPlayerLanguage();
  LocaleRepository.instance.addListener(_syncPlayerLanguage);

  // État local neutre : aucune activation, MAC, période d'essai ou licence
  // distante ne conditionne les sources saisies manuellement.
  await SubscriptionState.instance.initialize();

  // Le propriétaire des données est connu AVANT la première lecture SQLite.
  // Un démarrage sur un autre profil n'affiche jamais les sources du Profil 1.
  PlaylistRepository.mergeAllPlaylists = true;
  await ProfileRepository.instance.load();

  // 4) Chaînes : on charge les sources manuelles AVANT le 1er rendu.
  //
  //    POURQUOI bloquant ici : au redémarrage, les chaînes sont DÉJÀ en cache
  //    (SQLite). Si on attend leur chargement avant `runApp`, l'app ouvre
  //    DIRECTEMENT sur les chaînes — fini l'écran « Recherche de tes chaînes… »
  //    qui s'affichait à chaque démarrage le temps que le cache se charge.
  //    Timeout de sécurité : si la base est lente, on n'empêche JAMAIS l'app
  //    de démarrer (au pire, le cache arrivera via le stream juste après).
  //    Jusqu'à dix sources personnelles DU PROFIL ACTIF sont fusionnées.
  await PlaylistRepository.instance.initialize().timeout(
    const Duration(seconds: 6),
    onTimeout: () {},
  );
  // Actualise uniquement les listes déjà ajoutées manuellement. La routine
  // de rafraîchissement conserve le garde-fou « pas pendant une lecture ».
  if (!BootGuard.instance.safeMode) {
    unawaited(
      Future<void>.delayed(const Duration(minutes: 2), () {
        TvContentRefresh.run(waitIdle: true);
      }),
    );
    Timer.periodic(const Duration(hours: 6), (_) {
      TvContentRefresh.run(waitIdle: true);
    });
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

  // 7) Favoris du profil en cours : préchargés pour que le cœur ❤
  //    du lecteur affiche le bon état dès la 1re ouverture.
  unawaited(FavoritesRepository.instance.initialize());

  // 8) Notifications (alarmes « ton équipe joue bientôt ») : init du plugin +
  //    fuseaux horaires + canal Android. Idempotent, best-effort.
  unawaited(NotificationService.instance.init());

  // 9) Contrôle parental du profil en cours : le 1er rendu du Direct
  //    masque déjà l'Adulte si ce profil l'a activé (forcé sur Enfants).
  unawaited(ParentalControls.instance.load());

  // 10) Historique local par profil, sans restauration par MAC.
  unawaited(RecentlyWatchedRepository.instance.initialize());

  runApp(wrap == null ? const TvApp() : wrap(const TvApp()));

  // L'app est lancée : si elle tient quelques secondes, on efface l'historique
  // de boucle (un démarrage réussi « pardonne » les crashs précédents).
  BootGuard.instance.scheduleStableReset();
}
