// =========================================================
//  smart_search.dart — Moteur de recherche intelligent
// =========================================================
//  Remplace le filtre naïf « substring » de l'écran de recherche
//  par un vrai moteur de pertinence, inspiré de ce que font les
//  meilleures apps de la niche IPTV (TiviMate, OTT Navigator) et
//  les plateformes grand public (Netflix, YouTube) :
//
//  1. MULTI-MOTS, ORDRE LIBRE — « bein 1 » trouve « beIN SPORTS 1 »,
//     « sport france » trouve « France Sport TV ». Chaque mot de la
//     requête doit matcher quelque part (logique ET), mais l'ordre
//     n'a aucune importance.
//
//  2. TOLÉRANCE AUX FAUTES — « netflx », « bein sprot » : distance
//     d'édition bornée (1 faute pour un mot de 4-6 lettres, 2 pour
//     7+). Les transpositions (« sprot » → « sport ») comptent pour
//     UNE seule faute (algorithme OSA, pas Levenshtein simple).
//
//  3. ACCENTS & DÉCORATIONS IGNORÉS — « cine » trouve « Ciné+ »,
//     les décorations IPTV (« ★ FR| TF1 ᴴᴰ ») ne polluent pas le
//     matching (on cherche sur le nom brut ET le nom curé).
//
//  4. CLASSEMENT PAR PERTINENCE — un mot entier vaut plus qu'un
//     préfixe, qui vaut plus qu'un bout de mot, qui vaut plus
//     qu'une correction de faute. Le nom vaut plus que la
//     catégorie. Le nom qui COMMENCE par la requête remonte.
//
//  5. PERSONNALISATION — les favoris, les chaînes récemment
//     regardées et le temps de visionnage réel (30 jours) boostent
//     le classement : l'app apprend ce que TU regardes. C'est le
//     signal n°1 identifié dans la niche (« les meilleurs systèmes
//     promeuvent automatiquement les chaînes réellement regardées »).
//
//  6. ANTI-DOUBLONS IPTV — les playlists contiennent 5-20 variantes
//     de la même chaîne (HD/FHD/4K/backup). Sans traitement, la
//     première page de résultats est 20 fois le même nom. Ici, les
//     variantes au-delà de la première (même nom curé) descendent
//     progressivement — la meilleure variante reste en tête, les
//     autres restent accessibles plus bas.
//
//  Performance : tout est en mémoire, zéro dépendance. Les textes
//  normalisés sont mémoïsés par id de chaîne (même stratégie que
//  _ChannelComputedCache dans channel.dart) : la normalisation ne
//  se paie qu'UNE fois par chaîne et par session. Sur 27 000
//  chaînes, une requête complète reste sous ~40 ms — compatible
//  avec le debounce 300 ms de l'écran.
// =========================================================

import 'dart:math' as math;

import '../domain/channel.dart';

/// Signaux de personnalisation injectés par l'écran de recherche.
/// Tous optionnels : sans signaux, le moteur classe uniquement par
/// pertinence textuelle (dégradation douce, jamais bloquant).
class SearchSignals {
  const SearchSignals({
    this.favoriteIds = const <String>{},
    this.recentIds = const <String>[],
    this.watchMsById = const <String, int>{},
  });

  /// IDs des chaînes favorites (FavoritesRepository).
  final Set<String> favoriteIds;

  /// IDs des chaînes récemment regardées, ordonnées de la plus
  /// récente à la plus ancienne (RecentlyWatchedRepository).
  final List<String> recentIds;

  /// Temps de visionnage cumulé (ms) par chaîne sur 30 jours
  /// (WatchHistoryRepository.watchTimeByChannel).
  final Map<String, int> watchMsById;

  /// Instance vide — aucun boost de personnalisation.
  static const SearchSignals none = SearchSignals();
}

