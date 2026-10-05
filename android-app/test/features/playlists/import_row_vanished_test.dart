// =========================================================
//  import_row_vanished_test.dart — La ligne de la liste disparaît PENDANT
//  le téléchargement de ses chaînes
// =========================================================
//  Mesuré sur la box de test les 5 et 6 octobre 2026 (boîte noire) :
//    22:59:41  [XTREAM] 50000 chaînes live récupérées (145 s)
//    22:59:41  FOREIGN KEY constraint failed  → liste supprimée, import perdu
//    00:16:07  même scénario après 130,9 s
//  Ici on rejoue le scénario sur le vrai code (PlaylistRepository +
//  XtreamClient), avec un serveur Xtream simulé qui EFFACE la ligne de la
//  liste juste avant de rendre les chaînes. Attendu : l'import aboutit quand
//  même (ligne remise), et échoue comme avant si le repli est activé.
//  Aucune adresse réelle : tout est en 127.0.0.1.
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
import 'package:tv_king/features/playlists/domain/playlist.dart';

/// Serveur Xtream simulé. [beforeStreams] est exécuté juste avant de rendre
/// la liste des chaînes : c'est là que « quelque chose » efface la ligne.
http.Client _xtreamServer({required Future<void> Function() beforeStreams}) {
  return MockClient((http.Request r) async {
    final String? action = r.url.queryParameters['action'];
    if (action == null) {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'user_info': <String, dynamic>{'auth': 1, 'status': 'Active'},
          'server_info': <String, dynamic>{},
        }),
        200,
      );
    }
    if (action == 'get_live_categories') {
      return http.Response(
        jsonEncode(<Map<String, String>>[
          <String, String>{'category_id': '1', 'category_name': 'Sport'},
        ]),
        200,
      );
    }
    if (action == 'get_live_streams') {
      await beforeStreams();
      return http.Response(
        jsonEncode(<Map<String, Object>>[
          <String, Object>{'stream_id': 1, 'name': 'Une', 'category_id': '1'},
          <String, Object>{'stream_id': 2, 'name': 'Deux', 'category_id': '1'},
        ]),
        200,
      );
    }
    return http.Response('[]', 200);
  });
}

Future<void> _wipePlaylistsRows() async {
  final Database db = await PlaylistDatabase.instance.database;
  await db.delete('playlists');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    dir = await Directory.systemTemp.createTemp('zuno-vanished-');
    PlaylistDatabase.debugFilePath = '${dir.path}/tv_king.db';
    PlaylistRepository.mergeAllPlaylists = true;
  });

  tearDownAll(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  tearDown(() {
    RepairFlags.importReinsertOff = false;
  });

  test('ligne effacée pendant le téléchargement : la ligne est remise, l\'import aboutit',
      () async {
    final Playlist saved = await PlaylistRepository.instance.addXtreamPlaylist(
      name: 'Panel',
      serverUrl: 'http://127.0.0.1:8080',
      username: 'u1',
      password: 'p1',
      httpClient: _xtreamServer(beforeStreams: _wipePlaylistsRows),
    );
    expect(saved.channelCount, 2);
    final List<Playlist> all = await PlaylistRepository.instance.getAllPlaylists();
    expect(all.map((Playlist p) => p.id), contains(saved.id));
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.query(
      'channels',
      where: 'playlist_id = ?',
      whereArgs: <Object>[saved.id!],
    );
    expect(rows.length, 2, reason: 'les chaînes sont rattachées à la ligne remise');
    await PlaylistRepository.instance.deletePlaylist(saved.id!, reason: 'test');
  });

  test('repli zuno.import.reinsert_off : même scénario → échec comme avant, rien ne reste',
      () async {
    RepairFlags.importReinsertOff = true;
    await expectLater(
      PlaylistRepository.instance.addXtreamPlaylist(
        name: 'Panel',
        serverUrl: 'http://127.0.0.1:8080',
        username: 'u2',
        password: 'p2',
        httpClient: _xtreamServer(beforeStreams: _wipePlaylistsRows),
      ),
      throwsA(anything),
    );
    final List<Playlist> all = await PlaylistRepository.instance.getAllPlaylists();
    expect(all.where((Playlist p) => p.xtreamUsername == 'u2'), isEmpty);
  });

  test('ligne intacte : aucun avertissement, import normal', () async {
    final Playlist saved = await PlaylistRepository.instance.addXtreamPlaylist(
      name: 'Panel',
      serverUrl: 'http://127.0.0.1:8080',
      username: 'u3',
      password: 'p3',
      httpClient: _xtreamServer(beforeStreams: () async {}),
    );
    expect(saved.channelCount, 2);
    await PlaylistRepository.instance.deletePlaylist(saved.id!, reason: 'test');
  });
}
