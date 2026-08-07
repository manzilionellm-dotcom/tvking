// =========================================================
//  force_update_checker.dart — Mise à jour forcée (pilotée panel)
// =========================================================
//  L'admin décide, depuis le panneau, quand TOUS les utilisateurs
//  doivent mettre à jour. Le serveur stocke un seuil `minBuildTs`
//  (en SECONDES, même unité que kBuildTs injecté au build).
//
//  Règle : l'app est obsolète si `kBuildTs < minBuildTs`.
//    - minBuildTs = 0 (défaut) → AUCUN blocage.
//    - Quand l'admin appuie sur « Forcer la mise à jour », le serveur
//      pose minBuildTs = dernier build connu → toutes les apps PLUS
//      ANCIENNES sont bloquées, mais PAS celles déjà sur le dernier build.
//
//  Bonus : on envoie notre propre kBuildTs en paramètre `?build=` →
//  le serveur mémorise le build le plus récent vu « dans la nature »,
//  ce qui permet au bouton du panel de savoir quoi exiger.
//
//  Unités : TOUT est en secondes epoch. (Le bug précédent comparait des
//  secondes à des millisecondes → blocage permanent. Plus jamais.)
//
//  Fail-open : toute erreur réseau → on ne bloque pas. Build local
//  (kBuildTs == 0) → on ne bloque jamais. Aucun lien avec le cast.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/app/app_platform.dart';
import '../../../core/app/build_info.dart';
import '../../../core/update/build_flags.dart';
import '../../subscription/data/subscription_backend.dart';

class ForceUpdateChecker {
  ForceUpdateChecker._();
  static final ForceUpdateChecker instance = ForceUpdateChecker._();

  /// Signal « le panel vient (peut-être) de changer le seuil » —
  /// incrémenté par le temps réel (RealtimeSyncService, `sync config`).
  /// L'écran d'entrée (_AppEntry) l'écoute et relance mustUpdate() :
  /// un « Forcer la mise à jour » du panel bloque les apps EN DIRECT,
  /// sans attendre leur prochain démarrage.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// À appeler quand le serveur signale un changement de config.
  void requestRecheck() => revision.value++;

  /// `true` si l'app installée doit être mise à jour de force.
  Future<bool> mustUpdate(
      {Duration timeout = const Duration(seconds: 6)}) async {
    // Play Store : la mise à jour forcée passe par le Store, pas par
    // le sideload GitHub. On ne déclenche jamais ce flux côté Play.
    if (kIsStoreBuild) return false;
    if (kBuildTs <= 0) return false; // build local → jamais bloquant
    try {
      final Uri uri = Uri.parse(
        '$kSubscriptionBaseUrl/api/app-version?build=$kBuildTs'
        '&platform=${AppPlatform.id}',
      );
      final http.Response resp = await http.get(uri).timeout(timeout);
      if (resp.statusCode != 200) return false;
      final Object? decoded = jsonDecode(resp.body);
      if (decoded is! Map) return false;
      final Object? raw = decoded['minBuildTs'];
      final int minBuildTs =
          raw is int ? raw : int.tryParse('${raw ?? 0}') ?? 0;
      // Obsolète UNIQUEMENT si l'admin a posé un seuil ET qu'on est avant.
      return minBuildTs > 0 && kBuildTs < minBuildTs;
    } catch (e) {
      if (kDebugMode) debugPrint('[ForceUpdate] $e');
      return false; // fail-open
    }
  }
}
