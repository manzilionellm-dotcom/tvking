// =========================================================
//  first_batch_display_test.dart — Première liste d'une box vide :
//  les 1 000 premières chaînes s'affichent avant la fin de l'import.
// =========================================================
//  Vrai code (PlaylistRepository.addM3uPlaylist, SQLite via FFI), liste
//  synthétique en 127.0.0.1, client HTTP simulé. On écoute le flux des
//  chaînes : avec le correctif, une émission intermédiaire de 1 000
//  chaînes précède l'émission finale ; avec le repli
//  `zuno.import.first_batch_off`, seule la finale arrive. Une box qui a
//  déjà des chaînes n'émet jamais au milieu (règle anti-OOM, audit P1-3).
// =========================================================

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';

Uint8List _m3u(int channels, String tag) {
  final StringBuffer sb = StringBuffer('#EXTM3U\n');
  for (int i = 0; i < channels; i++) {
    sb
      ..write('#EXTINF:-1 tvg-id="$tag$i" group-title="G${i % 10}",Chaîne $tag $i\n')
      ..write('http://127.0.0.1/lot/$tag/$i.ts\n');
  }
  return Uint8List.fromList(sb.toString().codeUnits);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final PlaylistRepository repo = PlaylistRepository.instance;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    dir = await Directory.systemTemp.createTemp('zuno-lot-');
    PlaylistDatabase.debugFilePath = '${dir.path}/tv_king.db';
    PlaylistRepository.mergeAllPlaylists = true;
    await repo.initialize();
  });

  tearDownAll(() async {
    RepairFlags.debugReset();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  /// Importe [n] chaînes et renvoie les tailles de chaque émission du flux
  /// reçue PENDANT l'import.
  Future<List<int>> importAndWatch(int n, String tag) async {
    final List<int> sizes = <int>[];
    final StreamSubscription<List<Channel>> sub =
        repo.channelsStream.listen((List<Channel> c) => sizes.add(c.length));
    final http.Client client =
        MockClient((_) async => http.Response.bytes(_m3u(n, tag), 200));
    final Playlist saved = await repo.addM3uPlaylist(
      name: 'Lot $tag',
      url: 'http://127.0.0.1/lot/$tag.m3u',
      httpClient: client,
    );
    expect(saved.channelCount, n);
    // Laisse passer les événements déjà en file.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    return sizes;
  }

  test('box vide : le premier lot de 1 000 chaînes est émis avant la fin',
      () async {
    RepairFlags.debugReset();
    expect(repo.currentChannels, isEmpty, reason: 'box encore vide');
    final List<int> sizes = await importAndWatch(3500, 'a');
    expect(sizes, contains(1000), reason: 'premier lot affiché : $sizes');
    expect(sizes.last, 3500, reason: 'puis la liste complète : $sizes');
    expect(sizes.indexOf(1000), lessThan(sizes.lastIndexOf(3500)));
  });

  test('box déjà garnie : aucune émission au milieu (règle anti-OOM)',
      () async {
    RepairFlags.debugReset();
    expect(repo.currentChannels, isNotEmpty);
    final List<int> sizes = await importAndWatch(2500, 'b');
    expect(sizes.where((int s) => s < 3500 + 2500), isEmpty,
        reason: 'seule la liste complète (6 000) est émise : $sizes');
    expect(sizes.last, 6000);
  });

  test('repli zuno.import.first_batch_off : box vide, mais rien avant la fin',
      () async {
    // On revide la box : retrait des deux listes.
    for (final Playlist p in await repo.getAllPlaylists()) {
      await repo.deletePlaylist(p.id!);
    }
    expect(repo.currentChannels, isEmpty);
    RepairFlags.importFirstBatchOff = true;
    final List<int> sizes = await importAndWatch(2500, 'c');
    expect(sizes, isNot(contains(1000)), reason: 'repli : $sizes');
    expect(sizes.last, 2500);
  });
}
