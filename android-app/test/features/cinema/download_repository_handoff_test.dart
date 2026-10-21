import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/vod/data/download_repository.dart';
import 'package:tv_king/features/vod/domain/vod_movie.dart';

// Ces doubles ne créent aucune socket. La base SQLite et le répertoire
// temporaire sont réels ; seuls les deux await qui causent la course sont
// retenus pour observer la pause du vrai DownloadsRepository.
class _HeldDirectory extends Fake implements Directory {
  final entered = Completer<void>();
  final finish = Completer<Directory>();

  @override
  Future<Directory> create({bool recursive = false}) {
    entered.complete();
    return finish.future;
  }
}

class _HeldFile extends Fake implements File {
  _HeldFile(this.parent);

  @override
  final Directory parent;
}

class _HttpRequest extends Fake implements HttpClientRequest {
  int sendCount = 0;

  @override
  Future<HttpClientResponse> close() {
    sendCount++;
    throw StateError('Cette requête annulée ne doit jamais partir');
  }
}

class _HttpClient extends Fake implements HttpClient {
  final entered = Completer<void>();
  final finish = Completer<HttpClientRequest>();
  int closeCount = 0;

  @override
  set connectionTimeout(Duration? value) {}
  @override
  set autoUncompress(bool value) {}
  @override
  set userAgent(String? value) {}

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    entered.complete();
    return finish.future;
  }

  @override
  void close({bool force = false}) {
    expect(force, isTrue);
    closeCount++;
  }
}

VodMovie _movie(String id) => VodMovie(
      id: id,
      name: 'Film',
      category: 'Test',
      streamUrl: 'https://example.invalid/$id.mp4',
      containerExt: 'mp4',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final repository = DownloadsRepository.instance;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('zuno-download-handoff-');
    PlaylistDatabase.debugFilePath = '${directory.path}/test.db';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (_) async => directory.path);
    await repository.initialize();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    await directory.delete(recursive: true);
  });

  test('pause pendant la préparation disque : aucun client HTTP tardif',
      () async {
    final heldDirectory = _HeldDirectory();
    final heldFile = _HeldFile(heldDirectory);
    final outside = Zone.current;
    var clients = 0;
    await HttpOverrides.runZoned(() async {
      await IOOverrides.runZoned(() async {
        await repository.start(_movie('disk'));
        await heldDirectory.entered.future;
        var paused = false;
        final pause = repository.pause('disk').then((_) => paused = true);
        await Future<void>.value();
        expect(paused, isFalse);
        heldDirectory.finish.complete(directory);
        await pause;
        expect(clients, 0);
        expect(repository.byId('disk')!.status, DownloadStatus.paused);
      }, createFile: (path) {
        if (path.endsWith('Film-disk.mp4')) return heldFile;
        return outside.run(() => File(path));
      });
    }, createHttpClient: (_) {
      clients++;
      return _HttpClient();
    });
  });

  test('pause pendant getUrl : attend le job, ferme le client, ne lance rien',
      () async {
    final client = _HttpClient();
    final request = _HttpRequest();
    await HttpOverrides.runZoned(() async {
      await repository.start(_movie('http'));
      await client.entered.future;
      var paused = false;
      final pause = repository.pause('http').then((_) => paused = true);
      await Future<void>.value();
      expect(client.closeCount, greaterThan(0));
      expect(paused, isFalse);
      client.finish.complete(request);
      await pause;
      expect(request.sendCount, 0);
      expect(client.closeCount, greaterThanOrEqualTo(2));
      expect(repository.byId('http')!.status, DownloadStatus.paused);
    }, createHttpClient: (_) => client);
  });
}
