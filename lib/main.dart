// =========================================================
//  main.dart — Point d'entrée unique de l'application
// =========================================================
//  1. Initialise les bindings Flutter
//  2. Initialise libmpv (media_kit)
//  3. Configure la statut/nav bar transparente
//  4. Démarre les repositories en parallèle
//  5. Décide si on affiche l'onboarding ou directement Home
// =========================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';

import 'core/app/boot_guard.dart';
import 'core/app/guarded_main.dart';
import 'core/backend/backend_hosts.dart';
import 'core/privacy/privacy_shield.dart';
import 'core/profiles/profiles_repository.dart';
import 'core/profiles/remote_profiles_repository.dart';
import 'core/realtime/admin_message_banner.dart';
import 'core/realtime/realtime_sync_service.dart';
import 'core/crash/crash_reporting.dart';
import 'core/branding/brand_config.dart';
import 'core/branding/brand_logo.dart';
import 'core/branding/powered_by_marquee.dart';
import 'features/ads/data/startup_ad_repository.dart';
import 'features/ads/presentation/startup_ad_screen.dart';
import 'features/feedback/data/feedback_repository.dart';
import 'features/theme/data/remote_theme_repository.dart';
import 'core/notifications/notification_service.dart';
import 'core/update/update_prompt.dart';
import 'core/branding/verified_badge.dart';
import 'core/theme/app_text_styles.dart' show AppTextStyles;
import 'core/i18n/locale_repository.dart';
import 'core/i18n/l10n_extension.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/accent_controller.dart';
import 'core/theme/theme_mode_repository.dart';
import 'features/about/data/force_update_checker.dart';
import 'features/about/presentation/forced_update_screen.dart';
import 'l10n/generated/app_localizations.dart';
import 'features/about/data/update_checker.dart';
import 'features/cast/data/cast_manager.dart';
import 'features/channels/data/recent_searches_repository.dart';
import 'features/channels/data/recently_watched_repository.dart';
import 'features/channels/data/watch_history_repository.dart';
import 'features/stats/data/engagement_service.dart';
import 'features/stats/data/watch_stats_service.dart';
import 'features/vod/data/playback_position_repository.dart';
import 'features/vod/data/vod_download_service.dart';
import 'features/simple_home/presentation/simple_home_screen.dart';
import 'features/admin/data/admin_credentials.dart';
import 'features/device/data/device_identity.dart';
import 'features/epg/data/epg_repository.dart';
import 'features/onboarding/data/device_class_repository.dart';
import 'features/onboarding/data/onboarding_state.dart';
// Phase 1+/2026-06-01 : DevicePicker + Onboarding supprimes du
// flow. Imports retires (les fichiers existent toujours dans
// features/onboarding/presentation/ pour eventuelle reprise).
import 'features/player/data/player_settings.dart';
import 'features/playlists/data/favorites_repository.dart';
import 'features/playlists/data/cloud_backup_repository.dart';
import 'features/playlists/data/playlist_repository.dart';
import 'features/playlists/data/remote_source_repository.dart';
import 'features/playlists/data/source_content_watch.dart';
import 'features/pricing/data/pricing_repository.dart';
import 'core/flavor/flavor.dart';
import 'features/security/data/age_gate_settings.dart';
import 'features/security/data/parental_controls.dart';
import 'features/security/data/biometric_auth.dart';
import 'features/security/data/lock_settings.dart';
import 'features/security/presentation/age_gate_screen.dart';
import 'features/security/presentation/lock_screen.dart';
import 'features/recordings/data/recording_repository.dart';
import 'features/recordings/data/recording_scheduler.dart';
import 'features/recordings/data/ffmpeg_converter.dart';
import 'core/app/master_console.dart';
import 'features/sports/data/live_scores_service.dart';
import 'features/sports/data/match_alerts_service.dart';
import 'features/sports/data/sports_repository.dart';
import 'features/subscription/data/subscription_state.dart';
import 'features/subscription/presentation/guest_screen.dart';
import 'features/subscription/presentation/subscription_gate.dart';

void main() {
  // Tout le démarrage tourne sous le filet d'erreurs global PARTAGÉ
  // (cf. core/app/guarded_main.dart) : aucune exception, même AVANT le
  // 1er frame, ne peut fermer l'app — elle est loggée puis l'app continue.
  runGuarded(() async {
    // Identité du build The Few (application mobile, seul produit du
    // projet depuis le retrait des variantes TV et Red Room). Doit être
    // posée AVANT `bootApp()` (qui touche aux repos lisant `FlavorConfig`).
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    await bootApp();
  });
}

