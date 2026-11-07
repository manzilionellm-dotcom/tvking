import 'features/cast/data/cast_platform.dart';

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
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_video_player/native_video_player.dart';

import 'core/app/app_platform.dart';
import 'core/app/box_memory_budget.dart';
import 'core/blackbox/black_box.dart';
import 'core/blackbox/black_box_upload.dart';
import 'features/player/data/audio_diag_prefs.dart';
import 'features/player/data/image_prefs.dart';
import 'features/player/data/audio_report_store.dart';
import 'features/player/domain/audio_report_book.dart';
import 'core/update/update_service.dart';
import 'core/app/boot_guard.dart';
import 'core/app/startup_trace.dart';
import 'core/app/guarded_main.dart';
import 'core/app/repair_flags.dart';
import 'core/theme/bundled_fonts.dart';
import 'core/flavor/flavor.dart';
import 'core/i18n/locale_repository.dart';
import 'features/tv/core/tv_back_guard.dart';
import 'features/tv/core/tv_ambient_director.dart';
import 'features/tv/core/tv_comfort_schedule.dart';
import 'features/tv/core/tv_glass.dart';
import 'features/tv/core/tv_look.dart';
import 'core/notifications/notification_service.dart';
import 'features/channels/data/recently_watched_repository.dart';
import 'features/device/data/device_identity.dart';
import 'features/playlists/data/playlist_repository.dart';
import 'features/playlists/data/favorites_repository.dart';
import 'features/playlists/data/remote_source_repository.dart';
import 'features/recordings/data/recording_repository.dart';
import 'features/profiles/data/profile_repository.dart';
import 'features/security/data/parental_controls.dart';
import 'features/subscription/data/now_playing.dart';
import 'features/subscription/data/remote_activation_watch.dart';
import 'features/subscription/data/subscription_state.dart';
import 'features/theme/data/remote_theme_repository.dart';
import 'features/tv/core/tv_activity.dart';
import 'features/tv/core/tv_content_refresh.dart';
import 'features/tv/presentation/tv_app.dart';

