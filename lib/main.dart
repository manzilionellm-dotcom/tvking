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

import 'core/branding/brand_logo.dart';
import 'core/branding/powered_by_marquee.dart';
import 'core/notifications/notification_service.dart';
import 'core/branding/verified_badge.dart';
import 'core/theme/app_text_styles.dart' show AppTextStyles;
import 'core/i18n/locale_repository.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/accent_controller.dart';
import 'core/theme/theme_mode_repository.dart';
import 'core/app/build_info.dart';
import 'features/about/data/update_checker.dart';
import 'features/about/presentation/forced_update_screen.dart';
import 'l10n/generated/app_localizations.dart';
import 'features/about/data/update_checker.dart';
import 'features/cast/data/cast_manager.dart';
import 'features/channels/data/recent_searches_repository.dart';
import 'features/channels/data/recently_watched_repository.dart';
import 'features/channels/data/watch_history_repository.dart';
import 'features/channels/presentation/tv_home_screen.dart';
import 'features/tv/presentation/tv_splash_screen.dart';
import 'features/red_room/presentation/red_room_home_screen.dart';
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
import 'core/flavor/flavor.dart';
import 'features/security/data/age_gate_settings.dart';
import 'features/security/data/lock_settings.dart';
import 'features/security/presentation/age_gate_screen.dart';
import 'features/security/presentation/lock_screen.dart';
import 'features/recordings/data/recording_repository.dart';
import 'features/subscription/data/subscription_state.dart';
import 'features/subscription/presentation/subscription_gate.dart';

Future<void> main() async {
  // Identité du build BLACK7 ROYAL grand public. Doit être posée AVANT
  // `bootApp()` (qui touche aux repos, lesquels lisent `FlavorConfig`).
  // La variante Red Room a son propre entrypoint `main_redroom.dart`
  // qui pose `FlavorConfig.redRoom` puis appelle le MÊME `bootApp()`.
  FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
  await bootApp();
}

