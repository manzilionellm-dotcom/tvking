// =========================================================
//  secret_redactor.dart — Caviardage des secrets dans les journaux
// =========================================================
//  POURQUOI : les messages d'erreur remontés (ring de diagnostic, boîte
//  noire sur DISQUE, POST /api/error-log vers le panel) embarquent très
//  souvent l'URI complète d'une source IPTV. Or les URLs Xtream portent
//  les identifiants de l'abonné DANS le chemin
//  (`http://host/live/USER/PASS/123.ts`) ou dans la query
//  (`?username=U&password=P`). Sans caviardage, une simple `ClientException`
//  écrivait le mot de passe de l'abonné payant en clair sur le disque de la
//  box ET l'envoyait au backend → fuite de secret d'abonné.
//
//  Ce module est PUR (aucune I/O, aucune dépendance) et TESTABLE : il prend
//  un texte libre (pas seulement une URL bien formée, contrairement à
//  StreamDiagnostics.maskCredentials qui exige une Uri) et remplace les
//  motifs sensibles par « ••• ». Appliqué au point d'étranglement unique
//  CrashReporting.recordError → couvre TOUS les puits d'un coup.
// =========================================================

/// Caviardeur de secrets pour texte libre (messages d'erreur, traces).
class SecretRedactor {
  const SecretRedactor._();

  static const String _mask = '•••';

  // userinfo dans une URL : scheme://USER:PASS@host → scheme://•••:•••@host
  // PERF (run 003) : le quantificateur du schéma est BORNÉ à 32 caractères.
  // Sans borne, sur une longue ligne sans URL, le moteur avalait le reste de
  // la ligne à CHAQUE position puis backtrackait → O(n²) (timeout CI constaté
  // sur des lignes de 4 Ko dès que le redactor est passé sur le chemin de
  // toutes les lignes de log). Aucun schéma d'URI réel ne dépasse 32.
  static final RegExp _userInfo =
      RegExp(r'([a-zA-Z][a-zA-Z0-9+.\-]{0,31}://)[^/@\s:]+:[^/@\s]+@');

  // Paramètres de query sensibles : ?username=U&password=P&token=T …
  // On garde le nom du paramètre, on masque sa valeur (jusqu'au prochain
  // séparateur & / espace / guillemet / fin).
  static final RegExp _query = RegExp(
    // AUDIT 2026-07-29 : liste élargie — secret/auth/api_key/key/sig/pwd/
    // access_token/session passaient en clair.
    r'([?&](?:username|password|user|pass|pwd|token|access_token|session'
    r'|secret|auth|api_?key|key|sig|u|p)=)[^&\s"'
    "']+",
    caseSensitive: false,
  );

  // En-têtes sensibles sérialisés en texte libre (maps d'en-têtes dans un
  // ctx de log, dumps de requêtes) : `Authorization: Bearer xxx`,
  // `X-Admin-Secret: xxx`, `X-Api-Key: xxx`. AUDIT 2026-07-29 : aucun
  // motif ne les couvrait. Valeur bornée à 256 pour éviter tout backtrack.
  // La valeur d'en-tête peut contenir un espace (`Bearer <token>`) : on masque
  // jusqu'au prochain séparateur d'entrée (virgule, accolade, guillemet, fin
  // de ligne). Borné à 256 pour éviter tout backtrack pathologique.
  static final RegExp _header = RegExp(
    r'((?:authorization|x-admin-secret|x-api-key)\s*[:=]\s*)[^,;}\r\n"'
    "']{1,256}",
    caseSensitive: false,
  );

  /// Détection BORNÉE (simple `contains`, aucune regex) d'un nom d'en-tête
  /// sensible dans la ligne : sert uniquement à la sortie rapide de [redact]
  /// — les en-têtes n'exigent ni '/' ni '=' (`Authorization: Bearer xxx`),
  /// ils passeraient sinon sous le radar du raccourci.
  static bool _maybeHeader(String text) {
    final String lower = text.toLowerCase();
    return lower.contains('authorization') ||
        lower.contains('x-admin-secret') ||
        lower.contains('x-api-key');
  }

  // Chemin Xtream : .../USER/PASS/ID.ext — on masque les DEUX segments qui
  // précèdent le fichier terminal (schéma /live|/movie|/series ou racine).
  // On préserve les préfixes structurels connus (live/movie/series).
  // AUDIT 2026-07-29 : le segment terminal exigeait `\d+.ext` — un chemin
  // `/live/USER/PASS/stream` (sans extension, servi par certains panels)
  // passait en clair. Sous un préfixe structurel live|movie|series, les
  // deux segments suivants sont TOUJOURS user/pass : on accepte tout
  // segment terminal.
  static final RegExp _xtreamPath = RegExp(
    r'/(live|movie|series)/([^/\s]+)/([^/\s]+)/([^/\s"'
    "']+)",
    caseSensitive: false,
  );
  static final RegExp _xtreamBarePath = RegExp(
    r'(://[^/\s]+)/([^/\s]+)/([^/\s]+)/(\d+\.[a-zA-Z0-9]+)',
  );

  /// Renvoie [text] avec tous les secrets connus remplacés par « ••• ».
  /// Idempotent et tolérant : jamais d'exception (retourne l'entrée en cas
  /// d'imprévu). Une entrée sans secret ressort inchangée.
  static String redact(String text) {
    if (text.isEmpty) return text;
    // Sortie rapide : tous les motifs sensibles exigent un '/' (chemin ou
    // scheme://) ou un '=' (paramètre de query) — sauf les en-têtes, dont
    // le nom est cherché par un contains borné (pas de regex sur le cas
    // de très loin le plus fréquent : la ligne de log banale).
    if (!text.contains('/') && !text.contains('=') && !_maybeHeader(text)) {
      return text;
    }
    try {
      String out = text.replaceAllMapped(
          _userInfo, (Match m) => '${m.group(1)}$_mask:$_mask@');
      out = out.replaceAllMapped(_query, (Match m) => '${m.group(1)}$_mask');
      out = out.replaceAllMapped(_header, (Match m) => '${m.group(1)}$_mask');
      out = out.replaceAllMapped(
          _xtreamPath, (Match m) => '/${m.group(1)}/$_mask/$_mask/${m.group(4)}');
      out = out.replaceAllMapped(_xtreamBarePath,
          (Match m) => '${m.group(1)}/$_mask/$_mask/${m.group(4)}');
      return out;
    } catch (_) {
      return text;
    }
  }
}
