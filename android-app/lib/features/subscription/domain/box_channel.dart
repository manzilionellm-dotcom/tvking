// =========================================================
//  box_channel.dart — Lecture pure du canal panel → box
// =========================================================
//  Pas de réseau ici. On décide seulement :
//    - si un texte JSON est un signal (et rien d'autre) ;
//    - quelle adresse WebSocket ouvrir à partir du backend ;
//    - s'il faut relire les listes.
//
//  Un signal ne porte jamais de mot de passe ni d'adresse de flux.
//  Contrat : docs/CANAL-TEMPS-REEL.md.
// =========================================================

import 'dart:convert';

/// Un signal déjà vérifié. [seq] est le numéro de cette MAC.
class BoxChannelFrame {
  const BoxChannelFrame({
    required this.seq,
    required this.type,
    required this.mac,
  });

  final int seq;
  final String type;
  final String mac;
}

const Set<String> _secretKeys = <String>{
  'password',
  'username',
  'server_url',
  'm3u_url',
  'epg_url',
  'secret',
  'token',
};

bool _hasSecretKey(Object? value) {
  if (value is Map) {
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      final String key = '${entry.key}'.toLowerCase();
      if (_secretKeys.contains(key)) return true;
      if (_hasSecretKey(entry.value)) return true;
    }
  } else if (value is List) {
    for (final Object? item in value) {
      if (_hasSecretKey(item)) return true;
    }
  }
  return false;
}

/// null si le texte n'est pas un signal, ou s'il contient une clé
/// interdite. « hello » n'est pas un signal : c'est un battement.
BoxChannelFrame? parseBoxChannelFrame(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  if (_hasSecretKey(decoded)) return null;
  final Object? typeRaw = decoded['type'];
  if (typeRaw == 'hello') return null;
  final int seq = (decoded['seq'] as num?)?.toInt() ?? 0;
  final String type = typeRaw is String ? typeRaw : '';
  final String mac = decoded['mac'] is String ? decoded['mac'] as String : '';
  if (seq <= 0 || type.isEmpty || !mac.startsWith('MK:')) return null;
  return BoxChannelFrame(seq: seq, type: type, mac: mac);
}

/// Relire les listes pour ces noms. Les autres noms relisent
/// le statut (déjà fait par la veille) sans retélécharger.
bool channelRefreshesSources(String type) {
  return type == 'source' || type == 'source_clear';
}

/// wss si le backend est en https, ws sinon (le test local).
Uri boxChannelUri(String base, String mac) {
  final Uri http = Uri.parse(base);
  final String scheme = http.scheme == 'https' ? 'wss' : 'ws';
  return Uri(
    scheme: scheme,
    host: http.host,
    port: http.hasPort ? http.port : null,
    path: '/api/box/ws',
    queryParameters: <String, String>{'mac': mac},
  );
}
