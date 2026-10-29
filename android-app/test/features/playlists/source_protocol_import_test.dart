import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/deleted_sources.dart';
import 'package:tv_king/features/playlists/domain/source_fingerprint.dart';

import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/source_protocol_fallback.dart';
import 'package:tv_king/features/playlists/domain/open_source_input.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

const String _m3u = '#EXTM3U\n#EXTINF:-1 group-title="Test",Test\n'
    'http://stream.invalid/test.ts\n';
const String _url = 'https://source.invalid:8080/list.m3u?token=a%2Bb%26c';
const String _plain = 'http://source.invalid:8080/list.m3u?token=a%2Bb%26c';
const String _getPhp =
    'https://source.invalid:8080/get.php?username=viewer&password=test&type=m3u_plus';

Future<Playlist> _importGetPhp(http.Client client) {
  final OpenSourceDraft draft = OpenSourceInput.playlistLink(_getPhp).draft!;
  return PlaylistRepository.instance.addXtreamPlaylist(
    name: 'Compte test',
    serverUrl: draft.serverUrl!,
    username: draft.username!,
    password: draft.password!,
    allowHttpCompatibility: true,
    httpClient: client,
  );
}

http.Response _xtreamResponse(http.Request request, {bool emptyLive = false}) {
  if (request.url.path.endsWith('xmltv.php')) {
    return http.Response('<?xml version="1.0"?><tv></tv>', 200);
  }
  switch (request.url.queryParameters['action']) {
    case 'get_live_categories':
      return http.Response('[{"category_id":"1","category_name":"Test"}]', 200);
    case 'get_live_streams':
      return http.Response(emptyLive ? '[]' : jsonEncode(<Object>[
        <String, Object>{'stream_id': 1, 'name': 'Test', 'category_id': '1',
          'stream_type': 'live', 'container_extension': 'ts'},
      ]), 200);
    default:
      return http.Response('{"user_info":{"auth":1,"status":"Active"}}', 200);
  }
}

Future<void> _rememberM3u(String url) =>
    DeletedSources.remember(SourceFingerprint.ofM3uUrl(url));
Future<void> _rememberXtream(String server) =>
    DeletedSources.remember(SourceFingerprint.xtreamAliases(server, 'viewer'));
