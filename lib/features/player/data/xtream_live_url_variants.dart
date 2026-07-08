// =========================================================
//  xtream_live_url_variants.dart — Cascade de variantes d'URL live Xtream
// =========================================================
//  PROBLÈME TERRAIN : les panels Xtream ne servent pas tous le live
//  sous la même forme d'URL. Pour le MÊME flux, on rencontre :
//
//    http://host/USER/PASS/ID.ts           (forme courte historique)
//    http://host/live/USER/PASS/ID.ts      (forme standard)
//    http://host/live/USER/PASS/ID.m3u8    (HLS, panels « m3u8 only »)
//    http://host/USER/PASS/ID.m3u8         (HLS sans préfixe)
//
//  Certains panels répondent 404 (+ page HTML) sur la forme qu'on a
//  construite alors qu'une AUTRE forme marche — c'est le cas « France 2
//  donne 404 chez nous mais joue dans IBO ». IBO essaie plusieurs
//  formes ; nous aussi désormais.
//
//  Ce fichier est PUR (aucune dépendance) : il ne fait que fabriquer
//  la liste ORDONNÉE des URL candidates. La sonde réseau, le journal
//  et l'adoption de la variante gagnante restent dans le lecteur.
//
//  IMPORTANT : cette cascade ne doit être utilisée QUE pour les
//  sources de type XTREAM. Une playlist M3U générique peut contenir
//  des URLs arbitraires (CDN, tokens, chemins exotiques) qui
//  ressemblent par hasard au schéma USER/PASS/ID — les réécrire
//  casserait des flux valides. Le GATE est fait par l'appelant
//  (type de la playlist), pas ici.
// =========================================================

/// Fabrique la cascade de variantes d'URL pour un flux LIVE Xtream.
class XtreamLiveUrlVariants {
  XtreamLiveUrlVariants._();

  /// Extensions live connues du protocole Xtream.
  static const Set<String> _knownExtensions = <String>{'ts', 'm3u8'};

  /// Renvoie la liste ORDONNÉE et dédupliquée des URL à essayer,
  /// conformément à la cascade décidée (s'arrêter au premier succès) :
  ///
  ///   a) URL d'origine telle quelle ;
  ///   b) `…/live/USER/PASS/ID.m3u8` ;
  ///   c) `…/live/USER/PASS/ID.ts` ;
  ///   d) `…/USER/PASS/ID.m3u8` (sans préfixe).
  ///
  /// Si l'URL ne ressemble pas au schéma live Xtream (`[live/]USER/
  /// PASS/ID[.ext]`), on ne tente RIEN d'autre : la liste ne contient
  /// que l'original. La query (`?token=…`) et le host:port sont
  /// toujours préservés tels quels.
  static List<String> cascade(String url) {
    final Uri? u = Uri.tryParse(url.trim());
    if (u == null || !u.hasAuthority) return <String>[url];

    // Segments de chemin sans le segment vide d'un éventuel '/' final.
    final List<String> segs = u.pathSegments
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);

    final String user;
    final String pass;
    final String last;
    if (segs.length == 3) {
      // USER/PASS/ID[.ext]
      user = segs[0];
      pass = segs[1];
      last = segs[2];
    } else if (segs.length == 4 && segs[0].toLowerCase() == 'live') {
      // live/USER/PASS/ID[.ext]
      user = segs[1];
      pass = segs[2];
      last = segs[3];
    } else {
      return <String>[url]; // schéma non reconnu → URL intacte
    }

    // Sépare ID / extension. Une extension inconnue (ex : `.php`) n'est
    // PAS du live Xtream → on ne fabrique rien.
    final int dot = last.lastIndexOf('.');
    final String id;
    if (dot > 0) {
      final String ext = last.substring(dot + 1).toLowerCase();
      if (!_knownExtensions.contains(ext)) return <String>[url];
      id = last.substring(0, dot);
    } else {
      id = last; // pas d'extension : certains panels servent `/ID` nu
    }
    if (id.isEmpty || user.isEmpty || pass.isEmpty) return <String>[url];

    String build(List<String> pathSegments) =>
        u.replace(pathSegments: pathSegments).toString();

    final List<String> ordered = <String>[
      url, //                                        a) original
      build(<String>['live', user, pass, '$id.m3u8']), // b)
      build(<String>['live', user, pass, '$id.ts']), //   c)
      build(<String>[user, pass, '$id.m3u8']), //          d)
    ];

    // Déduplique en préservant l'ordre (l'original est souvent
    // identique à b, c ou d).
    final Set<String> seen = <String>{};
    return ordered
        .where((String v) => seen.add(v))
        .toList(growable: false);
  }
}
