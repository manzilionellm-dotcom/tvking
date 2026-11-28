// Sonde commune au témoin et au candidat. L'origine est locale, synthétique,
// et ne commence à émettre qu'une fois le lecteur et le fichier attachés.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/local_stream_relay.dart';

void main() {
  final fixture = Platform.environment['ZUNO_HLS_FIXTURE'];
  test('lecture et REC partagent les segments MPEG-TS multiplexés en clair',
      () async {
    final folder = await Directory.systemTemp.createTemp('zuno-hls-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final counts = <String, int>{};
    final sockets = <int>{};
    final requested = Completer<void>();
    final ready = Completer<void>();
    final errors = <String>[];
    final stopwatch = Stopwatch()..start();
    final file = File('${folder.path}/capture.ts');
    final output = Platform.environment['ZUNO_MEDIA_RESULT'];
    final client = HttpClient();
    final relay = LocalStreamRelay.instance;
    final url = 'http://127.0.0.1:${server.port}/media.m3u8';
    final playFile = File('${folder.path}/lecteur.ts');
    server.listen((r) async {
      sockets.add(r.connectionInfo!.remotePort);
      final name = r.uri.pathSegments.last;
      counts[name] = (counts[name] ?? 0) + 1;
      if (!requested.isCompleted) requested.complete();
      await ready.future;
      try {
        if (!RegExp(r'^(media\.m3u8|p\d+\.ts)$').hasMatch(name)) {
          r.response.statusCode = 404;
        } else {
          r.response.add(await File('$fixture/$name').readAsBytes());
        }
        await r.response.close();
      } on IOException {/* La sonde a fermé son lecteur. */}
    });
    try {
      final target = await relay.playUrlFor(url);
      final request = await client.getUrl(Uri.parse(target));
      final playback = request.close().then<void>((r) async {
        await r.pipe(playFile.openWrite());
      }).catchError((Object _) {});
      await requested.future.timeout(const Duration(seconds: 5));
      expect(await relay.startRecording(realUrl: url, filePath: file.path),
          isTrue);
      ready.complete();
      final segments = Directory(fixture!)
          .listSync()
          .whereType<File>()
          .where((f) => RegExp(r'/p\d+\.ts$').hasMatch(f.path))
          .toList();
      final expected = segments.fold<int>(0, (sum, f) => sum + f.lengthSync());
      final elapsed = Stopwatch()..start();
      while (file.lengthSync() < expected &&
          elapsed.elapsed < Duration(seconds: int.parse(Platform.environment['ZUNO_HLS_DEADLINE_S'] ?? '20'))) {
        if (elapsed.elapsedMilliseconds > 850 &&
            counts.length == 1 &&
            relay.recordedBytes(url) > 0) break;
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      await relay.stopRecording(url);
      client.close(force: true);
      try {
        await playback.timeout(const Duration(seconds: 1));
      } catch (_) {}
      final result = <String, Object>{
        'source_segments': segments.length,
        'expected_bytes': expected,
        'file_bytes': file.lengthSync(),
        'player_bytes': playFile.existsSync() ? playFile.lengthSync() : 0,
        'file_prefix_hex': (await file.openRead(0, 7).first)
            .map((e) => e.toRadixString(16).padLeft(2, '0'))
            .join(),
        'origin_requests': counts,
        'origin_tcp_connections': sockets.length,
        'elapsed_ms': stopwatch.elapsedMilliseconds,
        'errors': errors,
      };
      // Cumul et comparaison des signatures par unité décodée (image / bloc audio).
      for (final track in ['v:0', 'a:0']) {
        Future<List<String>> digest(String path) async {
          final p = await Process.run('ffmpeg', [
            '-nostdin',
            '-v',
            'error',
            '-threads',
            '1',
            '-i',
            path,
            '-map',
            '0:$track',
            '-threads',
            '1',
            '-f',
            'framemd5',
            '-'
          ]);
          if (p.exitCode != 0) return [];
          return const LineSplitter()
              .convert(p.stdout as String)
              .where((s) => s.isNotEmpty && !s.startsWith('#'))
              .map((s) => s.split(',').last.trim())
              .toList();
        }

        final reference = await digest('$fixture/media.m3u8');
        result['reference_$track'] = reference.length;
        for (final entry in {'file': file, 'player': playFile}.entries) {
          final d = await digest(entry.value.path);
          result['${entry.key}_$track'] = d.length;
          if (reference.isEmpty || !listEquals(d, reference))
            errors.add('${entry.key}_$track');
        }
      }
      if (output != null) await File(output).writeAsString(jsonEncode(result));
      expect(
          counts.values.every((n) => n == 1) &&
              counts.length == segments.length + 1,
          isTrue);
      expect(sockets, hasLength(1));
      expect(errors, isEmpty);
    } finally {
      if (!ready.isCompleted) ready.complete();
      client.close(force: true);
      await relay.stopRecording(url);
      await server.close(force: true);
      await folder.delete(recursive: true);
    }
  }, skip: fixture == null, timeout: const Timeout(Duration(minutes: 18)));
}
