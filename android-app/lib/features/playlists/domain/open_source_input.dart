// =========================================================
//  open_source_input.dart — Saisie ouverte d'une source
// =========================================================
//  L'application ne propose PLUS de liste « Serveur 1, Serveur 2… ».
//  La personne ajoute ELLE-MÊME sa source, chez n'importe quel
//  fournisseur. Aucun domaine n'est imposé, aucune liste blanche.
//
//  Trois façons, toutes ramenées à ce que le dépôt sait déjà
//  enregistrer (M3U ou Xtream) :
//    1. une adresse M3U ou M3U8, avec ou sans identifiants dans
//       l'adresse (compte:motdepasse@hôte, ou paramètres) ;
//    2. des identifiants Xtream Codes : adresse du serveur,
//       nom d'utilisateur, mot de passe ;
//    3. une adresse de lecteur du type get.php (ou player_api.php).
//       Si elle contient le nom et le mot de passe, on en tire un
//       compte Xtream. Sinon on explique, en français simple, ce
//       qui manque.
//
//  Ce fichier ne contacte aucun réseau et n'écrit aucun secret dans
//  un journal. Il dit seulement « cette saisie est complète » ou
//  « voici la phrase à montrer ».
//
//  Un abonné déjà configuré n'est pas concerné : sa liste est déjà
//  en base, avec l'adresse complète. On ne lui redemande rien.
// =========================================================

/// Façon dont la personne a choisi de saisir sa source.
enum OpenEntryMode {
  /// Adresse du serveur + nom + mot de passe.
  xtream,

  /// Adresse d'une liste .m3u ou .m3u8.
  m3u,

  /// Adresse de lecteur (get.php, player_api.php).
  player,
}

/// Ce qu'on pourra enregistrer, une fois la saisie acceptée.
enum OpenSourceKind {
  m3u,
  xtream,
}

/// Résultat prêt à passer au dépôt de listes. Jamais affiché tel quel.
class OpenSourceDraft {
  const OpenSourceDraft.m3u(this.m3uUrl)
      : kind = OpenSourceKind.m3u,
        serverUrl = null,
        username = null,
        password = null;

  const OpenSourceDraft.xtream({
    required this.serverUrl,
    required this.username,
    required this.password,
  })  : kind = OpenSourceKind.xtream,
        m3uUrl = null;

  final OpenSourceKind kind;

  /// Adresse complète de la liste, identifiants compris s'il y en a.
  final String? m3uUrl;

  /// Origine Xtream, sans get.php et sans slash final.
  final String? serverUrl;
  final String? username;
  final String? password;
}

/// Soit une source exploitable, soit une phrase à afficher.
class OpenSourceParse {
  const OpenSourceParse._({this.draft, this.error});

  final OpenSourceDraft? draft;

  /// Phrase en français simple. Nulle quand [draft] est là.
  final String? error;

  bool get isValid => draft != null && (error == null || error!.isEmpty);
}

/// Vérifie une saisie avant tout appel réseau.
abstract final class OpenSourceInput {
  /// Adresse absente ou pas en http(s).
  static const String errNeedUrl =
      'Colle une adresse qui commence par http:// ou https://.';

  /// Les trois champs Xtream ne sont pas tous remplis.
  static const String errNeedXtream =
      'Indique l\'adresse du serveur, le nom d\'utilisateur et le mot de passe.';

  /// Lien get.php sans les deux identifiants.
  static const String errNeedPlayerCreds =
      'Ce lien de lecteur n\'a pas de nom d\'utilisateur ou de mot de passe. '
      'Colle le lien complet, ou remplis les trois champs Xtream.';

  /// Schéma autre que http / https (fichier local, javascript, etc.).
  static const String errBadScheme =
      'Cette adresse n\'est pas utilisable. Il faut un lien http ou https.';

  /// Libellé du troisième mode, le même partout (TV, téléphone, tests).
  static const String playerLabel = 'Lien lecteur';

