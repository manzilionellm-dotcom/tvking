// =========================================================
//  source_link_utils.dart — Rendre TOUT lien M3U / Xtream acceptable
// =========================================================
//  Constat (panel admin + écrans d'ajout mobile/TV) : plusieurs points
//  d'entrée exigeaient un « http:// » tapé mot pour mot et rejetaient
//  tout le reste, tandis que d'autres (l'écran TV « code Xtream », le
//  panel admin qui pousse les sources aux deux apps) n'ajustaient RIEN
//  → un lien fourni par le revendeur sans schéma (juste « serveur.com:8080 »)
//  cassait silencieusement (mauvaise construction d'URL en aval) au lieu
//  d'être simplement complété.
//
//  Ce module centralise DEUX corrections, appliquées à CHAQUE point
//  d'entrée (mobile, TV, panel admin, sources distantes) :
//
//    1. ensureScheme : complète http:// si l'utilisateur a juste tapé/
//       collé le domaine (ou domaine:port), sans jamais toucher un lien
//       qui a déjà un schéma (http, https, ou autre).
//    2. tryExtractXtreamCredentials : beaucoup de fournisseurs ne donnent
//       qu'UN SEUL lien (de type get.php?username=X&password=Y) au lieu
//       de 3 informations séparées (serveur / utilisateur / mot de
//       passe). Si ce lien est collé dans le champ « serveur » Xtream,
//       on le reconnaît et on en extrait les 3 informations tout seul.
//    3. cleanInput : les liens/codes arrivent presque toujours par
//       WhatsApp/Telegram, qui injectent des caractères INVISIBLES
//       (espace sans chasse U+200B, marques directionnelles U+200E/F
//       des claviers arabes, NBSP…). `trim()` ne les retire pas (et ne
//       retire rien AU MILIEU) → un lien visuellement parfait est
//       réellement corrompu → 404/401 inexplicable. On les purge.
//    4. sanitizeXtreamServer : si un lien COMPLET (get.php?…, portail
//       /c/, player_api.php…) est collé dans le champ « serveur » alors
//       que identifiant/mot de passe sont AUSSI remplis, l'extraction
//       (point 2) ne se déclenche pas et l'app appelait get.php au lieu
//       de player_api.php → « Réponse non-JSON » pour un code valide.
//       On réduit l'entrée au VRAI serveur (schéma://hôte[:port][/base]).
// =========================================================

abstract final class SourceLinkUtils {
  /// Même règle que le parseur M3U (`m3u_parser.dart`) : un schéma valide
  /// est `lettre + (lettres/chiffres/+/-/.) puis "://"`. Couvre http,
  /// https, et tout autre protocole qu'un fournisseur pourrait donner.
  static final RegExp _schemeRx = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://');

  /// Caractères invisibles courants dans un copier-coller de messagerie :
  /// U+200B-U+200F (zéro-chasse + marques directionnelles), U+FEFF (BOM),
  /// U+00AD (trait d'union conditionnel), U+2060 (word joiner),
  /// U+2028/U+2029 (séparateurs de ligne Unicode).
  static final RegExp _invisibleRx =
      RegExp('[\u200B-\u200F\uFEFF\u00AD\u2060\u2028\u2029]');

  /// Purge les caractères invisibles PARTOUT dans la chaîne (pas juste aux
  /// extrémités), remplace les espaces insécables par des espaces normaux,
  /// puis trim. À appliquer à TOUTE saisie utilisateur (URL, serveur,
  /// identifiant, mot de passe) avant usage.
  static String cleanInput(String raw) {
    return raw
        .replaceAll(_invisibleRx, '')
        .replaceAll('\u00A0', ' ')
        .trim();
  }

  /// Complète `http://` si [raw] n'a AUCUN schéma (cas très courant :
  /// le revendeur/fournisseur donne juste « serveur.com » ou
  /// « serveur.com:8080 », sans préciser http://). Ne touche jamais un
  /// lien qui a déjà un schéma — jamais de double préfixe. Purge au
  /// passage les caractères invisibles (cf. [cleanInput]).
  static String ensureScheme(String raw) {
    final String s = cleanInput(raw);
    if (s.isEmpty || _schemeRx.hasMatch(s)) return s;
    // Lien « protocole-relatif » (//serveur.com) : on ne préfixe que le
    // schéma, sinon on produirait http:////serveur.com.
    if (s.startsWith('//')) return 'http:$s';
    return 'http://$s';
  }

