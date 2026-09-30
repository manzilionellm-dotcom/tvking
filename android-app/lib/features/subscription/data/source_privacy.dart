// =========================================================
//  source_privacy.dart — Ce qu'on a le droit d'envoyer au serveur
// =========================================================
//  Le signal « je suis en ligne » promet de ne jamais transmettre
//  le mot de passe. Pour Xtream, serveur + identifiant suffisent.
//  Pour une liste M3U, l'adresse complète contient très souvent
//  l'identifiant et le mot de passe : on n'envoie que l'hôte.
// =========================================================

/// Champ `server` du heartbeat, sans secret.
String heartbeatServerField({
  required bool xtream,
  required String serverOrUrl,
}) {
  final String raw = serverOrUrl.trim();
  if (raw.isEmpty) return '';
  if (xtream) return _hostOnly(raw);
  return _hostOnly(raw);
}

String _hostOnly(String raw) {
  final String withScheme = raw.contains('://') ? raw : 'http://$raw';
  try {
    final Uri uri = Uri.parse(withScheme);
    if (uri.host.isEmpty) return '';
    if (uri.hasPort) return '${uri.host}:${uri.port}';
    return uri.host;
  } catch (_) {
    return '';
  }
}