/// Séquence d'initialisation de l'application. Le flavor doit déjà avoir
/// été posé par `main()` — on lit `FlavorConfig.current` librement à
/// partir d'ici.
Future<void> bootApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enregistrements → MP4 galerie : on branche le convertisseur FFmpeg (fiable
  // sur nos flux TS/HLS). C'est fait ICI, dans l'entrée MOBILE uniquement : le
  // build TV ne pose jamais ce hook et ne référence donc jamais ffmpeg_kit
  // (retiré de son pubspec). La conversion garde la vidéo intacte (copie).
  recordingTsToMp4Hook = FfmpegConverter.tsToMp4;

  // libmpv natif — AVANT runApp pour ne pas crasher au premier lecteur.
  // GARDÉ : sur un appareil exotique où la lib native manque/échoue
  // (UnsatisfiedLinkError…), l'app NE DOIT PAS mourir au boot. On capte,
  // on signale, et on continue : le lecteur échouera proprement plus tard
  // (chaque écran lecteur a déjà ses propres try/catch).
  try {
    MediaKit.ensureInitialized();
  } catch (e, s) {
    CrashReporting.instance
        .recordError(e, s, context: 'MediaKit.ensureInitialized');
  }

  // DISJONCTEUR anti-boucle de redémarrage (cf. core/app/boot_guard.dart) :
  // si l'app s'est relancée plusieurs fois de suite (crash natif type
  // mémoire en ré-important une grosse source), on saute le ré-import
  // distant plus bas pour casser la boucle.
  await BootGuard.instance.beginBoot();

  // Rotation auto autorisée sur toutes les orientations supportées.
  // Sans ça, même quand l'utilisateur incline son téléphone en mode
  // paysage pour regarder un film, l'écran reste verrouillé en portrait
  // si l'auto-rotate Android est désactivé. Ici on FORCE l'app à
  // accepter les 3 orientations utiles (portraitUp + landscape gauche/droite).
  // portraitDown est exclu — personne ne regarde Netflix la tête en bas.
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Statut bar et nav bar transparentes pour que le fond couvre tout
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Démarre les repos en parallèle — non bloquant pour le first frame.
  // Les écrans qui en dépendent rebuildent via les Streams au fur et
  // à mesure que les données arrivent.
  unawaited(PlaylistRepository.instance.initialize().then((_) {
    // Modèle « tout géré par le revendeur » : on récupère la source
    // IPTV assignée à cet appareil par sa MAC (panel admin) et on la
    // charge automatiquement. Le client n'a rien à saisir. Puis on purge
    // toute source qui n'a pas marché (0 chaîne) pour ne rien laisser
    // traîner.
    // MODE SANS ÉCHEC : on saute ce ré-import (étape la plus gourmande,
    // suspect n°1 d'un crash mémoire en boucle) → l'app ouvre sur le cache.
    if (!BootGuard.instance.safeMode) {
      RemoteSourceRepository.sync().then((_) {
        PlaylistRepository.instance.pruneEmptyPlaylists();
      });
    }

    // Sauvegarde cloud par MAC : démarre l'upload automatique (à chaque
    // changement de playlists/favoris) et tente une restauration SI
    // l'utilisateur n'a aucune playlist locale (typiquement après une
    // réinstallation → il retrouve ses sources sans repayer ni resaisir).
    // Différée de 4 s pour laisser la source poussée par le panel
    // (RemoteSourceRepository) arriver en priorité.
    CloudBackupRepository.instance.start();
    Future<void>.delayed(const Duration(seconds: 4), () {
      unawaited(CloudBackupRepository.instance.restoreIfNeeded());
    });
  }));
  unawaited(FavoritesRepository.instance.initialize());
  unawaited(RecentlyWatchedRepository.instance.initialize());
  unawaited(RecentSearchesRepository.instance.initialize());
  unawaited(WatchHistoryRepository.instance.initialize());
  // PROFILS FAMILLE (même dispositif que le boot TV, main_tv.dart
  // « Profils famille ») : chargés AVANT les dépôts qui SUFFIXENT leurs
  // clés par profil (WatchStatsService, PlaybackPositionRepository…) pour
  // que leur PREMIER load lise déjà les clés du profil actif — sans ça,
  // ils liraient les données « Famille » puis les afficheraient au mauvais
  // profil jusqu'à la prochaine bascule. AWAIT assumé (une lecture
  // SharedPreferences, quasi instantanée) avec le même timeout de sécurité
  // que la TV : prefs lent ne retarde jamais le boot.
  await ProfilesRepository.instance
      .load()
      .timeout(const Duration(seconds: 2), onTimeout: () {});
  // Profils PILOTÉS PAR LE PANEL (mêmes règles que le boot TV) : le
  // propriétaire colle UNE source et le serveur génère les cinq profils
  // de la famille. Non bloquant : le `load()` ci-dessus a déjà servi la
  // liste en cache, la réponse serveur ne fait que la corriger.
  unawaited(RemoteProfilesRepository.instance.syncSelf());
  Timer.periodic(const Duration(minutes: 5), (_) {
    unawaited(RemoteProfilesRepository.instance.syncSelf());
  });
  // CONTRÔLE PARENTAL (Mode Enfants) : même appel que le boot TV (étape
  // « 8 » de main_tv.dart). Fire-and-forget, ne throw jamais — l'état est
  // lu par Réglages > Contrôle parental et par les écrans qui masquent
  // l'Adulte.
  unawaited(ParentalControls.instance.load());
  // Rétention (systèmes qui existaient mais n'étaient démarrés qu'en TV —
  // on les active AUSSI sur mobile) :
  //   • WatchStatsService : minutes/jour + top chaînes (dashboard « stats »)
  //   • EngagementService : streak quotidien + paliers célébrés à l'accueil
  //   • PlaybackPositionRepository : positions de reprise VOD (Continue
  //     Watching) — sans ce load, la reprise ne saurait pas où l'on en était.
  unawaited(WatchStatsService.instance.start());
  unawaited(EngagementService.instance.load());
  unawaited(PlaybackPositionRepository.instance.load());
  // TÉLÉCHARGEMENTS HORS-LIGNE : recharge la liste des films/épisodes déjà
  // téléchargés (même appel que le boot TV, main_tv.dart « 8z »). Sans ce
  // load, l'état des téléchargements n'existait sur mobile qu'après un
  // passage par l'écran Cinéma — le lecteur ne trouvait donc pas les
  // fichiers locaux (localFile) tant que Cinéma n'avait pas été ouvert.
  // Lecture SharedPreferences, non bloquant, ne throw jamais (try/catch
  // interne) — fire-and-forget comme les autres init.
  unawaited(VodDownloadService.instance.load());
  unawaited(EpgRepository.instance.initialize());
  unawaited(
    // Phase 1 / F-01 : juste apres l'init, on balaie les fiches
    // restees `ended_at IS NULL` parce que le process precedent a
    // ete tue par l'OS pendant l'enregistrement (NOT_STICKY).
    // recoverOrphans est idempotent — si rien a recuperer, no-op.
    // Le `.then((_) {})` final convertit Future<List<Recording>> en
    // Future<void> attendu par unawaited (strict-casts ON).
    RecordingRepository.instance
        .initialize()
        .then((_) => RecordingRepository.instance.recoverOrphans())
        // Enregistrements PROGRAMMÉS : après la récupération des orphelins
        // (pour ne pas finaliser à tort une capture natif en cours), le
        // planificateur réconcilie ce que le natif a capté pendant que
        // l'app dormait, puis tient son tick de 30 s.
        .then((_) => RecordingScheduler.instance.start()),
  );
  unawaited(PlayerSettings.instance.load());

  // Mode Bouclier (vie privée) : réglages + état VPN. Non bloquant ; sans
  // réglage mémorisé, le bouclier est éteint et n'a aucun effet.
  unawaited(PrivacyShield.instance.load());

  // Notifications locales (rappels EPG). Init non bloquant ; la permission
  // n'est demandée que lorsque l'utilisateur pose son 1er rappel.
  unawaited(NotificationService.instance.init());

  // MODE SPORT (demande du propriétaire, 06/09 : « prévenu en direct »).
  //  1) Équipes favorites chargées dès le boot — avant, seul l'écran
  //     Sport les lisait : un client qui n'ouvrait pas l'onglet n'avait
  //     ni alarme « joue bientôt » ni but de son équipe.
  //  2) La SENTINELLE des buts : veille app-wide qui ne fait une requête
  //     que pendant qu'un match qui compte se joue (cf. live_scores_service).
  //  3) Les alertes d'avant-match et de résultat, re-passées toutes les
  //     30 min tant que l'app vit (le service s'auto-limite à ce rythme) :
  //     avant, seule l'arrivée sur l'accueil les déclenchait, donc une app
  //     laissée ouverte sur un film ne reprogrammait jamais rien.
  unawaited(SportsRepository.instance.initialize());
  LiveScoresService.instance.startSentinel();
  Timer.periodic(const Duration(minutes: 30), (_) {
    unawaited(MatchAlertsService.instance.refresh());
  });

  // Identité unique de l'appareil (MAC virtuel "MK:XX:XX:XX:XX:XX").
  // Pré-chargée pour qu'elle soit dispo synchrone partout dès le
  // premier frame (About, Réglages, etc.).
  unawaited(DeviceIdentity.instance.preload());

  // FAILOVER backend (même blindage que la TV) : si le domaine maison
  // était KO au dernier lancement, on repart directement sur l'adresse
  // Cloudflare de secours mémorisée (retour auto au domaine maison au
  // 1er heartbeat réussi). Voir core/backend/backend_hosts.dart.
  await BackendHosts.loadPreferred();

  // Essai gratuit de 7 jours + abonnement 5 €/an. Au tout
  // premier boot, persiste firstLaunchAt = now pour démarrer le
  // compte à rebours local. PUIS sync avec le backend Cloudflare
  // qui est l'autorité finale (l'admin peut geler/débloquer un
  // client à distance depuis le panel /admin/panel).
  //
  // ROBUSTESSE (même recette que la TV) : si le réseau a un creux au
  // moment du boot, on RETENTE à 2/10/30 min tant que le serveur n'a
  // pas répondu — sans ça, une app restée ouverte gardait un statut
  // « inconnu » et laissait s'égrener la tolérance hors-ligne.
  unawaited(SubscriptionState.instance.initialize().then((_) async {
    await SubscriptionState.instance.syncWithBackend();
    for (final int minutes in <int>[2, 10, 30]) {
      if (SubscriptionState.instance.remote.exists) break;
      await Future<void>.delayed(Duration(minutes: minutes));
      if (SubscriptionState.instance.remote.exists) break;
      await SubscriptionState.instance.syncWithBackend();
    }
  }));
  // Re-synchro PÉRIODIQUE (6 h) tant que l'app tourne : fait glisser la
  // fenêtre de tolérance hors-ligne (kOfflineGraceDays) et propage les
  // actions du panel (activation, gel…) sans redémarrage. Heartbeat
  // léger — rien à voir avec le ré-import lourd des playlists (24 h).
  Timer.periodic(const Duration(hours: 6), (_) {
    SubscriptionState.instance.syncWithBackend();
  });

  // TEMPS RÉEL (WebSocket) : les actions du panel (activation, gel,
  // source poussée, message…) arrivent en < 1 s quand l'app est en
  // ligne, au lieu d'attendre les polls ci-dessus (qui RESTENT le filet
  // de sécurité). Fire-and-forget : le service ne throw jamais et se
  // reconnecte tout seul (backoff) — il ne retarde JAMAIS le démarrage.
  // Voir docs/REALTIME-PROTOCOL.md + core/realtime/.
  unawaited(RealtimeSyncService.instance.start(platform: 'mobile'));

  // NB : la "fixation à distance" (RemoteConfigRepository qui
  // fetchait des playlists depuis un Gist toutes les 30 min) a
  // été RETIRÉE à la demande user. The Few ne fournit aucun
  // contenu — l'utilisateur apporte sa propre URL IPTV en local.

  // Credentials du mode admin (PIN + GitHub PAT + gist ID). Chargés
  // tôt pour que l'entrée "Admin" dans Réglages sache si on demande
  // la création d'un PIN ou la vérification.
  unawaited(AdminCredentials.instance.initialize());

  // Pré-warm du cast : 1er scan SSDP 2s après le boot, puis re-scan
  // toutes les 60s en tâche de fond. Conséquence : dès que l'utilisateur
  // tape l'icône Cast, la liste des TVs apparaît instantanément — c'est
  // ce qui rend l'expérience "fluide comme YouTube".
  CastManager.instance.startWarmup();

  // Auto-refresh silencieux des playlists trop vieilles (> 12h depuis
  // la dernière sync). Lancé 3s après le boot pour ne pas concurrencer
  // le rendu initial. Si tout est récent, ne fait rien.
  Future<void>.delayed(const Duration(seconds: 3), () {
    PlaylistRepository.instance.refreshStale();
  });

  // SOURCES POUSSÉES PAR LE PANEL : re-synchro PÉRIODIQUE COURTE (5 min),
  // séparée du gros ré-import ci-dessous. AVANT ce correctif, une source
  // ajoutée/poussée par le revendeur APRÈS l'ouverture de l'app pouvait
  // rester invisible jusqu'à 24 h (l'ancien intervalle, partagé avec le
  // ré-import lourd) → pas « fluide et instantané ». Léger : un seul GET
  // JSON ; n'ajoute que ce qui manque (dédup existante), ne touche jamais
  // aux sources déjà chargées.
  Timer.periodic(const Duration(minutes: 5), (_) {
    if (!BootGuard.instance.safeMode) RemoteSourceRepository.sync();
  });

  // CONTENU du panel (parité TV) : le sync ci-dessus n'AJOUTE que les
  // sources manquantes — il ne voit jamais qu'un bouquet a été retiré ou
  // ajouté DANS une source existante. Sans ça, le seul filet côté mobile
  // était le ré-import 24 h plus bas : un client pouvait garder une
  // journée entière des chaînes que le revendeur avait retirées.
  // Cadence 5 min (et non 1 min comme la box) : sur batterie, une requête
  // par minute ne se justifie pas.
  if (!BootGuard.instance.safeMode) {
    SourceContentWatch.instance.start(every: const Duration(minutes: 5));
  }

  // AUTO-ACTUALISATION toutes les 24 h tant que l'app tourne : recharge
  // les playlists pour récupérer le contenu que le fournisseur a ajouté.
  // (À l'ouverture de l'app, le refreshStale ci-dessus couvre déjà le cas
  // "app relancée".) Silencieux.
  // P1-1 : en MODE SANS ÉCHEC (boucle de redémarrage détectée), on NE relance
  // PAS ce ré-import lourd (fetch+parse de toute la source = suspect OOM n°1).
  // refreshAll est par ailleurs protégé contre les passes concurrentes (mutex).
  Timer.periodic(const Duration(hours: 24), (_) {
    if (BootGuard.instance.safeMode) return;
    PlaylistRepository.instance.refreshAll();
  });

  // Choix Cinema / Daylight / System — chargé avant runApp pour
  // éviter un flash de mauvais thème au démarrage.
  await ThemeModeRepository.instance.initialize();

  // Couleur d'accent choisie par le client (bouton « Thème »). Chargée
  // avant runApp pour éviter un flash de la couleur par défaut.
  await AccentController.instance.initialize();

  // Thème DISTANT (nom de l'app + couleur d'accent) piloté par le panel
  // « Thème ». Non bloquant : s'applique dès que la réponse arrive et
  // RECONSTRUIT toute l'app (BrandConfig + AccentController sont dans le
  // Listenable racine). Si rien n'est configuré ou réseau KO → défauts.
  unawaited(RemoteThemeRepository.fetchAndApply());

  // Tarifs DISTANTS (à vie / 1 an / essai + promo) pilotés par le panel
  // « Tarifs ». Non bloquant : le bloc « Nos offres » se met à jour dès
  // que la réponse arrive (PricingRepository.notifier). Défauts maison
  // sinon (à vie 9,9 € · 1 an 4,9 € · essai 7 jours).
  unawaited(PricingRepository.fetch());

  // Invitation à laisser un avis (message piloté par le panel). Non
  // bloquant : l'accueil affichera la feuille plus tard si elle est active.
  unawaited(FeedbackRepository.instance.initialize());

  // Classe d'appareil (Téléphone / TV / Auto). Chargée tôt pour que
  // `_AppEntry` puisse décider immédiatement quel home afficher.
  await DeviceClassRepository.instance.initialize();

  // Langue préférée (FR / EN / ES / SV / DA / NB / AR / SW / Système).
  // Doit être chargée avant runApp pour éviter un flash de mauvaise
  // langue au premier frame.
  await LocaleRepository.instance.initialize();

  // Update checker — silencieux en arrière-plan. Le résultat est lu
  // par AboutScreen / un toast plus tard. Si une build plus récente est
  // dispo ET que l'utilisateur a laissé l'option "mise à jour" active,
  // on pousse une notification (en plus de la fenêtre au démarrage).
  unawaited(UpdateChecker.instance.check().then((UpdateInfo? info) {
    if (info != null && info.hasUpdate) {
      NotificationService.instance.notifyAppUpdate(
        latestTs: info.latestTs,
        versionLabel: info.latestVersion,
      );
    }
  }));

  // Annonces de l'équipe (poussées depuis le panel admin). Best-effort,
  // gardé par l'interrupteur Réglages, ne notifie qu'une seule fois par
  // annonce. Lancé après le boot pour ne pas concurrencer le 1er frame.
  Future<void>.delayed(const Duration(seconds: 4), () {
    NotificationService.instance.checkAnnouncement();
  });

  runApp(const TvKingApp());

  // App lancée : si elle tient quelques secondes, on efface l'historique de
  // boucle de crash (un démarrage réussi « pardonne » les crashs précédents).
  BootGuard.instance.scheduleStableReset();
}

