// =========================================================
//  playback_error_taxonomy.dart — Taxonomie des erreurs de lecture
// =========================================================
//  USINE v2 / S3 : une erreur de lecture n'est exploitable que si on
//  sait de QUELLE FAMILLE elle est, car la famille dicte la réaction :
//
//    • réseau        → retry (backoff) a du sens ;
//    • tokenExpired  → re-authentification PUIS retry — un retry
//                      aveugle sur un 403 est une boucle inutile ;
//    • source        → le flux/serveur est en cause : URL de secours
//                      ou erreur claire, marteler ne sert à rien ;
//    • décodeur      → fallback de piste/qualité ou décodage logiciel ;
//    • inconnu       → tout le reste (affiché brut, comme avant).
//
//  Classe PURE (aucun import Flutter) : testable en unit test simple.
//  Les motifs viennent des messages réellement observés dans la boîte
//  noire (libmpv/ffmpeg en anglais + codes HTTP) — voir les tests.
// =========================================================

/// Familles d'erreurs de lecture (S3). L'ordre n'a pas de sens ici,
/// la priorité de classement est dans [PlaybackErrorTaxonomy.classify].
enum PlaybackErrorCategory {
  /// Transport : DNS, TLS, timeout, connexion coupée/refusée…
  network,

  /// Authentification/compte : 401/403, token invalide ou expiré.
  tokenExpired,

  /// Le serveur répond mais le contenu est en cause : 404/5xx,
  /// manifeste invalide, flux vide, EOF immédiat…
  source,

  /// Le flux arrive mais ne se décode pas : codec non supporté,
  /// défaillance du décodeur matériel…
  decoder,

  /// Rien de reconnu — on n'invente pas de certitude.
  unknown,
}

/// Classement d'un message d'erreur brut (libmpv, HTTP, ffmpeg) vers
/// sa famille S3. Volontairement à base de motifs texte : c'est la
/// seule matière que `stream.error` de media_kit fournit.
abstract final class PlaybackErrorTaxonomy {
  // Chaque liste est en minuscules ; le message est abaissé avant test.
  // PRIORITÉ DE CLASSEMENT (du plus spécifique au plus générique) :
  // token → réseau → décodeur → source. Exemple : « HTTP 403 » doit
  // sortir en tokenExpired, jamais en source, même si « http » figure
  // aussi dans des motifs source.
  static const List<String> _token = <String>[
    '401', '403', 'unauthorized', 'forbidden', 'token', 'expired',
    'authentication', 'auth failed',
  ];
  static const List<String> _network = <String>[
    'timeout', 'timed out', 'dns', 'resolve', 'resolving',
    'connection refused', 'connection reset', 'connection closed',
    'network', 'unreachable', 'tls', 'ssl', 'certificate',
    'socket', 'no route to host', 'broken pipe',
  ];
  static const List<String> _decoder = <String>[
    'codec', 'decoder', 'decode', 'hwdec', 'unsupported format',
    'no decoder', 'failed to initialize a video decoder',
  ];
  static const List<String> _source = <String>[
    '404', '500', '502', '503', 'not found', 'manifest', 'playlist',
    'no streams', 'invalid data', 'first segment', 'm3u8',
    'empty file', 'file format', 'end of file', 'eof',
    'error when loading', 'could not open', 'failed to open',
  ];

  static bool _any(String lower, List<String> patterns) =>
      patterns.any((String p) => lower.contains(p));

  /// Classe [message] dans sa famille. Jamais d'exception : une chaîne
  /// vide ou exotique sort en [PlaybackErrorCategory.unknown].
  static PlaybackErrorCategory classify(String message) {
    final String lower = message.toLowerCase();
    if (lower.trim().isEmpty) return PlaybackErrorCategory.unknown;
    if (_any(lower, _token)) return PlaybackErrorCategory.tokenExpired;
    if (_any(lower, _network)) return PlaybackErrorCategory.network;
    if (_any(lower, _decoder)) return PlaybackErrorCategory.decoder;
    if (_any(lower, _source)) return PlaybackErrorCategory.source;
    return PlaybackErrorCategory.unknown;
  }

  /// Libellé court (stable, pour logs/agrégats — pas destiné à l'UI).
  static String label(PlaybackErrorCategory c) {
    switch (c) {
      case PlaybackErrorCategory.network:
        return 'reseau';
      case PlaybackErrorCategory.tokenExpired:
        return 'token';
      case PlaybackErrorCategory.source:
        return 'source';
      case PlaybackErrorCategory.decoder:
        return 'decodeur';
      case PlaybackErrorCategory.unknown:
        return 'inconnu';
    }
  }
}