/// Moteur de recherche. Tout est statique : pas d'état mutable en
/// dehors du cache de normalisation (mémoïsation pure).
abstract final class SmartSearch {
  // ------------------------------------------------------------
  //  Barème de pertinence textuelle (par mot de la requête).
  //  L'échelle est volontairement large pour que les bonus de
  //  personnalisation (max ~75) ne puissent pas faire remonter un
  //  résultat textuellement mauvais au-dessus d'un très bon match.
  // ------------------------------------------------------------
  static const int _kWordExact = 100; // mot entier identique
  static const int _kWordPrefix = 80; // début de mot
  static const int _kSubstring = 55; // bout de mot / dans le nom
  static const int _kFuzzyBase = 48; // faute corrigée (moins la distance)
  static const int _kFuzzyPerEdit = 10;
  static const int _kCategoryWordPrefix = 35; // match dans la catégorie
  static const int _kCategorySubstring = 28;

  // Bonus au niveau de la chaîne entière.
  //  Le plein-exact (80) dépasse le cumul maximal des bonus de
  //  personnalisation (~75) : si l'utilisateur tape EXACTEMENT le
  //  nom d'une chaîne, c'est elle qu'il veut — aucun favori
  //  approximatif ne doit passer devant.
  static const int _kFullExactBonus = 80; // nom == requête
  static const int _kStartsWithBonus = 24; // nom commence par la requête
  static const int _kFavoriteBonus = 30;
  static const int _kRecentMaxBonus = 22; // dégressif selon l'ancienneté
  static const int _kWatchTimeMaxBonus = 18; // proportionnel au visionnage
  static const int _kLogoBonus = 3; // départage les variantes sans logo

  // Anti-doublons : pénalité par variante supplémentaire du même
  // nom curé (la 1re variante n'est pas pénalisée).
  static const int _kDuplicatePenalty = 20;

  /// Nombre max de résultats retournés. Au-delà, la grille devient
  /// inutilisable de toute façon — mieux vaut inviter à préciser.
  static const int kDefaultLimit = 400;

  // ------------------------------------------------------------
  //  API principale
  // ------------------------------------------------------------

  /// Filtre et classe [pool] selon [query]. Retourne les chaînes
  /// par pertinence décroissante (au plus [limit]).
  static List<Channel> rank({
    required String query,
    required List<Channel> pool,
    SearchSignals signals = SearchSignals.none,
    int limit = kDefaultLimit,
  }) {
    final String queryNorm = normalize(query);
    final List<String> tokens = _tokenize(queryNorm);
    if (tokens.isEmpty || pool.isEmpty) return const <Channel>[];

    // --- Passe 1 : score textuel + bonus de personnalisation ---
    final List<_Scored> scored = <_Scored>[];
    // Rang de récence par id (0 = la plus récente) pour le bonus
    // dégressif — calculé une fois, pas par chaîne.
    final Map<String, int> recentRank = <String, int>{};
    for (int i = 0; i < signals.recentIds.length; i++) {
      recentRank.putIfAbsent(signals.recentIds[i], () => i);
    }
    // Le boost "temps de visionnage" est relatif au max observé :
    // pas de seuil magique en minutes.
    int maxWatchMs = 0;
    for (final int v in signals.watchMsById.values) {
      if (v > maxWatchMs) maxWatchMs = v;
    }

    for (final Channel c in pool) {
      final _SearchDoc doc = _docFor(c);
      final int text = _textScore(doc, tokens, queryNorm);
      if (text <= 0) continue; // un mot de la requête n'a rien trouvé
      int score = text;

      // ----- Personnalisation -----
      if (signals.favoriteIds.contains(c.id)) score += _kFavoriteBonus;
      final int? rRank = recentRank[c.id];
      if (rRank != null) {
        // 22, 20, 18… plancher à 6 : même une vieille entrée de
        // l'historique récent vaut mieux que rien.
        score += math.max(_kRecentMaxBonus - rRank * 2, 6);
      }
      final int watched = signals.watchMsById[c.id] ?? 0;
      if (watched > 0 && maxWatchMs > 0) {
        score += (_kWatchTimeMaxBonus * watched / maxWatchMs).round();
      }
      if (c.hasLogo) score += _kLogoBonus;
      score += _qualityBonus(c.quality);

      scored.add(_Scored(c, doc, score));
    }
    if (scored.isEmpty) return const <Channel>[];

    // --- Passe 2 : tri par score, puis pénalité de doublon ---
    scored.sort(_compare);
    final Map<String, int> seenNames = <String, int>{};
    bool anyPenalty = false;
    for (final _Scored s in scored) {
      final int nth = seenNames.update(
        s.doc.cleanNorm,
        (int v) => v + 1,
        ifAbsent: () => 0,
      );
      if (nth > 0) {
        // 2e variante : -20, 3e : -40, etc. (plafonné pour que les
        // variantes restent trouvables, juste plus bas).
        s.score -= math.min(nth, 5) * _kDuplicatePenalty;
        anyPenalty = true;
      }
    }
    // Re-tri uniquement si des pénalités ont bougé des scores.
    if (anyPenalty) scored.sort(_compare);

    final int n = math.min(limit, scored.length);
    return List<Channel>.generate(n, (int i) => scored[i].channel);
  }