  /// Schémas AUTORISÉS pour une source de PLAYLIST/panel (M3U, Xtream) :
  /// uniquement http/https. Un lien de FLUX peut être rtmp/rtsp/udp, mais une
  /// SOURCE collée par l'utilisateur qui n'est pas http(s) (`file://`,
  /// `gopher://`, `javascript:`…) est soit une erreur, soit une tentative
  /// d'injection (lire un fichier local, sonder un service interne). On la
  /// refuse en amont plutôt que de la fetcher aveuglément.
  static const Set<String> _allowedSourceSchemes = <String>{'http', 'https'};

  /// `true` si [url] (après complétion de schéma) est une source http(s)
  /// exploitable. Sert de VALIDATION D'ENTRÉE avant tout fetch d'une URL
  /// collée par l'utilisateur (correctif d'audit — anti-injection/SSRF).
  static bool isAllowedSourceUrl(String url) {
    final String s = ensureScheme(url);
    final Uri? uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return false;
    return _allowedSourceSchemes.contains(uri.scheme.toLowerCase());
  }

  /// Fichiers d'API/portail connus qu'un client colle souvent avec le
  /// lien complet : ils ne font PAS partie de l'adresse du serveur.
  static final RegExp _xtreamEndpointRx = RegExp(
    r'/(get|player_api|panel_api|xmltv|portal|enigma2?)\.php$',
    caseSensitive: false,
  );

  /// Réduit une saisie « serveur Xtream » au vrai serveur :
  /// `schéma://hôte[:port][/sous-chemin]`, SANS fichier .php connu, sans
  /// query (?username=…) ni fragment, sans slash final. Un éventuel
  /// sous-chemin réel (panel installé sous /xtream/) est CONSERVÉ —
  /// on ne retire que le fichier d'API et le chemin portail « /c ».
  /// Entrée déjà propre → renvoyée telle quelle (jamais de casse).
  static String sanitizeXtreamServer(String raw) {
    final String s = ensureScheme(raw);
    if (s.isEmpty) return s;
    final Uri? uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return s;

    String path = uri.path.replaceFirst(_xtreamEndpointRx, '');
    // Chemin « portail MAG/Stalker » (/c ou /c/) : pas un vrai chemin d'API.
    if (path == '/c' || path == '/c/') path = '';
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    final String portSuffix = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$portSuffix$path';
  }

  /// Détecte un lien Xtream/M3U COMPLET (ex. celui donné pour VLC/Smarters :
  /// `http://serveur.com:8080/get.php?username=X&password=Y&type=m3u_plus`)
  /// collé par erreur dans le champ « serveur » Xtream (au lieu des 3
  /// champs séparés). Si les paramètres `username` et `password` sont
  /// présents dans la requête, on reconstruit le VRAI serveur
  /// (`scheme://host[:port]`) et on renvoie les 3 informations déjà
  /// séparées. Renvoie `null` si [raw] ne ressemble pas à ce cas (lien
  /// déjà « propre », ou pas un lien du tout).
  static ({String server, String username, String password})?
      tryExtractXtreamCredentials(String raw) {
    final String s = ensureScheme(raw);
    if (s.isEmpty) return null;
    final Uri? uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return null;

    final String? user = uri.queryParameters['username'];
    final String? pass = uri.queryParameters['password'];
    if (user == null || user.isEmpty || pass == null || pass.isEmpty) {
      return null;
    }

    // Reconstruit le serveur via sanitizeXtreamServer : un panel installé
    // sous un sous-chemin (http://hôte/xtream/get.php?…) garde son
    // sous-chemin, seuls le fichier .php et la query sont retirés.
    return (
      server: sanitizeXtreamServer(s),
      username: user,
      password: pass,
    );
  }
}
