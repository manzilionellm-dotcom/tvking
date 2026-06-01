// =========================================================
//  flavor.dart — Aiguillage produit 7 MOTION / Red Room
// =========================================================
//  Le repo héberge DEUX produits qui partagent le même code :
//
//    - 7 MOTION  : lecteur IPTV premium, toutes catégories,
//                  biométrie OPTIONNELLE, pas de gate âge.
//    - Red Room  : lecteur adulte premium, UNIQUEMENT le
//                  contenu 18+, biométrie OBLIGATOIRE,
//                  modal "j'ai 18+" au 1er lancement.
//
//  Plutôt que de forker le repo (double maintenance garantie
//  + drift en 3 mois), on garde UN seul codebase avec deux
//  entrypoints `main.dart` (7 MOTION) et `main_redroom.dart`
//  (Red Room). Chacun initialise [FlavorConfig] avant `runApp`
//  et toute l'app lit ses paramètres via `FlavorConfig.current`.
//
//  Règle d'or : aucune `if (kReleaseMode)` ou autre détection
//  implicite. Le flavor est explicite, posé une fois au boot,
//  et il NE BOUGE PLUS jusqu'à la mort du processus.
//
//  Côté CI, on compile deux APKs :
//    flutter build apk -t lib/main.dart           → 7motion.apk
//    flutter build apk -t lib/main_redroom.dart   → redroom.apk
//  avec deux applicationId différents (cf. workflow Android).
// =========================================================

import 'package:flutter/foundation.dart';

/// Identité du produit lancé.
enum Flavor {
  sevenMotion,
  redRoom,
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
  ///   - 7 MOTION  → "7 MOTION"
  ///   - Red Room  → "Red Room"
  final String appName;

  /// Tagline courte affichée sous le wordmark sur le splash et
  /// les écrans vitrine.
  ///   - 7 MOTION  → "THE FEW · NOT FOR EVERYONE"
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
  /// Si un jour 7 MOTION et Red Room ont des serveurs differents,
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
        'Vérifie que main()/main_redroom() appelle '
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

  /// 7 MOTION — lecteur IPTV premium grand public.
  static const FlavorConfig sevenMotion = FlavorConfig(
    flavor: Flavor.sevenMotion,
    appName: '7 MOTION',
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

  /// Red Room — variante adulte stricte.
  ///
  /// Choix utilisateur post-test : on a desactive `biometricMandatory`.
  /// La premiere version forcait la biometrie a chaque cold start,
  /// mais sur les telephones sans verrouillage d'ecran configure cote
  /// OS, l'utilisateur se retrouvait bloque sans pouvoir entrer.
  /// L'age gate "j'ai 18+" reste obligatoire (legal minimum), et
  /// l'utilisateur peut toujours activer un verrou bio + PIN manuelle-
  /// ment via Reglages > Securite s'il le souhaite.
  ///
  /// Serveur IPTV : meme URL que 7 MOTION pour l'instant (decision
  /// utilisateur "un seul serveur partage"). Si on veut splitter
  /// adulte / grand public sur des serveurs differents plus tard,
  /// il suffit de changer cette ligne — aucune autre modif d'app.
  static const FlavorConfig redRoom = FlavorConfig(
    flavor: Flavor.redRoom,
    appName: 'Red Room',
    appTagline: 'STRICTLY 18+ · AFTER HOURS',
    adultOnly: true,
    biometricMandatory: false,
    requireAgeGate: true,
    // Idem 7 MOTION : bascule 2026-06-01 vers le nouveau revendeur.
    iptvServerUrl: 'http://yzrgxcat.getpremiumiptv.fr',
  );
}
