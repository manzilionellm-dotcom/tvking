// =========================================================
//  source_fingerprint.dart — Reconnaître UNE liste
// =========================================================
//  La même chaîne que le Worker (cloudflare/source_revoke.js).
//  Sert à savoir quelle liste locale correspond à celle que le
//  panel vient de retirer, sans jamais comparer les mots de passe.
// =========================================================

/// Empreinte stable d'une source IPTV.
abstract final class SourceFingerprint {
  static String? xtream(String? server, String? username) {
    final String host = (server ?? '').trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();
    final String user = (username ?? '').trim();
    if (host.isEmpty || user.isEmpty) return null;
    return 'xtream|$host|$user';
  }

  static String? m3u(String? url) {
    final String u = (url ?? '').trim();
    if (u.isEmpty) return null;
    return 'm3u|$u';
  }

  /// Depuis un objet renvoyé par le Worker (`revoked[]` ou `sources[]`).
  static String? fromMap(Map<String, dynamic> item) {
    final String type = (item['type'] as String? ?? '').trim().toLowerCase();
    if (type == 'xtream') {
      return xtream(item['server_url'] as String?, item['username'] as String?);
    }
    if (type == 'm3u') return m3u(item['m3u_url'] as String?);
    return null;
  }

  static List<String> revokedFromBody(Map<String, dynamic> body) {
    final Object? raw = body['revoked'];
    if (raw is! List) return const <String>[];
    final List<String> out = <String>[];
    for (final Object? item in raw) {
      if (item is! Map) continue;
      final String? fp = fromMap(item.cast<String, dynamic>());
      if (fp != null && !out.contains(fp)) out.add(fp);
    }
    return out;
  }
}

/// Quelles empreintes faut-il effacer en local ?
///
/// - [revoked] : tombstones du panel (même si la box ne les avait
///   jamais « mémorisées »).
/// - [remembered] : listes que CETTE box a déjà reçues du panel.
/// - [current] : listes encore assignées. On ne retire JAMAIS une
///   liste qui est encore là.
Set<String> fingerprintsToDrop({
  required Set<String> remembered,
  required Set<String> current,
  required Set<String> revoked,
}) {
  final Set<String> drop = <String>{...revoked, ...remembered.difference(current)};
  drop.removeAll(current);
  return drop;
}
