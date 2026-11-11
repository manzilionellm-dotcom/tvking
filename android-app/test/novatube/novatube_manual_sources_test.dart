import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/zuno_edition.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/playlists/data/xtream_client.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final PlaylistRepository repo = PlaylistRepository.instance;
  late Directory dir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlavorConfig.setCurrent(FlavorConfig.novatube);
    dir = await Directory.systemTemp.createTemp('novatube-manual-');
    PlaylistDatabase.debugFilePath = '${dir.path}/playlists.db';
    PlaylistRepository.mergeAllPlaylists = true;
    await repo.initialize();
  });

  tearDownAll(() async {
    CastPlatform.resetForTesting();
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    await dir.delete(recursive: true);
  });

  test('import M3U réel : lecture, cache et stream excluent les contenus adultes',
      () async {
    const String m3u = '''#EXTM3U
#EXTINF:-1 tvg-id="doc" group-title="Documentaires",Horizons
http://example.invalid/doc.ts
#EXTINF:-1 tvg-id="adult-category" group-title="ADULT",Fixture cachée
http://example.invalid/adult.ts
#EXTINF:-1 tvg-id="adult-name" group-title="Divers",XXX Fixture
http://example.invalid/hidden.ts
''';
    final List<List<Channel>> seen = <List<Channel>>[];
    final StreamSubscription<List<Channel>> sub = repo.channelsStream.listen(seen.add);
    final http.Client client = MockClient((_) async => http.Response(m3u, 200));
    addTearDown(client.close);
    final Playlist saved = await repo.addM3uPlaylist(
      name: 'Ma source', url: 'http://example.invalid/my.m3u', httpClient: client,
    );
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(saved.id, isNotNull);
    expect((await repo.getAllChannels()).map((Channel c) => c.id), <String>['doc']);
    expect(repo.currentChannels.map((Channel c) => c.id), <String>['doc']);
    expect(seen, isNotEmpty);
    expect(seen.expand((List<Channel> list) => list)
        .any((Channel c) => c.genre == ChannelGenre.adult), isFalse);
    expect(await RemoteSourceRepository.isServedByPanel(saved), isFalse);
    expect(await RemoteSourceRepository.deleteFromTv(saved), isTrue);
    expect(repo.currentChannels, isEmpty);
  });

  test('client Xtream manuel conserve connexion et chaînes du serveur saisi',
      () async {
    final List<String> actions = <String>[];
    final http.Client httpClient = MockClient((http.Request request) async {
      expect(request.url.host, 'example.invalid');
      final String action = request.url.queryParameters['action'] ?? '';
      actions.add(action);
      final Object body = switch (action) {
        '' => <String, Object>{'user_info': <String, Object>{'auth': 1, 'status': 'Active'}},
        'get_live_categories' => <Object>[
          <String, Object>{'category_id': '1', 'category_name': 'Documentaires'},
        ],
        'get_live_streams' => <Object>[
          <String, Object>{'stream_id': 7, 'name': 'Horizons', 'category_id': '1'},
        ],
        _ => <Object>[],
      };
      return http.Response(jsonEncode(body), 200);
    });
    final XtreamClient client = XtreamClient(
      serverUrl: 'http://example.invalid', username: 'fixture',
      password: 'fixture', httpClient: httpClient,
    );
    addTearDown(httpClient.close);
    await client.verifyCredentials();
    final List<Channel> channels = await client.fetchLiveChannels(playlistId: 1);
    expect(channels.single.name, 'Horizons');
    expect(actions, containsAll(<String>['', 'get_live_categories', 'get_live_streams']));
  });

  test('édition mobile conserve les transports Cast disponibles', () {
    CastPlatform.configureZuno(ZunoEdition.touch);
    expect(CastPlatform.canSend, isTrue);
    expect(CastPlatform.supports(CastDeviceKind.dlna), isTrue);
    expect(CastPlatform.supports(CastDeviceKind.roku), isTrue);
  });
}
