// =========================================================
//  title_curator.dart — Couche d'abstraction cinéma The Few
// =========================================================
//
//  Mission : transformer les noms de chaînes IPTV bruts —
//  souvent moches, techniques, criards — en titres présentables
//  à l'écran d'une plateforme premium. Style Apple TV+ /
//  Criterion : on ne montre JAMAIS au spectateur le bruit du
//  serveur (les "RAW", "FHD", "VIP", "PREMIUM", "BACKUP",
//  "[24/7]", etc.). On lui montre une chaîne, point.
//
//  Ce module est appelé EN AVAL du parser M3U/Xtream : les
//  données techniques restent intactes côté domain (parsing,
//  zapping, EPG, recherche), mais TOUT ce que l'utilisateur
//  voit (cards, hero, recherche, EPG, recommandations) passe
//  par `TitleCurator.curate(name)`.
//
//  Stratégie :
//    1. On strippe les préfixes ("ADULT:", "FR |", "[VIP]"…)
//       et suffixes ("RAW", "HD", "FHD", "4K", "BACKUP", "24/7",
//       "⚡", "★"…)
//    2. On remplace les variantes connues par des libellés
//       cinéma curés (un PETIT dictionnaire, élargi au fil
//       des découvertes — c'est volontairement minimaliste,
//       on ne veut pas mentir au spectateur, juste lisser).
//    3. On applique un Title Case respectueux (FR/EN), tout
//       en préservant les acronymes (TF1, BFM, BBC, CNN…).
//    4. Si après nettoyage il ne reste rien d'utile, on
//       retombe sur le nom d'origine — jamais d'écran vide.
//
//  PHILOSOPHIE : c'est de la lecture, pas du masquage. On
//  garde TOUTES les chaînes du provider, on les rend juste
//  présentables. Aucune chaîne n'est cachée ou renommée
//  trompeusement (ex: "AB1" ne devient pas "Apple Movies").
//  Le contrat avec l'utilisateur reste honnête.
// =========================================================

import 'package:flutter/foundation.dart';

abstract final class TitleCurator {
  // -----------------------------------------------------------------
  //  Préfixes IPTV typiques à virer en début de nom.
  // -----------------------------------------------------------------
  //  On supporte plusieurs séparateurs (`:`, `|`, `-`, `–`, `>`, `»`).
  //  Liste volontairement large car les providers sont bavards.
  //  Détectés en début de chaîne (case-insensitive), suivis d'un
  //  séparateur. On les retire avec leur séparateur.
  static const List<String> _stripPrefixes = <String>[
    'adult', 'adults', 'adulte', 'adultes', 'xxx', '18+',
    'vip', 'premium', 'plus', 'pro', 'platinum', 'gold', 'silver',
    'backup', 'bkp', 'bk', 'raw', 'main', 'master', 'src',
    'new', 'nouveau', 'updated', 'maj',
    'live', 'direct', 'en direct',
    'feed', 'source', 'stream',
    'opt', 'option 1', 'option 2', 'option 3',
    'multi', 'mono',
    // Drapeaux pays parfois écrits en préfixe texte
    'fr', 'be', 'lu', 'ca', 'us', 'uk', 'es', 'pt', 'it', 'de',
    'ar', 'mar', 'tn', 'dz', 'eg', 'sa',
    'fr fr', 'be fr', 'fr be',
  ];

  // -----------------------------------------------------------------
  //  Suffixes / mots-clés à virer où qu'ils soient dans le nom.
  // -----------------------------------------------------------------
  //  On matche en tant que mots complets pour ne pas casser des
  //  noms légitimes (`HD` ne doit pas trancher dans "Disney CHANNEL HD"
  //  → on garde "Disney Channel", on enlève "HD" tout seul).
  static const List<String> _stripWords = <String>[
    'raw', 'backup', 'bkp', 'feed', 'source', 'src', 'stream',
    'main', 'master', 'mirror',
    // Qualité video
    'fhd', 'uhd', 'sd', 'hd', 'hd+', 'full hd', 'fullhd', '4k', '4 k',
    'h265', 'h264', 'hevc', 'avc',
    // Frame rate (typiques sur les chaines sport / 24/7)
    '60fps', '60 fps', '30fps', '30 fps', '50fps', '25fps', '120fps',
    'iptv', 'xtream',
    'opt', 'option',
    // Combinaisons 24/7 / 24h
    '24/7', '24-7', '24h', '247',
    'vip', 'plus', 'premium',
    // Combinaisons qualite avec slash (HD/RAW, FHD/SD)
    // a virer AVANT que la normalisation des slashes les casse
    'hd/raw', 'fhd/raw', 'sd/raw', 'uhd/raw',
    'hd/sd', 'fhd/hd', '4k/uhd',
    // tags de qualité parfois entre crochets
    '[hd]', '[fhd]', '[uhd]', '[4k]', '[sd]', '[vip]', '[backup]',
    '[raw]', '[main]',
  ];

