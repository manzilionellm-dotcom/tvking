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
import 'package:media_kit/media_kit.dart';

import 'core/branding/brand_logo.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_repository.dart';
import 'features/about/data/update_checker.dart';
import 'features/cast/data/cast_manager.dart';
import 'features/channels/data/recently_watched_repository.dart';
import 'features/channels/presentation/home_screen.dart';
import 'features/device/data/device_identity.dart';
import 'features/device/data/remote_config_repository.dart';
import 'features/epg/data/epg_repository.dart';
import 'features/onboarding/data/onboarding_state.dart';
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

  // Pré-warm du cast : 1er scan SSDP 2s après le boot, puis re-scan
  // toutes les 60s en tâche de fond. Conséquence : dès que l'utilisateur
  // tape l'icône Cast, la liste des TVs apparaît instantanément — c'est
  // ce qui rend l'expérience "fluide comme YouTube".
  CastManager.instance.startWarmup();

  // Choix Cinema / Daylight / System — chargé avant runApp pour
  // éviter un flash de mauvais thème au démarrage.
  await ThemeModeRepository.instance.initialize();

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
      listenable: ThemeModeRepository.instance,
      builder: (BuildContext context, _) {
        return MaterialApp(
          title: BrandStrings.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.daylight,
          darkTheme: AppTheme.cinema,
          themeMode: ThemeModeRepository.instance.mode,
          home: const _AppEntry(),
        );
      },
    );
  }
}

/// Décide quel écran montrer en premier :
///   - Si onboarding pas encore complété → OnboardingScreen
///   - Sinon → HomeScreen
class _AppEntry extends StatefulWidget {
  const _AppEntry();

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  bool? _onboardingDone;

  @override
  void initState() {
    super.initState();
    OnboardingState.instance.hasCompleted().then((bool done) {
      if (mounted) setState(() => _onboardingDone = done);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_onboardingDone == null) {
      // Splash très court pendant qu'on lit SharedPreferences
      return const _Splash();
    }
    if (_onboardingDone == false) {
      return OnboardingScreen(
        onDone: () => setState(() => _onboardingDone = true),
      );
    }
    return const HomeScreen();
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
