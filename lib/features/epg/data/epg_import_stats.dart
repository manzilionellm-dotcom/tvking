// =========================================================
//  epg_import_stats.dart — Compteurs d'un import XMLTV
// =========================================================
//  POURQUOI (Vague 4). La boîte noire montrait « 12 / 900 » sans
//  dire POURQUOI. Le support ne pouvait pas trancher :
//    • fournisseur (XMLTV ne couvre que 12 chaînes)
//    • pont (0 alias, ou alias 1:1 last-write-wins)
//    • filtre (skipPredicate silencieux : id inconnu / hors fenêtre)
//  Ces compteurs + le texte [whyFr] ferment ce trou. Purs, testés
//  sans réseau. La fenêtre temps (~48 h) reste un FILTRE, pas un
//  plafond mémoire à monter.
// =========================================================

/// Compteurs produits par le parseur (une passe, zéro I/O).
class EpgParseStats {
  const EpgParseStats({
    required this.emitted,
    required this.xmltvChannelIdsSeen,
    required this.skippedUnknownId,
    required this.skippedOutsideWindow,
    required this.skippedInvalid,
  });

  static const EpgParseStats empty = EpgParseStats(
    emitted: 0,
    xmltvChannelIdsSeen: 0,
    skippedUnknownId: 0,
    skippedOutsideWindow: 0,
    skippedInvalid: 0,
  );

  /// Programmes RETENUS (émis vers SQLite) — l'ancien `total`.
  final int emitted;

  /// IDs `channel="…"` DISTINCTS vus dans le XMLTV (retenus + sautés).
  final int xmltvChannelIdsSeen;

  /// Sautés : id absent du filtre (pont trop mince OU fournisseur
  /// qui parle d'une chaîne hors bouquet).
  final int skippedUnknownId;

  /// Sautés : hors fenêtre (~1 h passé / ~48 h futur).
  final int skippedOutsideWindow;

  /// Sautés : programme XML mal formé (pas de titre, dates absentes).
  final int skippedInvalid;

  int get skippedTotal =>
      skippedUnknownId + skippedOutsideWindow + skippedInvalid;

  Map<String, Object?> toMap() => <String, Object?>{
        'emitted': emitted,
        'xmltvSeen': xmltvChannelIdsSeen,
        'skipUnknown': skippedUnknownId,
        'skipWindow': skippedOutsideWindow,
        'skipInvalid': skippedInvalid,
      };

  factory EpgParseStats.fromMap(Map<String, Object?> m) {
    int n(String k) => (m[k] as int?) ?? 0;
    return EpgParseStats(
      emitted: n('emitted'),
      xmltvChannelIdsSeen: n('xmltvSeen'),
      skippedUnknownId: n('skipUnknown'),
      skippedOutsideWindow: n('skipWindow'),
      skippedInvalid: n('skipInvalid'),
    );
  }
}

/// Rapport persisté (boîte noire + `epg.import_ok`) après un import.
class EpgImportReport {
  const EpgImportReport({
    required this.aliasCount,
    required this.xmltvChannelIdsSeen,
    required this.retained,
    required this.skippedUnknownId,
    required this.skippedOutsideWindow,
    required this.skippedInvalid,
    required this.coveredChannelCount,
    required this.knownChannelCount,
    required this.emptyEpgChannelIdCount,
    required this.whyFr,
  });

  /// Lignes dans `epg_aliases` (paires epg_id × channel_id).
  final int aliasCount;

  final int xmltvChannelIdsSeen;
  final int retained;
  final int skippedUnknownId;
  final int skippedOutsideWindow;
  final int skippedInvalid;

  /// DISTINCT channel_id en base APRÈS insert (déjà exposé).
  final int coveredChannelCount;

  /// Taille du filtre `knownChannelIds` (le dénominateur du 12/900).
  final int knownChannelCount;

  /// Chaînes Xtream/M3U vues sans `epg_channel_id` / `tvg-id` au
  /// dernier `saveAliases` — le pont ne peut rien inventer.
  final int emptyEpgChannelIdCount;

  /// Phrase FR pour le support : fournisseur vs pont vs filtre.
  final String whyFr;

  Map<String, Object?> toMap() => <String, Object?>{
        'aliasCount': aliasCount,
        'xmltvSeen': xmltvChannelIdsSeen,
        'retained': retained,
        'skipUnknown': skippedUnknownId,
        'skipWindow': skippedOutsideWindow,
        'skipInvalid': skippedInvalid,
        'covered': coveredChannelCount,
        'known': knownChannelCount,
        'emptyEpgId': emptyEpgChannelIdCount,
        'whyFr': whyFr,
      };

  factory EpgImportReport.fromMap(Map<String, Object?> m) {
    int n(String k) => (m[k] as int?) ?? 0;
    return EpgImportReport(
      aliasCount: n('aliasCount'),
      xmltvChannelIdsSeen: n('xmltvSeen'),
      retained: n('retained'),
      skippedUnknownId: n('skipUnknown'),
      skippedOutsideWindow: n('skipWindow'),
      skippedInvalid: n('skipInvalid'),
      coveredChannelCount: n('covered'),
      knownChannelCount: n('known'),
      emptyEpgChannelIdCount: n('emptyEpgId'),
      whyFr: (m['whyFr'] as String?) ?? '',
    );
  }
}

