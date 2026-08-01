// =========================================================
//  xtream_url_variants.dart — Variantes d'URL Xtream (live / VOD / séries)
// =========================================================
//  PROBLÈME TERRAIN : les panels Xtream ne servent pas tous un même
//  contenu sous la même forme d'URL. Pour le MÊME flux live :
//
//    http://host/USER/PASS/ID.ts           (forme courte historique)
//    http://host/live/USER/PASS/ID.ts      (forme standard)
//    http://host/live/USER/PASS/ID.m3u8    (HLS, panels « m3u8 only »)
//    http://host/USER/PASS/ID.m3u8         (HLS sans préfixe)
//
//  et pour la VOD / les séries, avec ou sans préfixe :
//
//    http://host/movie/USER/PASS/ID.mp4  ↔  http://host/USER/PASS/ID.mp4
//    http://host/series/USER/PASS/ID.mkv ↔  http://host/USER/PASS/ID.mkv
//
//  Certains panels répondent 404 (+ page HTML) sur la forme qu'on a
//  construite alors qu'une AUTRE forme marche — c'est le cas « France 2
//  donne 404 chez nous mais joue dans IBO ». IBO essaie plusieurs
//  formes ; nous aussi désormais — et on MÉMORISE la forme gagnante
//  par source (cf. XtreamUrlFormatStore) pour un zapping instantané.
//
//  Ce fichier est PUR (aucune dépendance) : il ne fait que parser le
//  schéma Xtream et fabriquer des URL candidates. La sonde réseau, le
//  journal et la persistance restent chez les appelants.
//
//  IMPORTANT : ces réécritures ne doivent être utilisées QUE pour les
//  sources de type XTREAM. Une playlist M3U générique peut contenir
//  des URLs arbitraires (CDN, tokens, chemins exotiques) qui
//  ressemblent par hasard au schéma USER/PASS/ID — les réécrire
//  casserait des flux valides. Le GATE est fait par l'appelant
//  (type de la playlist), pas ici.
// =========================================================

/// Nature du contenu — détermine le préfixe Xtream et les variantes
/// pertinentes.
enum XtreamContentType { live, movie, series }

/// URL Xtream décomposée : `[prefix/]USER/PASS/ID[.ext]` (+ query).
class XtreamUrlShape {
  const XtreamUrlShape({
    required this.uri,
    required this.prefix,
    required this.user,
    required this.pass,
    required this.id,
    required this.ext,
  });

  /// URI d'origine (host:port + query préservés à la reconstruction).
  final Uri uri;

  /// `live` / `movie` / `series`, ou `null` pour la forme nue.
  final String? prefix;

  final String user;
  final String pass;
  final String id;

  /// Extension SANS le point (`ts`, `m3u8`, `mp4`…), `null` si absente.
  final String? ext;

  /// Préfixes de chemin connus du protocole Xtream.
  static const Set<String> knownPrefixes = <String>{
    'live', 'movie', 'series',
  };

  /// Parse une URL au schéma Xtream. Renvoie `null` si la forme ne
  /// correspond pas (nombre de segments, préfixe inconnu…) — dans ce
  /// cas l'appelant NE DOIT PAS réécrire l'URL.
  static XtreamUrlShape? parse(String url) {
    final Uri? u = Uri.tryParse(url.trim());
    if (u == null || !u.hasAuthority) return null;
    final List<String> segs = u.pathSegments
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);

    final String? prefix;
    final String user;
    final String pass;
    final String last;
    if (segs.length == 3) {
      prefix = null;
      user = segs[0];
      pass = segs[1];
      last = segs[2];
    } else if (segs.length == 4 &&
        knownPrefixes.contains(segs[0].toLowerCase())) {
      prefix = segs[0].toLowerCase();
      user = segs[1];
      pass = segs[2];
      last = segs[3];
    } else {
      return null;
    }

    final int dot = last.lastIndexOf('.');
    final String id;
    final String? ext;
    if (dot > 0) {
      id = last.substring(0, dot);
      ext = last.substring(dot + 1).toLowerCase();
    } else {
      id = last;
      ext = null;
    }
    if (id.isEmpty || user.isEmpty || pass.isEmpty) return null;

