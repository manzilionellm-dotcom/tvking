import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/local_stream_relay.dart';

// Paquets de transport synthétiques ; aucune URL de fournisseur ni vidéo tierce.
List<int> _packets(int count, [int value = 0x31]) => <int>[
      for (int n = 0; n < count; n++) ...<int>[
        0x47,
        0x01,
        0x00,
        0x10 | (n & 15),
        ...List<int>.filled(184, value),
      ],
    ];

Future<void> _until(bool Function() condition) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition locale non atteinte');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _FaultyFile implements RandomAccessFile {
  _FaultyFile(this.inner, {this.writeFails = false, this.flushFails = false});
  final RandomAccessFile inner;
  final bool writeFails;
  final bool flushFails;
  bool closed = false;
  @override
  Future<RandomAccessFile> writeFrom(List<int> buffer,
      [int start = 0, int? end]) async {
    if (writeFails) throw const FileSystemException('Disque de test plein');
    await inner.writeFrom(buffer, start, end);
    return this;
  }

  @override
  Future<RandomAccessFile> flush() async {
    if (flushFails) throw const FileSystemException('Échec flush simulé');
    await inner.flush();
    return this;
  }

  @override
  Future<void> close() async {
    closed = true;
    await inner.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  late HttpServer server;
  late LocalStreamRelay relay;
  final List<HttpClient> clients = <HttpClient>[];
  String getUrl(String path) => 'http://127.0.0.1:${server.port}$path';
  String getPath([String name = 'capture.ts']) => '${directory.path}/$name';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('novatube_rec_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    relay = LocalStreamRelay.forTesting(
      firstMediaTimeout: const Duration(seconds: 2),
      networkTimeout: const Duration(seconds: 1),
      retryDelay: const Duration(milliseconds: 10),
      playlistPollDelay: const Duration(milliseconds: 10),
      maxReconnectFailures: 2,
    );
  });
  tearDown(() async {
    for (final HttpClient client in clients) {
      client.close(force: true);
    }
    clients.clear();
    await relay.closeForTesting();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('TS : REC attend les octets et partage une lecture fournisseur',
      () async {
    final Completer<HttpResponse> upstream = Completer<HttpResponse>();
    int connections = 0;
    server.listen((HttpRequest request) {
      connections++;
      request.response.bufferOutput = false;
      upstream.complete(request.response);
    });
    final String url = getUrl('/live');
    final String local = await relay.playUrlFor(url);
    bool started = false;
    final Future<bool> start = relay
        .startRecording(realUrl: url, filePath: getPath())
        .then((bool value) {
      started = true;
      return value;
    });
    final HttpResponse response = await upstream.future;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(started, isFalse,
        reason: 'Ouvrir le fichier ne signifie pas REC actif');
    final List<int> first = _packets(4);
    response.add(first);
    await response.flush();
    expect(await start, isTrue);
    final HttpClient client = HttpClient();
    clients.add(client);
    final HttpClientResponse player =
        await (await client.getUrl(Uri.parse(local))).close();
    final List<int> played = <int>[];
    final Completer<void> playerDone = Completer<void>();
    player.listen(played.addAll, onDone: playerDone.complete);
    await _until(() => played.length >= first.length);
    final List<int> second = _packets(4, 0x62);
    response.add(second);
    await response.flush();
    await _until(
        () => relay.recordedBytes(url) == first.length + second.length);
    final RelayRecordingResult result =
        await relay.stopRecordingResult(url, closePlayback: true);
    await playerDone.future;
    expect(connections, 1);
    expect(result.succeeded, isTrue);
    expect(result.bytes, first.length + second.length);
    expect(await File(getPath()).readAsBytes(), <int>[...first, ...second]);
    expect(played, <int>[...first, ...second]);
  });

  test('HLS : meilleure variante TS, redirection relative et segments uniques',
      () async {
    final Map<String, int> requests = <String, int>{};
    final Completer<void> segmentGate = Completer<void>();
    final Completer<RelayRecordingResult> ended =
        Completer<RelayRecordingResult>();
    final List<int> segmentA = _packets(4, 0x41);
    final List<int> segmentB = _packets(4, 0x42);
    server.listen((HttpRequest request) async {
      final String path = request.uri.path;
      requests.update(path, (int n) => n + 1, ifAbsent: () => 1);
      switch (path) {
        case '/master.m3u8':
          request.response.write('#EXTM3U\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=9000000\nfmp4.m3u8\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=5000000,CODECS="avc1.42e01e,mp4a.40.2"\nhigh.m3u8\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=1000000\nlow.m3u8\n');
        case '/fmp4.m3u8':
          request.response.write(
              '#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:2,\nchunk.m4s\n');
        case '/high.m3u8':
          request.response.statusCode = HttpStatus.found;
          request.response.headers
              .set(HttpHeaders.locationHeader, '/selected/media.m3u8');
        case '/selected/media.m3u8':
          request.response.write(
              '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:40\n#EXT-X-TARGETDURATION:2\n'
              '#EXTINF:2,\na.ts\n#EXTINF:2,\nb.ts\n#EXT-X-ENDLIST\n');
        case '/selected/a.ts':
          await segmentGate.future;
          request.response.add(segmentA);
        case '/selected/b.ts':
          request.response.add(segmentB);
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final String url = getUrl('/master.m3u8');
    final String local = await relay.playUrlFor(url);
    final Future<bool> start = relay.startRecording(
        realUrl: url, filePath: getPath(), onStopped: ended.complete);
    final HttpClient client = HttpClient();
    clients.add(client);
    final Future<List<int>> played = (() async {
      final HttpClientResponse response =
          await (await client.getUrl(Uri.parse(local))).close();
      return response.fold<List<int>>(
          <int>[], (List<int> all, List<int> bytes) => all..addAll(bytes));
    })();
    await _until(() => requests.containsKey('/selected/a.ts'));
    segmentGate.complete();
    expect(await start, isTrue);
    final RelayRecordingResult result = await ended.future;
    expect(result.reason, RelayStopReason.completed);
    expect(requests['/selected/a.ts'], 1);
    expect(requests['/selected/b.ts'], 1);
    expect(requests.containsKey('/low.m3u8'), isFalse);
    expect(requests.containsKey('/init.mp4'), isFalse);
    final List<int> expected = <int>[...segmentA, ...segmentB];
    expect(await File(getPath()).readAsBytes(), expected);
    expect(await played, expected);
  });

  test('HLS direct : rechargement gzip sans recopier les anciens segments',
      () async {
    int playlists = 0;
    final Map<String, int> segments = <String, int>{};
    server.listen((HttpRequest request) async {
      if (request.uri.path == '/live.m3u8') {
        playlists++;
        final String body = '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:42\n'
            '#EXT-X-TARGETDURATION:1\n#EXTINF:1,\na.ts\n'
            '${playlists > 1 ? '#EXTINF:1,\nb.ts\n' : ''}';
        request.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
        request.response.add(gzip.encode(body.codeUnits));
      } else {
        final String path = request.uri.path;
        segments.update(path, (int n) => n + 1, ifAbsent: () => 1);
        request.response.add(_packets(4, path == '/a.ts' ? 0x41 : 0x42));
      }
      await request.response.close();
    });
    final String url = getUrl('/live.m3u8');
    expect(
        await relay.startRecording(realUrl: url, filePath: getPath()), isTrue);
    await _until(() => relay.recordedBytes(url) == 8 * 188);
    final RelayRecordingResult result =
        await relay.stopRecordingResult(url, closePlayback: true);
    expect(result.succeeded, isTrue);
    expect(playlists, greaterThanOrEqualTo(2));
    expect(segments, <String, int>{'/a.ts': 1, '/b.ts': 1});
    expect(await File(getPath()).readAsBytes(),
        <int>[..._packets(4, 0x41), ..._packets(4, 0x42)]);
  });

  test('source muette : délai de démarrage borné, aucun faux REC', () async {
    relay = LocalStreamRelay.forTesting(
        firstMediaTimeout: const Duration(milliseconds: 80));
    int connections = 0;
    server.listen((HttpRequest request) {
      connections++;
    });
    final String url = getUrl('/silent');
    await expectLater(
        relay.startRecording(realUrl: url, filePath: getPath()),
        throwsA(isA<RelayRecordingException>()
            .having((e) => e.reason, 'reason', RelayStopReason.networkError)));
    expect(relay.isRecording(url), isFalse);
    expect(await File(getPath()).length(), 0);
    expect(connections, 1);
  });

  for (final (String name, String content) item in <(String, String)>[
    ('HTML HTTP200', '<html>Authentification requise</html>'),
    ('JSON HTTP200', '{"error":"refused"}'),
    ('M3U catalogue', '#EXTM3U\n#EXTINF:-1,Chaîne\n/live.ts\n'),
    (
      'HLS chiffré',
      '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXTINF:2,\na.ts\n'
    ),
    ('HLS fMP4', '#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:2,\na.m4s\n'),
    ('HLS byte range', '#EXTM3U\n#EXT-X-BYTERANGE:188@0\n#EXTINF:2,\na.ts\n'),
    (
      'HLS audio séparé',
      '#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",URI="audio.m3u8"\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=1000000,AUDIO="aud"\nvideo.m3u8\n'
    ),
  ]) {
    test('${item.$1} : jamais écrit comme vidéo', () async {
      server.listen((HttpRequest request) async {
        request.response.write(item.$2);
        await request.response.close();
      });
      await expectLater(
          relay.startRecording(realUrl: getUrl('/source'), filePath: getPath()),
          throwsA(isA<RelayRecordingException>().having(
              (e) => e.reason, 'reason', RelayStopReason.unsupportedStream)));
      expect(await File(getPath()).length(), 0);
    });
  }

  test('échec HTTP après début HLS : fichier clos et arrêt signalé', () async {
    final Completer<RelayRecordingResult> ended =
        Completer<RelayRecordingResult>();
    server.listen((HttpRequest request) async {
      if (request.uri.path == '/source') {
        request.response.write(
            '#EXTM3U\n#EXTINF:2,\na.ts\n#EXTINF:2,\nb.ts\n#EXT-X-ENDLIST\n');
      } else if (request.uri.path == '/a.ts') {
        request.response.add(_packets(4));
      } else {
        request.response.statusCode = 503;
      }
      await request.response.close();
    });
    expect(
        await relay.startRecording(
            realUrl: getUrl('/source'),
            filePath: getPath(),
            onStopped: ended.complete),
        isTrue);
    final RelayRecordingResult result = await ended.future;
    expect(result.reason, RelayStopReason.networkError);
    expect(result.succeeded, isFalse);
    expect(await File(getPath()).length(), 4 * 188);
    expect(relay.isRecording(getUrl('/source')), isFalse);
  });

  for (final bool failOnWrite in <bool>[true, false]) {
    test(
        'disque : ${failOnWrite ? 'write' : 'flush'} échoué ne devient pas sauvegardé',
        () async {
      late _FaultyFile file;
      relay = LocalStreamRelay.forTesting(openFile: (File target) async {
        file = _FaultyFile(await target.open(mode: FileMode.write),
            writeFails: failOnWrite, flushFails: !failOnWrite);
        return file;
      });
      server.listen((HttpRequest request) async {
        request.response.bufferOutput = false;
        request.response.add(_packets(4));
        await request.response.flush();
      });
      final String url = getUrl('/live');
      if (failOnWrite) {
        await expectLater(
            relay.startRecording(realUrl: url, filePath: getPath()),
            throwsA(isA<RelayRecordingException>()
                .having((e) => e.reason, 'reason', RelayStopReason.diskError)));
      } else {
        expect(await relay.startRecording(realUrl: url, filePath: getPath()),
            isTrue);
        final RelayRecordingResult result =
            await relay.stopRecordingResult(url, closePlayback: true);
        expect(result.reason, RelayStopReason.diskError);
        expect(result.succeeded, isFalse);
      }
      expect(file.closed, isTrue);
    });
  }

  test('ancien fichier : refus avant troncature', () async {
    final List<int> previous = _packets(4);
    await File(getPath()).writeAsBytes(previous);
    int requests = 0;
    server.listen((HttpRequest request) async {
      requests++;
      await request.response.close();
    });
    await expectLater(
        relay.startRecording(realUrl: getUrl('/live'), filePath: getPath()),
        throwsA(isA<RelayRecordingException>()
            .having((e) => e.reason, 'reason', RelayStopReason.diskError)));
    expect(await File(getPath()).readAsBytes(), previous);
    expect(requests, 0);
  });

  test('annulation avant média : démarrage refusé et aucune reconnexion',
      () async {
    int requests = 0;
    server.listen((HttpRequest request) {
      requests++;
    });
    final String url = getUrl('/live');
    final Future<void> assertion = expectLater(
        relay.startRecording(realUrl: url, filePath: getPath()),
        throwsA(isA<RelayRecordingException>()
            .having((e) => e.reason, 'reason', RelayStopReason.cancelled)));
    await _until(() => requests == 1);
    await relay.stopRecordingResult(url, closePlayback: true);
    await assertion;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(requests, 1);
    expect(await File(getPath()).length(), 0);
  });
}
