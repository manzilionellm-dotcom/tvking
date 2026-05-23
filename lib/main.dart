// =========================================================
//  main.dart — Point d'entrée unique de l'application
// =========================================================
//  Toute app Flutter commence ici, dans `main()`.
//  Rôle de ce fichier :
//    1. Configurer ce qui doit l'être avant tout rendu
//       (orientation forcée, statut bar transparente, etc.).
//    2. Lancer le widget racine `TvKingApp`.
//
//  On garde ce fichier le plus court possible : toute la
//  logique vit dans des modules séparés (core/, features/).
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme/app_theme.dart';
import 'features/channels/presentation/home_screen.dart';

void main() {
  // On garantit que les bindings Flutter sont initialisés
  // avant d'appeler une API native (ici, SystemChrome).
  WidgetsFlutterBinding.ensureInitialized();

  // Statut bar / barre de navigation système transparentes :
  // notre gradient de fond couvre TOUT l'écran.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const TvKingApp());
}

/// Racine de l'application.
///
/// `MaterialApp` orchestre la navigation, le thème, la locale,
/// et instancie le Navigator. Pour la phase 1, on a un seul
/// écran (HomeScreen). On ajoutera GoRouter quand on aura
/// plusieurs routes.
class TvKingApp extends StatelessWidget {
  const TvKingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TV King',
      debugShowCheckedModeBanner: false, // pas de bandeau "DEBUG"
      theme: AppTheme.dark,
      home: const HomeScreen(),
    );
  }
}
