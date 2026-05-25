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

import 'core/theme/app_theme.dart';
import 'features/about/data/update_checker.dart';
import 'features/channels/data/recently_watched_repository.dart';
import 'features/channels/presentation/home_screen.dart';
import 'features/onboarding/data/onboarding_state.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/player/data/player_settings.dart';
import 'features/playlists/data/favorites_repository.dart';
import 'features/playlists/data/playlist_repository.dart';

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
  unawaited(PlayerSettings.instance.load());

  // Update checker — silencieux en arrière-plan. Le résultat est lu
  // par AboutScreen / un toast plus tard.
  unawaited(UpdateChecker.instance.check());

  runApp(const TvKingApp());
}

class TvKingApp extends StatelessWidget {
  const TvKingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TV King',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const _AppEntry(),
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

/// Splash minimal — apparaît max 50 ms le temps que le flag
/// onboarding soit lu depuis SharedPreferences.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1216),
      body: Center(
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: const Color(0xFFFFCB05),
            borderRadius: BorderRadius.circular(22),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFFFFCB05).withValues(alpha: 0.4),
                blurRadius: 32,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Icon(
            Icons.live_tv_rounded,
            color: Colors.black,
            size: 56,
          ),
        ),
      ),
    );
  }
}
