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
// "", "★"…)
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

import '../i18n/l10n_now.dart';

/// Jeton éditorial canonique d'une catégorie « crue ».
/// La map [_categoryEditorial] pointe vers ces jetons STABLES ; le
/// libellé affiché est résolu au dernier moment via `l10nNow` (voir
/// [TitleCurator.curateCategory]) pour suivre la langue active.
enum _EditorialCategory {
  afterDark,
  cinema,
  series,
  sports,
  football,
  news,
  kids,
  music,
  documentary,
  general,
  entertainment,
}

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
  // Pas de "★" ni "" ni "" dans une UI premium.
  // -----------------------------------------------------------------
  static final RegExp _decorations = RegExp(
    r'[★☆●○◆◇■□▪▫•‣⚡✨✦✧❤♥♦♣♠➤➜▶▷◀◁→←↑↓↔↕↗↖↘↙‼‼️🔥💎💯🎬🎥📺🇦-🇿]+',
    unicode: true,
  );

  // -----------------------------------------------------------------
  //  ANTI-TOFU (photo client, box réelle) : les panels décorent leurs
  //  catégories avec des pictogrammes que la police des box N'A PAS →
  //  affichés en carrés rayés (tofu). `_decorations` ci-dessus est une
  //  liste FERMÉE, impossible à tenir à jour. Ici : balayage LARGE par
  //  PLAGES Unicode — tout ce qui est emoji/symbole/pictogramme/zone
  //  privée/sélecteur invisible saute. Les plages restent en dehors des
  //  écritures réelles (latin, arabe, cyrillique, CJK… intactes).
  //    1F000-1FBFF  emoji + symboles étendus + legacy computing
  //    2190-2BFF    flèches, symboles divers, dingbats, formes
  //    FE00-FE0F    sélecteurs de variante (emoji invisibles)
  //    E000-F8FF    zone privée (tofu garanti)
  //    200B-200F / 2060-2064  invisibles zéro-chasse
  //    20D0-20FF    diacritiques de symboles
  //    FFFD         caractère de remplacement (encodage cassé)
  // -----------------------------------------------------------------
  // v2 (photo client, les carrés SURVIVAIENT aux plages) : LISTE BLANCHE.
  // La liste noire de plages est un jeu perdu d'avance — chaque panel invente
  // un nouveau pictogramme. Ici on inverse : on ne GARDE que ce que toutes
  // les polices TV savent dessiner — lettres/diacritiques/chiffres de TOUTES
  // les écritures (\p{L}\p{M}\p{N} : latin, arabe, cyrillique, CJK…),
  // espaces, et la ponctuation usuelle des noms de chaînes/catégories.
  // TOUT le reste est balayé, connu ou inconnu.
  static final RegExp _unrenderable = RegExp(
    '[^\\p{L}\\p{M}\\p{N}\\s'
    r".,:;!?'’\-–—&+/()\[\]{}|#%@°«»" '"'
    ']+',
    unicode: true,
  );

  // Marques INVISIBLES à purger malgré la liste blanche : les sélecteurs de
  // variante (FE0F…) et diacritiques de symboles sont classés \p{M} (gardé
  // pour l'arabe/l'indien) mais ne servent qu'à décorer des emojis déjà
  // supprimés — seuls, ils redeviennent des tofu.
  static final RegExp _invisibleMarks = RegExp(
    r'[\u{FE00}-\u{FE0F}\u{180B}-\u{180D}\u{20D0}-\u{20FF}]+',
    unicode: true,
  );

  /// Balayage anti-tofu PARTAGÉ (photo client : le template d'accueil passe
  /// par `ChannelClassifier.prettifyCategory`, pas par `curate()` — il doit
  /// purger exactement pareil). Liste blanche + purge des marques invisibles.
  static String stripUnrenderable(String s) {
    return s
        .replaceAll(_unrenderable, ' ')
        .replaceAll(_invisibleMarks, '');
  }

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
  //  I18N — POURQUOI `l10nNow` ici plutôt qu'une localisation à
  //  l'affichage : `curateCategory` est consommée depuis le domain
  //  (`Channel.prettyCategory`) ET depuis features/tv — localiser
  //  chaque call-site aurait éparpillé la logique. Le chemin éditorial
  //  n'est PAS mis en cache (contrairement à `curate()`), donc le
  //  libellé est re-résolu à chaque rebuild et suit la langue active.
  //  La map garde des JETONS stables ; « Cinéma », « Séries », « Info »…
  //  réutilisent les clés existantes (catFilterMovies, sectionSeries,
  //  catInfo…), seules editorialAfterDark / editorialGeneralist sont
  //  nouvelles.
  static const Map<String, _EditorialCategory> _categoryEditorial =
      <String, _EditorialCategory>{
    'adult': _EditorialCategory.afterDark,
    'adults': _EditorialCategory.afterDark,
    'adulte': _EditorialCategory.afterDark,
    'adultes': _EditorialCategory.afterDark,
    'xxx': _EditorialCategory.afterDark,
    '18+': _EditorialCategory.afterDark,
    'porn': _EditorialCategory.afterDark,
    'porno': _EditorialCategory.afterDark,

    'movies': _EditorialCategory.cinema,
    'movie': _EditorialCategory.cinema,
    'films': _EditorialCategory.cinema,
    'vod': _EditorialCategory.cinema,
    'cinema': _EditorialCategory.cinema,
    'cinéma': _EditorialCategory.cinema,

    'series': _EditorialCategory.series,
    'séries': _EditorialCategory.series,
    'tv shows': _EditorialCategory.series,
    'tv show': _EditorialCategory.series,
    'shows': _EditorialCategory.series,

    'sport': _EditorialCategory.sports,
    'sports': _EditorialCategory.sports,
    'football': _EditorialCategory.football,
    'soccer': _EditorialCategory.football,
    'fútbol': _EditorialCategory.football,

    'news': _EditorialCategory.news,
    'actu': _EditorialCategory.news,
    'actualités': _EditorialCategory.news,

    'kids': _EditorialCategory.kids,
    'children': _EditorialCategory.kids,
    'enfants': _EditorialCategory.kids,
    'cartoon': _EditorialCategory.kids,
    'cartoons': _EditorialCategory.kids,

    'music': _EditorialCategory.music,
    'musique': _EditorialCategory.music,
    'concert': _EditorialCategory.music,

    'documentary': _EditorialCategory.documentary,
    'docs': _EditorialCategory.documentary,
    'docu': _EditorialCategory.documentary,
    'doc': _EditorialCategory.documentary,

    'general': _EditorialCategory.general,
    'généraliste': _EditorialCategory.general,
    'entertainment': _EditorialCategory.entertainment,
  };

  /// Libellé TRADUIT d'un jeton éditorial (résolu à l'appel, jamais caché).
  static String _editorialLabel(_EditorialCategory cat) {
    switch (cat) {
      case _EditorialCategory.afterDark:
        return l10nNow.editorialAfterDark;
      case _EditorialCategory.cinema:
        return l10nNow.catFilterMovies;
      case _EditorialCategory.series:
        return l10nNow.sectionSeries;
      case _EditorialCategory.sports:
        return l10nNow.genreSports;
      case _EditorialCategory.football:
        return l10nNow.navTabFootball;
      case _EditorialCategory.news:
        return l10nNow.catInfo;
      case _EditorialCategory.kids:
        return l10nNow.sectionKids;
      case _EditorialCategory.music:
        return l10nNow.sectionMusic;
      case _EditorialCategory.documentary:
        return l10nNow.sectionDocs;
      case _EditorialCategory.general:
        return l10nNow.editorialGeneralist;
      case _EditorialCategory.entertainment:
        return l10nNow.sectionEntertainment;
    }
  }

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

    // 1b) Retire les décorations Unicode (★ etc.)
    s = s.replaceAll(_decorations, ' ');

    // 1c) ANTI-TOFU liste blanche : tout caractère hors lettres/chiffres/
    // ponctuation usuelle saute — connu ou inconnu (v. _unrenderable).
    s = stripUnrenderable(s);

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
    final _EditorialCategory? editorial = _categoryEditorial[key];
    if (editorial != null) return _editorialLabel(editorial);
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
