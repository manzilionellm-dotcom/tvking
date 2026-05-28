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
import 'core/branding/verified_badge.dart';
import 'core/theme/app_text_styles.dart' show AppTextStyles;
import 'core/i18n/locale_repository.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_repository.dart';
import 'l10n/generated/app_localizations.dart';
import 'features/about/data/update_checker.dart';
import 'features/cast/data/cast_manager.dart';
import 'features/channels/data/recent_searches_repository.dart';
import 'features/channels/data/recently_watched_repository.dart';
import 'features/channels/data/watch_history_repository.dart';
import 'features/channels/presentation/home_screen.dart';
import 'features/channels/presentation/tv_home_screen.dart';
import 'features/admin/data/admin_credentials.dart';
import 'features/device/data/device_identity.dart';
import 'features/epg/data/epg_repository.dart';
import 'features/onboarding/data/device_class_repository.dart';
import 'features/onboarding/data/onboarding_state.dart';
import 'features/onboarding/presentation/device_picker_screen.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/player/data/player_settings.dart';
import 'features/playlists/data/favorites_repository.dart';
import 'features/playlists/data/playlist_repository.dart';
import 'core/flavor/flavor.dart';
import 'features/security/data/age_gate_settings.dart';
import 'features/security/data/lock_settings.dart';
import 'features/security/presentation/age_gate_screen.dart';
import 'features/security/presentation/lock_screen.dart';
import 'features/recordings/data/recording_repository.dart';
import 'features/subscription/data/subscription_state.dart';
import 'features/subscription/presentation/subscription_gate.dart';

Future<void> main() async {
  // Identité du build 7 MOTION grand public. Doit être posée AVANT
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
  unawaited(PlaylistRepository.instance.initialize());
  unawaited(FavoritesRepository.instance.initialize());
  unawaited(RecentlyWatchedRepository.instance.initialize());
  unawaited(RecentSearchesRepository.instance.initialize());
  unawaited(WatchHistoryRepository.instance.initialize());
  unawaited(EpgRepository.instance.initialize());
  unawaited(RecordingRepository.instance.initialize());
  unawaited(PlayerSettings.instance.load());

  // Identité unique de l'appareil (MAC virtuel "MK:XX:XX:XX:XX:XX").
  // Pré-chargée pour qu'elle soit dispo synchrone partout dès le
  // premier frame (About, Réglages, etc.).
  unawaited(DeviceIdentity.instance.preload());

  // Essai gratuit de 10 jours + abonnement 13 €/an. Au tout
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
  // été RETIRÉE à la demande user. 7 MOTION ne fournit aucun
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

  // Choix Cinema / Daylight / System — chargé avant runApp pour
  // éviter un flash de mauvais thème au démarrage.
  await ThemeModeRepository.instance.initialize();

  // Classe d'appareil (Téléphone / TV / Auto). Chargée tôt pour que
  // `_AppEntry` puisse décider immédiatement quel home afficher.
  await DeviceClassRepository.instance.initialize();

  // Langue préférée (FR / EN / ES / SV / DA / NB / AR / SW / Système).
  // Doit être chargée avant runApp pour éviter un flash de mauvaise
  // langue au premier frame.
  await LocaleRepository.instance.initialize();

  // Update checker — silencieux en arrière-plan. Le résultat est lu
  // par AboutScreen / un toast plus tard.
  unawaited(UpdateChecker.instance.check());

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
      ]),
      builder: (BuildContext context, _) {
        return MaterialApp(
          // Titre Material — utilisé par Android pour le label de l'app
          // dans le recent-apps switcher. Reflet du flavor courant.
          title: FlavorConfig.current.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.daylight,
          darkTheme: AppTheme.cinema,
          themeMode: ThemeModeRepository.instance.mode,

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

/// Décide quel écran montrer en premier :
///   - 1er lancement → DevicePickerScreen (téléphone / TV / auto)
///   - puis OnboardingScreen (3 slides)
///   - puis HomeScreen (Phone ou TV selon le choix)
///
/// Le flag onboarding est aussi utilisé pour considérer que le
/// device picker a été vu (les deux sont liés au "1er lancement").
class _AppEntry extends StatefulWidget {
  const _AppEntry();

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  bool? _onboardingDone;
  bool _devicePicked = false;
  // Verrouillage biométrique : null = pas encore chargé, true/false = état
  // du réglage `security.lock_on_open`. Tant que `_unlocked` est false ET
  // que le lock est activé, on affiche `LockScreen` au lieu de l'app.
  bool? _lockEnabled;
  bool _unlocked = false;
  // Confirmation 18+ (utilisée uniquement par le flavor Red Room).
  // `null` = pas encore chargé, `true` = déjà confirmée à un précédent
  // boot. Si le flavor n'exige pas le gate, on saute en posant `true`
  // directement dans initState.
  bool? _ageGateConfirmed;

  @override
  void initState() {
    super.initState();
    OnboardingState.instance.hasCompleted().then((bool done) {
      if (mounted) {
        setState(() {
          _onboardingDone = done;
          // Si l'onboarding est complété, on considère que le device
          // picker l'est aussi (il vient AVANT). Pour un user qui a
          // déjà l'app installée et qui se met à jour, c'est juste.
          _devicePicked = done;
        });
      }
    });

    // Charge le réglage lock_on_open en parallèle. L'app n'attend pas
    // ce flag pour montrer le splash, mais on en a besoin avant le
    // premier rendu d'écran fonctionnel pour décider lock vs app.
    // Sur Red Room (biometricMandatory = true), on FORCE le lock à
    // ON quoi qu'ait choisi l'utilisateur dans Réglages.
    final FlavorConfig flavor = FlavorConfig.current;
    if (flavor.biometricMandatory) {
      _lockEnabled = true;
    } else {
      LockSettings.instance.isLockEnabled().then((bool enabled) {
        if (mounted) {
          setState(() => _lockEnabled = enabled);
        }
      });
    }

    // Gate âge : uniquement Red Room. Sur 7 MOTION, on by-pass
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

    // 1) Première étape : choix de la classe d'appareil
    if (!_devicePicked) {
      return DevicePickerScreen(
        onDone: () => setState(() => _devicePicked = true),
      );
    }

    // 2) Onboarding (slides bienvenue / playlist / premium)
    if (_onboardingDone == false) {
      return OnboardingScreen(
        onDone: () => setState(() => _onboardingDone = true),
      );
    }

    // 3) Gate de monétisation — l'admin peut geler / bannir un
    //    client à distance via le panel web, et le trial expire
    //    au bout de 10 jours. Si l'une de ces conditions s'applique,
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
            return isTv ? const TvHomeScreen() : const HomeScreen();
          },
        );
      },
    );
  }
}

/// Splash 7 MOTION — apparaît max 50 ms le temps que le flag
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
                    // Ligne "7 MOTION ✓" — le badge bleu vérifié à côté
                    // du wordmark, comme sur les profils Instagram /
                    // WhatsApp / Twitter officiels.
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text('7 MOTION', style: AppTextStyles.headlineLarge),
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
