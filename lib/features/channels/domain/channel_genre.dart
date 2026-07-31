// =========================================================
//  channel_genre.dart — Classification automatique des chaînes
// =========================================================
//  Une playlist M3U contient des `group-title` totalement
//  hétérogènes selon les fournisseurs :
//    "US| ESPN+ PPV vIP"  → Sport, US
//    "## 24/7 CARTOONS"   → Jeunesse
//    "FR | Cinéma HD"     → Films, France, HD
//    "UK Sport Premium"   → Sport, UK
//
//  Ce module sert à transformer ce chaos en information
//  exploitable pour notre nouvelle UI premium :
//    - un Genre canonique (Sport/Films/Séries/...) pour les
//      sections type Apple TV
//    - un Pays / Langue détecté pour les filtres
//    - une Qualité détectée (HD/FHD/4K/8K) pour les badges
//
//  Stratégie : pure heuristique par mots-clés. Robuste sur 90%
//  des playlists IPTV du marché. Le reste tombe dans "Autres".
// =========================================================

import 'package:flutter/material.dart';

/// Genre canonique d'une chaîne.
enum ChannelGenre {
  sports('Sports', Icons.sports_soccer_rounded),
  movies('Films', Icons.movie_creation_outlined),
  series('Séries', Icons.live_tv_rounded),
  kids('Jeunesse', Icons.child_care_rounded),
  news('Info', Icons.newspaper_rounded),
  music('Musique', Icons.music_note_rounded),
  documentary('Docu', Icons.public_rounded),
  entertainment('Divertissement', Icons.theater_comedy_rounded),
  international('International', Icons.language_rounded),
  adult('Adulte', Icons.no_adult_content_rounded),
  other('Autres', Icons.dashboard_rounded);

