// =========================================================
//  tv_delete_test.dart — « Supprimer » sur la télé tient pour de bon
// =========================================================
//  Vrai code de synchronisation (RemoteSourceRepository), vrai SQLite
//  (sqflite_common_ffi), serveur simulé par MockClient : aucune adresse
//  réelle. Le serveur simulé applique vraiment DELETE /api/self-source.
//
//  Avant le 06/10/2026 : supprimer sur la télé n'effaçait que la copie
//  locale ; la vérification suivante la réimportait (« si je les efface,
//  elles reviennent »). Le refus durable vaut aussi avec l’ancien repli
//  `zuno.source.tv_delete_legacy`.
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
import 'package:tv_king/features/playlists/data/cloud_backup_repository.dart';
import 'package:tv_king/features/playlists/data/deleted_sources.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/playlists/domain/tv_delete.dart';
import 'package:tv_king/features/playlists/domain/source_fingerprint.dart';

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
  List<Map<String, Object?>> revoked = <Map<String, Object?>>[];
  bool down = false;

  http.Client client() => MockClient((http.Request r) async {
        if (down && r.url.path.startsWith('/api/')) throw const SocketException('serveur coupé (injecté)');
        final String path = r.url.path;
        if (path.startsWith('/api/device-source/')) {
          return http.Response(jsonEncode(<String, Object?>{'mac': kMac, 'sources': served, 'revoked': revoked}), 200);
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

  test('coupure après le refus durable : la ligne restante disparaît au redémarrage', () async {
    final _Server s = _Server();
    await _sync(s);
    final Playlist deleted = _find(await _lists(), 'panel-a.invalid');
    await DeletedSources.remember(SourceFingerprint.ofPlaylist(deleted));
    // SQLite garde encore la ligne si le processus est tué pendant le DELETE.
    await PlaylistDatabase.instance.closeForTesting();
    await PlaylistRepository.instance.initialize();
    expect(_has(PlaylistRepository.instance.currentPlaylists, 'panel-a.invalid'), isFalse);
    expect(_has(await _lists(), 'client-b.invalid'), isTrue);
    await _sync(s);
    expect(_has(await _lists(), 'panel-a.invalid'), isFalse);
  });

  test('révocations déjà appliquées : les nouveaux retraits restent durables après reprise', () async {
    final _Server s = _Server();
    await _sync(s);
    final List<Map<String, Object?>> oldSnapshot = List<Map<String, Object?>>.of(s.served);
    final List<Playlist> before = await _lists();
    final Set<String> completed = SourceFingerprint.ofPlaylist(_find(before, 'panel-a.invalid')).toSet();
    await RemoteSourceRepository.applyRevocations(completed.toList());
    s.revoked = oldSnapshot;
    s.served = <Map<String, Object?>>[];
    final Future<RemoteSyncResult> syncing = http.runWithClient(
      () => RemoteSourceRepository.sync(force: true, alreadyRevoked: completed), s.client);
    // Le lot est capturé au moment de l'appel : une modification ultérieure
    // ne doit pas faire sauter la suppression de la seconde liste.
    completed.addAll(SourceFingerprint.ofPlaylist(_find(before, 'client-b.invalid')));
    expect(await syncing, RemoteSyncResult.noSource);
    expect(await _lists(), isEmpty);
    expect(await PlaylistRepository.instance.getAllChannels(), isEmpty);
    expect(await DeletedSources.read(), hasLength(2));

    await PlaylistDatabase.instance.closeForTesting();
    await PlaylistRepository.instance.initialize();
    s.served = oldSnapshot;
    s.revoked = <Map<String, Object?>>[];
    await _sync(s);
    expect(await _lists(), isEmpty, reason: 'ancienne réponse après réouverture SQLite');
    expect(await DeletedSources.read(), hasLength(2));
  });

  test('M3U saisi à la main puis effacé : ne revient pas sous sa forme Xtream', () async {
    const String link = 'http://account.invalid/get.php?username=user&password=pass&type=m3u_plus';
    final http.Client file = MockClient((_) async => http.Response(_m3u('manual', 1), 200));
    final Playlist playlist = await PlaylistRepository.instance.addM3uPlaylist(name: 'Manuel', url: link, httpClient: file);
    await PlaylistRepository.instance.deletePlaylist(playlist.id!);
    final _Server s = _Server()..served = <Map<String, Object?>>[
      <String, Object?>{'type': 'xtream', 'server_url': 'http://account.invalid', 'username': 'user', 'password': 'pass'},
    ];
    await PlaylistDatabase.instance.closeForTesting();
    await _sync(s);
    expect(await _lists(), isEmpty);
    file.close();
  });

  test('un ajout Xtream lent commencé avant la suppression ne la lève pas à son retour', () async {
    const Playlist source = Playlist(id: null, name: 'Compte', type: PlaylistType.xtream,
      xtreamServer: 'http://account.invalid', xtreamUsername: 'user', xtreamPassword: 'pass', createdAt: 1);
    final Database db = await PlaylistDatabase.instance.database;
    final int oldId = await db.insert('playlists', source.toMap());
    final http.Client slow = MockClient((_) async {
      await PlaylistRepository.instance.deletePlaylist(oldId);
      return http.Response('{"user_info":{"auth":1,"status":"Active"}}', 200);
    });
    await expectLater(PlaylistRepository.instance.addXtreamPlaylist(name: 'En cours',
      serverUrl: source.xtreamServer!, username: 'user', password: 'pass', httpClient: slow),
      throwsA(isA<PlaylistDeletedException>()));
    expect(await _lists(), isEmpty);
    slow.close();
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

  test('liste du panel : ni synchronisation forcée ni renvoi ne ressuscitent la liste', () async {
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
    expect(_has(await _lists(), 'panel-a.invalid'), isFalse);
    // Redémarrage : la mémoire de suppression est sur disque.
    await PlaylistDatabase.instance.closeForTesting();
    await _sync(s);
    expect(_has(await _lists(), 'panel-a.invalid'), isFalse);
  });

  test('serveur injoignable : suppression locale durable au retour du réseau', () async {
    final _Server s = _Server();
    await _sync(s);
    s.down = true;
    expect(await _deleteOnTv(s, 'client-b.invalid'), isTrue);
    expect(_has(await _lists(), 'client-b.invalid'), isFalse);
    s.down = false;
    await _sync(s);
    expect(_has(await _lists(), 'client-b.invalid'), isFalse);
  });

  test('le repli historique ne contourne plus la suppression durable', () async {
    final _Server s = _Server();
    await _sync(s);
    RepairFlags.tvDeleteLegacy = true;
    expect(await _deleteOnTv(s, 'panel-a.invalid'), isTrue);
    expect(_has(await _lists(), 'panel-a.invalid'), isFalse);
    await _sync(s);
    expect(_has(await _lists(), 'panel-a.invalid'), isFalse);
  });

  test('suppression manuelle pendant le téléchargement : import annulé', () async {
    final PlaylistRepository repo = PlaylistRepository.instance;
    final http.Client client = MockClient((http.Request request) async {
      final List<Playlist> pending = await _lists();
      await repo.deletePlaylist(pending.single.id!);
      return http.Response(_m3u('late', 3), 200);
    });
    await expectLater(repo.addM3uPlaylist(
      name: 'En cours', url: 'http://late.invalid/l.m3u', httpClient: client,
    ), throwsA(isA<PlaylistDeletedException>()));
    expect(await _lists(), isEmpty);
    expect(await repo.getAllChannels(), isEmpty);
    final http.Client good = MockClient((_) async => http.Response(_m3u('new', 2), 200));
    await expectLater(repo.addM3uPlaylist(
      name: 'Restauration', url: 'http://late.invalid/l.m3u', httpClient: good,
      restoreDeleted: false,
    ), throwsA(isA<PlaylistDeletedException>()));
    // Un nouvel ajout volontaire est autorisé, avec un nouvel identifiant.
    expect((await repo.addM3uPlaylist(
      name: 'Ajout volontaire', url: 'http://late.invalid/l.m3u', httpClient: good,
    )).channelCount, 2);
    client.close();
    good.close();
  });

  test('ancienne sauvegarde : les listes supprimées ne sont pas restaurées', () async {
    final _Server s = _Server();
    await _sync(s);
    for (final Playlist p in await _lists()) {
      await PlaylistRepository.instance.deletePlaylist(p.id!);
    }
    await PlaylistDatabase.instance.closeForTesting();
    int downloads = 0;
    await http.runWithClient(() => CloudBackupRepository.instance.restoreIfNeeded(),
      () => MockClient((http.Request r) async {
        if (r.url.path.startsWith('/api/backup/')) {
          return http.Response(jsonEncode(<String, Object?>{'data': <String, Object?>{
            'playlists': <Map<String, Object?>>[
              <String, Object?>{'type': 'm3u', 'name': 'Ancienne', 'm3u_url': 'http://panel-a.invalid/l.m3u'},
            ], 'favorites': <String>[],
          }}), 200);
        }
        if (r.url.host == 'panel-a.invalid') downloads++;
        return http.Response('{}', 404);
      }),
    );
    expect(await _lists(), isEmpty);
    expect(downloads, 0, reason: 'la source supprimée est refusée avant le réseau');
    await _sync(s);
    expect(await _lists(), isEmpty);
  });

  test('révocation panel pendant une synchro : annule le téléchargement sans attendre', () async {
    final String url = 'http://pending.invalid/list.m3u';
    await http.runWithClient(() => RemoteSourceRepository.sync(force: true),
      () => MockClient((http.Request r) async {
        if (r.url.path.startsWith('/api/device-source/')) {
          return http.Response(jsonEncode(<String, Object?>{'sources': <Object>[
            <String, String>{'type': 'm3u', 'm3u_url': url},
          ]}), 200);
        }
        if (r.url.host == 'pending.invalid') {
          expect(await RemoteSourceRepository.applyRevocations(<String>['m3u|$url']), 1);
          return http.Response(_m3u('late', 2), 200);
        }
        return http.Response('{}', 404);
      }),
    );
    expect(await _lists(), isEmpty);
    expect(await PlaylistRepository.instance.getAllChannels(), isEmpty);
  });

  test('refus du DELETE serveur : le choix local reste durable', () async {
    final _Server s = _Server();
    await _sync(s);
    final Playlist p = _find(await _lists(), 'client-b.invalid');
    final http.Client good = s.client();
    final http.Client failing = MockClient((http.Request r) async {
      if (r.method == 'DELETE') return http.Response('indisponible', 503);
      return http.Response.fromStream(await good.send(r));
    });
    expect(await RemoteSourceRepository.deleteFromTv(p, client: failing), isTrue);
    await _sync(s);
    expect(_has(await _lists(), 'client-b.invalid'), isFalse);
    good.close();
    failing.close();
  });

  test('dernière suppression : sauvegarde vide avec refus, restaurable après réinstallation', () async {
    final _Server s = _Server();
    await _sync(s);
    for (final Playlist p in await _lists()) {
      await PlaylistRepository.instance.deletePlaylist(p.id!);
    }
    Map<String, dynamic>? backup;
    await http.runWithClient(() => CloudBackupRepository.instance.uploadForTesting(),
      () => MockClient((http.Request r) async {
        if (r.url.path.startsWith('/api/backup/') && r.method == 'PUT') {
          backup = (jsonDecode(r.body) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
          return http.Response('{}', 200);
        }
        return http.Response('{}', 404);
      }),
    );
    expect(backup, isNotNull);
    expect(backup!['playlists'], isEmpty);
    expect(backup!['deleted_source_hashes'], hasLength(2));
    expect(jsonEncode(backup), isNot(contains('panel-a.invalid')));
    // Une installation neuve n'a ni base ni refus locaux.
    await PlaylistDatabase.instance.closeForTesting();
    await databaseFactory.deleteDatabase(PlaylistDatabase.debugFilePath!);
    await http.runWithClient(() => CloudBackupRepository.instance.restoreIfNeeded(),
      () => MockClient((http.Request r) async => http.Response(
        r.url.path.startsWith('/api/backup/') ? jsonEncode(<String, Object?>{'data': backup}) : '{}',
        r.url.path.startsWith('/api/backup/') ? 200 : 404,
      )),
    );
    await _sync(s);
    expect(await _lists(), isEmpty);
    expect(await DeletedSources.read(), hasLength(2));
  });

  test('base neuve vide : ne remplace pas la sauvegarde distante', () async {
    int uploads = 0;
    await http.runWithClient(() => CloudBackupRepository.instance.uploadForTesting(),
      () => MockClient((http.Request r) async {
        if (r.method == 'PUT') uploads++;
        return http.Response('{}', 200);
      }),
    );
    expect(uploads, 0);
  });

  test('ancien refus TV : migration avant restauration, nouvel ajout volontaire possible', () async {
    const String url = 'http://panel-a.invalid/l.m3u';
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(RemoteSourceRepository.tvRefusedKey,
        jsonEncode(<String, int>{'m3u|$url': 1}));
    final http.Client good = MockClient((_) async => http.Response(_m3u('new', 2), 200));
    await expectLater(PlaylistRepository.instance.addM3uPlaylist(
      name: 'Automatique', url: url, httpClient: good, restoreDeleted: false,
    ), throwsA(isA<PlaylistDeletedException>()));
    expect(prefs.getString(RemoteSourceRepository.tvRefusedKey), isNull);
    final Playlist added = await PlaylistRepository.instance.addM3uPlaylist(
      name: 'Volontaire', url: url, httpClient: good,
    );
    expect(added.channelCount, 2);
    expect(await DeletedSources.read(), isEmpty);
    good.close();
  });

  test('migration v6 : conserve les listes et ajoute les refus durables', () async {
    final _Server s = _Server();
    await _sync(s);
    final Database db = await PlaylistDatabase.instance.database;
    await db.execute('DROP TABLE deleted_sources');
    await db.execute('PRAGMA user_version = 6');
    await PlaylistDatabase.instance.closeForTesting();
    expect(await _lists(), hasLength(2));
    expect(await DeletedSources.read(), isEmpty);
    await _deleteOnTv(s, 'panel-a.invalid');
    await _sync(s);
    expect(_has(await _lists(), 'panel-a.invalid'), isFalse);
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

    test('un refus persiste après absence ou renvoi global du panel', () {
      final Map<String, int> r = <String, int>{'a': 100, 'b': 100};
      expect(pruneRefused(r, servedFingerprints: <String>{'a'}).keys, <String>['a', 'b']);
      expect(pruneRefused(r, servedFingerprints: <String>{'a', 'b'}, panelResendAtMs: 50).length, 2);
      expect(pruneRefused(r, servedFingerprints: <String>{'a', 'b'}, panelResendAtMs: 150).length, 2);
      expect(isRefusedOnTv('a', r), isTrue);
      expect(isRefusedOnTv(null, r), isFalse);
    });
  });
}
