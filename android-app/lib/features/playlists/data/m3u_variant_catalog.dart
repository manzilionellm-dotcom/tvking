import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:sqflite/sqflite.dart';

import '../../channels/domain/channel.dart';

/// Le tvg-id désigne le guide et peut couvrir SD, HD et UHD. Les favoris et
/// le focus ont besoin d'un identifiant par flux, dès le premier lot affiché.
typedef _SourceStream = ({int playlist, String guide, String fingerprint});

class M3uVariantCatalog {
  M3uVariantCatalog(this._saved);

  final Map<_SourceStream, String> _saved;
  final Map<_SourceStream, String> _added = {};
  final Map<String, String> guides = {};

  static Future<List<Channel>> read(
      Database db, List<Channel> channels, Map<String, String> guides) async {
    if (channels.isEmpty) return channels;
    // Les deux alias historiques d'une famille dépendent de l'ordre initial.
    // On garde leur association après réordonnancement. Les autres variantes
    // ont un identifiant déterministe et ne demandent aucune écriture.
    return db.transaction((txn) async {
      await txn.execute('''CREATE TABLE IF NOT EXISTS m3u_variant_ids (
        playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
        guide TEXT NOT NULL, fingerprint TEXT NOT NULL, app_id TEXT NOT NULL UNIQUE,
        PRIMARY KEY (playlist_id,guide,fingerprint))''');
      final rows = await txn.query('m3u_variant_ids');
      final saved = <_SourceStream, String>{
        for (final row in rows)
          (
            playlist: row['playlist_id'] as int,
            guide: row['guide'] as String,
            fingerprint: row['fingerprint'] as String
          ): row['app_id'] as String
      };
      final sources = await txn.query('playlists',
          columns: ['id'], where: 'type = ?', whereArgs: ['m3u']);
      final projection = M3uVariantCatalog(saved);
      final result = await projection
          ._project(channels, {for (final s in sources) s['id'] as int});
      if (projection._added.isNotEmpty) {
        final batch = txn.batch();
        for (final e in projection._added.entries) {
          batch.rawInsert(
              '''INSERT INTO m3u_variant_ids (playlist_id,guide,fingerprint,app_id)
            SELECT id,?,?,? FROM playlists WHERE id=?''',
              [e.key.guide, e.key.fingerprint, e.value, e.key.playlist]);
        }
        await batch.commit(noResult: true);
      }
      guides.addAll(projection.guides);
      return result;
    });
  }

  Future<List<Channel>> _project(
      List<Channel> input, Set<int> m3uSources) async {
    final rawIds = <String>{};
    final families = {for (final key in _saved.keys) key.guide};
    for (final c in input) {
      if (!rawIds.add(c.id)) families.add(c.id);
    }
    if (families.isEmpty) return input;
    final reserved = _saved.values.toSet();
    final emitted = <String>{};
    final streams = <_SourceStream>{};
    final result = <Channel>[];
    var checked = 0;
    for (final c in input) {
      String id = c.id;
      final playlist = c.playlistId ?? 0;
      final scoped = '$id~p$playlist';
      if (m3uSources.contains(playlist) && families.contains(id)) {
        // Une même liste peut répéter le même tvg-id des milliers de fois.
        // Céder régulièrement le fil d'interface sans dupliquer tout le catalogue.
        if (++checked % 128 == 0) await Future<void>.delayed(Duration.zero);
        final bytes =
            const DartSha256().hashSync(utf8.encode(c.streamUrl)).bytes;
        final hash = base64UrlEncode(bytes).replaceAll('=', '');
        final key = (playlist: playlist, guide: id, fingerprint: hash);
        if (!streams.add(key)) continue;
        final existing = _saved[key];
        if (existing != null) {
          id = existing;
        } else {
          if (reserved.contains(id) || emitted.contains(id)) id = scoped;
          if (id == scoped &&
              (reserved.contains(id) ||
                  emitted.contains(id) ||
                  rawIds.contains(id))) {
            id = '$scoped~$hash';
            // Un tvg-id peut être n'importe quelle chaîne, même un de nos suffixes.
            while (rawIds.contains(id) ||
                reserved.contains(id) ||
                emitted.contains(id)) {
              id += '~';
            }
          }
          if (id == c.id || id == scoped) {
            _added[key] = id;
            reserved.add(id);
          }
        }
        guides[id] = c.id;
      } else if (emitted.contains(id) || reserved.contains(id)) {
        // Conserve la fusion historique pour les comptes Xtream.
        id = scoped;
      }
      if (!emitted.add(id)) continue;
      result.add(id == c.id
          ? c
          : Channel(
              id: id,
              playlistId: c.playlistId,
              name: c.name,
              category: c.category,
              streamUrl: c.streamUrl,
              isLive: c.isLive,
              logoUrl: c.logoUrl,
              currentProgram: c.currentProgram,
              catchupSupported: c.catchupSupported,
              catchupDays: c.catchupDays,
              catchupSource: c.catchupSource));
    }
    return result;
  }
}
