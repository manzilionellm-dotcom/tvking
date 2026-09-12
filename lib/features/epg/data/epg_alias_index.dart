// =========================================================
//  epg_alias_index.dart — Pont EPG 1:N (pur, sans I/O)
// =========================================================
//  POURQUOI (Vague 4). L'ancien pont était une Map last-write-wins :
//  20 variantes « TF1 HD / TF1 FHD / TF1 RAW » partageant
//  `epg_channel_id = TF1.fr` → UNE seule ligne dans `epg_aliases`.
//  Un programme XMLTV n'allait donc QUE sur la dernière chaîne
//  vue. TiviMate, lui, pose le même guide sur TOUTES les variantes.
//
//  Ici : un id EPG normalisé → LISTE de Channel.id. Aucune base,
//  aucun réseau — testable en mémoire. La persistance SQLite
//  (table `epg_aliases`, PK composite) est l'affaire du repository.
// =========================================================

import 'epg_id.dart';

/// Index mémoire `id EPG normalisé → Channel.id` (plusieurs chaînes).
class EpgAliasIndex {
  EpgAliasIndex();

  /// Clef = [EpgId.normalize], valeur = Channel.id uniques, ordre d'ajout.
  final Map<String, List<String>> _byNorm = <String, List<String>>{};

  /// Chaînes vues SANS `epg_channel_id` (fournisseur muet → pas d'alias).
  /// Compteur seulement : on n'invente pas d'id à partir du nom
  /// (trop de collisions « TF1 HD » / « TF1 +1 »).
  int emptyEpgIdCount = 0;

  /// Nombre de paires (epg_id, channel_id) — c'est « #aliases en table ».
  int get pairCount {
    int n = 0;
    for (final List<String> v in _byNorm.values) {
      n += v.length;
    }
    return n;
  }

  /// Nombre d'ids EPG distincts (après normalisation).
  int get keyCount => _byNorm.length;

  bool get isEmpty => _byNorm.isEmpty;

  /// Ajoute une correspondance. [epgId] vide → incrémente
  /// [emptyEpgIdCount] et n'écrit rien (cause mesurée : pas d'alias).
  /// Doublon (même paire) → ignoré. Plafond : l'appelant borne.
  void add(String epgId, String channelId) {
    final String ch = channelId.trim();
    if (ch.isEmpty) return;
    final String norm = EpgId.normalize(epgId);
    if (norm.isEmpty) {
      emptyEpgIdCount++;
      return;
    }
    final List<String> list = _byNorm.putIfAbsent(norm, () => <String>[]);
    if (!list.contains(ch)) list.add(ch);
  }

  /// Enregistre qu'une chaîne n'avait pas d'`epg_channel_id` (sans
  /// passer par [add] avec une chaîne vide — plus lisible à l'appel).
  void recordEmpty() => emptyEpgIdCount++;

  /// Channel.id qui doivent recevoir le programme XMLTV [xmltvId].
  /// Liste vide = inconnu (le filtre skipPredicate l'aura déjà écarté
  /// si on a fusionné l'index dans `known`).
  List<String> lookup(String xmltvId) {
    final String norm = EpgId.normalize(xmltvId);
    if (norm.isEmpty) return const <String>[];
    return List<String>.unmodifiable(_byNorm[norm] ?? const <String>[]);
  }

  /// Copie défensive id normalisé → Channel.id (pour SQLite / tests).
  Map<String, List<String>> toMap() {
    return <String, List<String>>{
      for (final MapEntry<String, List<String>> e in _byNorm.entries)
        e.key: List<String>.from(e.value),
    };
  }

  /// Reconstruit un index depuis une Map (clés brutes OU déjà normalisées).
  factory EpgAliasIndex.fromMap(Map<String, List<String>> raw) {
    final EpgAliasIndex idx = EpgAliasIndex();
    for (final MapEntry<String, List<String>> e in raw.entries) {
      for (final String ch in e.value) {
        idx.add(e.key, ch);
      }
    }
    return idx;
  }

  /// Chaque Channel.id connu est aussi joignable via SA propre forme
  /// normalisée (M3U : `tvg-id` = Channel.id, XMLTV « tf1.fr » ≠ « TF1.fr »).
  /// N'élargit JAMAIS au-delà de [known] — pas d'alias orphelin.
  void addSelfAliases(Iterable<String> knownChannelIds) {
    for (final String id in knownChannelIds) {
      add(id, id);
    }
  }

  // ============================================================
  //  FILTRE PARSEUR + REMAP (le cœur du pont)
  // ============================================================

  /// Élargit le filtre XMLTV : ids de chaînes + formes normalisées +
  /// ids EPG dont AU MOINS une chaîne est dans [known].
  ///
  /// `known == null` = pas de filtre (on garde tout) → on renvoie null.
  /// Jamais d'élargissement sauvage : un alias dont la chaîne n'est
  /// pas dans le bouquet est ignoré (même règle qu'avant Vague 4).
  static Set<String>? mergeKnown(
    Set<String>? known,
    EpgAliasIndex aliases,
  ) {
    if (known == null) return null;
    if (known.isEmpty && aliases.isEmpty) return known;
    final Set<String> out = <String>{};
    for (final String id in known) {
      out.add(id);
      final String n = EpgId.normalize(id);
      if (n.isNotEmpty) out.add(n);
    }
    for (final MapEntry<String, List<String>> e in aliases._byNorm.entries) {
      if (e.value.any(known.contains)) {
        out.add(e.key);
      }
    }
    return out;
  }

  /// True si l'id XMLTV [channelId] n'est PAS dans [known] (exact OU
  /// normalisé). `known == null` → on ne saute jamais (pas de filtre).
  static bool isUnknown(String channelId, Set<String>? known) {
    if (known == null) return false;
    if (known.contains(channelId)) return false;
    final String n = EpgId.normalize(channelId);
    return n.isEmpty || !known.contains(n);
  }

  /// Un programme XMLTV → UNE LIGNE PAR variante Channel.
  ///
  /// Si l'index ne connaît pas l'id, on garde la ligne telle quelle
  /// (M3U déjà canonique, ou id hors pont — le filtre l'a accepté).
  List<Map<String, Object?>> expandRow(Map<String, Object?> row) {
    final String raw = row['channel_id']?.toString() ?? '';
    final List<String> targets = lookup(raw);
    if (targets.isEmpty) return <Map<String, Object?>>[row];
    if (targets.length == 1 && targets.first == raw) {
      return <Map<String, Object?>>[row];
    }
    return <Map<String, Object?>>[
      for (final String ch in targets) <String, Object?>{...row, 'channel_id': ch},
    ];
  }
}
