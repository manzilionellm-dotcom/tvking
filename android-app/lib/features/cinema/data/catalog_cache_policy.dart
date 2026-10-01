// =========================================================
//  catalog_cache_policy.dart — Règles du cache catalogue
// =========================================================
//  Fonctions PURES (pas de disque, pas de réseau, pas de widget).
//  Elles décident :
//    • quand une nouvelle liste a le droit de REMPLACER l'ancienne ;
//    • combien de temps attendre avant un nouvel essai ;
//    • comment dire « mis à jour il y a X » ;
//    • quoi montrer si le serveur renvoie vide ou plante.
//
//  Tout est testé dans test/features/cinema/catalog_cache_test.dart.
//  Le disque et le téléchargement appliquent ces règles, ils ne les
//  réinventent pas.
// =========================================================

/// Version du fichier sur la box. Un fichier d'une autre version est
/// ignoré (on ne l'efface pas : on ne comprend pas son contenu).
const int kCatalogFormatVersion = 1;

/// Taille max du catalogue films OU séries sur le disque (octets).
/// Au-delà, on garde l'ancien catalogue plutôt que d'écrire un morceau.
const int kCatalogMaxBytes = 48 * 1024 * 1024;

/// Résumé d'une fiche : on ne garde pas un roman entier sur la box.
const int kCatalogPlotMax = 400;

/// Pause entre deux catégories, pour ne pas saturer la box ni le serveur.
const Duration kCatalogChunkGap = Duration(milliseconds: 400);

/// Base du délai entre deux essais (1,5 s, puis 3 s, 6 s…).
const int kCatalogBackoffBaseMs = 1500;

/// Plafond du délai : 2 minutes. Au-delà, attendre plus ne change rien
/// pour le client, et un retour au catalogue déjà enregistré suffit.
const int kCatalogBackoffCapMs = 120000;

/// Unités de la phrase « mis à jour il y a … ».
enum CatalogAgeUnit { justNow, minutes, hours, days }

/// Âge d'un catalogue, prêt à être traduit par l'écran.
class CatalogAge {
  const CatalogAge(this.unit, this.amount);
  final CatalogAgeUnit unit;

  /// 0 pour [CatalogAgeUnit.justNow]. Sinon le nombre de minutes, d'heures
  /// ou de jours (toujours au moins 1).
  final int amount;
}

/// « Mis à jour il y a X », sans texte : l'écran choisit la langue.
CatalogAge catalogAge(DateTime updatedAt, DateTime now) {
  final Duration d = now.difference(updatedAt);
  if (d.isNegative || d.inSeconds < 45) {
    return const CatalogAge(CatalogAgeUnit.justNow, 0);
  }
  if (d.inMinutes < 60) {
    final int minutes = d.inMinutes < 1 ? 1 : d.inMinutes;
    return CatalogAge(CatalogAgeUnit.minutes, minutes);
  }
  if (d.inHours < 48) {
    final int hours = d.inHours < 1 ? 1 : d.inHours;
    return CatalogAge(CatalogAgeUnit.hours, hours);
  }
  final int days = d.inDays < 1 ? 1 : d.inDays;
  return CatalogAge(CatalogAgeUnit.days, days);
}

/// Délai avant le prochain essai.
///
/// [attempt] commence à 1 (premier échec → premier délai).
/// Chaque essai double le délai, jusqu'au plafond.
/// [jitterPermille] vaut de 0 à 1000 et AJOUTE jusqu'à 30 % du délai :
/// deux box qui ratent en même temps ne retapent pas le serveur à la
/// même seconde.
Duration catalogBackoff({
  required int attempt,
  required int jitterPermille,
}) {
  if (attempt < 1) {
    throw ArgumentError.value(attempt, 'attempt', 'commence à 1');
  }
  final int shift = (attempt - 1) > 8 ? 8 : (attempt - 1);
  int ms = kCatalogBackoffBaseMs * (1 << shift);
  if (ms > kCatalogBackoffCapMs) ms = kCatalogBackoffCapMs;
  int permille = jitterPermille;
  if (permille < 0) permille = 0;
  if (permille > 1000) permille = 1000;
  final int jitter = (ms * permille * 3) ~/ 10000;
  return Duration(milliseconds: ms + jitter);
}

/// Est-ce qu'on a le droit d'afficher CE catalogue à la place de l'ancien ?
///
/// Non si :
///   • le fichier n'est pas de la version qu'on sait lire ;
///   • le téléchargement n'est pas allé au bout (liste partielle) ;
///   • une catégorie annoncée n'a pas de fichier ;
///   • il n'y a aucune catégorie, ou aucun titre.
///
/// Une réponse vide ne remplace JAMAIS un catalogue déjà rempli :
/// [titleCount] à 0 est refusé, que l'ancien compte soit 0 ou 40 000.
/// S'il n'y avait rien avant non plus, on n'enregistre pas un catalogue
/// vide : l'écran dira « indisponible » et proposera Réessayer, au lieu
/// de figer « zéro film » sur la box.
bool shouldPublishCatalog({
  required int version,
  required bool complete,
  required int categoryCount,
  required int coveredCategories,
  required int titleCount,
}) {
  if (version != kCatalogFormatVersion) return false;
  if (!complete) return false;
  if (categoryCount <= 0) return false;
  if (coveredCategories != categoryCount) return false;
  if (titleCount <= 0) return false;
  return true;
}

/// Faut-il GARDER en mémoire une liste de catégories qu'on vient de
/// recevoir ?
///
/// Une liste non vide : oui.
/// Une liste vide alors que CHAQUE compte a répondu sans erreur : oui
/// (le serveur n'a vraiment pas de VOD — on ne le redemande pas en boucle
/// pendant cette ouverture).
/// Une liste vide à cause d'un délai dépassé ou d'une erreur : NON.
/// Sinon le prochain affichage croit que « c'est vide » et n'essaie plus.
bool rememberCategoryList({
  required int count,
  required bool anySuccess,
  required bool anyFailure,
}) {
  if (count > 0) return true;
  if (anySuccess && !anyFailure) return true;
  return false;
}

/// Une page de titres n'entre dans le cache mémoire que si le serveur
/// a RÉPONDU. Un échec ne doit pas être mémorisé comme « catégorie vide ».
bool shouldCacheTitlePage({required bool fetchFailed}) => !fetchFailed;

/// Choisit la liste de films à montrer.
///
/// [incoming] null = le serveur n'a pas répondu (erreur, délai).
/// Une réponse vide ou en erreur ne jette pas la liste précédente, ni
/// celle enregistrée sur la box.
List<T> keepPreviousWhenEmpty<T>({
  required List<T>? incoming,
  required List<T> previous,
  required List<T> disk,
}) {
  if (incoming != null && incoming.isNotEmpty) return incoming;
  if (previous.isNotEmpty) return previous;
  if (disk.isNotEmpty) return disk;
  return incoming ?? previous;
}
