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
  static final RegExp _userInfo =
      RegExp(r'([a-zA-Z][a-zA-Z0-9+.\-]*://)[^/@\s:]+:[^/@\s]+@');

  // Paramètres de query sensibles : ?username=U&password=P&token=T …
  // On garde le nom du paramètre, on masque sa valeur (jusqu'au prochain
  // séparateur & / espace / guillemet / fin).
  static final RegExp _query = RegExp(
    r'([?&](?:username|password|user|pass|token|u|p)=)[^&\s"'
    "']+",
    caseSensitive: false,
  );

  // Chemin Xtream : .../USER/PASS/ID.ext — on masque les DEUX segments qui
  // précèdent le fichier terminal (schéma /live|/movie|/series ou racine).
  // On préserve les préfixes structurels connus (live/movie/series).
  static final RegExp _xtreamPath = RegExp(
    r'/(live|movie|series)/([^/\s]+)/([^/\s]+)/(\d+\.[a-zA-Z0-9]+)',
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
    try {
      String out = text.replaceAllMapped(
          _userInfo, (Match m) => '${m.group(1)}$_mask:$_mask@');
      out = out.replaceAllMapped(_query, (Match m) => '${m.group(1)}$_mask');
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
