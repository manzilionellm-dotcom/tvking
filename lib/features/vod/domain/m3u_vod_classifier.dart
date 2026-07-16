// =========================================================
//  m3u_vod_classifier.dart — Classification VOD des entrées M3U
// =========================================================
//  Une playlist M3U « dans la nature » mélange TOUT : chaînes live,
//  films (fichiers .mp4/.mkv servis par le panel) et épisodes de
//  séries (« Breaking Bad S01 E03 »). Historiquement, l'app marquait
//  chaque entrée `isLive: true` → les films M3U polluaient les listes
//  de chaînes et n'apparaissaient JAMAIS dans le Cinéma.
//
//  Ce classificateur décide, pour une entrée M3U, si c'est :
//    - une chaîne LIVE   (flux continu .ts/.m3u8/rtmp/udp…)
//    - un FILM           (fichier fini, pas de numérotation SxxExx)
//    - un ÉPISODE        (fichier fini + numérotation SxxExx / 1x03)
//
//  RÈGLES VOLONTAIREMENT CONSERVATRICES — un live classé film perdrait
//  Guide/REC/zapping : on ne bascule en VOD QUE sur des indices
//  d'URL quasi certains (chemin Xtream /movie/ ou /series/, extension
//  de fichier fini), JAMAIS sur le seul nom ou group-title (trop
//  ambigu : un groupe « FILMS » peut contenir des chaînes cinéma live).
//
//  Logique PURE (aucun import Flutter) : tourne dans l'isolate du
//  parser M3U et se teste unitairement.
// =========================================================

/// Nature d'une entrée M3U.
enum M3uVodKind { live, movie, episode }

/// Numérotation extraite du nom d'un épisode (« Vikings S02 E05 » →
/// series « Vikings », saison 2, épisode 5).
class M3uEpisodeTag {
  const M3uEpisodeTag({
    required this.seriesName,
    required this.season,
    required this.episode,
  });

  /// Nom de la série, débarrassé de la numérotation et des séparateurs.
  final String seriesName;
  final int season;
  final int episode;
}

abstract final class M3uVodClassifier {
  /// Extensions de FICHIER FINI (un film/épisode est un fichier borné,
  /// seekable — par opposition à un flux continu .ts/.m3u8).
  static const Set<String> _fileExtensions = <String>{
    'mp4', 'mkv', 'avi', 'mov', 'm4v', 'webm', 'flv', 'wmv', 'mpg', 'mpeg',
  };

  /// « S01 E03 », « S1E3 », « s01.e03 », « S01-E03 »… (insensible à la casse).
  static final RegExp _sxxExx = RegExp(
    r'\bS(\d{1,2})\s*[\s._-]?\s*E(\d{1,4})\b',
    caseSensitive: false,
  );

  /// Variante « 1x03 » / « 01x03 ».
  static final RegExp _nxn = RegExp(r'\b(\d{1,2})x(\d{1,4})\b');

  /// Segments de chemin Xtream faisant foi : {server}/movie/{u}/{p}/id.ext
  /// et {server}/series/{u}/{p}/id.ext. Beaucoup de M3U « get.php » listent
  /// leurs VOD sous cette forme → indice quasi certain.
  static final RegExp _moviePath = RegExp(r'/movies?/', caseSensitive: false);
  static final RegExp _seriesPath = RegExp(r'/series/', caseSensitive: false);

  /// Classe une entrée M3U d'après son URL (fait foi) et son nom (ne sert
  /// QUE à départager film/épisode une fois le caractère VOD établi).
  static M3uVodKind classify({required String url, required String name}) {
    final String lower = url.toLowerCase();

    // Les protocoles de diffusion continue ne sont jamais des fichiers VOD.
    if (lower.startsWith('udp://') ||
        lower.startsWith('rtp://') ||
        lower.startsWith('rtsp://')) {
      return M3uVodKind.live;
    }

    // 1) Chemin Xtream explicite — l'indice le plus fort.
    if (_seriesPath.hasMatch(lower)) return M3uVodKind.episode;
    if (_moviePath.hasMatch(lower)) {
      // Un panel peut ranger des épisodes sous /movie/ : la numérotation
      // SxxExx dans le nom l'emporte alors sur le segment de chemin.
      return episodeTag(name) != null ? M3uVodKind.episode : M3uVodKind.movie;
    }

    // 2) Extension de fichier fini dans le CHEMIN (pas la query string).
    final String ext = _pathExtension(lower);
    if (_fileExtensions.contains(ext)) {
      return episodeTag(name) != null ? M3uVodKind.episode : M3uVodKind.movie;
    }

    // 3) Tout le reste (.ts, .m3u8, sans extension, schémas divers) = live.
    return M3uVodKind.live;
  }

  /// Extrait la numérotation « SxxExx » ou « 1x03 » d'un nom d'épisode,
  /// ainsi que le nom de série nettoyé. `null` si aucune numérotation.
  static M3uEpisodeTag? episodeTag(String name) {
    RegExpMatch? m = _sxxExx.firstMatch(name);
    m ??= _nxn.firstMatch(name);
    if (m == null) return null;
    final int season = int.tryParse(m.group(1) ?? '') ?? 0;
    final int episode = int.tryParse(m.group(2) ?? '') ?? 0;
    if (season <= 0 && episode <= 0) return null;

    // Nom de série = ce qui précède la numérotation, sinon ce qui la suit
    // (« S01E02 - Pilot » → « Pilot » est un TITRE, pas un nom de série ;
    // dans ce cas dégradé on garde le nom complet nettoyé).
    String series = name.substring(0, m.start).trim();
    series = series.replaceAll(RegExp(r'[\s._|:\-–—]+$'), '').trim();
    if (series.isEmpty) {
      series = name
          .replaceFirst(m.group(0)!, ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'^[\s._|:\-–—]+|[\s._|:\-–—]+$'), '')
          .trim();
    }
    if (series.isEmpty) return null;
    return M3uEpisodeTag(seriesName: series, season: season, episode: episode);
  }

  /// Extension du DERNIER segment de chemin de l'URL, query string exclue
  /// (« http://x/movie/u/p/123.mkv?token=abc » → « mkv »).
  static String _pathExtension(String lowerUrl) {
    int end = lowerUrl.indexOf('?');
    if (end < 0) end = lowerUrl.indexOf('#');
    final String path = end < 0 ? lowerUrl : lowerUrl.substring(0, end);
    final int slash = path.lastIndexOf('/');
    final String segment = slash < 0 ? path : path.substring(slash + 1);
    final int dot = segment.lastIndexOf('.');
    if (dot < 0 || dot == segment.length - 1) return '';
    return segment.substring(dot + 1);
  }
}
