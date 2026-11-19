// =========================================================
//  m3u_vod_classifier.dart — Film, épisode ou direct ? (fichier M3U)
// =========================================================
//  Un fichier M3U mélange tout : chaînes en direct, films, épisodes de
//  séries. Cinéma ne veut que les deux derniers. Ce fichier décide, pour
//  UNE ligne du M3U (nom + catégorie + adresse), de ce qu'elle est.
//
//  Fonctions PURES (aucun réseau, aucun widget, aucun fichier) :
//    • testables avec de vraies lignes de M3U ;
//    • appelables depuis un ISOLATE (le M3U d'un gros fournisseur pèse
//      des dizaines de Mo et ne doit JAMAIS être lu sur le fil de l'écran).
//
//  Règles, par ordre de confiance :
//    1. L'adresse porte le mot « /series/ » → épisode ; « /movie/ » → film
//       (c'est la forme standard des fournisseurs de type Xtream).
//    2. L'adresse porte « /live/ » (ou timeshift, radio…) → direct.
//    3. Sinon, seul un VRAI fichier vidéo (mp4, mkv, avi…) compte. Une
//       adresse .m3u8 ou .ts sans marqueur est un direct : on ne prend pas
//       une chaîne « Films 24/7 » pour un film.
//    4. Un fichier vidéo dont le nom contient S01E02, 1x02, « Saison 1
//       Épisode 2 »… est un épisode ; sinon c'est un film.
// =========================================================

/// Ce qu'une entrée du M3U est pour Cinéma. Un direct n'a pas de valeur :
/// la fonction [M3uVodClassifier.classify] rend `null`.
enum M3uVodKind { movie, episode }

/// Nom d'épisode décomposé : « Breaking Bad S01E02 Cat's in the Bag ».
class M3uEpisodeName {
  const M3uEpisodeName({
    required this.series,
    required this.season,
    required this.episode,
    required this.title,
  });

  /// Nom de la série, sans le code saison / épisode.
  final String series;
  final int season;
  final int episode;

  /// Ce qui suit le code (titre de l'épisode), souvent vide.
  final String title;
}

abstract final class M3uVodClassifier {
  /// Extensions de VRAIS fichiers vidéo. Volontairement sans `ts` ni
  /// `m3u8` : ce sont les formats des chaînes en direct.
  static const Set<String> videoExtensions = <String>{
    'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'mpg', 'mpeg',
    'vob', 'divx', '3gp', 'ogv', 'm2ts',
  };

  static final RegExp _rxSeriesPath = RegExp(r'/series/');
  static final RegExp _rxMoviePath = RegExp(r'/movie/');
  static final RegExp _rxLivePath =
      RegExp(r'/(?:live|timeshift|streaming|radio)/');
  static final RegExp _rxExt = RegExp(r'^[a-z0-9]{1,5}$');

  /// Film, épisode, ou `null` (direct, radio, adresse inutilisable).
  static M3uVodKind? classify({
    required String name,
    required String group,
    required String url,
  }) {
    if (!isPlayableScheme(url)) return null;
    final String path = pathOf(url).toLowerCase();
    if (_rxSeriesPath.hasMatch(path)) return M3uVodKind.episode;
    if (_rxMoviePath.hasMatch(path)) return M3uVodKind.movie;
    if (_rxLivePath.hasMatch(path)) return null;
    if (!videoExtensions.contains(extensionOf(url))) return null;
    if (parseEpisode(name) != null) return M3uVodKind.episode;
    return M3uVodKind.movie;
  }

  /// http, https et file : le reste (rtmp, udp, rtsp…) est du direct.
  static bool isPlayableScheme(String url) {
    final String u = url.trimLeft().toLowerCase();
    return u.startsWith('http://') ||
        u.startsWith('https://') ||
        u.startsWith('file://');
  }

  /// Chemin de l'adresse, sans serveur, sans « ?… » ni « #… ».
  /// Coupé à la main : une adresse de M3U contient souvent des espaces ou
  /// des accents que `Uri.parse` refuse.
  static String pathOf(String url) {
    String s = url.trim();
    final int cut = s.indexOf(RegExp(r'[?#]'));
    if (cut >= 0) s = s.substring(0, cut);
    final int scheme = s.indexOf('://');
    if (scheme >= 0) {
      final int slash = s.indexOf('/', scheme + 3);
      s = slash < 0 ? '' : s.substring(slash);
    }
    return s;
  }

  /// Extension du fichier (« mkv »), vide s'il n'y en a pas.
  static String extensionOf(String url) {
    final String path = pathOf(url);
    final String last = path.substring(path.lastIndexOf('/') + 1);
    final int dot = last.lastIndexOf('.');
    if (dot < 0 || dot == last.length - 1) return '';
    final String ext = last.substring(dot + 1).toLowerCase();
    return _rxExt.hasMatch(ext) ? ext : '';
  }

  // Les trois écritures d'un code saison / épisode, de la plus sûre à la
  // moins sûre. Le « (?<![A-Za-z0-9]) » évite de couper un mot : « Les
  // Misérables » ne contient pas de « s » collé à un « e » suivi de chiffres.
  static final RegExp _rxSxxExx = RegExp(
    r'(?<![A-Za-z0-9])[Ss](\d{1,3})[\s._\-]*[Ee](\d{1,4})(?![0-9])',
  );
  static final RegExp _rxNxNN = RegExp(
    r'(?<![A-Za-z0-9])(\d{1,2})[xX](\d{1,3})(?![0-9A-Za-z])',
  );
  static final RegExp _rxWords = RegExp(
    r'(?:saison|season|staffel|temporada|stagione|seizoen)\s*(\d{1,3})'
    r'[^0-9]{0,14}?(?:[eé]pisode|episodio|folge|aflevering|ep|e)\s*\.?\s*'
    r'(\d{1,4})(?![0-9])',
    caseSensitive: false,
  );
  static final RegExp _rxEdges = RegExp(
    r'^[\s\-–—:|._,\[\(]+|[\s\-–—:|._,\]\(]+$',
  );

  /// « Breaking Bad S01E02 Cat's in the Bag » → série, saison 1, épisode 2.
  /// `null` si le nom ne contient aucun code, ou si rien ne précède le code
  /// (impossible de savoir de quelle série il s'agit).
  static M3uEpisodeName? parseEpisode(String name) {
    for (final RegExp rx in <RegExp>[_rxSxxExx, _rxNxNN, _rxWords]) {
      final RegExpMatch? m = rx.firstMatch(name);
      if (m == null) continue;
      final String series = _trimEdges(name.substring(0, m.start));
      if (series.isEmpty) continue;
      return M3uEpisodeName(
        series: series,
        season: int.parse(m.group(1)!),
        episode: int.parse(m.group(2)!),
        title: _trimEdges(name.substring(m.end)),
      );
    }
    return null;
  }

  static String _trimEdges(String s) =>
      s.replaceAll(_rxEdges, '').replaceAll(RegExp(r'\s{2,}'), ' ').trim();

  /// Nom lisible tiré d'une adresse (M3U sans ligne #EXTINF) :
  /// « …/Mon%20Film_2020.mkv » → « Mon Film 2020 ».
  static String nameFromUrl(String url) {
    final String path = pathOf(url);
    String last = path.substring(path.lastIndexOf('/') + 1);
    try {
      last = Uri.decodeComponent(last);
    } catch (_) {
      // Pourcentage mal formé : on garde le texte tel quel.
    }
    final int dot = last.lastIndexOf('.');
    if (dot > 0) last = last.substring(0, dot);
    return last.replaceAll(RegExp(r'[._]+'), ' ').trim();
  }
}
