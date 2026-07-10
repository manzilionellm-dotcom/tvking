// =========================================================
//  source_input_normalizer.dart — Tolérance aux FAUTES DE FRAPPE
// =========================================================
//  Le client tape son lien M3U / code Xtream à la TÉLÉCOMMANDE, souvent
//  en recopiant un message WhatsApp lettre par lettre. Résultat observé
//  sur le terrain : `htp://`, `server,com` (virgule au lieu du point),
//  `serveur..com`, un espace glissé au milieu, `:8080.` — et l'app
//  répondait « connexion impossible » pour un abonnement pourtant VALIDE.
//
//  Ce module répare ces fautes AVANT tout appel réseau, en fonctions
//  PURES (aucune dépendance Flutter/IO → testables à la milliseconde) :
//
//    • normalizeUrl : espaces/retours à la ligne purgés, schéma réparé
//      (htp:// → http://…), hôte réparé (virgules → points, `..` → `.`),
//      port nettoyé (`:8080.` → `:8080`), casse du schéma+hôte abaissée.
//      La casse du CHEMIN et de la QUERY est PRÉSERVÉE : les identifiants
//      Xtream (username=John) sont sensibles à la casse.
//      Chaque correction VISIBLE est décrite (« server,com → server.com »)
//      pour que l'écran puisse dire ce qu'il a réparé (confiance).
//
//    • analyze : AUTO-DÉTECTION du type de lien collé/tapé. Un lien
//      `get.php?username=X&password=Y` → les 3 champs Xtream déjà
//      extraits ; un `.m3u`/`.m3u8` → chemin M3U ; un portail Xtream
//      sans identifiants → serveur pré-rempli. Le client n'a PAS à
//      savoir ce que veut dire « Xtream ».
//
//  On RÉUTILISE SourceLinkUtils (cleanInput / tryExtractXtreamCredentials /
//  sanitizeXtreamServer) : ce fichier n'ajoute que la couche « fautes de
//  frappe », sans dupliquer la normalisation existante.
// =========================================================

import 'source_link_utils.dart';

/// Ce que représente l'entrée du client, détecté tout seul.
enum SourceInputKind {
  /// Lien Xtream complet (get.php?username=…) OU portail Xtream reconnu.
  xtream,

  /// Lien direct vers un fichier de liste (.m3u / .m3u8).
  m3u,

  /// Impossible de trancher (domaine seul, texte quelconque…) : l'écran
  /// demandera au client, avec les champs déjà pré-remplis.
  unknown,
}

/// Résultat de [SourceInputNormalizer.normalizeUrl].
class NormalizedInput {
  const NormalizedInput({required this.value, required this.fixes});

  /// L'URL réparée, prête pour le réseau.
  final String value;

  /// Corrections lisibles (« server,com → server.com ») à montrer au
  /// client. Vide = rien n'a été réparé (ou juste du cosmétique
  /// invisible : casse du schéma, http:// complété — on ne l'affiche pas
  /// pour ne pas inquiéter inutilement).
  final List<String> fixes;

  bool get wasFixed => fixes.isNotEmpty;
}

/// Résultat de [SourceInputNormalizer.analyze] : le type détecté + les
/// champs déjà extraits quand c'est possible.
class SourceInputAnalysis {
  const SourceInputAnalysis({
    required this.kind,
    required this.url,
    required this.fixes,
    this.xtreamServer,
    this.xtreamUsername,
    this.xtreamPassword,
  });

  final SourceInputKind kind;

  /// L'entrée normalisée (URL réparée), quel que soit le type.
  final String url;

  /// Corrections appliquées (cf. [NormalizedInput.fixes]).
  final List<String> fixes;

  /// Renseignés quand [kind] == xtream. `xtreamUsername`/`xtreamPassword`
  /// peuvent rester null si le lien ne les contenait pas (portail seul) :
  /// l'écran les demandera, serveur déjà pré-rempli.
  final String? xtreamServer;
  final String? xtreamUsername;
  final String? xtreamPassword;

