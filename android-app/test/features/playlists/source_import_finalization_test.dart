import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/deleted_sources.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/playlists/domain/source_fingerprint.dart';

const String _first = 'http://source.invalid/first.m3u';
const String _second = 'http://source.invalid/second.m3u';

class _Provider {
  List<Map<String, dynamic>> sources = <Map<String, dynamic>>[
    <String, dynamic>{'type': 'm3u', 'm3u_url': _first},
  ];
  bool refused = false;
  int channels = 1;
  Future<void> Function(Uri url)? beforeDownload;

  http.Client client() => MockClient((http.Request request) async {
    if (request.url.path.startsWith('/api/device-source/')) {
      return http.Response(jsonEncode(<String, Object>{
        'sources': sources,
        'rev': 1,
      }), 200);
    }
    if (request.url.path == '/api/device-proof') {
      return http.Response('{"ok":true}', 200);
    }
    if (request.url.host == 'source.invalid') {
      await beforeDownload?.call(request.url);
      if (refused) return http.Response('Refus', 403);
      final String stem = request.url.pathSegments.last.split('.').first;
      return http.Response('#EXTM3U\n${<String>[
        for (int i = 0; i < channels; i++)
          '#EXTINF:-1 tvg-id="$stem-$i" group-title="Test",$stem-$i\n'
          'http://stream.invalid/$stem-$i.ts\n',
      ].join()}', 200);
    }
    return http.Response('{}', 404);
  });
}

Future<RemoteSyncResult> _sync(_Provider provider) => http.runWithClient(
  () => RemoteSourceRepository.sync(force: true), provider.client,
);

