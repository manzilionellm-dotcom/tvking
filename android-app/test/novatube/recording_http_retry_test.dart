import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/local_stream_relay.dart';

// Synthetic transport packets only. These tests exercise the real HTTP relay,
// not the gallery/export mock. No provider URL, account or private video.
List<int> _packets(int value) => <int>[
      for (int n = 0; n < 4; n++) ...<int>[
        0x47, 0x01, 0x00, 0x10 | n, ...List<int>.filled(184, value),
      ],
    ];

void main() {
  late Directory directory;
  late HttpServer server;
  late LocalStreamRelay relay;
  String url(String path) => 'http://127.0.0.1:${server.port}$path';
  String getPath() => '${directory.path}/capture.ts';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('novatube_http_rec_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    relay = LocalStreamRelay.forTesting(
      firstMediaTimeout: const Duration(seconds: 2),
      networkTimeout: const Duration(seconds: 1),
      retryDelay: const Duration(milliseconds: 10),
      maxReconnectFailures: 3,
    );
  });
  tearDown(() async {
    await relay.closeForTesting();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  // 401/403/458/509 : refus « connexion encore occupée » d'un fournisseur
  // 1 connexion max pendant la bascule direct → relais (avant tout média).
  for (final int transient in <int>[
    408, 429, 500, 502, 503, 504, 401, 403, 458, 509,
  ]) {
    test('REC recovers from HTTP $transient before first media', () async {
      int requests = 0;
      final List<int> media = _packets(0x31);
      server.listen((HttpRequest request) async {
        requests++;
        if (requests == 1) {
          request.response.statusCode = transient;
          request.response.write('Temporary refusal: not media');
          await request.response.close();
          return;
        }
        request.response.bufferOutput = false;
        request.response.add(media);
        await request.response.flush();
        // Keep the live connection open until the recorder stops it.
      });
      final String source = url('/live');
      expect(await relay.startRecording(
        realUrl: source, filePath: getPath(),
      ), isTrue);
      final RelayRecordingResult result =
          await relay.stopRecordingResult(source, closePlayback: true);
      expect(requests, 2);
      expect(result.succeeded, isTrue);
      expect(result.bytes, media.length);
      expect(await File(getPath()).readAsBytes(), media);
    });
  }

  for (final int permanent in <int>[400, 404, 410]) {
    test('REC does not retry permanent HTTP $permanent', () async {
      int requests = 0;
      server.listen((HttpRequest request) async {
        requests++;
        request.response.statusCode = permanent;
        await request.response.close();
      });
      await expectLater(
        relay.startRecording(realUrl: url('/live'), filePath: getPath()),
        throwsA(isA<RelayRecordingException>().having(
          (RelayRecordingException e) => e.reason,
          'reason', RelayStopReason.networkError,
        )),
      );
      expect(requests, 1);
      expect(await File(getPath()).length(), 0);
    });
  }

  test('REC stops after the bounded HTTP retry budget', () async {
    int requests = 0;
    server.listen((HttpRequest request) async {
      requests++;
      request.response.statusCode = 503;
      await request.response.close();
    });
    final Stopwatch watch = Stopwatch()..start();
    await expectLater(
      relay.startRecording(realUrl: url('/live'), filePath: getPath()),
      throwsA(isA<RelayRecordingException>()),
    );
    // Bascule : budget en temps (firstMediaTimeout = 2 s), plus 3 essais.
    expect(requests, greaterThan(3));
    expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
    expect(await File(getPath()).length(), 0);
  });

  test('REC recovers when the provider drops connections during handoff',
      () async {
    int requests = 0;
    final List<int> media = _packets(0x51);
    server.listen((HttpRequest request) async {
      requests++;
      if (requests <= 2) {
        // Coupure brutale sans réponse HTTP (fournisseur encore occupé).
        final Socket socket = await request.response.detachSocket(
          writeHeaders: false,
        );
        socket.destroy();
        return;
      }
      request.response.bufferOutput = false;
      request.response.add(media);
      await request.response.flush();
    });
    final String source = url('/live');
    expect(await relay.startRecording(
      realUrl: source, filePath: getPath(),
    ), isTrue);
    final RelayRecordingResult result =
        await relay.stopRecordingResult(source, closePlayback: true);
    expect(requests, 3);
    expect(result.succeeded, isTrue);
    expect(await File(getPath()).readAsBytes(), media);
  });

  test('a 403 after media is final: HLS segments are never retried on it',
      () async {
    final Map<String, int> requests = <String, int>{};
    final List<int> first = _packets(0x61);
    final Completer<RelayRecordingResult> stopped =
        Completer<RelayRecordingResult>();
    server.listen((HttpRequest request) async {
      final String path = request.uri.path;
      requests.update(path, (int n) => n + 1, ifAbsent: () => 1);
      if (path == '/live.m3u8') {
        request.response.write('#EXTM3U\n'
            '#EXT-X-TARGETDURATION:1\n#EXT-X-MEDIA-SEQUENCE:0\n'
            '#EXTINF:1,\na.ts\n#EXTINF:1,\nb.ts\n#EXT-X-ENDLIST\n');
      } else if (path == '/a.ts') {
        request.response.add(first);
      } else {
        request.response.statusCode = 403;
      }
      await request.response.close();
    });
    expect(await relay.startRecording(
      realUrl: url('/live.m3u8'),
      filePath: getPath(),
      onStopped: stopped.complete,
    ), isTrue);
    final RelayRecordingResult result =
        await stopped.future.timeout(const Duration(seconds: 2));
    expect(result.reason, RelayStopReason.networkError);
    expect(requests['/b.ts'], 1);
    expect(await File(getPath()).readAsBytes(), first);
  });

  test('HLS retry keeps previous segments and never duplicates their bytes',
      () async {
    final Map<String, int> requests = <String, int>{};
    final List<int> first = _packets(0x41);
    final List<int> second = _packets(0x42);
    final Completer<RelayRecordingResult> stopped =
        Completer<RelayRecordingResult>();
    server.listen((HttpRequest request) async {
      final String path = request.uri.path;
      final int count = requests.update(path, (int n) => n + 1,
          ifAbsent: () => 1);
      if (path == '/live.m3u8') {
        request.response.write('#EXTM3U\n'
            '#EXT-X-TARGETDURATION:1\n#EXT-X-MEDIA-SEQUENCE:0\n'
            '#EXTINF:1,\na.ts\n#EXTINF:1,\nb.ts\n#EXT-X-ENDLIST\n');
      } else if (path == '/a.ts') {
        request.response.add(first);
      } else if (path == '/b.ts' && count == 1) {
        request.response.statusCode = 503;
        request.response.write('Temporary refusal');
      } else if (path == '/b.ts') {
        request.response.add(second);
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    expect(await relay.startRecording(
      realUrl: url('/live.m3u8'),
      filePath: getPath(),
      onStopped: stopped.complete,
    ), isTrue);
    final RelayRecordingResult result =
        await stopped.future.timeout(const Duration(seconds: 2));
    expect(result.reason, RelayStopReason.completed);
    expect(requests, <String, int>{'/live.m3u8': 1, '/a.ts': 1, '/b.ts': 2});
    expect(await File(getPath()).readAsBytes(), <int>[...first, ...second]);
  });

  test('stopping REC cancels retry delay without another upstream request',
      () async {
    await relay.closeForTesting();
    relay = LocalStreamRelay.forTesting(
      firstMediaTimeout: const Duration(seconds: 2),
      networkTimeout: const Duration(seconds: 1),
      retryDelay: const Duration(seconds: 1),
      maxReconnectFailures: 3,
    );
    final Completer<void> refused = Completer<void>();
    int requests = 0;
    server.listen((HttpRequest request) async {
      requests++;
      request.response.statusCode = 503;
      await request.response.close();
      if (!refused.isCompleted) refused.complete();
    });
    final String source = url('/live');
    final Future<void> checked = expectLater(
      relay.startRecording(realUrl: source, filePath: getPath()),
      throwsA(isA<RelayRecordingException>()),
    );
    await refused.future;
    await relay.stopRecordingResult(source, closePlayback: true)
        .timeout(const Duration(milliseconds: 750));
    await checked;
    expect(requests, 1);
  });
}
