// =========================================================
//  main.dart — Point d'entrée unique de l'application
// =========================================================
//  1. Initialise les bindings Flutter
//  2. Initialise le PlaylistRepository (qui charge depuis SQLite
//     les playlists et chaînes déjà persistées)
//  3. Force la statut/nav bar en transparent
//  4. Lance MaterialApp
// =========================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'core/theme/app_theme.dart';
import 'features/channels/presentation/home_screen.dart';
import 'features/playlists/data/favorites_repository.dart';
import 'features/playlists/data/playlist_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise libmpv pour la lecture vidéo (Phase 1.3).
  // À appeler AVANT runApp, sinon la 1ʳᵉ ouverture d'un flux
  // génère un crash natif.
  MediaKit.ensureInitialized();

  // Statut bar et nav bar transparentes pour que notre dégradé
  // s'étende jusqu'aux bords de l'écran.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialise les repositories (ouvre la base SQLite + émettent
  // l'état courant). Fait en parallèle du build du widget tree
  // pour ne pas bloquer le first frame ; HomeScreen recevra les
  // chaînes via les Streams.
  unawaited(PlaylistRepository.instance.initialize());
  unawaited(FavoritesRepository.instance.initialize());

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
      home: const HomeScreen(),
    );
  }
}