    return XtreamUrlShape(
      uri: u,
      prefix: prefix,
      user: user,
      pass: pass,
      id: id,
      ext: ext,
    );
  }

  /// Reconstruit une URL avec [newPrefix] (`null` = forme nue) et
  /// [newExt] (`null` = garder l'extension d'origine, y compris
  /// « aucune »).
  String build({required String? newPrefix, String? newExt}) {
    final String? effExt = newExt ?? ext;
    final String file = effExt == null ? id : '$id.$effExt';
    return uri.replace(pathSegments: <String>[
      if (newPrefix != null) newPrefix,
      user,
      pass,
      file,
    ]).toString();
  }
}

/// Une URL candidate de la cascade + le CODE de format qui la décrit
/// (c'est ce code qu'on persiste quand la variante gagne).
class XtreamUrlCandidate {
  const XtreamUrlCandidate({required this.url, required this.formatCode});

  final String url;

  /// `prefix:ext` — préfixe `none` pour la forme nue, `ext` vide pour
  /// « conserver l'extension du contenu » (cas VOD : le conteneur
  /// mp4/mkv est propre à chaque film, seul le préfixe se mémorise).
  final String formatCode;
}

/// Fabrique les cascades de variantes et applique un format mémorisé.
class XtreamUrlVariants {
  XtreamUrlVariants._();

  /// Extensions live connues du protocole Xtream.
  static const Set<String> liveExtensions = <String>{'ts', 'm3u8'};

  /// Cascade ORDONNÉE et dédupliquée pour un contenu [type]
  /// (s'arrêter au premier succès) :
  ///
  ///   LIVE   : a) originale ; b) `live/U/P/ID.m3u8` ;
  ///            c) `live/U/P/ID.ts` ; d) `U/P/ID.m3u8`.
  ///   MOVIE  : a) originale ; b) `movie/U/P/ID.<ext>` ;
  ///            c) `U/P/ID.<ext>` (extension du conteneur conservée).
  ///   SERIES : a) originale ; b) `series/U/P/ID.<ext>` ;
  ///            c) `U/P/ID.<ext>`.
  ///
  /// Si l'URL ne ressemble pas au schéma Xtream (ou extension live
  /// inconnue pour un live), on ne tente RIEN : liste = [originale].
  static List<XtreamUrlCandidate> cascadeFor(
    String url,
    XtreamContentType type,
  ) {
    final XtreamUrlCandidate original = XtreamUrlCandidate(
      url: url,
      formatCode: formatCodeOf(url) ?? 'original',
    );
    final XtreamUrlShape? shape = XtreamUrlShape.parse(url);
    if (shape == null) return <XtreamUrlCandidate>[original];

    final List<XtreamUrlCandidate> ordered;
    switch (type) {
      case XtreamContentType.live:
        // Un live avec une extension hors protocole (`.mp4`…) n'est pas
        // du live Xtream réécrivable — on n'invente rien.
        if (shape.ext != null && !liveExtensions.contains(shape.ext)) {
          return <XtreamUrlCandidate>[original];
        }
        // ORDRE : on préfère le `.ts` (préfixé `/live/`) au HLS. Un `.ts`
        // = UNE seule connexion continue via le relais (regarder +
        // enregistrer sur 1 socket), idéal pour les comptes « max 1
        // connexion » — c'est ce que fait IBO. Le HLS (`.m3u8`) ouvre au
        // contraire plusieurs connexions (playlist repollée + segments)
        // et sature un compte 1-connexion → écran noir (terrain
        // 2026-07-09, compte « connexions 3/1 »). On ne retombe sur le
        // HLS que si le `.ts` préfixé échoue.
        ordered = <XtreamUrlCandidate>[
          original,
          XtreamUrlCandidate(
            url: shape.build(newPrefix: 'live', newExt: 'ts'),
            formatCode: 'live:ts',
          ),
          XtreamUrlCandidate(
            url: shape.build(newPrefix: 'live', newExt: 'm3u8'),
            formatCode: 'live:m3u8',
          ),
          XtreamUrlCandidate(
            url: shape.build(newPrefix: null, newExt: 'm3u8'),
            formatCode: 'none:m3u8',
          ),
        ];
      case XtreamContentType.movie:
        ordered = <XtreamUrlCandidate>[
          original,
          XtreamUrlCandidate(
            url: shape.build(newPrefix: 'movie'),
            formatCode: 'movie:',
          ),
          XtreamUrlCandidate(
            url: shape.build(newPrefix: null),
            formatCode: 'none:',
          ),
        ];
      case XtreamContentType.series:
        ordered = <XtreamUrlCandidate>[
          original,
          XtreamUrlCandidate(
            url: shape.build(newPrefix: 'series'),
            formatCode: 'series:',
          ),
          XtreamUrlCandidate(
            url: shape.build(newPrefix: null),
            formatCode: 'none:',
          ),
        ];
    }

    // Déduplique par URL en préservant l'ordre (l'originale absorbe
    // souvent une des variantes).
    final Set<String> seen = <String>{};
    return ordered
        .where((XtreamUrlCandidate c) => seen.add(c.url))
        .toList(growable: false);
  }