  /// Tri : score décroissant, puis nom le plus court d'abord (les
  /// noms courts sont les « canoniques » : « TF1 » avant
  /// « TF1 FHD H265 BACKUP »), puis alphabétique pour la stabilité.
  static int _compare(_Scored a, _Scored b) {
    final int byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final int byLen = a.doc.nameNorm.length.compareTo(b.doc.nameNorm.length);
    if (byLen != 0) return byLen;
    return a.doc.nameNorm.compareTo(b.doc.nameNorm);
  }

  // ------------------------------------------------------------
  //  Score textuel
  // ------------------------------------------------------------

  /// Score d'une chaîne pour la requête tokenisée. 0 = rejet
  /// (au moins un mot de la requête n'a AUCUNE correspondance).
  static int _textScore(
    _SearchDoc doc,
    List<String> tokens,
    String queryNorm,
  ) {
    int sum = 0;
    for (final String token in tokens) {
      final int best = _tokenScore(doc, token);
      if (best <= 0) return 0; // logique ET stricte
      sum += best;
    }
    // Moyenne (et non somme) pour ne pas favoriser mécaniquement
    // les requêtes longues.
    int score = sum ~/ tokens.length;

    // Bonus « la chaîne EST ce qu'on a tapé ».
    if (doc.nameNorm == queryNorm || doc.cleanNorm == queryNorm) {
      score += _kFullExactBonus;
    } else if (doc.nameNorm.startsWith(queryNorm) ||
        doc.cleanNorm.startsWith(queryNorm)) {
      score += _kStartsWithBonus;
    }
    return score;
  }

  /// Meilleure correspondance d'UN mot de la requête dans le
  /// document (nom brut, nom curé, catégorie).
  static int _tokenScore(_SearchDoc doc, String token) {
    int best = 0;

    // --- Mots du nom (brut + curé confondus) ---
    for (final String w in doc.nameWords) {
      if (w == token) return _kWordExact; // impossible de faire mieux
      if (best < _kWordPrefix && w.startsWith(token)) {
        best = _kWordPrefix;
      }
    }

    // --- Substring dans le nom complet (« sport1 » dans
    //     « eurosport1 ») ---
    if (best < _kSubstring &&
        (doc.nameNorm.contains(token) || doc.cleanNorm.contains(token))) {
      best = _kSubstring;
    }

    // --- Tolérance aux fautes (mots du nom uniquement — corriger
    //     des fautes contre la catégorie produit trop de bruit) ---
    final int maxEdits = _maxEditsFor(token.length);
    if (maxEdits > 0 && best < _kFuzzyBase - _kFuzzyPerEdit) {
      for (final String w in doc.nameWords) {
        // Un écart de longueur > maxEdits ne peut pas matcher :
        // évite l'OSA (coûteux) dans l'immense majorité des cas.
        if ((w.length - token.length).abs() > maxEdits) continue;
        final int d = _osaDistance(token, w, maxEdits);
        if (d >= 0) {
          final int s = _kFuzzyBase - d * _kFuzzyPerEdit;
          if (s > best) best = s;
          if (d == 1 && best >= _kFuzzyBase - _kFuzzyPerEdit) break;
        }
      }
    }

    // --- Catégorie (plus faible que le nom) ---
    if (best < _kCategoryWordPrefix) {
      for (final String w in doc.categoryWords) {
        if (w == token || w.startsWith(token)) {
          best = _kCategoryWordPrefix;
          break;
        }
      }
    }
    if (best < _kCategorySubstring && doc.categoryNorm.contains(token)) {
      best = _kCategorySubstring;
    }
    return best;
  }

