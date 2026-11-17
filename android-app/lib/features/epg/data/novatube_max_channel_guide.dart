// Complément au XMLTV local pour un canal Xtream ouvert par l'utilisateur.
// Le cache appartient à l'écran. Aucune requête pendant le zapping.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../channels/domain/channel.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/xtream_client.dart';
import '../../playlists/domain/playlist.dart';
import '../domain/epg_program.dart';

class NovaMaxChannelGuide {
  XtreamClient? _client;
  bool _closed = false;
  Future<List<EpgProgram>>? _pending;

  Future<List<EpgProgram>> load(Channel channel) =>
      _pending ??= _load(channel);

  void dispose() {
    _closed = true;
    _client?.dispose();
    _client = null;
  }

  Future<List<EpgProgram>> _load(Channel channel) async {
    if (_closed) return [];
    final match = RegExp(r'^xtream-(\d+)$').firstMatch(channel.id);
    if (match == null || channel.playlistId == null) return [];
    final sources = PlaylistRepository.instance.currentPlaylists;
    for (final source in sources) {
      if (source.id != channel.playlistId || source.type != PlaylistType.xtream) continue;
      final host = source.xtreamServer, user = source.xtreamUsername, password = source.xtreamPassword;
      if (host == null || user == null || password == null) return [];
      final client = XtreamClient(serverUrl: host, username: user, password: password);
      _client = client;
      try {
        final bytes = await client.fetchActionBytes('get_simple_data_table',
            extra: {'stream_id': match.group(1)!}, softMax: 2 * 1024 * 1024);
        if (bytes == null) return [];
        return await compute(parseMaxChannelGuide, (channelId: channel.id, bytes: bytes));
      } finally {
        if (identical(client, _client)) dispose();
      }
    }
    return [];
  }
}

List<EpgProgram> parseMaxChannelGuide(({String channelId, Uint8List bytes}) input) {
  final data = jsonDecode(utf8.decode(input.bytes, allowMalformed: true));
  if (data is! Map || data['epg_listings'] is! List) return [];
  final result = <EpgProgram>[];
  final seen = <int>{};
  for (final r in (data['epg_listings'] as List).take(3000)) {
    if (r is! Map) continue;
    final start = int.tryParse('${r['start_timestamp']}');
    final end = int.tryParse('${r['stop_timestamp'] ?? r['end_timestamp']}');
    if (start == null || end == null || start <= 0 || end <= start ||
        end > 4102444800 || !seen.add(start)) continue;
    final title = _epgText(r['title']);
    if (title.isEmpty) continue;
    final archive = r['has_archive'];
    result.add(EpgProgram(channelId: input.channelId, startTime: start * 1000,
      stopTime: end * 1000, title: title, description: _epgText(r['description']),
      replayAvailable: archive == null ? null : (archive == true || '$archive' == '1')));
  }
  return result;
}

String _epgText(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) return '';
  final value = raw.trim();
  try {
    final decoded = utf8.decode(base64.decode(value));
    if (decoded.trim().isNotEmpty && !decoded.contains(RegExp(r'[\x00-\x08\x0E-\x1F]'))) {
      return decoded.trim();
    }
  } on FormatException {
    // Plusieurs serveurs fournissent déjà le titre en clair.
  }
  return value;
}