/// Construit le POURQUOI en français. Pure : les chiffres parlent,
/// on ne devine pas au-delà de ce qu'ils permettent.
///
/// Ordre des règles = chaîne de causalité (comme le diagnostic
/// lecture de la boîte noire) : d'abord « pas de données », ensuite
/// le pont, ensuite le fournisseur, ensuite le filtre temps.
String explainEpgCoverage({
  required int aliasCount,
  required int xmltvChannelIdsSeen,
  required int retained,
  required int skippedUnknownId,
  required int skippedOutsideWindow,
  required int coveredChannelCount,
  required int knownChannelCount,
  required int emptyEpgChannelIdCount,
}) {
  if (knownChannelCount <= 0 && xmltvChannelIdsSeen <= 0 && retained <= 0) {
    return 'Pas encore de sync EPG mesurée — relancer un ajout/refresh '
        'de source ou attendre le resync (toutes les ~12 h).';
  }
  if (xmltvChannelIdsSeen == 0 && retained == 0) {
    return 'Fournisseur : le XMLTV n\'a fourni aucun id de chaîne '
        '(fichier vide, URL morte, ou parse à 0). '
        'Ce n\'est pas le pont.';
  }
  if (aliasCount == 0 &&
      emptyEpgChannelIdCount > 0 &&
      skippedUnknownId > 0) {
    return 'Pont vide : $emptyEpgChannelIdCount chaîne(s) sans '
        'epg_channel_id (le fournisseur ne les a pas étiquetées) '
        'et $skippedUnknownId programme(s) sautés (id inconnu). '
        'Le XMLTV parle, le pont n\'a rien à apparier.';
  }
  if (aliasCount == 0 && skippedUnknownId > retained) {
    return 'Pont vide : 0 alias en table, $skippedUnknownId programme(s) '
        'sautés (id inconnu) pour $xmltvChannelIdsSeen id(s) XMLTV vus. '
        'Cause typique : resync/M3U sans saveAliases, ou matching '
        'exact d\'avant Vague 4. Relancer un refresh de la source.';
  }
  if (knownChannelCount > 0 &&
      coveredChannelCount > 0 &&
      coveredChannelCount * 10 < knownChannelCount &&
      xmltvChannelIdsSeen > 0 &&
      xmltvChannelIdsSeen * 5 < knownChannelCount &&
      skippedUnknownId < xmltvChannelIdsSeen) {
    return 'Fournisseur : le XMLTV ne couvre que $xmltvChannelIdsSeen '
        'id(s) pour $knownChannelCount chaîne(s) du bouquet '
        '($coveredChannelCount avec guide). Le pont a $aliasCount '
        'alias — ce n\'est pas lui le goulot.';
  }
  if (skippedUnknownId > retained && xmltvChannelIdsSeen > 0) {
    return 'Filtre / pont : $skippedUnknownId programme(s) sautés '
        '(id inconnu) vs $retained retenu(s). '
        '${aliasCount} alias en table, $xmltvChannelIdsSeen id(s) '
        'XMLTV vus'
        '${emptyEpgChannelIdCount > 0 ? ', $emptyEpgChannelIdCount chaîne(s) sans epg_channel_id' : ''}. '
        'Soit le pont rate encore des variantes, soit le XMLTV '
        'parle d\'ids hors bouquet.';
  }
  if (retained == 0 && skippedOutsideWindow > 0 && skippedUnknownId == 0) {
    return 'Filtre temps : $skippedOutsideWindow programme(s) hors '
        'fenêtre (~48 h). Le pont a reconnu les ids — on n\'importe '
        'pas 7 jours sur $knownChannelCount chaînes (Firestick 1 Go).';
  }
  if (knownChannelCount > 0 &&
      coveredChannelCount >= knownChannelCount) {
    return 'OK : le guide couvre $coveredChannelCount / $knownChannelCount '
        'chaîne(s). $aliasCount alias, $xmltvChannelIdsSeen id(s) XMLTV.';
  }
  if (knownChannelCount > 0 && coveredChannelCount > 0) {
    return 'Couverture $coveredChannelCount / $knownChannelCount. '
        'Pont : $aliasCount alias. XMLTV : $xmltvChannelIdsSeen id(s) vus, '
        '$retained retenu(s), $skippedUnknownId sauté(s) (id inconnu), '
        '$skippedOutsideWindow hors fenêtre'
        '${emptyEpgChannelIdCount > 0 ? ', $emptyEpgChannelIdCount sans epg_channel_id' : ''}.';
  }
  return 'Import : $retained retenu(s), $skippedUnknownId id inconnu, '
      '$skippedOutsideWindow hors fenêtre, $xmltvChannelIdsSeen id(s) '
      'XMLTV, $aliasCount alias.';
}
