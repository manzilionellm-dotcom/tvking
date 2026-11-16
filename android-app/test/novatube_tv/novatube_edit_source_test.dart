import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('une modification conserve la liste en cas de refus et son identifiant en cas de succès', () async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    final tmp = await Directory.systemTemp.createTemp('edition-liste-');
    PlaylistDatabase.debugFilePath = '${tmp.path}/test.db';
    addTearDown(() async {
      await PlaylistDatabase.instance.closeForTesting();
      await tmp.delete(recursive: true);
    });
    final repo = PlaylistRepository.instance;
    final client = MockClient((req) async => req.url.path == '/refus'
        ? http.Response('', 403)
        : http.Response('#EXTM3U\n#EXTINF:-1,Mire ${req.url.path}\n${req.url.origin}/test.ts\n',200));
    addTearDown(client.close);
    final old = await repo.addM3uPlaylist(name:'Initiale', url:'http://localhost/a', httpClient:client);
    await expectLater(repo.editSource(old,name:'Ratée',address:'http://localhost/refus',httpClient:client),throwsException);
    expect((await repo.getAllPlaylists()).single.name,'Initiale');
    expect(repo.currentChannels.single.name,'Mire /a');
    await repo.editSource(old,name:'Nouvelle',address:'http://localhost/b',httpClient:client);
    final saved = (await repo.getAllPlaylists()).single;
    expect(saved.id,old.id);
    expect(saved.name,'Nouvelle');
    expect(saved.m3uUrl,'http://localhost/b');
    expect(repo.currentChannels.single.name,'Mire /b');
    await repo.editSource(saved,name:'Renommée');
    expect((await repo.getAllPlaylists()).single.name,'Renommée');
    expect(repo.currentChannels.single.name,'Mire /b');
    var cancelled = false;
    final waiting = MockClient((_) async {
      cancelled = true;
      return http.Response('#EXTM3U\n#EXTINF:-1,Annulée\nhttp://localhost/mire.ts\n',200);
    });
    addTearDown(waiting.close);
    await expectLater(repo.addM3uPlaylist(name:'À annuler', url:'http://localhost/stop',
        httpClient:waiting, isCancelled:() => cancelled), throwsException);
    expect((await repo.getAllPlaylists()).map((p) => p.name), ['Renommée']);
    expect(repo.currentChannels.single.name,'Mire /b');
  });
}