class TvKingApp extends StatelessWidget {
  const TvKingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable:
          Listenable.merge(<Listenable>[
        ThemeModeRepository.instance,
        LocaleRepository.instance,
        AccentController.instance,
        BrandConfig.instance,
      ]),
      builder: (BuildContext context, _) {
        return MaterialApp(
          // Titre Material — utilisé par Android pour le label de l'app
          // dans le recent-apps switcher. Reflet du nom (surchargeable
          // à distance via le panel « Thème »).
          title: BrandConfig.instance.appName,
          debugShowCheckedModeBanner: false,
          // Thème VERROUILLÉ en Cinema (sombre). L'app est conçue
          // « Maison Noir » : ses ~900 couleurs sont des constantes
          // sombres (AppColors). Un thème clair Material laissait ces
          // couleurs sombres en place → textes par défaut sombres sur
          // fonds restés sombres = contenu invisible. On force donc le
          // mode sombre quoi qu'il arrive (y compris si l'OS est en
          // clair) ; le sélecteur Apparence a été retiré des Réglages.
          theme: AppTheme.cinema,
          darkTheme: AppTheme.cinema,
          themeMode: ThemeMode.dark,

          // Internationalisation — la liste des langues supportées
          // sort de `LocaleRepository`. Quand l'utilisateur choisit
          // "Système" (locale=null), Flutter retombe sur la langue
          // de l'OS s'il y a un .arb correspondant, sinon sur fr.
          locale: LocaleRepository.instance.locale,
          supportedLocales: LocaleRepository.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],

          // Clamp du textScaler système. Sur Android TV, l'option
          // "Accessibilité → Taille du texte" peut monter à 200%,
          // ce qui CASSE TOUS LES LAYOUTS d'apps fixés en dp (cards
          // débordent, boutons coupent leur label, etc.).
          //   - min 0.9 : aucune raison de rétrécir, c'est moche.
          //   - max 1.25 : laisse l'utilisateur agrandir un peu pour
          //     les yeux fatigués, mais pas au point de casser les
          //     mesures de boutons / lignes / icônes.
          // S'applique partout — phone comme TV — pour cohérence.
          builder: (BuildContext context, Widget? child) {
            final MediaQueryData mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                textScaler: mq.textScaler.clamp(
                  minScaleFactor: 0.9,
                  maxScaleFactor: 1.25,
                ),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },

          home: const _AppEntry(),
        );
      },
    );
  }
}

