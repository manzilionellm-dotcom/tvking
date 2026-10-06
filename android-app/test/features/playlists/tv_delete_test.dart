// =========================================================
//  tv_delete_test.dart — « Supprimer » sur la télé tient pour de bon
// =========================================================
//  Vrai code de synchronisation (RemoteSourceRepository), vrai SQLite
//  (sqflite_common_ffi), serveur simulé par MockClient : aucune adresse
//  réelle. Le serveur simulé applique vraiment DELETE /api/self-source.
//
//  Avant le 06/10/2026 : supprimer sur la télé n'effaçait que la copie
//  locale ; la vérification suivante la réimportait (« si je les efface,
//  elles reviennent »). Contre-preuve avec le repli
//  `zuno.source.tv_delete_legacy` : la liste revient.
// =========================================================
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/playlists/domain/tv_delete.dart';

const String kMac = 'MK:AA:BB:CC:DD:EE';

String _m3u(String tag, int n) {
  final StringBuffer sb = StringBuffer('#EXTM3U\n');
  for (int i = 0; i < n; i++) {
    sb.write('#EXTINF:-1 tvg-id="$tag$i" group-title="G",$tag $i\nhttp://127.0.0.1/s/$tag/$i.ts\n');
  }
  return sb.toString();
}

/// Serveur simulé : une liste du panel et une liste ajoutée par le client.
class _Server {
  List<Map<String, Object?>> served = <Map<String, Object?>>[
    <String, Object?>{'type': 'm3u', 'm3u_url': 'http://panel-a.invalid/l.m3u', 'origin': 'panel'},
    <String, Object?>{'type': 'm3u', 'm3u_url': 'http://client-b.invalid/l.m3u', 'origin': 'self', 'id': 'self-b-1'},
  ];
  final List<String> deletes = <String>[];
  bool down = false;

  http.Client client() => MockClient((http.Request r) async {
        if (down && r.url.path.startsWith('/api/')) throw const SocketException('serveur coupé (injecté)');
        final String path = r.url.path;
        if (path.startsWith('/api/device-source/')) {
          return http.Response(jsonEncode(<String, Object?>{'mac': kMac, 'sources': served}), 200);
        }
        if (path.startsWith('/api/self-source/') && r.method == 'DELETE') {
          final String id = r.url.queryParameters['id'] ?? '';
          deletes.add(id);
          served = served.where((Map<String, Object?> s) => s['id'] != id).toList();
          return http.Response('{"ok":true}', 200);
        }
        if (path.startsWith('/api/')) return http.Response('{}', 404);
        if (r.url.host == 'panel-a.invalid') return http.Response(_m3u('A', 4), 200);
        if (r.url.host == 'client-b.invalid') return http.Response(_m3u('B', 3), 200);
        return http.Response('inconnu', 404);
      });
}

Future<void> _sync(_Server s, {bool force = true}) =>
    http.runWithClient(() => RemoteSourceRepository.sync(force: force), s.client);

Future<List<Playlist>> _lists() => PlaylistRepository.instance.getAllPlaylists();

Playlist _find(List<Playlist> ps, String host) =>
    ps.firstWhere((Playlist p) => (p.m3uUrl ?? '').contains(host));

bool _has(List<Playlist> ps, String host) => ps.any((Playlist p) => (p.m3uUrl ?? '').contains(host));

