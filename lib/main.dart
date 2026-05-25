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
import 'core/i18n/locale_repository.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_repository.dart';
import 'l10n/generated/app_localizations.dart';
import 'features/about/data/update_checker.dart';
import 'features/cast/data/cast_manager.dart';
import 'features/channels/data/recently_watched_repository.dart';
import 'features/channels/data/watch_history_repository.dart';
import 'features/channels/presentation/home_screen.dart';
import 'features/channels/presentation/tv_home_screen.dart';
import 'features/admin/data/admin_credentials.dart';
import 'features/device/data/device_identity.dart';
import 'features/device/data/remote_config_repository.dart';
import 'features/epg/data/epg_repository.dart';
import 'features/onboarding/data/device_class_repository.dart';
import 'features/onboarding/data/onboarding_state.dart';
import 'features/onboarding/presentation/device_picker_screen.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/player/data/player_settings.dart';
import 'features/playlists/data/favorites_repository.dart';
import 'features/playlists/data/playlist_repository.dart';
import 'features/recordings/data/recording_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // libmpv natif — AVANT runApp pour ne pas crasher au premier lecteur
  MediaKit.ensureInitialized();

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
  unawaited(WatchHistoryRepository.instance.initialize());
  unawaited(EpgRepository.instance.initialize());
  unawaited(RecordingRepository.instance.initialize());
  unawaited(PlayerSettings.instance.load());

  // Identité unique de l'appareil (MAC virtuel "MK:XX:XX:XX:XX:XX").
  // Pré-chargée pour qu'elle soit dispo synchrone partout dès le
  // premier frame (About, Réglages, etc.).
  unawaited(DeviceIdentity.instance.preload());

  // Provisioning à distance : si une URL est déjà configurée,
  // RemoteConfigRepository va fetch + appliquer les playlists du
  // serveur, puis re-fetcher toutes les 30 min en tâche de fond.
  unawaited(RemoteConfigRepository.instance.initialize());

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
          title: BrandStrings.appName,
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
  }

  @override
  Widget build(BuildContext context) {
    if (_onboardingDone == null) {
      return const _Splash();
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

    // 3) Home — version TV ou téléphone selon le choix utilisateur.
    //    On re-watche le repo pour qu'un changement dans Réglages
    //    (futur) bascule immédiatement le layout.
    return ListenableBuilder(
      listenable: DeviceClassRepository.instance,
      builder: (BuildContext context, _) {
        final bool isTv =
            DeviceClassRepository.instance.isTvFor(context);
        return isTv ? const TvHomeScreen() : const HomeScreen();
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
    return const Scaffold(
      backgroundColor: AppColors.voidSurface,
      body: Center(
        child: BrandLogo.splash(),
      ),
    );
  }
}