  // -----------------------------------------------------------------
  //  Caractères / symboles décoratifs à virer entièrement.
  //  Pas de "★" ni "⚡" ni "✨" dans une UI premium.
  // -----------------------------------------------------------------
  static final RegExp _decorations = RegExp(
    r'[★☆●○◆◇■□▪▫•‣⚡✨✦✧❤♥♦♣♠➤➜▶▷◀◁→←↑↓↔↕↗↖↘↙‼‼️🔥💎💯🎬🎥📺🇦-🇿]+',
    unicode: true,
  );

  // -----------------------------------------------------------------
  //  Bandes de separateurs IPTV : ##, ##########, ____,
  //  ========, --------, ~~~~~~~ et derivees. Tres frequents
  //  dans les flux Xtream pour signaler une nouvelle categorie
  //  ou separer visuellement.
  //  Exemples reels du fournisseur Lionel :
  //    "## 24/7 ACTION/ADVENTURE ##"
  //    "## 24/7 CARTOON ##"
  //    "### FRANCE CARRIBEAN ###"
  //  On les retire au debut, a la fin, OU encadres d'espaces au
  //  milieu d'un nom. Seuil >=2 pour matcher les `##` typiques.
  //  Risque de faux-positif : on touche pas a "F#" ou "C#" car
  //  ils n'ont qu'UN # (pas 2+), donc safe.
  // -----------------------------------------------------------------
  static final RegExp _bulkSeparators = RegExp(
    r'(^|\s)[#_=*\-~]{2,}(\s|$)',
  );

  // -----------------------------------------------------------------
  //  Acronymes à NE PAS title-caser (rester en MAJ).
  // -----------------------------------------------------------------
  //  TF1, BFM, RMC, BBC, CNN, ESPN, NHK, etc.
  static final Set<String> _preserveAcronyms = <String>{
    'TF1', 'TF2', 'TF6', 'TF8', 'BFM', 'RMC', 'CNN', 'BBC', 'BBM',
    'ABC', 'CBS', 'NBC', 'FOX', 'ESPN', 'NHK', 'NPR', 'PBS',
    'M6', 'W9', 'C8', 'CSTAR', 'RTL', 'RTBF', 'NRJ', 'D8', 'D17',
    'BEIN', 'SSC', 'SHOWMAX', 'MBC', 'ART', 'OSN',
    'HBO', 'AMC', 'FX', 'MTV', 'VH1', 'CW',
    'NFL', 'NBA', 'NHL', 'MLB', 'UFC', 'WWE', 'F1', 'MOTOGP',
    'RAI', 'TVE', 'TVP', 'ORF', 'SRF', 'SVT', 'NRK', 'DR', 'YLE',
    'TV5', 'TV6', 'TV4',
    'KTO', 'CJN', 'LCP', 'LCI',
    'OCS', 'TNT', 'TPS', 'TMC', 'TFX',
    'UHD', 'FHD',
  };