/// Décide quel écran montrer en premier (post-Phase 1+/2026-06-01) :
///   - Age gate (Red Room) si jamais confirme
///   - Lock biometrique si active
///   - HomeScreen directement (Phone ou TV selon DeviceClass.auto)
///
/// DevicePickerScreen + OnboardingScreen ont ete RETIRES du flow :
/// les utilisateurs entrent directement dans l'app, sans demo ni
/// tuto. Voir le commentaire dans build() (etape "1)") pour les
/// details.
class _AppEntry extends StatefulWidget {
  const _AppEntry();

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> with WidgetsBindingObserver {
  // Onboarding/DevicePicker retires du flow (cf. build). On garde le
  // flag `_onboardingDone` pour ne pas re-evaluer en boucle et pour
  // qu'on puisse restaurer le flow sans refactor si on change d'avis.
  bool? _onboardingDone;
  // Verrouillage biométrique : null = pas encore chargé, true/false = état
  // du réglage `security.lock_on_open`. Tant que `_unlocked` est false ET
  // que le lock est activé, on affiche `LockScreen` au lieu de l'app.
  bool? _lockEnabled;
  bool _unlocked = false;
  // L'appareil SAIT-il s'authentifier (capteur biométrique OU PIN/schéma
  // système) ? `null` = réponse local_auth pas encore arrivée. Sert à ne
  // sauter le verrou sur un appareil classé « TV » QUE s'il n'a réellement
  // aucun moyen d'auth (vraie box) — une tablette 10-12" paysage est classée
  // TV par l'heuristique DeviceClass.auto mais possède capteur/PIN : sans ce
  // test, son verrou biométrique était silencieusement ignoré.
  bool? _canAuthenticate;
  // Confirmation 18+ (héritée de l'ancienne variante Red Room, retirée).
  // `requireAgeGate` étant désormais toujours `false`, ce gate ne
  // s'affiche jamais — la valeur est posée à `true` dans initState.
  // `null` = pas encore chargé, `true` = déjà confirmée à un précédent
  // boot. Si le flavor n'exige pas le gate, on saute en posant `true`
  // directement dans initState.
  bool? _ageGateConfirmed;
  // Mise à jour FORCÉE : passe à true si la version installée est jugée
  // obsolète (cf. _checkForcedUpdate). Tant que false, l'app fonctionne
  // normalement (fail-open : si la vérif réseau échoue, on ne bloque pas).
  bool _forceUpdate = false;

  // Pub vidéo de démarrage (pilotée par le panel). `_adResolved` = on sait
  // s'il y a une pub (fetch terminé ou court délai de secours) ; `_adShow`
  // = on doit la jouer ; `_adDone` = terminée/passée.
  bool _adResolved = false;
  bool _adShow = false;
  bool _adDone = false;

  // CONSOLE MAÎTRE : la promesse de master_console.dart (« s'ouvre
  // DIRECTEMENT sur le générateur de tests ») est tenue par un push
  // automatique UNIQUE post-frame — ce flag empêche de re-pousser le
  // générateur à chaque rebuild du ListenableBuilder.
  bool _consolePushed = false;

  /// Résout la pub de démarrage SANS jamais bloquer l'accueil plus de 2,5 s.
  Future<void> _resolveAd() async {
    Timer(const Duration(milliseconds: 2500), () {
      if (mounted && !_adResolved) setState(() => _adResolved = true);
    });
    await StartupAdRepository.instance.fetch();
    final bool show = await StartupAdRepository.instance.shouldShow();
    if (mounted) {
      setState(() {
        _adShow = show;
        _adResolved = true;
      });
    }
  }

  /// MISE À JOUR FORCÉE — pilotée à distance depuis le panel.
  ///
  /// Désactivée par défaut (le serveur renvoie minBuildTs=0). Ne bloque
  /// QUE si l'admin a appuyé sur « Forcer la mise à jour » ET que cette
  /// app est plus ancienne que le dernier build (kBuildTs < minBuildTs,
  /// tout en SECONDES → plus de bug d'unités). Fail-open en cas d'erreur.
  Future<void> _checkForcedUpdate() async {
    final bool must = await ForceUpdateChecker.instance.mustUpdate();
    if (must && mounted) {
      setState(() => _forceUpdate = true);
    }
  }

  /// Vérification de MAJ in-app (sideload) — même logique que la TV Box :
  /// on ne se contente pas d'un seul contrôle au boot, on re-vérifie
  /// PÉRIODIQUEMENT (12 h) et à chaque RETOUR AU PREMIER PLAN. Ainsi, dès
  /// qu'une nouvelle version est publiée sur « prod », le client voit la
  /// boîte « Mise à jour disponible → Mettre à jour » sans avoir à
  /// redémarrer l'app — et l'accepter installe directement le nouvel APK.
  Timer? _updateTimer;

  /// Garde anti-empilement : `maybePromptUpdate` attend toute la boîte de
  /// dialogue + le téléchargement ; on évite qu'un tick périodique ou un
  /// `resumed` en ouvre une seconde par-dessus.
  bool _updateChecking = false;

  /// Félicitation d'activation (une seule fois) : dès que
  /// [SubscriptionState] lève `justActivated`, on montre un message vert au
  /// client et on acquitte pour ne pas le répéter.
  void _onSubscriptionChanged() {
    if (!mounted || !SubscriptionState.instance.justActivated) return;
    SubscriptionState.instance.acknowledgeActivation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 6),
          content: Text(context.l10n.subActivatedNotice),
        ),
      );
    });
  }

  Future<void> _maybeCheckUpdate() async {
    if (_updateChecking || !mounted) return;
    _updateChecking = true;
    try {
      await maybePromptUpdate(context);
    } finally {
      _updateChecking = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _checkForcedUpdate();
    // Temps réel : quand l'admin appuie « Forcer la mise à jour » sur le
    // panel, le RealtimeSyncService incrémente `revision` → re-check
    // immédiat, l'écran de blocage apparaît sans redémarrage.
    ForceUpdateChecker.instance.revision.addListener(_checkForcedUpdate);
    // Notification d'activation : quand le serveur confirme l'abonnement
    // payant du client (transition essai → payé), on le félicite UNE fois.
    SubscriptionState.instance.addListener(_onSubscriptionChanged);
    // Cycle de vie : re-vérifier la MAJ au retour au premier plan (comme
    // la TV Box). Un client qui rouvre l'app après une publication voit
    // tout de suite la proposition de mise à jour.
    WidgetsBinding.instance.addObserver(this);
    // Mise à jour in-app (sideload) : détection NON bloquante après le
    // 1er frame, avec un léger délai pour ne pas gêner le boot/lock.
    // Fail-open : si rien de neuf ou erreur réseau, ne fait rien.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) _maybeCheckUpdate();
      });
    });
    // Re-contrôle PÉRIODIQUE (12 h) tant que l'app tourne — identique à la
    // TV Box : une app laissée ouverte finit par proposer la MAJ elle aussi.
    _updateTimer = Timer.periodic(
      const Duration(hours: 12),
      (_) => _maybeCheckUpdate(),
    );
    _resolveAd();
    OnboardingState.instance.hasCompleted().then((bool done) {
      if (mounted) {
        setState(() {
          _onboardingDone = done;
          // DevicePicker retire — la decision se fait via DeviceClass.auto
          // (taille d'ecran). Plus de drapeau `_devicePicked`.
        });
      }
    });

    // Verrouillage à l'ouverture = OPT-IN (désactivé par défaut). Sur une
    // install fraîche, l'app s'ouvre SANS empreinte ni code — aucune
    // friction pour celui qui vient de télécharger. L'utilisateur qui le
    // souhaite peut l'activer dans Réglages > Sécurité (pref
    // `security.lock_on_open`, défaut false). On LIT donc ce réglage au lieu
    // de forcer le verrou. Le LockScreen (empreinte + PIN de secours) reste
    // disponible pour ceux qui activent l'option.
    final FlavorConfig flavor = FlavorConfig.current;
    LockSettings.instance.isLockEnabled().then((bool enabled) {
      if (mounted) setState(() => _lockEnabled = enabled);
    });
    // Capacité d'auth de l'appareil, chargée en parallèle (réponse quasi
    // immédiate — appel plugin local, zéro réseau). `isSupported()` ne throw
    // jamais (wrapper) : `false` en cas d'erreur → sur box, comportement
    // inchangé (pas de blocage).
    BiometricAuth.instance.isSupported().then((bool ok) {
      if (mounted) setState(() => _canAuthenticate = ok);
    });

    // Gate âge : uniquement Red Room. Sur The Few, on by-pass
    // directement avec `true` pour ne pas bloquer le boot.
    if (flavor.requireAgeGate) {
      AgeGateSettings.instance.isConfirmed().then((bool ok) {
        if (mounted) {
          setState(() => _ageGateConfirmed = ok);
        }
      });
    } else {
      _ageGateConfirmed = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour au premier plan : re-vérifie la MAJ in-app (l'admin a pu
    // publier une nouvelle version pendant que l'app était en arrière-plan).
    if (state == AppLifecycleState.resumed) {
      _maybeCheckUpdate();
      // Thème immersif : si le jour a changé pendant l'arrière-plan, bascule
      // sur la couleur du jour (sans effet en mode fixe). O(1).
      AccentController.instance.refreshDailyIfNeeded();
    }
  }

  @override
  void dispose() {
    ForceUpdateChecker.instance.revision.removeListener(_checkForcedUpdate);
    SubscriptionState.instance.removeListener(_onSubscriptionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Splash tant qu'on n'a pas chargé les flags persistés.
    if (_onboardingDone == null ||
        _lockEnabled == null ||
        _ageGateConfirmed == null) {
      return const _Splash();
    }

    // 0) MISE À JOUR FORCÉE — prioritaire sur tout le reste. Si la version
    //    installée est obsolète, on ne laisse RIEN d'autre s'afficher.
    //    "Réessayer" relance la vérif (utile après réinstallation).
    if (_forceUpdate) {
      return ForcedUpdateScreen(
        onRetry: () {
          setState(() => _forceUpdate = false);
          _checkForcedUpdate();
        },
      );
    }

    // 0a) Gate "j'ai 18 ans" — Red Room uniquement. Le flavor sevenMotion
    //     a posé `_ageGateConfirmed = true` dans initState, donc on saute.
    //     Si non confirmé : l'écran s'affiche, le bouton "ENTRER" met à
    //     jour la pref et passe la suite. Le refus tente de quitter l'app.
    if (_ageGateConfirmed == false) {
      return AgeGateScreen(
        onConfirmed: () => setState(() => _ageGateConfirmed = true),
      );
    }

    // 0b) Verrouillage biométrique. AVANT : sauté dès que l'appareil était
    //     classé « TV » — or l'heuristique DeviceClass.auto classe aussi une
    //     TABLETTE 10"+ paysage comme TV, et son verrou (activé par le user
    //     dans Réglages > Sécurité) était alors ignoré en silence. La bonne
    //     question n'est pas « est-ce une TV ? » mais « l'appareil PEUT-il
    //     s'authentifier ? » (local_auth.isDeviceSupported) :
    //       • capteur/PIN présent (téléphone, tablette) → verrou affiché,
    //         MÊME si l'écran est classé TV ;
    //       • vraie box TV sans aucun moyen d'auth → pas de blocage
    //         (comportement historique conservé).
    //     Ne s'applique qu'au cold start ; pas de re-lock au retour de
    //     background (choix UX).
    final bool isTvDevice = DeviceClassRepository.instance.isTvFor(context);
    if (_lockEnabled == true && !_unlocked) {
      // Téléphone/écran non-TV : verrou direct, sans attendre local_auth
      // (LockScreen a de toute façon son PIN app en parachute).
      if (!isTvDevice) {
        return LockScreen(
          onUnlocked: () => setState(() => _unlocked = true),
        );
      }
      // Classé TV : on attend la (rapide) réponse de local_auth avant de
      // trancher — sinon on risquerait un frame d'accueil déverrouillé
      // sur tablette avant l'apparition du verrou.
      if (_canAuthenticate == null) return const _Splash();
      if (_canAuthenticate == true) {
        return LockScreen(
          onUnlocked: () => setState(() => _unlocked = true),
        );
      }
      // Box sans capteur ni PIN système : on n'affiche rien (un LockScreen
      // y serait une impasse sans clavier tactile pratique).
    }

    // 1) DevicePicker + 2) Onboarding : SUPPRIMES (decision produit
    //    2026-06-01). L'utilisateur entre directement dans l'app, pas
    //    de demo / tuto / choix de classe d'appareil au 1er lancement.
    //
    //    - DeviceClass reste en mode `auto` (DeviceClassRepository
    //      defaut) : l'app detecte au runtime via la taille d'ecran.
    //    - OnboardingState est marquee completed silencieusement la
    //      1ere fois pour ne PAS replonger l'user dans le tuto si on
    //      change d'avis et qu'on remet l'ecran un jour.
    //
    //    L'utilisateur qui n'a pas de playlist arrive directement sur
    //    le home avec un etat vide + bouton "Ajouter une playlist"
    //    (deja present dans Reglages > Playlists). C'est plus direct
    //    qu'un onboarding qui lui explique ce qu'il sait deja
    //    (il a installe une app IPTV, il sait qu'il faut une source).
    if (_onboardingDone == false) {
      // One-shot : marque completed pour ne pas re-evaluer cette
      // branche aux prochains setState et eviter le flash UI. Pas
      // d'attente du Future (best-effort cote persistance).
      _onboardingDone = true;
      // ignore: discarded_futures
      OnboardingState.instance.markCompleted();
    }

    // 3) Gate de monétisation — l'admin peut geler / bannir un
    //    client à distance via le panel web, et le trial expire
    //    au bout de 7 jours. Si l'une de ces conditions s'applique,
    //    on affiche un écran bloquant à la place de l'app. L'écran
    //    est listenable au SubscriptionState : dès que l'admin
    //    réactive le client (ou marque payé), l'app débloque
    //    automatiquement au prochain refresh.
    // La bannière « message admin » temps réel (WebSocket) est posée dans
    // un Stack AU-DESSUS de tout le flux normal (gate, pub, home) : un
    // message poussé par le panel s'affiche donc quel que soit l'écran
    // courant. Zéro coût quand il n'y a rien (SizedBox.shrink).
    return Stack(
      children: <Widget>[
        ListenableBuilder(
          listenable: SubscriptionState.instance,
          builder: (BuildContext context, _) {
            if (SubscriptionState.instance.shouldBlockUser) {
              return const SubscriptionGateScreen();
            }
            // 3b) PUB VIDÉO de démarrage (pilotée par le panel), juste avant
            //     l'accueil. Tant qu'on ne sait pas encore (réseau), bref
            //     splash pour éviter un flash d'accueil avant la pub.
            // BUILD CONSOLE MAÎTRE : app SÉPARÉE (package + nom « 7 The Few
            // Master »), mais FONCTIONNALITÉ COMPLÈTE — l'exploitant ajoute ses
            // propres sources M-Trio/Xtream comme dans l'app cliente, puis
            // envoie des tests via l'entrée invité (débloquée par sa MAC maître,
            // avec la boîte noire). On saute juste la pub de démarrage.
            //
            // Ouverture DIRECTE sur le générateur de tests (promesse de
            // master_console.dart) : SimpleHomeScreen reste la racine et on
            // pousse GuestScreen(consoleMode: true) une seule fois, post-frame.
            // Choisi plutôt que « GuestScreen en home » parce que :
            //   • le back (geste/bouton système) ramène à l'accueil complet —
            //     indispensable pour gérer ses sources comme dans l'app
            //     cliente (le pouvoir « tests » reste verrouillé serveur) ;
            //   • aucune bifurcation dans le flux d'activation/StreamBuilder
            //     de SimpleHomeScreen — zéro risque de régression là-bas.
            // Le push est placé ICI (et pas dans initState) pour rester
            // DERRIÈRE les gates prioritaires : mise à jour forcée et blocage
            // abonnement s'affichent avant, comme pour l'app cliente.
            if (kMasterConsole) {
              if (!_consolePushed) {
                _consolePushed = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  Navigator.of(this.context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const GuestScreen(consoleMode: true),
                    ),
                  );
                });
              }
              return const SimpleHomeScreen();
            }
            if (!_adResolved) return const _Splash();
            if (_adShow && !_adDone) {
              return StartupAdScreen(
                config: StartupAdRepository.instance.config,
                onDone: () {
                  StartupAdRepository.instance.markShown();
                  if (mounted) setState(() => _adDone = true);
                },
              );
            }

            // 4) Home — application MOBILE (7 MOTION). Les variantes TV et
            //    Red Room ont été retirées du projet : il ne reste que le
            //    mobile, piloté par le panel.
            return const SimpleHomeScreen();
          },
        ),
        // Bannière message admin — en haut, sous la barre de statut.
        const Align(
          alignment: Alignment.topCenter,
          child: SafeArea(child: AdminMessageBanner()),
        ),
      ],
    );
  }
}

/// Splash The Few — apparaît max 50 ms le temps que le flag
/// onboarding soit lu depuis SharedPreferences. Toujours en Cinema
/// Mode : c'est l'identité du produit qui s'affiche en premier.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.voidSurface,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const BrandLogo.splash(),
                    const SizedBox(height: 18),
                    // Ligne "The Few ✓" — le badge bleu vérifié à côté
                    // du wordmark, comme sur les profils Instagram /
                    // WhatsApp / Twitter officiels.
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(BrandConfig.instance.appName,
                            style: AppTextStyles.headlineLarge),
                        const SizedBox(width: 8),
                        const VerifiedBadge.large(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // ----- Signature marquee qui défile -----
            const PoweredByMarquee(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