  /// Compte Xtream saisi dans trois champs.
  ///
  /// Si la personne a collé une adresse get.php dans le champ serveur,
  /// on en retire l'origine et, si les champs nom / mot de passe sont
  /// vides, les identifiants qui sont déjà dans l'adresse.
  static OpenSourceParse xtream({
    required String server,
    required String username,
    required String password,
  }) {
    final String user = username.trim();
    final String pass = password.trim();
    final String? normalized = _normalize(server);
    if (normalized == null) {
      return const OpenSourceParse._(error: errNeedXtream);
    }
    if (_badScheme(normalized)) {
      return const OpenSourceParse._(error: errBadScheme);
    }
    final Uri? uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) {
      return const OpenSourceParse._(error: errNeedUrl);
    }

    String finalUser = user;
    String finalPass = pass;
    String base = _withoutTrailingSlash(normalized);
    if (_isPlayerPath(uri)) {
      if (finalUser.isEmpty) {
        finalUser = (uri.queryParameters['username'] ?? '').trim();
      }
      if (finalPass.isEmpty) {
        finalPass = (uri.queryParameters['password'] ?? '').trim();
      }
      base = _origin(uri);
    }
    if (base.isEmpty || finalUser.isEmpty || finalPass.isEmpty) {
      return const OpenSourceParse._(error: errNeedXtream);
    }
    return OpenSourceParse._(
      draft: OpenSourceDraft.xtream(
        serverUrl: base,
        username: finalUser,
        password: finalPass,
      ),
    );
  }

  /// Adresse de liste M3U / M3U8, ou lien get.php collé dans ce champ.
  ///
  /// Un get.php complet devient un compte Xtream (guide, films, séries).
  /// Une autre adresse http(s) reste une liste M3U, quel que soit l'hôte.
  static OpenSourceParse playlistLink(String raw) {
    return _link(raw, playerOnly: false);
  }

  /// Adresse de lecteur. Un get.php sans identifiants est refusé avec
  /// une phrase claire. Une liste .m3u collée ici est quand même acceptée :
  /// on ne bloque pas la personne parce qu'elle a choisi le mauvais onglet.
  static OpenSourceParse playerLink(String raw) {
    return _link(raw, playerOnly: true);
  }

  static OpenSourceParse _link(String raw, {required bool playerOnly}) {
    final String? normalized = _normalize(raw);
    if (normalized == null) {
      return const OpenSourceParse._(error: errNeedUrl);
    }
    if (_badScheme(normalized)) {
      return const OpenSourceParse._(error: errBadScheme);
    }
    final Uri? uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) {
      return const OpenSourceParse._(error: errNeedUrl);
    }
    if (_isPlayerPath(uri)) {
      final String user = (uri.queryParameters['username'] ?? '').trim();
      final String pass = (uri.queryParameters['password'] ?? '').trim();
      if (user.isEmpty || pass.isEmpty) {
        return const OpenSourceParse._(error: errNeedPlayerCreds);
      }
      return OpenSourceParse._(
        draft: OpenSourceDraft.xtream(
          serverUrl: _origin(uri),
          username: user,
          password: pass,
        ),
      );
    }
    if (playerOnly) {
      // Pas un get.php : on accepte quand même une liste http(s).
      // Le système est ouvert, le mauvais onglet ne doit pas bloquer.
    }
    return OpenSourceParse._(draft: OpenSourceDraft.m3u(normalized));
  }

  /// Ajoute http:// si la personne a oublié le schéma. Ne touche pas
  /// à un schéma déjà présent (même s'il est refusé plus loin).
  static String? _normalize(String raw) {
    final String s = raw.trim();
    if (s.isEmpty) return null;
    final String lower = s.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return s;
    }
    if (s.contains('://')) return s;
    return 'http://$s';
  }

  static bool _badScheme(String value) {
    final String lower = value.toLowerCase();
    return !lower.startsWith('http://') && !lower.startsWith('https://');
  }

  static bool _isPlayerPath(Uri uri) {
    final String path = uri.path.toLowerCase();
    return path.endsWith('get.php') || path.endsWith('player_api.php');
  }

  static String _origin(Uri uri) {
    final String port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  static String _withoutTrailingSlash(String value) {
    if (value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }
}