  /// Nombre de fautes tolérées selon la longueur du mot tapé.
  /// En dessous de 4 lettres, corriger crée plus de bruit que de
  /// service (« tf1 » ne doit pas matcher « tf2 » ni « rt1 »).
  static int _maxEditsFor(int len) {
    if (len >= 7) return 2;
    if (len >= 4) return 1;
    return 0;
  }

  static int _qualityBonus(ChannelQuality q) {
    switch (q) {
      case ChannelQuality.q8K:
      case ChannelQuality.q4K:
        return 4;
      case ChannelQuality.fhd:
        return 3;
      case ChannelQuality.hd:
        return 2;
      case ChannelQuality.sd:
        return 0;
    }
  }

  // ------------------------------------------------------------
  //  Normalisation & tokenisation
  // ------------------------------------------------------------

  /// Minuscules + accents retirés + tout séparateur/décoration
  /// réduit à UN espace. Publique : l'écran peut l'utiliser pour
  /// surligner les correspondances s'il le souhaite un jour.
  static String normalize(String s) {
    final String lower = s.toLowerCase();
    final StringBuffer out = StringBuffer();
    bool lastWasSpace = true; // évite les espaces de tête/doublés
    for (final int rune in lower.runes) {
      final String ch = String.fromCharCode(rune);
      final String? mapped = _accentMap[ch];
      final String c = mapped ?? ch;
      final bool keep = _isKeepable(c);
      if (keep) {
        out.write(c);
        lastWasSpace = false;
      } else if (!lastWasSpace) {
        out.write(' ');
        lastWasSpace = true;
      }
    }
    return out.toString().trimRight();
  }

  /// Un caractère « utile » : lettre a-z ou chiffre. Tout le reste
  /// (ponctuation, |, ★, émojis, ᴴᴰ…) devient séparateur.
  static bool _isKeepable(String c) {
    if (c.length != 1) return false;
    final int code = c.codeUnitAt(0);
    return (code >= 0x61 && code <= 0x7A) || // a-z
        (code >= 0x30 && code <= 0x39); // 0-9
  }

  static List<String> _tokenize(String norm) => norm
      .split(' ')
      .where((String t) => t.isNotEmpty)
      .toList(growable: false);

  static const Map<String, String> _accentMap = <String, String>{
    'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ý': 'y', 'ÿ': 'y',
    'ç': 'c', 'ñ': 'n', 'ß': 'ss', 'æ': 'ae', 'œ': 'oe',
  };

  // ------------------------------------------------------------
  //  Distance d'édition bornée (OSA = Levenshtein + transposition)
  // ------------------------------------------------------------

