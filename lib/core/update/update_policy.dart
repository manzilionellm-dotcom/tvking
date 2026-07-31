// =========================================================
//  update_policy.dart — ANTI-HARCÈLEMENT des mises à jour (pur, testé)
// =========================================================
//  Problème terrain (2026-07-31) : « je viens d'installer l'app, et une
//  heure après on me fait encore installer une autre ». L'auto-MAJ ne
//  connaissait qu'un cooldown PAR VERSION : chaque nouvelle publication
//  (ou un manifeste-appât) relançait l'installateur système aussitôt.
//
//  Règles (auto-MAJ uniquement — le bouton manuel des Réglages reste
//  un geste volontaire, jamais filtré) :
//    1. GRÂCE D'INSTALLATION : pendant [freshInstallGrace] après la
//       première ouverture d'un build fraîchement installé, on ne
//       propose RIEN. Celui qui vient d'installer est tranquille.
//    2. UNE PROPOSITION PAR [proposalGap] MAXI, toutes versions
//       confondues : publier 5 builds dans la journée ne génère qu'UNE
//       proposition. (Avant : « une version encore plus récente lève le
//       silence » → harcèlement en période de publication intense.)
//    3. MÊME VERSION : jamais reproposée avant [sameVersionCooldown]
//       (le client a déjà vu l'installateur pour elle).
//    4. `mandatory` (correctif critique, décidé côté serveur) perce la
//       grâce et l'espacement — mais pas la règle 3 (pas de boucle
//       d'installateur même pour un correctif critique).
//
//  Décision 100 % PURE (aucun I/O) → testée unitairement. La lecture/
//  écriture des horodatages vit dans UpdateService.
// =========================================================

class UpdatePolicy {
  UpdatePolicy._();

  /// Après une installation fraîche (premier lancement d'un nouveau
  /// build), silence total de l'auto-MAJ pendant cette durée.
  static const Duration freshInstallGrace = Duration(hours: 12);

  /// Espacement minimal entre deux propositions automatiques, TOUTES
  /// versions confondues : au pire une seule sollicitation par jour.
  static const Duration proposalGap = Duration(hours: 24);

  /// Une version déjà proposée (installateur ouvert) n'est jamais
  /// reproposée avant ce délai — même un correctif critique.
  static const Duration sameVersionCooldown = Duration(hours: 24);

  /// Faut-il proposer automatiquement [versionCode] maintenant ?
  ///   [lastLaunchedCode]/[lastLaunchedAtMs] : dernier installateur ouvert.
  ///   [lastProposalAtMs] : dernière proposition auto (toutes versions).
  ///   [firstRunAtMs]     : première ouverture du build INSTALLÉ (0 = inconnu
  ///                        → pas de grâce, on ne bloque pas une vraie MAJ).
  static bool shouldPropose({
    required bool mandatory,
    required int versionCode,
    required int nowMs,
    int? lastLaunchedCode,
    int? lastLaunchedAtMs,
    int? lastProposalAtMs,
    int firstRunAtMs = 0,
  }) {
    // Règle 3 — même version trop récemment proposée : silence, même
    // pour un correctif critique (sinon boucle d'installateur).
    if (lastLaunchedCode == versionCode &&
        lastLaunchedAtMs != null &&
        nowMs - lastLaunchedAtMs < sameVersionCooldown.inMilliseconds) {
      return false;
    }
    // Règle 4 — un correctif critique perce grâce et espacement.
    if (mandatory) return true;
    // Règle 1 — grâce après installation fraîche.
    if (firstRunAtMs > 0 &&
        nowMs - firstRunAtMs < freshInstallGrace.inMilliseconds) {
      return false;
    }
    // Règle 2 — au plus une proposition par [proposalGap].
    if (lastProposalAtMs != null &&
        nowMs - lastProposalAtMs < proposalGap.inMilliseconds) {
      return false;
    }
    return true;
  }
}