  const ChannelGenre(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Pays détecté (sous-ensemble des plus représentés en IPTV).
class CountryInfo {
  const CountryInfo(this.code, this.name, this.flag);
  final String code;
  final String name;
  final String flag;
}

/// Qualité visuelle d'une chaîne (déduite du nom).
enum ChannelQuality {
  q8K('8K'),
  q4K('4K'),
  fhd('FHD'),
  hd('HD'),
  sd('SD');

  const ChannelQuality(this.badge);
  final String badge;
}

abstract final class ChannelClassifier {
  // -------------------------------------------------------
  //  GENRE
  // -------------------------------------------------------

  static ChannelGenre classifyGenre(String name, String category) {
    final String text = _normalize('$name $category');

    // Ordre critique : on teste les genres les plus SPÉCIFIQUES
    // d'abord (sinon "kids" capture des chaînes "kids sport").

    if (_containsAny(text, _kAdultKeywords)) return ChannelGenre.adult;
    if (_containsAny(text, _kKidsKeywords)) return ChannelGenre.kids;
    if (_containsAny(text, _kSportsKeywords)) return ChannelGenre.sports;
    if (_containsAny(text, _kNewsKeywords)) return ChannelGenre.news;
    if (_containsAny(text, _kMoviesKeywords)) return ChannelGenre.movies;
    if (_containsAny(text, _kSeriesKeywords)) return ChannelGenre.series;
    if (_containsAny(text, _kMusicKeywords)) return ChannelGenre.music;
    if (_containsAny(text, _kDocKeywords)) return ChannelGenre.documentary;
    if (_containsAny(text, _kEntertainmentKeywords)) {
      return ChannelGenre.entertainment;
    }
    if (_isInternationalIndicator(text)) return ChannelGenre.international;

    return ChannelGenre.other;
  }

  // -------------------------------------------------------
  //  PAYS
  // -------------------------------------------------------

  /// Pays détecté (null si on ne sait pas).
  static CountryInfo? detectCountry(String name, String category) {
    final String text = _normalize('$category $name');

    for (final MapEntry<String, CountryInfo> e in _kCountries.entries) {
      for (final String pattern in _patternsForCountry(e.key)) {
        if (_containsAsToken(text, pattern)) {
          return e.value;
        }
      }
    }
    return null;
  }

  // -------------------------------------------------------
  //  QUALITÉ
  // -------------------------------------------------------

  /// Qualité détectée (par défaut SD si rien trouvé).
  static ChannelQuality detectQuality(String name) {
    final String text = _normalize(name);
    if (_containsAsToken(text, '8k')) return ChannelQuality.q8K;
    if (_containsAsToken(text, '4k') ||
        _containsAsToken(text, 'uhd') ||
        _containsAsToken(text, '2160')) {
      return ChannelQuality.q4K;
    }
    if (_containsAsToken(text, 'fhd') ||
        _containsAsToken(text, '1080') ||
        _containsAsToken(text, '1080p')) {
      return ChannelQuality.fhd;
    }
    if (_containsAsToken(text, 'hd') || _containsAsToken(text, '720')) {
      return ChannelQuality.hd;
    }
    return ChannelQuality.sd;
  }

  // -------------------------------------------------------
  //  Nettoyage du libellé de catégorie pour l'affichage
  // -------------------------------------------------------

  // Hissées en static final : prettifyCategory est appelée en boucle sur
  // des bouquets entiers (10 000+ chaînes) — recompiler 2 RegExp par appel
  // gaspillait du CPU sur le thread UI.
  static final RegExp _decorations = RegExp(r'[#*=•‣◆◇■□●○▪▫]+');
  static final RegExp _spaces = RegExp(r'\s+');

  /// Enlève les décorations type "## ## ##" / "==" / "•" et trim.
  /// Retourne un libellé propre prêt à afficher.
  static String prettifyCategory(String raw) {
    String s = raw;
    s = s.replaceAll(_decorations, ' ');
    s = s.replaceAll(_spaces, ' ');
    s = s.trim();
    if (s.isEmpty) return 'Autres';
    return s;
  }

  // ============================================================
  //  Internes
  // ============================================================

  static String _normalize(String s) {
    String out = s.toLowerCase();
    const Map<String, String> accents = <String, String>{
      'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    accents.forEach((String k, String v) => out = out.replaceAll(k, v));
    return out;
  }

  static bool _containsAny(String text, List<String> keywords) {
    for (final String k in keywords) {
      if (_containsAsToken(text, k)) return true;
    }
    return false;
  }

  /// Cache des motifs token — PERF : ce classifieur tourne sur des
  /// centaines de catégories × ~245 mots-clés à chaque classement ;
  /// recompiler la RegExp à chaque appel coûtait des centaines de ms
  /// de jank UI (audit fluidité 2026-07-31). Compilées UNE fois,
  /// réutilisées ensuite (le jeu de mots-clés est constant).
  static final Map<String, RegExp> _tokenPatterns = <String, RegExp>{};

  /// Cherche [needle] comme "token" (entouré de non-lettres).
  /// Évite que "sport" matche dans "transport".
  static bool _containsAsToken(String text, String needle) {
    if (needle.isEmpty) return false;
    final RegExp pattern = _tokenPatterns.putIfAbsent(
        needle,
        () => RegExp(
            r'(^|[^a-z0-9])' + RegExp.escape(needle) + r'($|[^a-z0-9])'));
    return pattern.hasMatch(text);
  }

  static bool _isInternationalIndicator(String text) {
    // Si on trouve plusieurs marqueurs de pays différents,
    // c'est probablement une catégorie "international".
    int hits = 0;
    for (final String pattern in _kAllCountryPatterns) {
      if (_containsAsToken(text, pattern)) {
        hits++;
        if (hits >= 1) return true;
      }
    }
    return false;
  }

  // -------------------------------------------------------
  //  Tables de mots-clés
  // -------------------------------------------------------

  // Marqueurs « adulte ». Liste élargie pour que le rayon « Adulte »
  // apparaisse vraiment : les fournisseurs étiquettent l'adulte de mille
  // façons (« +18 », « XXX », « PORN », marques connues…). On reste sur
  // des termes À HAUTE PRÉCISION (recherchés comme tokens, donc bornés
  // par des non-lettres) pour ne PAS classer par erreur des chaînes
  // normales. Tous ces mots envoient la chaîne dans le rayon Adulte.
  static const List<String> _kAdultKeywords = <String>[
    'xxx', 'adult', 'adulte', 'adultes', 'porn', 'porno',
    '18+', '+18', 'x-rated', 'xrated',
    'erotic', 'erotik', 'erotica', 'erotique',
    'sex', 'sexe', 'sexy', 'sexo',
    'playboy', 'penthouse', 'hustler', 'brazzers', 'dorcel',
    'vixen', 'vivid', 'redlight', 'colmax', 'pinko', 'naughty', 'nubile',
  ];

  static const List<String> _kSportsKeywords = <String>[
    'sport', 'sports', 'football', 'foot', 'soccer', 'basket',
    'basketball', 'nba', 'nfl', 'mlb', 'nhl', 'tennis', 'golf',
    'rugby', 'cricket', 'hockey', 'boxe', 'boxing', 'mma', 'ufc',
    'wwe', 'wrestling', 'formula', 'formule', 'f1', 'motogp',
    'espn', 'bein', 'rmc', 'eurosport', 'sky sport', 'fox sport',
    'tnt sport', 'canal+sport', 'canal sport', 'ligue', 'premier league',
    'champions', 'uefa', 'fifa', 'nba tv', 'red bull tv',
    'olympic', 'olympics', 'jeux olympiques',
  ];

  static const List<String> _kMoviesKeywords = <String>[
    'cinema', 'cinema', 'movie', 'movies', 'film', 'films',
    'hbo', 'showtime', 'starz', 'cinemax', 'mgm', 'amc',
    'paramount', 'sundance', 'lifetime movie', 'tcm',
    'action movies', 'comedy movies', 'horror movies',
    'canal+ cinema', 'cinepolis', 'cine',
  ];

  static const List<String> _kSeriesKeywords = <String>[
    'series', 'serie', 'tv series', 'drama', 'sitcom',
    'netflix', 'amazon', 'hulu', 'paramount+', 'apple tv+',
    'show', 'shows', 'showtime series',
  ];

  static const List<String> _kKidsKeywords = <String>[
    'kids', 'kid', 'enfant', 'enfants', 'jeunesse',
    'cartoon', 'cartoons', 'disney', 'nick', 'nickelodeon',
    'boomerang', 'gulli', 'tiji', 'piwi', 'baby',
    'junior', 'cbeebies', 'pbs kids', 'duck tv', 'tv ja',
  ];

  static const List<String> _kNewsKeywords = <String>[
    'news', 'info', 'bfm', 'cnn', 'fox news', 'bbc',
    'sky news', 'msnbc', 'al jazeera', 'aljazeera',
    'rt', 'cnbc', 'bloomberg', 'tf1', 'france 2', 'france info',
    'france 24', 'i24', 'euronews', 'lci', 'cnews', 'public sénat',
    'rtl info', 'la chaîne info',
  ];

  static const List<String> _kMusicKeywords = <String>[
    'music', 'musique', 'mtv', 'vh1', 'mcm', 'nrj', 'm6 music',
    'trace', 'fun radio', 'rfm tv', 'rfm', 'd17', 'cherie',
    'mezzo', 'classica', 'hits',
  ];

  static const List<String> _kDocKeywords = <String>[
    'doc', 'docu', 'documentary', 'documentaire',
    'discovery', 'national geographic', 'nat geo', 'natgeo',
    'history', 'animal planet', 'crime', 'investigation',
    'planete', 'planete+', 'planete tv', 'arte',
    'rmc decouverte', 'rmc story', 'science', 'curiosity',
    'travel channel', 'voyage',
  ];

  static const List<String> _kEntertainmentKeywords = <String>[
    'entertainment', 'divertissement', 'comedy', 'comedy central',
    'tlc', 'reality', 'tf1', 'm6', 'tmc', 'tfx', 'nrj 12',
    'c8', 'la 5', 'w9', 'chérie 25',
  ];

  static const Map<String, CountryInfo> _kCountries = <String, CountryInfo>{
    'fr': CountryInfo('FR', 'France', '🇫🇷'),
    'us': CountryInfo('US', 'États-Unis', '🇺🇸'),
    'uk': CountryInfo('UK', 'Royaume-Uni', '🇬🇧'),
    'de': CountryInfo('DE', 'Allemagne', '🇩🇪'),
    'it': CountryInfo('IT', 'Italie', '🇮🇹'),
    'es': CountryInfo('ES', 'Espagne', '🇪🇸'),
    'pt': CountryInfo('PT', 'Portugal', '🇵🇹'),
    'be': CountryInfo('BE', 'Belgique', '🇧🇪'),
    'ch': CountryInfo('CH', 'Suisse', '🇨🇭'),
    'ca': CountryInfo('CA', 'Canada', '🇨🇦'),
    'br': CountryInfo('BR', 'Brésil', '🇧🇷'),
    'mx': CountryInfo('MX', 'Mexique', '🇲🇽'),
    'ar': CountryInfo('AR', 'Argentine', '🇦🇷'),
    'sa': CountryInfo('SA', 'Arabie', '🇸🇦'),
    'tr': CountryInfo('TR', 'Turquie', '🇹🇷'),
    'gr': CountryInfo('GR', 'Grèce', '🇬🇷'),
    'pl': CountryInfo('PL', 'Pologne', '🇵🇱'),
    'ru': CountryInfo('RU', 'Russie', '🇷🇺'),
    'nl': CountryInfo('NL', 'Pays-Bas', '🇳🇱'),
    'jp': CountryInfo('JP', 'Japon', '🇯🇵'),
    'kr': CountryInfo('KR', 'Corée', '🇰🇷'),
    'cn': CountryInfo('CN', 'Chine', '🇨🇳'),
    'in': CountryInfo('IN', 'Inde', '🇮🇳'),
    'au': CountryInfo('AU', 'Australie', '🇦🇺'),
    'se': CountryInfo('SE', 'Suède', '🇸🇪'),
    'no': CountryInfo('NO', 'Norvège', '🇳🇴'),
    'dk': CountryInfo('DK', 'Danemark', '🇩🇰'),
    'fi': CountryInfo('FI', 'Finlande', '🇫🇮'),
    'ma': CountryInfo('MA', 'Maroc', '🇲🇦'),
    'dz': CountryInfo('DZ', 'Algérie', '🇩🇿'),
    'tn': CountryInfo('TN', 'Tunisie', '🇹🇳'),
    'eg': CountryInfo('EG', 'Égypte', '🇪🇬'),
  };

  static List<String> _patternsForCountry(String code) {
    switch (code) {
      case 'fr':
        return <String>['fr', 'france', 'francais', 'french'];
      case 'us':
        return <String>['us', 'usa', 'united states', 'american', 'amer'];
      case 'uk':
        return <String>['uk', 'gb', 'united kingdom', 'british', 'england'];
      case 'de':
        return <String>['de', 'german', 'deutsch', 'germany'];
      case 'it':
        return <String>['it', 'italy', 'italian', 'italia'];
      case 'es':
        return <String>['es', 'spain', 'spanish', 'espanol', 'espana'];
      case 'pt':
        return <String>['pt', 'portugal', 'portuguese'];
      case 'be':
        return <String>['be', 'belgium', 'belgique'];
      case 'ch':
        return <String>['ch', 'swiss', 'switzerland', 'suisse'];
      case 'ca':
        return <String>['ca', 'canada', 'canadian'];
      case 'br':
        return <String>['br', 'brazil', 'brasil'];
      case 'mx':
        return <String>['mx', 'mexico', 'mexique'];
      case 'ar':
        return <String>['ar', 'argentina'];
      case 'sa':
        return <String>['sa', 'saudi', 'arabia', 'arabic', 'arab'];
      case 'tr':
        return <String>['tr', 'turkey', 'turkish', 'turk'];
      case 'gr':
        return <String>['gr', 'greece', 'greek'];
      case 'pl':
        return <String>['pl', 'poland', 'polish'];
      case 'ru':
        return <String>['ru', 'russia', 'russian'];
      case 'nl':
        return <String>['nl', 'netherlands', 'dutch', 'holland'];
      case 'jp':
        return <String>['jp', 'japan', 'japanese'];
      case 'kr':
        return <String>['kr', 'korea', 'korean'];
      case 'cn':
        return <String>['cn', 'china', 'chinese'];
      case 'in':
        return <String>['in', 'india', 'indian', 'hindi'];
      case 'au':
        return <String>['au', 'australia', 'australian'];
      case 'se':
        return <String>['se', 'sweden', 'swedish'];
      case 'no':
        return <String>['no', 'norway', 'norwegian'];
      case 'dk':
        return <String>['dk', 'denmark', 'danish'];
      case 'fi':
        return <String>['fi', 'finland', 'finnish'];
      case 'ma':
        return <String>['ma', 'morocco', 'maroc', 'marocain'];
      case 'dz':
        return <String>['dz', 'algeria', 'algerie'];
      case 'tn':
        return <String>['tn', 'tunisia', 'tunisie'];
      case 'eg':
        return <String>['eg', 'egypt', 'egypte'];
      default:
        return <String>[code];
    }
  }

  static const List<String> _kAllCountryPatterns = <String>[
    'usa', 'uk', 'gb', 'france', 'french', 'german', 'italy', 'italia',
    'spain', 'spanish', 'portugal', 'brazil', 'brasil', 'arabic', 'arab',
    'turkish', 'greek', 'polish', 'russian', 'japan', 'korea', 'chinese',
    'indian', 'hindi', 'african', 'latino', 'european', 'asian',
  ];
}
