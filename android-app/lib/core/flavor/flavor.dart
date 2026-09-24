// =========================================================
//  flavor.dart — Configuration produit The Few (mobile)
// =========================================================
//  Le projet ne contient plus qu'UN seul produit : l'application
//  MOBILE The Few (7 MOTION). Les anciennes variantes TV
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
/// produit : l'application mobile The Few (7 MOTION). Les variantes
/// TV et Red Room ont été retirées. L'enum est conservé (un seul membre)
/// pour ne pas casser les lecteurs de `FlavorConfig.current.flavor`.
enum Flavor {
  sevenMotion,
  // « Privé » — édition 18+ : MÊME app, mais nom/logo dédiés et
  // catalogue limité aux chaînes adultes (adultOnly = true).
  prive,
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
  });

  /// Identité technique du build (utile pour les analytics, le
  /// heartbeat backend, les logs).
  final Flavor flavor;

  /// Nom affiché à l'utilisateur (titre de l'app, barre, splash).
  ///   - The Few  → "The Few"
  ///   - Red Room  → "Red Room"
  final String appName;

  /// Tagline courte affichée sous le wordmark sur le splash et
  /// les écrans vitrine.
  ///   - The Few  → "THE FEW · NOT FOR EVERYONE"
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

  // NB (P1-10 / AGENTS.md règle n°2) : il N'Y A PLUS d'URL de serveur IPTV
  // en dur ici. Les URLs des serveurs « par défaut » vivent UNIQUEMENT côté
  // backend (variable `DEFAULT_SERVERS` / table D1 `default_servers`,
  // récupérées via `GET /api/servers`). Aucune URL de flux ni host revendeur
  // n'est commité dans l'app (dépôt public) — évite la fuite + le HTTP clair.

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

  /// The Few — lecteur IPTV premium grand public.
  static const FlavorConfig sevenMotion = FlavorConfig(
    flavor: Flavor.sevenMotion,
    appName: 'The Few',
    appTagline: 'NOT FOR EVERYONE',
    adultOnly: false,
    biometricMandatory: false,
    requireAgeGate: false,
    // Serveurs IPTV « par défaut » : fournis par le backend (GET /api/servers),
    // jamais en dur ici. Les identifiants individuels sont saisis au login.
  );

  /// Privé — édition 18+ « by invitation only ». MÊME app que The Few
  /// (même code, même backend, même lecteur), mais :
  ///   - nom/logo dédiés (« Privé »),
  ///   - `adultOnly` = true → SEULES les chaînes adultes (Live Adult /
  ///     Cinema Adult…) sont affichées (filtre au repository),
  ///   - portail d'âge (18+) au 1er lancement.
  static const FlavorConfig prive = FlavorConfig(
    flavor: Flavor.prive,
    appName: 'Privé',
    appTagline: '18+ · BY INVITATION ONLY',
    adultOnly: true,
    biometricMandatory: false,
    requireAgeGate: true,
    // Idem : aucun serveur IPTV en dur (cf. sevenMotion).
  );
}