  // -----------------------------------------------------------------
  //  Renommages "éditoriaux" minimalistes.
  //  Petits adoucissements cinéma sur catégories trop crues.
  //  On reste HONNÊTE : on ne mente pas sur le contenu, on adoucit
  //  la présentation. Le label catégorie d'origine reste accessible
  //  côté domain pour la recherche.
  // -----------------------------------------------------------------
  static const Map<String, String> _categoryEditorial = <String, String>{
    'adult': 'After Dark',
    'adults': 'After Dark',
    'adulte': 'After Dark',
    'adultes': 'After Dark',
    'xxx': 'After Dark',
    '18+': 'After Dark',
    'porn': 'After Dark',
    'porno': 'After Dark',

    'movies': 'Cinéma',
    'movie': 'Cinéma',
    'films': 'Cinéma',
    'vod': 'Cinéma',
    'cinema': 'Cinéma',
    'cinéma': 'Cinéma',

    'series': 'Séries',
    'séries': 'Séries',
    'tv shows': 'Séries',
    'tv show': 'Séries',
    'shows': 'Séries',

    'sport': 'Sports',
    'sports': 'Sports',
    'football': 'Football',
    'soccer': 'Football',
    'fútbol': 'Football',

    'news': 'Info',
    'actu': 'Info',
    'actualités': 'Info',

    'kids': 'Jeunesse',
    'children': 'Jeunesse',
    'enfants': 'Jeunesse',
    'cartoon': 'Jeunesse',
    'cartoons': 'Jeunesse',

    'music': 'Musique',
    'musique': 'Musique',
    'concert': 'Musique',

    'documentary': 'Documentaires',
    'docs': 'Documentaires',
    'docu': 'Documentaires',
    'doc': 'Documentaires',

    'general': 'Généraliste',
    'généraliste': 'Généraliste',
    'entertainment': 'Divertissement',
  };

  /// Cache LRU naïf — `curate()` est appelé sur 20 000+ chaînes à
  /// chaque rebuild d'écran. Sans cache, on saturait le main thread
  /// (mêmes raisons que `ChannelClassifier` ailleurs dans la base).
  static final Map<String, String> _cache = <String, String>{};
  static const int _cacheMaxEntries = 8000;