  bool get hasXtreamCredentials =>
      xtreamUsername != null && xtreamPassword != null;
}

abstract final class SourceInputNormalizer {
  /// Schéma déjà VALIDE (http, https, rtmp…) : on n'y touche pas
  /// (même règle que SourceLinkUtils / m3u_parser).
  static final RegExp _validSchemeRx =
      RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*)://');

  /// Schéma http(s) CASSÉ par une faute de frappe : `htp://`, `http:/`,
  /// `http//`, `ttp://`, `htttp://`, `https:\`… On exige au moins un `t`
  /// et un `p` PLUS un séparateur (`:`/`;` + slashes, ou ≥ 2 slashes) —
  /// jamais un hôte qui commencerait par ces lettres ne matche.
  static final RegExp _brokenHttpRx = RegExp(
    r'^(h{0,2}t{1,3}p{1,2}s?)([:;][/\\]{0,3}|[/\\]{2,3})',
    caseSensitive: false,
  );

  /// Répare une URL tapée à la télécommande. Fonction PURE.
  /// Voir l'en-tête du fichier pour la liste des réparations.
  static NormalizedInput normalizeUrl(String raw) {
    final List<String> fixes = <String>[];

    // 1) Invisibles de messagerie (délégué à SourceLinkUtils) puis
    //    ESPACES / RETOURS À LA LIGNE partout : jamais légitimes dans une
    //    URL, toujours une faute de frappe ou un copier-coller qui a
    //    « plié » le lien sur deux lignes.
    String s = SourceLinkUtils.cleanInput(raw);
    final String noSpaces = s.replaceAll(RegExp(r'\s+'), '');
    if (noSpaces != s) fixes.add('espaces retirés');
    s = noSpaces;
    if (s.isEmpty) return NormalizedInput(value: '', fixes: fixes);

    // 2) SCHÉMA. Ordre important : on teste d'abord le schéma http cassé
    //    (car `htp://` matche AUSSI la forme « schéma valide »),
    //    puis un schéma valide quelconque, puis les cas sans schéma.
    String scheme;
    String rest;
    final Match? broken = _brokenHttpRx.firstMatch(s);
    if (broken != null) {
      scheme = broken.group(1)!.toLowerCase().endsWith('s') ? 'https' : 'http';
      rest = s.substring(broken.end);
      // On ne signale que si la RÉPARATION change vraiment quelque chose
      // (un `http://` correct matche aussi, mais ne mérite aucun message).
      final String before = broken.group(0)!;
      if (before.toLowerCase() != '$scheme://') {
        fixes.add('$before → $scheme://');
      }
    } else {
      final Match? valid = _validSchemeRx.firstMatch(s);
      if (valid != null) {
        scheme = valid.group(1)!.toLowerCase(); // rtmp://, ftp://… gardés
        rest = s.substring(valid.end);
      } else if (s.startsWith('//')) {
        // Lien « protocole-relatif » (//serveur.com).
        scheme = 'http';
        rest = s.substring(2);
      } else {
        // Aucun schéma : on complète http:// en silence (comportement
        // historique d'ensureScheme — pas une « faute », pas de message).
        scheme = 'http';
        rest = s;
      }
    }

    // 3) AUTORITÉ (hôte[:port]) vs CHEMIN+QUERY : l'autorité s'arrête au
    //    premier `/`, `?` ou `#`. Tout ce qui suit garde sa CASSE
    //    (usernames Xtream sensibles à la casse).
    int cut = rest.length;
    for (final String stop in <String>['/', '?', '#']) {
      final int i = rest.indexOf(stop);
      if (i >= 0 && i < cut) cut = i;
    }
    String authority = rest.substring(0, cut);
    final String tail = rest.substring(cut);

    // 4) Réparations de l'AUTORITÉ. Un éventuel user:pass@ (rare mais
    //    légal) est préservé tel quel — sensible à la casse lui aussi.
    String userInfo = '';
    final int at = authority.lastIndexOf('@');
    if (at >= 0) {
      userInfo = authority.substring(0, at + 1);
      authority = authority.substring(at + 1);
    }
    final String authBefore = authority;

    // Virgule au lieu du point : `server,com` → `server.com` (touches
    // voisines sur la plupart des claviers). Puis points doublés, points
    // parasites en tête/queue d'hôte.
    authority = authority.replaceAll(',', '.');
    authority = authority.replaceAll(RegExp(r'\.{2,}'), '.');

    // Sépare hôte / port au DERNIER `:` (un seul port possible).
    String host = authority;
    String port = '';
    final int colon = authority.lastIndexOf(':');
    if (colon >= 0) {
      host = authority.substring(0, colon);
      port = authority.substring(colon + 1);
    }
    while (host.startsWith('.')) {
      host = host.substring(1);
    }
    while (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    host = host.toLowerCase(); // les noms de domaine sont insensibles à la casse

    // Port : ne garde que les chiffres (`:8080.` → `:8080`) ; un port
    // vide après nettoyage = deux-points parasites, on le retire.
    port = port.replaceAll(RegExp(r'[^0-9]'), '');
    authority = port.isEmpty ? host : '$host:$port';

    // On signale la réparation d'hôte/port seulement si elle dépasse la
    // simple mise en minuscules (cosmétique, sans conséquence).
    if (authBefore.toLowerCase() != authority) {
      fixes.add('$authBefore → $authority');
    }

    return NormalizedInput(
      value: '$scheme://$userInfo$authority$tail',
      fixes: fixes,
    );
  }

  /// Fichiers d'API Xtream reconnus en fin de chemin (sans identifiants
  /// dans la query) : le lien désigne un PANEL Xtream, pas un fichier M3U.
  static final RegExp _xtreamPathRx = RegExp(
    r'/(get|player_api|panel_api)\.php/?$',
    caseSensitive: false,
  );

  /// Auto-détection : répare l'entrée puis devine ce que c'est.
  /// Fonction PURE — aucun appel réseau, juste de l'analyse de texte.
  static SourceInputAnalysis analyze(String raw) {
    final NormalizedInput n = normalizeUrl(raw);
    final String url = n.value;
    if (url.isEmpty) {
      return SourceInputAnalysis(
          kind: SourceInputKind.unknown, url: '', fixes: n.fixes);
    }

    // 1) Lien Xtream COMPLET (get.php?username=X&password=Y…) : on
    //    réutilise l'extracteur existant → les 3 champs déjà séparés.
    final ({String server, String username, String password})? creds =
        SourceLinkUtils.tryExtractXtreamCredentials(url);
    if (creds != null) {
      return SourceInputAnalysis(
        kind: SourceInputKind.xtream,
        url: url,
        fixes: n.fixes,
        xtreamServer: creds.server,
        xtreamUsername: creds.username,
        xtreamPassword: creds.password,
      );
    }

    final Uri? uri = Uri.tryParse(url);
    final String path = uri?.path ?? '';
    final String lowerPath = path.toLowerCase();

    // 2) Fichier de liste : .m3u / .m3u8 en fin de chemin.
    if (lowerPath.endsWith('.m3u') || lowerPath.endsWith('.m3u8')) {
      return SourceInputAnalysis(
          kind: SourceInputKind.m3u, url: url, fixes: n.fixes);
    }

    // 3) Portail Xtream SANS identifiants (get.php nu, player_api.php,
    //    chemin portail /c) : serveur pré-rempli, identifiants à saisir.
    final bool portalPath = lowerPath == '/c' || lowerPath == '/c/';
    if (_xtreamPathRx.hasMatch(path) || portalPath) {
      return SourceInputAnalysis(
        kind: SourceInputKind.xtream,
        url: url,
        fixes: n.fixes,
        xtreamServer: SourceLinkUtils.sanitizeXtreamServer(url),
      );
    }

    // 4) Impossible de trancher (domaine seul « serveur.com:8080 »…) :
    //    l'écran demandera M3U ou Xtream, champs déjà pré-remplis.
    return SourceInputAnalysis(
        kind: SourceInputKind.unknown, url: url, fixes: n.fixes);
  }
}