Future<bool> _deleteOnTv(_Server s, String host) async {
  final Playlist p = _find(await _lists(), host);
  return http.runWithClient(() => RemoteSourceRepository.deleteFromTv(p), s.client);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    dir = await Directory.systemTemp.createTemp('zuno-tvdel-');
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = '${dir.path}/tv_king.db';
    PlaylistRepository.mergeAllPlaylists = true;
    SharedPreferences.setMockInitialValues(<String, Object>{'device.virtual_mac.v1': kMac});
    RepairFlags.tvDeleteLegacy = false;
    RepairFlags.sourceRetryAlways = false;
    RemoteSourceRepository.notePanelResend(0);
  });

  tearDown(() async {
    RepairFlags.tvDeleteLegacy = false;
    await PlaylistDatabase.instance.closeForTesting();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('deux listes en même temps sur la télé (panel + client)', () async {
    final _Server s = _Server();
    await _sync(s);
    final List<Playlist> ps = await _lists();
    expect(_find(ps, 'panel-a.invalid').channelCount, 4);
    expect(_find(ps, 'client-b.invalid').channelCount, 3);
  });

  test('liste ajoutée par le client : supprimée sur la télé ET sur le serveur, ne revient pas', () async {
    final _Server s = _Server();
    await _sync(s);
    expect(await _deleteOnTv(s, 'client-b.invalid'), isTrue);
    expect(s.deletes, <String>['self-b-1']);
    expect(_has(await _lists(), 'client-b.invalid'), isFalse);
    await _sync(s);
    await _sync(s, force: false);
    expect(_has(await _lists(), 'client-b.invalid'), isFalse, reason: 'le serveur ne la sert plus');
    expect(_has(await _lists(), 'panel-a.invalid'), isTrue, reason: 'l’autre liste ne bouge pas');
  });

  test('liste du panel : supprimée sur la télé, plus réimportée ; le panel la renvoie → elle revient', () async {
    final _Server s = _Server();
    await _sync(s);
    expect(await _deleteOnTv(s, 'panel-a.invalid'), isTrue);
    expect(s.deletes, isEmpty, reason: 'la box ne supprime jamais une liste du panel sur le serveur');
    await _sync(s);
    await _sync(s, force: false);
    expect(_has(await _lists(), 'panel-a.invalid'), isFalse, reason: 'supprimée = supprimée');
    expect(_has(await _lists(), 'client-b.invalid'), isTrue);

    // Le revendeur renvoie la liste depuis le panel (ordre « liste »).
    RemoteSourceRepository.notePanelResend(DateTime.now().millisecondsSinceEpoch + 1);
    await _sync(s);
    expect(_find(await _lists(), 'panel-a.invalid').channelCount, 4);
  });

  test('serveur injoignable pour une liste du client : rien n’est effacé, l’écran le dit', () async {
    final _Server s = _Server();
    await _sync(s);
    s.down = true;
    expect(await _deleteOnTv(s, 'client-b.invalid'), isFalse);
    expect(_has(await _lists(), 'client-b.invalid'), isTrue);
  });

  test('contre-preuve : ancien comportement (repli) → la liste revient', () async {
    final _Server s = _Server();
    await _sync(s);
    RepairFlags.tvDeleteLegacy = true;
    expect(await _deleteOnTv(s, 'panel-a.invalid'), isTrue);
    expect(_has(await _lists(), 'panel-a.invalid'), isFalse);
    await _sync(s);
    expect(_has(await _lists(), 'panel-a.invalid'), isTrue, reason: 'le défaut d’avant est bien détecté');
  });

  test('Désactiver / Activer : immédiat, sans retéléchargement ; une relecture ne rallume pas', () async {
    final _Server s = _Server();
    await _sync(s);
    final Playlist a = _find(await _lists(), 'panel-a.invalid');
    final int before = PlaylistRepository.instance.currentChannels.length;
    expect(before, 7, reason: '4 + 3 chaînes, les deux listes ensemble');

    await PlaylistRepository.instance.setPlaylistHidden(a.id!, true);
    expect(PlaylistRepository.instance.currentChannels.length, 3, reason: 'désactivée : ses chaînes partent tout de suite');
    await _sync(s);
    await _sync(s, force: false);
    expect(PlaylistRepository.instance.currentChannels.length, 3, reason: 'la relecture du serveur ne la rallume pas');
    expect(_find(await _lists(), 'panel-a.invalid').hidden, isTrue, reason: 'gardée, pas effacée');

    await PlaylistRepository.instance.setPlaylistHidden(a.id!, false);
    expect(PlaylistRepository.instance.currentChannels.length, 7, reason: 'réactivée : de retour sans téléchargement');
  });

  group('règles pures', () {
    test('décision selon l’origine', () {
      final List<Map<String, dynamic>> served = <Map<String, dynamic>>[
        <String, dynamic>{'type': 'm3u', 'm3u_url': 'http://p/x', 'origin': 'panel'},
        <String, dynamic>{'type': 'xtream', 'server_url': 'http://s:80', 'username': 'u', 'origin': 'self', 'id': 'abc'},
      ];
      expect(decideTvDelete(playlistFingerprints: <String>['m3u|http://p/x'], served: served).kind,
          TvDeleteKind.refusePanelList);
      final TvDeleteDecision d = decideTvDelete(playlistFingerprints: <String>['xtream|http://s:80|u'], served: served);
      expect(d.kind, TvDeleteKind.removeOnServer);
      expect(d.serverId, 'abc');
      expect(decideTvDelete(playlistFingerprints: <String>['m3u|http://autre'], served: served).kind,
          TvDeleteKind.localOnly);
    });

    test('un refus tombe quand le panel ne sert plus la liste ou la renvoie après', () {
      final Map<String, int> r = <String, int>{'a': 100, 'b': 100};
      expect(pruneRefused(r, servedFingerprints: <String>{'a'}).keys, <String>['a']);
      expect(pruneRefused(r, servedFingerprints: <String>{'a', 'b'}, panelResendAtMs: 50).length, 2);
      expect(pruneRefused(r, servedFingerprints: <String>{'a', 'b'}, panelResendAtMs: 150), isEmpty);
      expect(isRefusedOnTv('a', r), isTrue);
      expect(isRefusedOnTv(null, r), isFalse);
    });
  });
}
