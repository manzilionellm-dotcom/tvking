// =========================================================
//  flavor.dart — Configuration produit BLACK7 ROYAL (mobile)
// =========================================================
//  Le projet ne contient plus qu'UN seul produit : l'application
//  MOBILE BLACK7 ROYAL (7 MOTION). Les anciennes variantes TV
//  (Android TV / Fire TV) et Red Room (édition adulte) ont été
//  retirées du projet.
//
//  [FlavorConfig] reste en place (un seul flavor `sevenMotion`) pour
//  centraliser le nom de l'app, sa tagline et l'URL serveur, et pour
//  ne pas casser les nombreux lecteurs de `FlavorConfig.current`.
//
//  Règle d'or : le flavor est explicite, posé une fois par `main()`
//  via `FlavorConfig.setCurrent(...)` AVANT `runApp`, et il NE BOUGE
//  PLUS jusqu'à la mort du processus.
//
//  Côté CI, on compile un seul APK :
//    flutter build apk -t lib/main.dart   → 7motion.apk
// =========================================================

import 'package:flutter/foundation.dart';

/// Identité du produit lancé. Le projet ne contient plus qu'un seul
/// produit : l'application mobile BLACK7 ROYAL (7 MOTION). Les variantes
/// TV et Red Room ont été retirées. L'enum est conservé (un seul membre)
/// pour ne pas casser les lecteurs de `FlavorConfig.current.flavor`.
enum Flavor {
  sevenMotion,
}

@immutable
class FlavorConfig {
  const FlavorConfig({
    required this.flavor,
    required this.appName,
    required this.appTagline,
    required this.adultOnly,
    required this.biometricMandatory,
    required this.requireAgeGate,
    required this.iptvServerUrl,
  });

  /// Identité technique du build (utile pour les analytics, le
  /// heartbeat backend, les logs).
  final Flavor flavor;

  /// Nom affiché à l'utilisateur (titre de l'app, barre, splash).
  ///   - BLACK7 ROYAL  → "BLACK7 ROYAL"
  ///   - Red Room  → "Red Room"
  final String appName;

  /// Tagline courte affichée sous le wordmark sur le splash et
  /// les écrans vitrine.
  ///   - BLACK7 ROYAL  → "THE FEW · NOT FOR EVERYONE"
  ///   - Red Room  → "STRICTLY 18+ · AFTER HOURS"
  final String appTagline;

  /// `true` → ne montre QUE les chaînes [ChannelGenre.adult].
  /// Le filtre est appliqué côté repository (point unique de
  /// lecture des chaînes), donc favoris / recherche / EPG /
  /// recommandations héritent automatiquement de la restriction.
  final bool adultOnly;

  /// `true` → l'authentification biométrique (empreinte / PIN
  /// système) est OBLIGATOIRE à chaque cold start, indépendamment
  /// du réglage utilisateur dans Réglages. L'écran de réglages
  /// masque même la case à cocher (qui est forcée à ON).
  final bool biometricMandatory;

  /// `true` → un modal "Vous devez avoir 18 ans ou plus" est
  /// affiché AU PREMIER lancement (puis le choix est mémorisé en
  /// SharedPreferences). Un refus = sortie de l'app.
  final bool requireAgeGate;

  /// URL du serveur Xtream Codes utilise PAR DEFAUT pour ce flavor.
  /// Cache au client (qui ne voit que les 2 champs identifiant /
  /// code secret) — c'est l'app qui fournit le serveur implicitement.
  /// Strategie revendeur : tous les clients de cette app pointent
  /// vers le meme serveur central, identifie par leurs credentials.
  /// Si un jour BLACK7 ROYAL et Red Room ont des serveurs differents,
  /// il suffit de changer cette ligne sur la variante concernee.
  final String iptvServerUrl;

  /// Configuration actuelle. Doit être posée par `main()` AVANT
  /// le premier `runApp(...)`. Si on lit sans avoir set, on a un
  /// `StateError` clair plutôt qu'un null deref dans 12 widgets.
  static FlavorConfig? _current;

  static FlavorConfig get current {
    final FlavorConfig? c = _current;
    if (c == null) {
      throw StateError(
        'FlavorConfig.current accédé avant initialisation. '
        'Vérifie que main() appelle '
        'FlavorConfig.setCurrent(...) avant runApp().',
      );
    }
    return c;
  }

  /// Pose le flavor courant. À appeler une seule fois par main() AVANT
  /// `bootApp()`. Nommé `setCurrent` (pas juste `set`) parce que `set`
  /// est ambigu en Dart avec les setters de propriété — la lisibilité
  /// prime sur la brièveté ici.
  static void setCurrent(FlavorConfig config) {
    _current = config;
    if (kDebugMode) {
      debugPrint('[Flavor] init → ${config.flavor.name} '
          '(${config.appName})');
    }
  }

  /// Helper pour les tests : remet à null entre 2 cas. Pas
  /// d'usage en production.
  @visibleForTesting
  static void resetForTesting() {
    _current = null;
  }

  // -------------------------------------------------------
  //  Configurations canoniques (utilisées par les mains)
  // -------------------------------------------------------

  /// BLACK7 ROYAL — lecteur IPTV premium grand public.
  static const FlavorConfig sevenMotion = FlavorConfig(
    flavor: Flavor.sevenMotion,
    appName: 'BLACK7 ROYAL',
    appTagline: 'THE FEW · NOT FOR EVERYONE',
    adultOnly: false,
    biometricMandatory: false,
    requireAgeGate: false,
    // 2026-06-01 : bascule depuis `pro.best-iptvinreviews.com`
    // (saturé en 458 + TTFB 50-77s, plantait login + cast) vers le
    // nouveau revendeur `yzrgxcat.getpremiumiptv.fr`. URL choisie
    // par l'utilisateur, credentials individuels saisis au login
    // (Identifiant + code secret) — pas hardcodes.
    iptvServerUrl: 'http://yzrgxcat.getpremiumiptv.fr',
  );
}
