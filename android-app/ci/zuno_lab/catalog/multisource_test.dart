import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';

/// Liste M3U « façon fournisseur » : attributs tvg-*, groupes, une
/// adresse par chaîne. ~140 octets par chaîne, comme en vrai.
Uint8List _m3u(int channels, int source) {
  final StringBuffer sb = StringBuffer('#EXTM3U\n');
  for (int i = 0; i < channels; i++) {
    sb
      ..write('#EXTINF:-1 tvg-id="ch$source-$i.fr" tvg-name="Chaîne $i" ')
      ..write('tvg-logo="http://127.0.0.1/logo/$i.png" ')
      ..write('group-title="Groupe ${i % 40}",Chaîne $i\n')
      ..write('http://127.0.0.1/mesure/$source/$i.ts\n');
  }
  return Uint8List.fromList(sb.toString().codeUnits);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // La lecture fusionnée (TV) consulte la marque courante.
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    dir = await Directory.systemTemp.createTemp('zuno-import-');
    PlaylistDatabase.debugFilePath = '${dir.path}/tv_king.db';
    PlaylistRepository.mergeAllPlaylists = true;
  });

  tearDownAll(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('dix listes dans le dépôt TV fusionné : insertion, refus et suppression', () async {
    final repo = PlaylistRepository.instance;
    final db = await PlaylistDatabase.instance.database;
    final rows = <Map<String,Object?>>[];
    final ids = <int>[];
    final client = MockClient((r) async {
      final n = int.parse(r.url.pathSegments.last);
      return n == 99 ? http.Response('indisponible', 404) : http.Response.bytes(_m3u(10000, n), 200);
    });
    addTearDown(client.close);
    for (int i = 1; i <= 10; i++) {
      final clock = Stopwatch()..start();
      final saved = await repo.addM3uPlaylist(name:'Mire $i',url:'http://127.0.0.1/mire/$i',httpClient:client);
      final elapsed = clock.elapsedMilliseconds;
      expect(saved.channelCount,10000);
      ids.add(saved.id!);
      final found = (await db.rawQuery('SELECT COUNT(*) AS n FROM channels')).single['n'];
      rows.add({'lists':i,'sqlite_rows':found,'visible_repo':repo.currentChannels.length,'import_ms_incl_fixture':elapsed,'rss_bytes':ProcessInfo.currentRss});
      expect(found,i*10000);
    }
    bool refused = false;
    try {
      await repo.addM3uPlaylist(name:'Refus',url:'http://127.0.0.1/mire/99',httpClient:client);
    } catch (_) { refused = true; }
    expect(refused,isTrue);
    expect((await db.rawQuery('SELECT COUNT(*) AS n FROM channels')).single['n'],100000);
    await repo.deletePlaylist(ids[4]);
    final counts = await db.rawQuery('SELECT playlist_id, COUNT(*) AS n FROM channels GROUP BY playlist_id ORDER BY playlist_id');
    expect(counts,hasLength(9));
    expect(counts.any((r)=>r['playlist_id']==ids[4]),isFalse);
    expect(counts.every((r)=>r['n']==10000),isTrue);
    final file = Platform.environment['ZUNO_MULTI_OUTPUT'];
    if(file != null) await File(file).writeAsString(jsonEncode({'series':rows,'invalid_preserved_100000':true,'remaining_counts':counts,'visible_after_delete':repo.currentChannels.length}));
  },timeout:const Timeout(Duration(minutes:8)));
}