Future<Playlist> _add(_Provider provider, String name, String url) =>
    http.runWithClient(() => PlaylistRepository.instance.addM3uPlaylist(
      name: name, url: url,
    ), provider.client);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': 'MK:AA:BB:CC:DD:EE',
    });
    dir = await Directory.systemTemp.createTemp('zuno-import-finalization-');
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = '${dir.path}/tv_king.db';
    PlaylistRepository.mergeAllPlaylists = false;
    await PlaylistRepository.instance.initialize();
  });

  tearDown(() async {
    await PlaylistDatabase.instance.closeForTesting();
    await dir.delete(recursive: true);
  });

  test('premier import sain : aucun commit de cartes vides, source durable et visible', () async {
    expect(await _sync(_Provider()), RemoteSyncResult.loaded);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(RemoteSourceRepository.failuresKey), isFalse);
    expect(prefs.containsKey(RemoteSourceRepository.panelOffKey), isFalse);
    expect(prefs.getStringList(RemoteSourceRepository.rememberedKey),
        <String>[SourceFingerprint.m3u(_first)!]);
    final Database db = await PlaylistDatabase.instance.database;
    final Map<String, Object?> source = (await db.query('playlists')).single;
    expect(source['channel_count'], 1);
    expect(source['last_synced_at'], isNotNull);
    expect(source['is_active'], 1);
    expect(await db.query('channels'), hasLength(1));
    expect(PlaylistRepository.instance.currentChannels, hasLength(1));
  });

  test('les anciennes chaînes vides restent équivalentes à une carte absente', () async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(RemoteSourceRepository.failuresKey, '');
    await prefs.setString(RemoteSourceRepository.panelOffKey, '');
    expect(await _sync(_Provider()), RemoteSyncResult.loaded);
    expect(prefs.getString(RemoteSourceRepository.failuresKey), '');
    expect(prefs.getString(RemoteSourceRepository.panelOffKey), '');
  });

  test('une ancienne carte d’échec ou de masquage est réellement effacée', () async {
    final String fingerprint = SourceFingerprint.m3u(_first)!;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(RemoteSourceRepository.failuresKey,
        jsonEncode(<String, Object>{fingerprint: <String, int>{
          'at': DateTime.now().millisecondsSinceEpoch,
          'n': 1,
        }}));
    await prefs.setString(RemoteSourceRepository.panelOffKey,
        jsonEncode(<String, bool>{fingerprint: false}));
    expect(await _sync(_Provider()), RemoteSyncResult.loaded);
    expect(prefs.getString(RemoteSourceRepository.failuresKey), '{}');
    expect(prefs.getString(RemoteSourceRepository.panelOffKey), '{}');
    final Playlist saved =
        (await PlaylistRepository.instance.getAllPlaylists()).single;
    expect(saved.hidden, isFalse);
    expect(PlaylistRepository.instance.currentChannels, hasLength(1));
  });

  test('un nouvel échec fournisseur est persisté avant le résultat de sync', () async {
    expect(await _sync(_Provider()..refused = true),
        RemoteSyncResult.sourceFailed);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> failures = jsonDecode(
      prefs.getString(RemoteSourceRepository.failuresKey)!,
    ) as Map<String, dynamic>;
    final Map<String, dynamic> failure =
        failures[SourceFingerprint.m3u(_first)] as Map<String, dynamic>;
    expect(failure['n'], 1);
    expect(failure['at'], greaterThan(0));
    expect(await PlaylistRepository.instance.getAllPlaylists(), isEmpty);
  });

  test('une activation refusée conserve l’ancienne liste active et visible', () async {
    final _Provider provider = _Provider();
    final Playlist previous = await _add(provider, 'Ancienne', _first);
    final Database db = await PlaylistDatabase.instance.database;
    // Refus réel de SQLite à la finalisation : toute la transaction doit
    // revenir en arrière, et l'import doit supprimer sa ligne incomplète.
    await db.execute('''
      CREATE TRIGGER reject_import_activation
      BEFORE UPDATE OF is_active ON playlists
      WHEN NEW.name = 'Nouvelle' AND NEW.is_active = 1
      BEGIN
        SELECT RAISE(ABORT, 'activation refusée par le stockage');
      END
    ''');
    await expectLater(_add(provider, 'Nouvelle', _second), throwsException);
    final Playlist remaining =
        (await PlaylistRepository.instance.getAllPlaylists()).single;
    expect(remaining.id, previous.id);
    expect(remaining.isActive, isTrue);
    expect(PlaylistRepository.instance.currentChannels.single.playlistId,
        previous.id);
    expect((await db.query('channels')).single['playlist_id'], previous.id);
  });

  test('une suppression pendant l’import ne désactive pas l’ancienne liste', () async {
    final _Provider provider = _Provider();
    final Playlist previous = await _add(provider, 'Ancienne', _first);
    provider.beforeDownload = (Uri url) async {
      if (url.toString() != _second) return;
      final Playlist pending =
          (await PlaylistRepository.instance.getAllPlaylists())
              .singleWhere((Playlist playlist) => playlist.m3uUrl == _second);
      await PlaylistRepository.instance.deletePlaylist(pending.id!);
    };
    await expectLater(_add(provider, 'Nouvelle', _second),
        throwsA(isA<PlaylistDeletedException>()));
    final Playlist remaining =
        (await PlaylistRepository.instance.getAllPlaylists()).single;
    expect(remaining.id, previous.id);
    expect(remaining.isActive, isTrue);
    expect(PlaylistRepository.instance.currentChannels.single.playlistId,
        previous.id);
    final List<String> rejected =
        await DeletedSources.hashes(SourceFingerprint.ofM3uUrl(_second));
    expect(await DeletedSources.read(), containsAll(rejected));
  });

  test('actualiser une autre source ne change pas la sélection courante', () async {
    final _Provider provider = _Provider();
    final Playlist previous = await _add(provider, 'Choisie', _first);
    final Playlist other = await _add(provider, 'Autre', _second);
    await PlaylistRepository.instance.setActivePlaylist(previous.id!);
    provider.channels = 2;
    expect(await http.runWithClient(
      () => PlaylistRepository.instance.refreshPlaylist(other), provider.client,
    ), isTrue);
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> active =
        await db.query('playlists', where: 'is_active = 1');
    expect(active.single['id'], previous.id);
    expect(await db.query('channels', where: 'playlist_id = ?',
        whereArgs: <Object>[other.id!]), hasLength(2));
    expect(PlaylistRepository.instance.currentChannels.single.playlistId,
        previous.id);
  });
}