  /// Transforme un nom IPTV brut en titre présentable.
  /// Si le résultat serait vide, retourne `raw` tel quel — l'UI
  /// préfère un nom moche à un blanc.
  static String curate(String raw) {
    if (raw.isEmpty) return raw;
    final String? hit = _cache[raw];
    if (hit != null) return hit;

    String s = raw;

    // 1a) Retire les bandes de separateurs IPTV : ########,
    //     ________, ======== etc. en debut/fin/milieu (≥3 chars).
    //     replaceAll en boucle car une bande au milieu peut creer
    //     un nouveau debut/fin apres remplacement.
    String before;
    int safety = 4;
    do {
      before = s;
      s = s.replaceAll(_bulkSeparators, ' ');
      safety--;
    } while (before != s && safety > 0);

    // 1b) Retire les décorations Unicode (★ ⚡ 🔥 ✨ etc.)
    s = s.replaceAll(_decorations, ' ');

    // 2) Retire les crochets [VIP], [HD], (BACKUP), {RAW}, etc.
    s = s.replaceAllMapped(
      RegExp(r'[\[\(\{]\s*([^\[\]\(\)\{\}]+?)\s*[\]\)\}]'),
      (Match m) {
        final String inside = (m.group(1) ?? '').trim().toLowerCase();
        if (_stripWords.contains(inside) ||
            _stripPrefixes.contains(inside) ||
            RegExp(r'^\d{1,4}$').hasMatch(inside)) {
          return ' '; // on jette
        }
        return m.group(0)!; // on garde tel quel
      },
    );

    // 3) Strip préfixes "FR :", "ADULT |", "VIP -", etc.
    //    On boucle pour gérer les empilements ("FR | VIP : XXX -")
    bool changed = true;
    int safetyLoops = 4;
    while (changed && safetyLoops-- > 0) {
      changed = false;
      for (final String prefix in _stripPrefixes) {
        final RegExp rx = RegExp(
          '^\\s*' + RegExp.escape(prefix) + r'\s*[:|\-–>»]\s*',
          caseSensitive: false,
        );
        final String next = s.replaceFirst(rx, '');
        if (next != s) {
          s = next;
          changed = true;
        }
      }
    }

    // 4) Retire les mots-isolés indésirables (raw / fhd / 24/7 / vip…)
    for (final String w in _stripWords) {
      final RegExp rx = RegExp(
        r'(^|\s)' + RegExp.escape(w) + r'(\s|$)',
        caseSensitive: false,
      );
      s = s.replaceAll(rx, ' ');
    }

    // 5) Retire les numéros isolés type "TF1 1 HD" → "TF1 HD" (les
    //    parseurs IPTV ajoutent souvent "1", "2", "3" pour des
    //    déclinaisons techniques qui ne veulent rien dire à l'écran).
    //    On ne touche PAS aux noms qui SONT un numéro entièrement (ex:
    //    "Sport 1", "BeIN Sports 2" ← légitimes).
    if (RegExp(r'[A-Za-zÀ-ÿ]{3,}').hasMatch(s)) {
      s = s.replaceAll(RegExp(r'\b(?:opt|src|feed)\s*\d+\b', caseSensitive: false), ' ');
    }

    // 6) Normalise les espaces et la ponctuation résiduelle.
    //    /|\ deviennent des espaces. C'est ici que "HD/RAW" devient
    //    "HD RAW" et "MOVIES/ACTORS" devient "MOVIES ACTORS".
    s = s.replaceAll(RegExp(r'[\|/\\]+'), ' ');
    s = s.replaceAll(RegExp(r'\s*[-–—]\s*$'), '');
    s = s.replaceAll(RegExp(r'^\s*[-–—]\s*'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 6.5) DEUXIÈME passe de strip words sur le résultat normalisé.
    //      Apres step 6, "HD/RAW" est devenu "HD RAW" : maintenant
    //      les tokens HD et RAW peuvent etre attrapes par
    //      _stripWords s'ils n'avaient pas matche au step 4 (ou si
    //      le slash etait dans le chemin).
    //      Pareil pour "MOVIES/ACTORS RAW 60fps" qui devient
    //      "MOVIES ACTORS RAW 60fps" → ici on attrape RAW + 60fps.
    for (final String w in _stripWords) {
      final RegExp rx = RegExp(
        r'(^|\s)' + RegExp.escape(w) + r'(\s|$)',
        caseSensitive: false,
      );
      s = s.replaceAll(rx, ' ');
    }
    // Re-normalise les espaces apres ce 2e strip.
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 7) Title-case respectueux (en gardant les acronymes connus
    //    et les sigles courts en majuscules).
    s = _titleCase(s);

    if (s.isEmpty) {
      _putInCache(raw, raw);
      return raw;
    }
    _putInCache(raw, s);
    return s;
  }

  /// Variante pour les catégories — applique le dictionnaire éditorial
  /// si le terme nu est reconnu, sinon utilise `curate()` standard.
  static String curateCategory(String raw) {
    if (raw.isEmpty) return raw;
    final String key = raw.trim().toLowerCase();
    final String? editorial = _categoryEditorial[key];
    if (editorial != null) return editorial;
    return curate(raw);
  }

  /// Title-case avec préservation des acronymes connus (`TF1`, `BBC`…).
  /// Garde les particules courantes en minuscule au milieu d'un titre
  /// ("de", "la", "et", "of", "the"…) pour l'élégance.
  static String _titleCase(String s) {
    const Set<String> lowers = <String>{
      'de', 'la', 'le', 'les', 'du', 'des', 'et', 'à', 'au', 'aux',
      'en', 'un', 'une', 'sur',
      'of', 'the', 'and', 'or', 'a', 'an', 'in', 'on', 'at', 'by',
    };
    final List<String> words = s.split(RegExp(r'\s+'));
    final List<String> out = <String>[];
    for (int i = 0; i < words.length; i++) {
      final String w = words[i];
      if (w.isEmpty) continue;
      // Acronymes : on respecte la version connue.
      final String upper = w.toUpperCase();
      if (_preserveAcronyms.contains(upper)) {
        out.add(upper);
        continue;
      }
      // Sigles 1-3 lettres déjà tout en majuscules → on garde.
      if (w.length <= 3 && w == upper && RegExp(r'^[A-Z0-9]+$').hasMatch(w)) {
        out.add(w);
        continue;
      }
      // Particules au milieu : on les laisse en minuscule (jamais en
      // tête de phrase, sinon on capitalise).
      final String low = w.toLowerCase();
      if (i > 0 && lowers.contains(low)) {
        out.add(low);
        continue;
      }
      // Capitalisation standard.
      out.add(low[0].toUpperCase() + low.substring(1));
    }
    return out.join(' ');
  }

  static void _putInCache(String raw, String pretty) {
    if (_cache.length >= _cacheMaxEntries) {
      // Stratégie naïve : on vide quand ça déborde. Acceptable car
      // les noms se restabilisent en quelques rebuilds.
      _cache.clear();
      if (kDebugMode) debugPrint('[TitleCurator] cache vidé (overflow)');
    }
    _cache[raw] = pretty;
  }
}