  /// Compatibilité : cascade LIVE sous forme de simples URLs
  /// (signature historique, utilisée par les tests d'origine).
  static List<String> cascade(String url) => cascadeFor(
        url,
        XtreamContentType.live,
      ).map((XtreamUrlCandidate c) => c.url).toList(growable: false);

  /// CODE de format d'une URL telle quelle (`live:ts`, `none:m3u8`,
  /// `movie:`…) ou `null` si elle n'a pas le schéma Xtream. Pour les
  /// préfixes VOD (movie/series) l'extension n'est PAS encodée : elle
  /// appartient au contenu, pas au panel.
  static String? formatCodeOf(String url) {
    final XtreamUrlShape? shape = XtreamUrlShape.parse(url);
    if (shape == null) return null;
    final String prefix = shape.prefix ?? 'none';
    final bool vod = shape.prefix == 'movie' || shape.prefix == 'series';
    return vod ? '$prefix:' : '$prefix:${shape.ext ?? ''}';
  }

  /// Applique un format MÉMORISÉ (`prefix:ext`) à une URL du même
  /// schéma. Renvoie `null` si l'URL n'est pas réécrivable (pas du
  /// schéma Xtream — fichier local, CDN…) ou si le code est invalide.
  /// Une extension vide dans le code = conserver celle du contenu.
  static String? applyFormat(String url, String formatCode) {
    final XtreamUrlShape? shape = XtreamUrlShape.parse(url);
    if (shape == null) return null;
    final int sep = formatCode.indexOf(':');
    if (sep <= 0) return null;
    final String prefix = formatCode.substring(0, sep);
    final String ext = formatCode.substring(sep + 1);
    if (prefix != 'none' && !XtreamUrlShape.knownPrefixes.contains(prefix)) {
      return null;
    }
    return shape.build(
      newPrefix: prefix == 'none' ? null : prefix,
      newExt: ext.isEmpty ? null : ext,
    );
  }

  /// Type de contenu déduit du PRÉFIXE de l'URL (`movie` / `series` /
  /// `live`), ou `null` pour une forme nue — l'appelant tranche alors
  /// avec ce qu'il sait du contenu (`Channel.isLive`).
  static XtreamContentType? detectType(String url) {
    switch (XtreamUrlShape.parse(url)?.prefix) {
      case 'live':
        return XtreamContentType.live;
      case 'movie':
        return XtreamContentType.movie;
      case 'series':
        return XtreamContentType.series;
      default:
        return null;
    }
  }
}

/// SECONDE CHANCE DE L'APERÇU (terrain 2026-08-01) — le plein écran joue,
/// l'aperçu affiche le logo : le plein écran déroule la cascade complète
/// tandis que l'aperçu s'arrêtait à la PREMIÈRE forme d'URL. Or beaucoup de
/// panels ne servent le live que sous `live/USER/PASS/ID.ts` : la forme nue
/// renvoie HTTP 404 → aperçu mort sur TOUTES les chaînes.
///
/// Renvoie le PROCHAIN candidat à tenter pour [url] (type [type]) en sautant
/// les formats déjà essayés ([tried], par `formatCode`), ou `null` s'il n'en
/// reste plus. Fonction PURE — l'aperçu s'en sert pour UNE ou DEUX tentatives
/// supplémentaires seulement (jamais les 8 sondes du plein écran, qui
/// ouvriraient trop de connexions).
XtreamUrlCandidate? nextPreviewVariant({
  required String url,
  required XtreamContentType type,
  required Set<String> tried,
}) {
  for (final XtreamUrlCandidate c in XtreamUrlVariants.cascadeFor(url, type)) {
    if (!tried.contains(c.formatCode)) return c;
  }
  return null;
}
