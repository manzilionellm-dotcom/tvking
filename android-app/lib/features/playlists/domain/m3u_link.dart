// =========================================================
//  m3u_link.dart — Un lien « get.php » EST un compte Xtream
// =========================================================
//  Les revendeurs envoient presque toujours un lien de la forme
//    http://serveur:port/get.php?username=U&password=P&type=m3u_plus&output=ts
//  Ce lien fait générer au fournisseur un fichier M3U complet (chaînes,
//  films, séries : des dizaines de Mo, parfois plus de 90 s à produire —
//  mesuré le 05/10/2026 : « refusée après 90,0 s »).
//
//  Les grandes applications ne téléchargent pas ce fichier : elles
//  lisent les MÊMES identifiants par l'API Xtream (player_api.php),
//  qui renvoie la liste des chaînes TV seule, en JSON léger, en
//  quelques secondes. Films et séries viennent ensuite, à la demande.
//
//  Ce fichier extrait le compte Xtream d'un tel lien. Pur, testé.
//  Aucune adresse réelle ici.
// =========================================================

/// Compte Xtream déduit d'un lien get.php.
class XtreamAccount {
  const XtreamAccount({
    required this.serverUrl,
    required this.username,
    required this.password,
  });

  /// `http://serveur:port` (sans « / » final, sans chemin).
  final String serverUrl;
  final String username;
  final String password;
}

/// `null` si le lien n'est pas un get.php avec identifiants (lien vers un
/// fichier .m3u statique, lien « lecteur », autre fournisseur…) : il garde
/// alors le chemin M3U classique.
XtreamAccount? xtreamFromM3uLink(String? raw) {
  final String text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final Uri? uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  // Le fichier doit s'appeler get.php, quel que soit le dossier.
  final String last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
  if (last.toLowerCase() != 'get.php') return null;
  final String user = (uri.queryParameters['username'] ?? '').trim();
  final String pass = (uri.queryParameters['password'] ?? '').trim();
  if (user.isEmpty || pass.isEmpty) return null;
  final String port = uri.hasPort ? ':${uri.port}' : '';
  return XtreamAccount(
    serverUrl: '${uri.scheme}://${uri.host}$port',
    username: user,
    password: pass,
  );
}