/// Séquence d'initialisation partagée par les deux entrypoints
/// (`main.dart` et `main_redroom.dart`). Le flavor doit déjà avoir
/// été posé par l'appelant — on lit `FlavorConfig.current` librement
/// à partir d'ici.
Future<void> bootApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  // libmpv natif — AVANT runApp pour ne pas crasher au premier lecteur
  MediaKit.ensureInitialized();

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
    // charge automatiquement. Le client n'a rien à saisir.
    RemoteSourceRepository.sync();

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
        .then((_) {}),
  );
  unawaited(PlayerSettings.instance.load());

  // Notifications locales (rappels EPG). Init non bloquant ; la permission
  // n'est demandée que lorsque l'utilisateur pose son 1er rappel.
  unawaited(NotificationService.instance.init());

  // Identité unique de l'appareil (MAC virtuel "MK:XX:XX:XX:XX:XX").
  // Pré-chargée pour qu'elle soit dispo synchrone partout dès le
  // premier frame (About, Réglages, etc.).
  unawaited(DeviceIdentity.instance.preload());

  // Essai gratuit de 7 jours + abonnement 5 €/an. Au tout
  // premier boot, persiste firstLaunchAt = now pour démarrer le
  // compte à rebours local. PUIS sync avec le backend Cloudflare
  // qui est l'autorité finale (l'admin peut geler/débloquer un
  // client à distance depuis le panel /admin/panel).
  unawaited(SubscriptionState.instance.initialize().then((_) {
    // Sync non bloquant : si le réseau est down, l'app utilise
    // le trial local en fallback (calcul offline).
    SubscriptionState.instance.syncWithBackend();
  }));

  // NB : la "fixation à distance" (RemoteConfigRepository qui
  // fetchait des playlists depuis un Gist toutes les 30 min) a
  // été RETIRÉE à la demande user. BLACK7 ROYAL ne fournit aucun
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

  // AUTO-ACTUALISATION toutes les 24 h tant que l'app tourne : recharge
  // les playlists pour récupérer le contenu que le fournisseur a ajouté,
  // et re-vérifie la source poussée par MAC. (À l'ouverture de l'app, le
  // refreshStale ci-dessus couvre déjà le cas "app relancée".) Silencieux.
  Timer.periodic(const Duration(hours: 24), (_) {
    RemoteSourceRepository.sync();
    PlaylistRepository.instance.refreshAll();
  });

  // Choix Cinema / Daylight / System — chargé avant runApp pour
  // éviter un flash de mauvais thème au démarrage.
  await ThemeModeRepository.instance.initialize();

  // Couleur d'accent choisie par le client (bouton « Thème »). Chargée
  // avant runApp pour éviter un flash de la couleur par défaut.
  await AccentController.instance.initialize();

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
      ]),
      builder: (BuildContext context, _) {
        return MaterialApp(
          // Titre Material — utilisé par Android pour le label de l'app
          // dans le recent-apps switcher. Reflet du flavor courant.
          title: FlavorConfig.current.appName,
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

class _AppEntryState extends State<_AppEntry> {
  // Onboarding/DevicePicker retires du flow (cf. build). On garde le
  // flag `_onboardingDone` pour ne pas re-evaluer en boucle et pour
  // qu'on puisse restaurer le flow sans refactor si on change d'avis.
  bool? _onboardingDone;
  // Verrouillage biométrique : null = pas encore chargé, true/false = état
  // du réglage `security.lock_on_open`. Tant que `_unlocked` est false ET
  // que le lock est activé, on affiche `LockScreen` au lieu de l'app.
  bool? _lockEnabled;
  bool _unlocked = false;
  // Version TV : on affiche d'abord l'écran de démarrage dédié
  // (logo + MAC en gros, cf. TvSplashScreen) avant l'accueil 10-foot.
  // `false` au cold start → le splash s'affiche une fois par lancement ;
  // l'utilisateur a ainsi toujours le temps de lire/photographier sa MAC
  // pour la donner à son fournisseur. Passe `true` quand il valide ENTRER.
  bool _tvIntroSeen = false;
  // Confirmation 18+ (utilisée uniquement par le flavor Red Room).
  // `null` = pas encore chargé, `true` = déjà confirmée à un précédent
  // boot. Si le flavor n'exige pas le gate, on saute en posant `true`
  // directement dans initState.
  bool? _ageGateConfirmed;
  // Mise à jour FORCÉE : passe à true si la version installée est jugée
  // obsolète (cf. _checkForcedUpdate). Tant que false, l'app fonctionne
  // normalement (fail-open : si la vérif réseau échoue, on ne bloque pas).
  bool _forceUpdate = false;

  /// Vérifie si une version nettement plus récente est publiée. Si oui,
  /// on bloque l'app sur l'écran de mise à jour. Silencieux/non bloquant
  /// en cas d'erreur réseau ou de build local (kBuildTs == 0).
  Future<void> _checkForcedUpdate() async {
    if (kBuildTs <= 0) return; // build local → jamais de blocage
    try {
      final UpdateInfo? info = await UpdateChecker.instance.check();
      if (info == null || info.latestTs <= 0) return;
      final bool obsolete =
          info.latestTs - kBuildTs > kForceUpdateGraceSeconds;
      if (obsolete && mounted) {
        setState(() => _forceUpdate = true);
      }
    } catch (_) {
      // fail-open : on ne bloque jamais sur une erreur de vérification.
    }
  }

  @override
  void initState() {
    super.initState();
    _checkForcedUpdate();
    OnboardingState.instance.hasCompleted().then((bool done) {
      if (mounted) {
        setState(() {
          _onboardingDone = done;
          // DevicePicker retire — la decision se fait via DeviceClass.auto
          // (taille d'ecran). Plus de drapeau `_devicePicked`.
        });
      }
    });

    // Verrouillage TOUJOURS actif au démarrage (demande client) : comme
    // une app bancaire, on exige l'authentification au lancement, quel
    // que soit le flavor — on ne lit plus de réglage optionnel. Le
    // LockScreen propose empreinte + code PIN de secours, donc aucun
    // risque de blocage même sur un appareil sans biométrie configurée.
    final FlavorConfig flavor = FlavorConfig.current;
    _lockEnabled = true;

    // Gate âge : uniquement Red Room. Sur BLACK7 ROYAL, on by-pass
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

    // 0b) Verrouillage biométrique — AVANT tout autre écran. L'utilisateur
    //     doit s'authentifier (empreinte ou PIN système) si le réglage
    //     `security.lock_on_open` est activé OU si le flavor exige
    //     biometricMandatory (Red Room). Ne s'applique qu'au cold start ;
    //     pas de re-lock sur retour de background (choix UX).
    if (_lockEnabled == true && !_unlocked) {
      return LockScreen(
        onUnlocked: () => setState(() => _unlocked = true),
      );
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
    return ListenableBuilder(
      listenable: SubscriptionState.instance,
      builder: (BuildContext context, _) {
        if (SubscriptionState.instance.shouldBlockUser) {
          return const SubscriptionGateScreen();
        }
        // 4) Home — version TV ou téléphone selon le choix utilisateur.
        return ListenableBuilder(
          listenable: DeviceClassRepository.instance,
          builder: (BuildContext context, _) {
            final bool isTv =
                DeviceClassRepository.instance.isTvFor(context);
            // Flavor Red Room (adulte) sur téléphone : accueil dédié à 2
            // onglets (En direct / Cinéma). Même code partagé, présentation
            // spécifique. La TV garde l'accueil 10-foot pour l'instant.
            if (FlavorConfig.current.flavor == Flavor.redRoom && !isTv) {
              return const RedRoomHomeScreen();
            }
            // Téléphone : nouvel accueil "simple" (pays → catégories).
            if (!isTv) return const SimpleHomeScreen();
            // TV : écran de démarrage dédié (logo + MAC) au 1er affichage,
            // puis l'accueil 10-foot une fois ENTRER validé.
            return _tvIntroSeen
                ? const TvHomeScreen()
                : TvSplashScreen(
                    onEnter: () => setState(() => _tvIntroSeen = true),
                  );
          },
        );
      },
    );
  }
}

/// Splash BLACK7 ROYAL — apparaît max 50 ms le temps que le flag
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
                    // Ligne "BLACK7 ROYAL ✓" — le badge bleu vérifié à côté
                    // du wordmark, comme sur les profils Instagram /
                    // WhatsApp / Twitter officiels.
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text('BLACK7 ROYAL', style: AppTextStyles.headlineLarge),
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
