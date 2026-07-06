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
// =========================================================

abstract final class SourceLinkUtils {
  /// Même règle que le parseur M3U (`m3u_parser.dart`) : un schéma valide
  /// est `lettre + (lettres/chiffres/+/-/.) puis "://"`. Couvre http,
  /// https, et tout autre protocole qu'un fournisseur pourrait donner.
  static final RegExp _schemeRx = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://');

  /// Complète `http://` si [raw] n'a AUCUN schéma (cas très courant :
  /// le revendeur/fournisseur donne juste « serveur.com » ou
  /// « serveur.com:8080 », sans préciser http://). Ne touche jamais un
  /// lien qui a déjà un schéma — jamais de double préfixe.
  static String ensureScheme(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || _schemeRx.hasMatch(s)) return s;
    return 'http://$s';
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
    final String s = ensureScheme(raw.trim());
    if (s.isEmpty) return null;
    final Uri? uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return null;

    final String? user = uri.queryParameters['username'];
    final String? pass = uri.queryParameters['password'];
    if (user == null || user.isEmpty || pass == null || pass.isEmpty) {
      return null;
    }

    final String portSuffix = uri.hasPort ? ':${uri.port}' : '';
    final String server = '${uri.scheme}://${uri.host}$portSuffix';
    return (server: server, username: user, password: pass);
  }
}