Future<void> _restartSourceStore() async {
  await PlaylistDatabase.instance.closeForTesting();
  await PlaylistRepository.instance.initialize();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
  final Directory dir = Directory.systemTemp.createTempSync('source-protocol-');
  PathProviderPlatform.instance = _Paths(dir.path);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final Database db = await PlaylistDatabase.instance.database;
    await db.delete('channels');
    await db.delete('playlists');
    await db.delete('deleted_sources');
    await PlaylistRepository.instance.initialize();
  });

  test('M3U : une erreur TLS de protocole importe et mémorise le lien HTTP', () async {
    final List<String> calls = <String>[];
    final http.Client client = MockClient((http.Request request) async {
      calls.add(request.url.toString());
      if (request.url.scheme == 'https') {
        throw const HandshakeException('WRONG_VERSION_NUMBER');
      }
      return http.Response(_m3u, 200);
    });
    final Playlist saved = await PlaylistRepository.instance.addM3uPlaylist(
      name: 'Liste test', url: _url, allowHttpCompatibility: true, httpClient: client,
    );
    expect(calls, <String>[_url, _plain]);
    expect(saved.m3uUrl, _plain);
    expect(saved.channelCount, 1);
    expect((await PlaylistRepository.instance.getAllPlaylists()).single.m3uUrl, _plain);
  });

  test('M3U : HTTPS fonctionnel reste HTTPS', () async {
    final List<String> schemes = <String>[];
    final http.Client client = MockClient((http.Request request) async {
      schemes.add(request.url.scheme);
      return http.Response(_m3u, 200);
    });
    final Playlist saved = await PlaylistRepository.instance.addM3uPlaylist(
      name: 'Liste test', url: _url, allowHttpCompatibility: true, httpClient: client,
    );
    expect(schemes, <String>['https']);
    expect(saved.m3uUrl, _url);
  });

  for (final int status in <int>[401, 403]) {
    test('M3U : HTTP $status ne provoque aucun passage en HTTP', () async {
      final List<String> schemes = <String>[];
      final http.Client client = MockClient((http.Request request) async {
        schemes.add(request.url.scheme);
        return http.Response('Refus', status);
      });
      await expectLater(PlaylistRepository.instance.addM3uPlaylist(
        name: 'Liste test', url: _url, allowHttpCompatibility: true, httpClient: client,
      ), throwsException);
      expect(schemes, isNotEmpty);
      expect(schemes.toSet(), <String>{'https'});
      expect(await PlaylistRepository.instance.getAllPlaylists(), isEmpty);
    });
  }

  test('M3U : le certificat refusé reste un échec HTTPS', () async {
    final List<String> schemes = <String>[];
    final http.Client client = MockClient((http.Request request) async {
      schemes.add(request.url.scheme);
      throw const HandshakeException('CERTIFICATE_VERIFY_FAILED');
    });
    await expectLater(PlaylistRepository.instance.addM3uPlaylist(
      name: 'Liste test', url: _url, allowHttpCompatibility: true, httpClient: client,
    ), throwsException);
    expect(schemes.toSet(), <String>{'https'});
    expect(await PlaylistRepository.instance.getAllPlaylists(), isEmpty);
  });

  test('M3U : un repli HTTP invalide ne tourne pas en boucle et ne reste pas en base', () async {
    final List<String> schemes = <String>[];
    final http.Client client = MockClient((http.Request request) async {
      schemes.add(request.url.scheme);
      if (request.url.scheme == 'https') {
        throw const HandshakeException('WRONG_VERSION_NUMBER');
      }
      return http.Response('<html>Refus</html>', 200);
    });
    await expectLater(PlaylistRepository.instance.addM3uPlaylist(
      name: 'Liste test', url: _url, allowHttpCompatibility: true, httpClient: client,
    ), throwsA(isA<SourceProtocolFallbackFailure>()));
    expect(schemes, <String>['https', 'http']);
    expect(await PlaylistRepository.instance.getAllPlaylists(), isEmpty);
  });

  test('get.php passe par Xtream et conserve le serveur HTTP validé', () async {
    final List<Uri> calls = <Uri>[];
    final http.Client client = MockClient((http.Request request) async {
      calls.add(request.url);
      if (request.url.scheme == 'https') {
        throw const HandshakeException('WRONG_VERSION_NUMBER');
      }
      return _xtreamResponse(request);
    });
    final Playlist saved = await http.runWithClient(() => _importGetPhp(client), () => client);
    expect(saved.xtreamServer, 'http://source.invalid:8080');
    expect(saved.channelCount, 1);
    expect(calls.where((Uri u) => u.scheme == 'https'), hasLength(1));
    expect(calls.where((Uri u) => u.path.endsWith('get.php')), isEmpty);
    expect((await PlaylistRepository.instance.getAllPlaylists()).single.xtreamServer,
      'http://source.invalid:8080');
  });

  test('get.php : un repli HTTP refusé ne lance pas ensuite un import M3U', () async {
    final List<Uri> calls = <Uri>[];
    final http.Client client = MockClient((http.Request request) async {
      calls.add(request.url);
      if (request.url.scheme == 'https') {
        throw const HandshakeException('WRONG_VERSION_NUMBER');
      }
      return http.Response('Refus', 403);
    });
    await expectLater(_importGetPhp(client), throwsA(isA<SourceProtocolFallbackFailure>()));
    expect(calls, hasLength(2));
    expect(calls.where((Uri u) => u.path.endsWith('get.php')), isEmpty);
    expect(await PlaylistRepository.instance.getAllPlaylists(), isEmpty);
  });

  test('get.php : le budget HTTP reste consommé si les chaînes sont vides', () async {
    final List<Uri> calls = <Uri>[];
    final http.Client client = MockClient((http.Request request) async {
      calls.add(request.url);
      if (request.url.scheme == 'https') {
        throw const HandshakeException('WRONG_VERSION_NUMBER');
      }
      return _xtreamResponse(request, emptyLive: true);
    });
    await expectLater(_importGetPhp(client), throwsA(isA<SourceProtocolFallbackFailure>()));
    expect(calls.where((Uri u) => u.scheme == 'https'), hasLength(1));
    expect(calls.where((Uri u) => u.path.endsWith('get.php')), isEmpty);
    expect(await PlaylistRepository.instance.getAllPlaylists(), isEmpty);
  });

  test('deux actualisations des listes attendent le même résultat', () async {
    await PlaylistRepository.instance.addM3uPlaylist(
      name: 'Liste test', url: _plain,
      httpClient: MockClient((_) async => http.Response(_m3u, 200)),
    );
    final Completer<void> started = Completer<void>();
    final Completer<void> release = Completer<void>();
    int requests = 0;
    await http.runWithClient(() async {
      final Future<int> first = PlaylistRepository.instance.refreshAll();
      await started.future;
      bool done = false;
      final Future<int> second = PlaylistRepository.instance.refreshAll().then((int result) {
        done = true;
        return result;
      });
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      release.complete();
      expect(await Future.wait(<Future<int>>[first, second]), <int>[1, 1]);
      expect(requests, 1);
    }, () => MockClient((_) async {
      requests++;
      if (!started.isCompleted) started.complete();
      await release.future;
      return http.Response(_m3u, 200);
    }));
  });

  test('une demande manuelle suit la passe automatique et relit les sources récentes', () async {
    final Playlist first = await PlaylistRepository.instance.addM3uPlaylist(
      name: 'Ancienne', url: _plain,
      httpClient: MockClient((_) async => http.Response(_m3u, 200)),
    );
    await PlaylistRepository.instance.addM3uPlaylist(
      name: 'Récente', url: 'http://source.invalid:8080/recent.m3u',
      httpClient: MockClient((_) async => http.Response(_m3u, 200)),
    );
    final Database db = await PlaylistDatabase.instance.database;
    await db.update('playlists', <String, Object>{'last_synced_at': 1},
      where: 'id = ?', whereArgs: <Object>[first.id!]);
    final Completer<void> started = Completer<void>();
    final Completer<void> release = Completer<void>();
    int requests = 0;
    await http.runWithClient(() async {
      final Future<int> automatic = PlaylistRepository.instance.refreshAll(
        skipSyncedWithin: const Duration(hours: 6),
      );
      await started.future;
      final Future<int> manual = PlaylistRepository.instance.refreshAll();
      release.complete();
      expect(await automatic, 1);
      expect(await manual, 2);
      expect(requests, 3);
    }, () => MockClient((_) async {
      requests++;
      if (!started.isCompleted) started.complete();
      await release.future;
      return http.Response(_m3u, 200);
    }));
  });

  for (final String revoked in <String>[_plain, _url]) {
    test('une suppression de l’identité $revoked pendant le repli gagne', () async {
      // Un ancien refus peut être levé par ce nouvel ajout volontaire.
      // Le retrait suivant, pendant le réseau, doit rester définitif.
      await _rememberM3u(_plain);
      final http.Client client = MockClient((http.Request request) async {
        if (request.url.scheme == 'https') {
          throw const HandshakeException('WRONG_VERSION_NUMBER');
        }
        await _rememberM3u(revoked);
        return http.Response(_m3u, 200);
      });
      await expectLater(PlaylistRepository.instance.addM3uPlaylist(
        name: 'Liste test', url: _url, allowHttpCompatibility: true, httpClient: client,
      ), throwsA(isA<PlaylistDeletedException>()));
      expect(await PlaylistRepository.instance.getAllPlaylists(), isEmpty);
      expect(await PlaylistRepository.instance.getAllChannels(), isEmpty);
      await _restartSourceStore();
      expect(await PlaylistRepository.instance.getAllPlaylists(), isEmpty);
    });
  }

  test('un réajout volontaire HTTPS vers HTTP reste présent au redémarrage', () async {
    await _rememberM3u(_plain);
    // La levée est limitée aux alias de la demande, jamais aux autres listes.
    await _rememberM3u('http://other.invalid/private.m3u');
    final http.Client client = MockClient((http.Request request) async {
      if (request.url.scheme == 'https') {
        throw const HandshakeException('WRONG_VERSION_NUMBER');
      }
      return http.Response(_m3u, 200);
    });
    final Playlist saved = await PlaylistRepository.instance.addM3uPlaylist(
      name: 'Liste test', url: _url, allowHttpCompatibility: true, httpClient: client,
    );
    expect(saved.m3uUrl, _plain);
    await _restartSourceStore();
    expect((await PlaylistRepository.instance.getAllPlaylists()).single.m3uUrl, _plain);
    final Database db = await PlaylistDatabase.instance.database;
    expect(await db.query('deleted_sources'), hasLength(1));
  });

  test('un retrait Xtream HTTP pendant la vérification interdit l’insertion', () async {
    await _rememberXtream('http://source.invalid:8080');
    final List<Uri> calls = <Uri>[];
    final http.Client client = MockClient((http.Request request) async {
      calls.add(request.url);
      if (request.url.scheme == 'https') {
        throw const HandshakeException('WRONG_VERSION_NUMBER');
      }
      await _rememberXtream('http://source.invalid:8080');
      return _xtreamResponse(request);
    });
    await expectLater(_importGetPhp(client), throwsA(isA<SourceProtocolFallbackFailure>()
      .having((SourceProtocolFallbackFailure e) => e.cause, 'cause', isA<PlaylistDeletedException>())));
    expect(calls, hasLength(2));
    expect(await PlaylistRepository.instance.getAllPlaylists(), isEmpty);
    await _restartSourceStore();
    expect(await PlaylistRepository.instance.getAllPlaylists(), isEmpty);
  });

  test('un compte Xtream HTTP supprimé peut être réajouté via son lien HTTPS', () async {
    await _rememberXtream('http://source.invalid:8080');
    final http.Client client = MockClient((http.Request request) async {
      if (request.url.scheme == 'https') {
        throw const HandshakeException('WRONG_VERSION_NUMBER');
      }
      return _xtreamResponse(request);
    });
    await http.runWithClient(() => _importGetPhp(client), () => client);
    await _restartSourceStore();
    expect((await PlaylistRepository.instance.getAllPlaylists()).single.xtreamServer,
      'http://source.invalid:8080');
  });
}
