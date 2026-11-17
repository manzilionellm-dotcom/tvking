// =========================================================
//  m3u_vod_scanner.dart — Lit un M3U ligne par ligne, garde films + épisodes
// =========================================================
//  Un M3U de gros fournisseur fait 30 à 100 Mo et mélange 30 000 chaînes en
//  direct avec 100 000 films et épisodes. On ne garde en mémoire QUE les films
//  et les épisodes : chaque ligne est lue, jugée, puis oubliée.
//
//  Le lecteur est PUR (aucun réseau, aucun fichier, aucun widget) : on lui
//  donne des lignes, il rend des entrées. Il tourne donc dans un isolate et
//  se teste avec quelques lignes écrites à la main.
//
//  Tolérances (les M3U de la nature sont tordus) :
//    • attributs entre guillemets doubles, simples, ou sans guillemets ;
//    • virgule dans le nom, apostrophe dans la catégorie ;
//    • #EXTGRP sur une ligne à part ;
//    • lignes #EXTVLCOPT / #KODIPROP / #EXT-X-… ignorées ;
//    • adresse sans ligne #EXTINF (le nom vient alors du fichier) ;
//    • BOM en tête, lignes vides, espaces partout.
// =========================================================
import '../domain/m3u_vod_classifier.dart';

/// Un film ou un épisode lu dans le M3U.
class M3uVodEntry {
  const M3uVodEntry({
    required this.kind,
    required this.name,
    required this.category,
    required this.url,
    required this.ext,
    this.logo,
    this.series = '',
    this.season = 1,
    this.episode = 0,
  });

  final M3uVodKind kind;

  /// Nom affiché tel que le M3U le donne (film), ou nom COMPLET de la ligne
  /// (épisode : l'écran en retire le nom de la série et le code SxxExx).
  final String name;

  /// `group-title` brut (nettoyé plus tard pour l'affichage).
  final String category;
  final String url;

  /// Extension du fichier (mkv, mp4…), « mp4 » par défaut.
  final String ext;
  final String? logo;

  /// Épisodes seulement : nom de la série, saison, numéro.
  final String series;
  final int season;
  final int episode;
}

/// Lecteur incrémental. On appelle [feed] pour chaque ligne ; [onEntry] est
/// appelé à chaque film / épisode trouvé.
class M3uVodScanner {
  M3uVodScanner({required this.onEntry});

  final void Function(M3uVodEntry entry) onEntry;

  /// Statistiques, pour la boîte noire.
  int lines = 0;
  int urls = 0;
  int movies = 0;
  int episodes = 0;

  // Réglages lus sur la ligne #EXTINF, en attente de l'adresse qui suit.
  Map<String, String>? _attrs;
  String _pendingName = '';
  String _extGroup = '';

  static final RegExp _rxAttr = RegExp(
    r'''([A-Za-z0-9_\-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"',]+))''',
  );

  /// Une ligne du fichier (avec ou sans saut de ligne final).
  void feed(String raw) {
    lines++;
    String line = raw.trim();
    if (line.isEmpty) return;
    if (lines == 1 && line.codeUnitAt(0) == 0xFEFF) {
      line = line.substring(1).trimLeft();
      if (line.isEmpty) return;
    }
    if (line.codeUnitAt(0) == 0x23) {
      // « # » : commentaire ou balise.
      final String upper = line.length > 8 ? line.substring(0, 8).toUpperCase() : line.toUpperCase();
      if (upper.startsWith('#EXTINF')) {
        _readExtInf(line);
      } else if (upper.startsWith('#EXTGRP')) {
        final int colon = line.indexOf(':');
        _extGroup = colon < 0 ? '' : line.substring(colon + 1).trim();
      }
      return;
    }
    _readUrl(line);
  }

  void _readExtInf(String line) {
    final int colon = line.indexOf(':');
    final String body = colon < 0 ? '' : line.substring(colon + 1);
    // La 1re virgule HORS guillemets sépare les réglages du nom affiché.
    int comma = -1;
    String quote = '';
    for (int i = 0; i < body.length; i++) {
      final String c = body[i];
      if (quote.isNotEmpty) {
        if (c == quote) quote = '';
      } else if (c == '"' || c == "'") {
        quote = c;
      } else if (c == ',') {
        comma = i;
        break;
      }
    }
    if (comma < 0) comma = body.lastIndexOf(',');
    final String head = comma < 0 ? body : body.substring(0, comma);
    final String name = comma < 0 ? '' : body.substring(comma + 1).trim();
    final Map<String, String> attrs = <String, String>{};
    for (final RegExpMatch m in _rxAttr.allMatches(head)) {
      attrs[m.group(1)!.toLowerCase()] =
          (m.group(2) ?? m.group(3) ?? m.group(4) ?? '').trim();
    }
    _attrs = attrs;
    _pendingName = name.isNotEmpty ? name : (attrs['tvg-name'] ?? '');
  }

  void _readUrl(String url) {
    urls++;
    final Map<String, String> attrs = _attrs ?? const <String, String>{};
    String name = _pendingName;
    final String group = (attrs['group-title'] ?? '').isNotEmpty
        ? attrs['group-title']!
        : _extGroup;
    final String logo = attrs['tvg-logo'] ?? '';
    _attrs = null;
    _pendingName = '';
    _extGroup = '';

    // Jugement : la ligne est-elle un film, un épisode, un direct ?
    if (name.isEmpty) name = M3uVodClassifier.nameFromUrl(url);
    final M3uVodKind? kind =
        M3uVodClassifier.classify(name: name, group: group, url: url);
    if (kind == null) return;

    String ext = M3uVodClassifier.extensionOf(url);
    if (ext.isEmpty) ext = 'mp4';
    final String? poster = _poster(logo);
    if (kind == M3uVodKind.movie) {
      movies++;
      onEntry(M3uVodEntry(
        kind: kind,
        name: name,
        category: group,
        url: url,
        ext: ext,
        logo: poster,
      ));
      return;
    }
    episodes++;
    final M3uEpisodeName? parsed = M3uVodClassifier.parseEpisode(name);
    onEntry(M3uVodEntry(
      kind: kind,
      name: name,
      category: group,
      url: url,
      ext: ext,
      logo: poster,
      // Adresse « /series/ » sans code dans le nom : l'épisode porte le nom
      // de la ligne, saison 1, numéro inconnu (0 → classé par ordre du M3U).
      series: parsed?.series ?? name,
      season: parsed?.season ?? 1,
      episode: parsed?.episode ?? 0,
    ));
  }

  static String? _poster(String raw) {
    final String s = raw.trim();
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    return null;
  }
}