// =========================================================
//  Point d'entrée TV — le filet d'erreurs global (« l'app ne se ferme
//  JAMAIS toute seule ») est désormais MUTUALISÉ avec le mobile dans
//  core/app/guarded_main.dart (`runGuarded`). Avant, ce filet était
//  dupliqué ici ; on le partage maintenant pour garantir un comportement
//  IDENTIQUE sur tous les flavors (mobile, Privé, TV).
// =========================================================
/// Canal de mise à jour, posé par le CI : vide pour les clients,
/// « test » pour la box de test (voir build-zuno-tv.yml).
const String kZunoUpdateChannel = String.fromEnvironment('ZUNO_UPDATE_CHANNEL');

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
Future<void> bootstrapZunoTv({Widget Function(Widget app)? wrap}) async {
  // Inter, JetBrains Mono et les styles partagés sont embarqués.
  // Les titres TV utilisent Inter, pas Oswald (chasse trop étroite à 3 m).
  // Posé avant toute UI : les polices de la première ouverture ne dépendent
  // plus du réseau, même si aucun cache n'existe encore sur l'appareil.
  configureTvFontLoading();

  // RETOUR « UN À UN » : un appui Retour ne recule que d'UN écran (voir
  // tv_back_guard.dart). Inscrit avant runApp → consulté avant le Navigator.
  TvBackGuard.install();

  // Flavor explicite (un seul produit pour l'instant : The Few).
  FlavorConfig.setCurrent(FlavorConfig.sevenMotion);

  // La base des chaînes (SQLite) ne dépend pas du disjoncteur.
  // On l'ouvre pendant le premier accès disque (préférences du
  // boot) : sur l'émulateur API 29 ce premier accès prenait ~860 ms
  // et la base ~190 ms, l'une après l'autre. Le profil, lui, passe
  // par les mêmes préférences : on ne le lance pas en même temps,
  // sinon son plafond de 500 ms partirait pendant que le boot
  // occupe encore le canal.
  PlaylistRepository.mergeAllPlaylists = true;
  StartupTrace.mark('playlists.begin');
  final Future<void> playlistsReady = PlaylistRepository.instance
      .initialize()
      .timeout(const Duration(seconds: 6), onTimeout: () {});

  // DISJONCTEUR anti-boucle de redémarrage : si la TV s'est relancée
  // plusieurs fois de suite (crash natif type mémoire en ré-important une
  // grosse source), on passe en MODE SANS ÉCHEC et on saute le ré-import
  // distant plus bas → la boucle est cassée. Voir core/app/boot_guard.dart.
  await StartupTrace.step('bootGuard', BootGuard.instance.beginBoot);

  // RAM de la box AVANT le premier écran : le focus, les logos et le
  // fond lisent ce palier. 300 ms maximum — un binder lent ne retient
  // pas le démarrage (on reste alors au palier prudent). Le PC n'a pas
  // le plugin : palier large, comme l'index Cinéma.
  if (Platform.isAndroid) {
    await StartupTrace.step(
      'memoryBudget',
      () => BoxMemoryBudget.load().timeout(
        const Duration(milliseconds: 300),
        onTimeout: () {},
      ),
    );
  } else {
    BoxMemoryBudget.useDesktop();
    StartupTrace.mark('memoryBudget.desktop');
  }

  // Le paquet ZUNO est également distribué sur téléphone. On distingue
  // le matériel AVANT les services et le diagnostic, sans changer la MAC,
  // la licence ni le namespace historique « tv » de ZUNO dans le panel.
  await StartupTrace.step('castPlatform', CastPlatform.initializeZuno);
  AppPlatform.configureZuno(isAndroidHandset: CastPlatform.isAndroidHandset);

  // MISE À JOUR IN-APP : la TV ne regarde QUE sa propre release (zuno-tv),
  // publiée par build-zuno-tv.yml (version.json + zuno-tv.apk). Même clé de
  // signature à chaque build → l'installateur met à jour PAR-DESSUS, sans
  // désinstaller (favoris, listes, licence conservés).
  UpdateService.manifestUrl =
      'https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-tv/version.json';
  UpdateService.apkPrefix = 'zuno-tv';
  // Box de TEST seulement (build test_box, --dart-define=ZUNO_UPDATE_CHANNEL=test) :
  // le bouton voit aussi la release de test, et prend la plus récente des
  // deux. Un APK client n'a jamais ce réglage : il ne lit que zuno-tv.
  if (kZunoUpdateChannel == 'test') {
    UpdateService.extraManifestUrls = const <String>[
      'https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-tv-test/version.json',
    ];
  }

  // BOÎTE NOIRE (enregistreur de vol) : le plus tôt possible, pour que tout le
  // démarrage soit journalisé et que la raison de la DERNIÈRE fermeture soit
  // lue (Android 11+). Best-effort : ne bloque jamais le boot.
  await StartupTrace.step(
    'blackBox',
    () => BlackBox.instance.initialize(flavor: AppPlatform.zunoEditionName),
  );
  _wireAudioDiagnostic();
  // Le journal part vers le panel (même Worker, même MAC). L'envoi
  // est coupé par l'interrupteur « En plus ». Rien ici ne touche au son.
  BlackBoxUpload.instance.start();
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

  // Ces lectures ne dépendent pas l'une de l'autre (préférences,
  // langue, orientation). Les enchaîner ajoutait leur durée au
  // démarrage. Future.wait les fait ensemble : le premier écran
  // attend le plus lent, pas la somme.
  // https://docs.flutter.dev/perf/best-practices
  await Future.wait<void>(<Future<void>>[
    StartupTrace.step('audioPreferences', AudioDiagPrefs.load),
    StartupTrace.step('imagePreferences', ImagePrefs.load),
    StartupTrace.step('repairFlags', RepairFlags.load),
    // Langue : bloquant, mais en parallèle du reste. Le 1er rendu
    // est déjà dans la bonne langue (pas de flash en français).
    StartupTrace.step('locale', LocaleRepository.instance.initialize),
    // La TV est TOUJOURS en paysage (sur PC la fenêtre est libre).
    if (Platform.isAndroid)
      SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    playlistsReady,
  ]);
  StartupTrace.mark('playlists.end');
  // Palette confort : préférence locale (soir par défaut). Lecture
  // disque seulement, avant le premier cadre, pour éviter un flash.
  await StartupTrace.step('comfort', TvComfortSchedule.instance.load);
  await StartupTrace.step('ambient', TvAmbientDirector.instance.load);
  // Flou du verre : seulement si la box a de la RAM. Sinon le voile
  // translucide suffit (pas de BackdropFilter).
  await StartupTrace.step('glass', TvGlassPolicy.load);
  await StartupTrace.step('look', TvLook.instance.load);
  // Profil : après le boot, le canal des préférences est libre.
  // Plafond 500 ms, comme avant. Défaut synchrone = profil 1.
  StartupTrace.mark('profile.begin');
  await ProfileRepository.instance.load().timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
  StartupTrace.mark('profile.end');
  // Langue des pistes audio (direct, aperçu, film). On la relit si
  // la personne change la langue dans Réglages : le prochain zap
  // prend la nouvelle, sans rouvrir la chaîne en cours.
  _syncPlayerLanguage();
  LocaleRepository.instance.addListener(_syncPlayerLanguage);

  // --- Briques PARTAGÉES avec le mobile (non bloquant) ---
  // 1) Identité stable (MAC) → le panel reconnaît l'appareil TV.
  unawaited(DeviceIdentity.instance.preload());
  // 2) Licence/abonnement : heartbeat + statut depuis le MÊME worker.
  unawaited(
    SubscriptionState.instance.initialize().then((_) {
      SubscriptionState.instance.syncWithBackend();
    }),
  );
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
  //    Le chargement local a démarré avec le disjoncteur (plus haut)
  //    et il est déjà terminé ici.
  //    La source distante se (re)synchronise après, sans bloquer : si on a
  //    déjà des chaînes en cache, ça reste SILENCIEUX (pas d'écran « Recherche »).
  //    MODE SANS ÉCHEC : on SAUTE ce ré-import — c'est l'étape la plus
  //    gourmande (fetch + parse de toute la source) et le suspect n°1 d'un
  //    crash mémoire en boucle. L'app ouvre sur le cache existant.
  // Veille unique : lecture légère du statut (1 s en attente, 2 s
  // ensuite ; 25 s si la prise est ouverte). Les codes IPTV ne partent
  // que si le panel a changé
  // la source. En mode sans échec on lit quand même la licence,
  // mais on ne retélécharge pas une grosse liste.
  RemoteActivationWatch.instance.start(
    allowSourceImport: !BootGuard.instance.safeMode,
  );
  if (!BootGuard.instance.safeMode) {
    unawaited(RemoteSourceRepository.sync());

    // MISE À JOUR AUTOMATIQUE (demande du propriétaire 27/09/2026) :
    //   • 2 minutes après l'ouverture : la box va chercher TOUT ce qui est
    //     nouveau (source posée dans le panel + nouvelles chaînes chez le
    //     fournisseur), sans que le client ne fasse rien ;
    //   • puis toutes les 6 heures tant que la box reste allumée ;
    //   • entre les deux, la veille (quelques secondes) voit une
    //     activation ou une liste retirée dans le panel ;
    //   • 3 minutes après l'ouverture : si une nouvelle version de Zuno
    //     existe, l'APK est pré-téléchargé en silence → dans Réglages, « Mise
    //     à jour » ouvre l'installateur immédiatement.
    // RÈGLE ABSOLUE conservée : jamais de re-téléchargement pendant que le
    // client est dans Direct ou dans le lecteur (TvActivity.isBusy) — on
    // attend son retour à l'accueil. Pourquoi pas toutes les 2 minutes pour
    // les chaînes : re-télécharger 10 000+ chaînes en boucle saturerait la
    // box et ferait bloquer le compte par le fournisseur IPTV.
    unawaited(
      Future<void>.delayed(const Duration(minutes: 2), () {
        TvContentRefresh.run(waitIdle: true);
      }),
    );
    Timer.periodic(const Duration(hours: 6), (_) {
      TvContentRefresh.run(waitIdle: true);
    });
    // MISE À JOUR DE L'APP SANS BOUTON (demande du propriétaire, 05/10/2026) :
    //   • 1 minute après l'ouverture, puis toutes les 30 minutes, et dès
    //     qu'un ordre « force_update » arrive du panel : la box vérifie,
    //     télécharge et contrôle l'APK en silence, puis ouvre elle-même
    //     l'installateur Android quand elle est à l'accueil (une fois par
    //     version). Il reste la confirmation « Installer » d'Android, que
    //     toute app hors Play Store doit obtenir. Repli :
    //     zuno.update.auto_install_off (l'APK attend Réglages → Mise à jour).
    unawaited(
      Future<void>.delayed(const Duration(minutes: 1), () {
        UpdateService.instance.autoUpdate(busy: () => TvActivity.isBusy);
      }),
    );
    // Box de TEST (release zuno-tv-test dans extraManifestUrls) : vérification
    // toutes les 60 s, pour qu'un build arrive dans la minute (mesuré le
    // 06/10/2026 : « 3 à 5 minutes avant que la mise à jour arrive »). Les
    // clients gardent 30 min + l'ordre « force_update » du panel, qui est
    // immédiat. Repli : zuno.update.test_poll_legacy.
    final bool testBox = UpdateService.extraManifestUrls.isNotEmpty &&
        !RepairFlags.testUpdatePollLegacy;
    Timer.periodic(
      testBox ? const Duration(minutes: 1) : const Duration(minutes: 30),
      (_) {
        UpdateService.instance.autoUpdate(busy: () => TvActivity.isBusy);
      },
    );
  } else {
    debugPrint(
      '[main_tv] mode sans échec → ré-import de la source distante sauté.',
    );
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

  // 6) Profils : déjà chargés avec les chaînes (voir plus haut).
  //    Le défaut synchrone reste le profil 1 si le disque a dépassé
  //    500 ms. Le choix à l'écran, s'il est activé, arrive APRÈS
  //    l'accueil (voir TvHubScreen).
  // 7) Favoris du profil en cours : préchargés pour que le cœur ❤
  //    du lecteur affiche le bon état dès la 1re ouverture.
  unawaited(FavoritesRepository.instance.initialize());

  // 8) Notifications (alarmes « ton équipe joue bientôt ») : init du plugin +
  //    fuseaux horaires + canal Android. Idempotent, best-effort.
  if (Platform.isAndroid) unawaited(NotificationService.instance.init());

  // 9) Contrôle parental du profil en cours : le 1er rendu du Direct
  //    masque déjà l'Adulte si ce profil l'a activé (forcé sur Enfants).
  unawaited(ParentalControls.instance.load());

  // 10) Historique du profil en cours, puis restauration serveur si ce
  //     tiroir est vide (la box neuve). N'écrase jamais un historique là.
  unawaited(
    RecentlyWatchedRepository.instance.initialize().then((_) {
      if (!BootGuard.instance.safeMode) RemoteSourceRepository.syncHistory();
    }),
  );

  StartupTrace.mark('runApp');
  WidgetsBinding.instance.addPostFrameCallback((_) {
    StartupTrace.mark('frame.submitted');
  });
  unawaited(
    WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) {
      StartupTrace.mark('frame.rasterized');
      StartupTrace.watchFrames();
      // Une boucle Dart vivante sur le splash n'est pas un démarrage réussi.
      // Le délai de stabilité commence seulement après la première image réelle.
      BootGuard.instance.scheduleStableReset();
    }),
  );
  runApp(wrap == null ? const TvApp() : wrap(const TvApp()));
}
