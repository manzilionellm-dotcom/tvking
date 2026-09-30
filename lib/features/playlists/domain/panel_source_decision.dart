// =========================================================
//  panel_source_decision.dart — Ce que le panel vient de dire
// =========================================================
//  Décisions pures sur le JSON déjà renvoyé par le Worker actuel
//  (`GET /api/device-source/:mac`). Aucune nouvelle route.
//
//  Une liste vidée est un tableau `sources` présent et vide, sans
//  objet `source`. L'absence du champ n'est PAS un effacement :
//  d'anciennes réponses n'avaient que `source`.
// =========================================================

/// Empreinte d'une liste qu'on a nous-mêmes posée depuis le panel.
/// Sert à la retirer sans toucher à une liste ajoutée à la main.
class ProvisionKey {
  const ProvisionKey.xtream(this.server, this.username)
      : m3uUrl = '',
        kind = 'xtream';

  const ProvisionKey.m3u(this.m3uUrl)
      : server = '',
        username = '',
        kind = 'm3u';

  final String kind;
  final String server;
  final String username;
  final String m3uUrl;

  String get wire => kind == 'm3u'
      ? 'm3u|$m3uUrl'
      : 'xtream|$server|$username';

  static ProvisionKey? parse(String wire) {
    if (wire.startsWith('m3u|')) {
      final String url = wire.substring(4);
      if (url.isEmpty) return null;
      return ProvisionKey.m3u(url);
    }
    if (wire.startsWith('xtream|')) {
      final List<String> parts = wire.split('|');
      if (parts.length < 3 || parts[1].isEmpty) return null;
      return ProvisionKey.xtream(parts[1], parts.sublist(2).join('|'));
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is ProvisionKey && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;
}

/// Le corps est-il un effacement explicite de la liste assignée ?
bool panelClearedSources(Map<String, dynamic> body) {
  if (!body.containsKey('sources')) return false;
  final Object? list = body['sources'];
  if (list is! List || list.isNotEmpty) return false;
  final Object? src = body['source'];
  if (src is Map && src.isNotEmpty) return false;
  return true;
}

/// Clés à retirer.
///
/// [explicitClear] : on retire ce que le panel avait posé.
/// Les ordres `source_remove` retirent leur cible même sans
/// effacement global. Une liste qui n'est dans aucun des deux
/// reste (elle a été ajoutée à la main).
Set<ProvisionKey> keysToRemove({
  required bool explicitClear,
  required Set<ProvisionKey> provisioned,
  required List<Map<String, dynamic>> orders,
}) {
  final Set<ProvisionKey> out = <ProvisionKey>{};
  if (explicitClear) out.addAll(provisioned);
  for (final Map<String, dynamic> order in orders) {
    if (order['kind'] != 'source_remove') continue;
    final Object? target = order['target'];
    if (target is! Map) continue;
    final String server = '${target['server'] ?? ''}'.trim();
    final String user = '${target['username'] ?? ''}'.trim();
    final String m3u = '${target['m3u_url'] ?? ''}'.trim();
    if (m3u.isNotEmpty) {
      out.add(ProvisionKey.m3u(m3u));
    } else if (server.isNotEmpty) {
      out.add(ProvisionKey.xtream(server, user));
    }
  }
  return out;
}

/// Corps d'ordre acceptable. On n'applique pas un JSON bancal.
bool orderLooksValid(Map<String, dynamic> order) {
  final Object? id = order['id'];
  final Object? kind = order['kind'];
  if (id is! int || id <= 0) return false;
  if (kind is! String || kind.isEmpty) return false;
  const Set<String> known = <String>{
    'source_remove',
    'source_activate',
    'source_update',
  };
  return known.contains(kind);
}