  /// Distance Optimal String Alignment entre [a] et [b], ou -1 si
  /// elle dépasse [maxDist]. La transposition de deux lettres
  /// adjacentes (« sprot » → « sport ») compte pour 1 — c'est LA
  /// faute de frappe la plus courante sur un clavier tactile.
  static int _osaDistance(String a, String b, int maxDist) {
    final int la = a.length;
    final int lb = b.length;
    if ((la - lb).abs() > maxDist) return -1;

    // Trois lignes glissantes suffisent (la transposition regarde
    // deux lignes en arrière).
    List<int> prev2 = List<int>.filled(lb + 1, 0);
    List<int> prev = List<int>.generate(lb + 1, (int j) => j);
    List<int> cur = List<int>.filled(lb + 1, 0);

    for (int i = 1; i <= la; i++) {
      cur[0] = i;
      int rowMin = cur[0];
      for (int j = 1; j <= lb; j++) {
        final int cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        int v = math.min(
          math.min(prev[j] + 1, cur[j - 1] + 1),
          prev[j - 1] + cost,
        );
        if (i > 1 &&
            j > 1 &&
            a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          v = math.min(v, prev2[j - 2] + 1);
        }
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      // Coupure : si toute la ligne dépasse la borne, inutile de
      // continuer — la distance finale ne peut que croître.
      if (rowMin > maxDist) return -1;
      final List<int> tmp = prev2;
      prev2 = prev;
      prev = cur;
      cur = tmp;
    }
    final int d = prev[lb];
    return d <= maxDist ? d : -1;
  }

  // ------------------------------------------------------------
  //  Cache des documents normalisés
  // ------------------------------------------------------------

  /// Mémoïsation par id de chaîne — même logique (et même
  /// justification de perf) que `_ChannelComputedCache` dans
  /// channel.dart : normaliser 27 000 noms à CHAQUE frappe
  /// coûterait bien plus que le matching lui-même.
  static final Map<String, _SearchDoc> _docCache = <String, _SearchDoc>{};

  static _SearchDoc _docFor(Channel c) => _docCache.putIfAbsent(
        c.id,
        () {
          final String nameNorm = normalize(c.name);
          final String cleanNorm = normalize(c.cleanName);
          final String categoryNorm = normalize(c.category);
          // Mots du nom brut ET du nom curé, dédupliqués : le curé
          // révèle des mots que les décorations IPTV collaient.
          final Set<String> words = <String>{
            ..._tokenize(nameNorm),
            ..._tokenize(cleanNorm),
          };
          return _SearchDoc(
            nameNorm: nameNorm,
            cleanNorm: cleanNorm,
            categoryNorm: categoryNorm,
            nameWords: words.toList(growable: false),
            categoryWords: _tokenize(categoryNorm),
          );
        },
      );

  /// À appeler si une playlist est supprimée (même contrat que
  /// `_ChannelComputedCache.invalidate`). Optionnel : le coût
  /// mémoire résiduel est de quelques dizaines d'octets par id.
  static void invalidate(Iterable<String> ids) {
    for (final String id in ids) {
      _docCache.remove(id);
    }
  }

  /// Vidage complet — à appeler à la suppression d'une playlist (audit
  /// 2026-07-29 : `invalidate` n'avait AUCUN appelant, le cache statique
  /// grossissait sans jamais rendre la mémoire, y compris après suppression
  /// de la source ; sur une source 100 k chaînes cela immobilisait des
  /// dizaines de Mo à vie). Recalcul paresseux à la frappe suivante.
  static void clearAll() => _docCache.clear();
}

/// Texte pré-normalisé d'une chaîne, prêt à matcher.
class _SearchDoc {
  const _SearchDoc({
    required this.nameNorm,
    required this.cleanNorm,
    required this.categoryNorm,
    required this.nameWords,
    required this.categoryWords,
  });

  final String nameNorm;
  final String cleanNorm;
  final String categoryNorm;
  final List<String> nameWords;
  final List<String> categoryWords;
}

/// Paire (chaîne, score) mutable le temps du classement.
class _Scored {
  _Scored(this.channel, this.doc, this.score);
  final Channel channel;
  final _SearchDoc doc;
  int score;
}
