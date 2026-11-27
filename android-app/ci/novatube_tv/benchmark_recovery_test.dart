// Banc manuel Linux, sans fournisseur. Fournir une mire TS de 4 secondes
// à 25 i/s et 1 504 000 bit/s ainsi que NOVATUBE_RECOVERY_OUTPUT.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/player/data/local_stream_relay.dart';
import 'package:tv_king/features/player/domain/live_fallback.dart';

void main() {
  final mediaOnly = Platform.environment['NOVATUBE_MEDIA_ONLY'] == '1';
  final output = Platform.environment['NOVATUBE_RECOVERY_OUTPUT'];
  final fixture = Platform.environment['NOVATUBE_RECOVERY_TS'];
  test('mesurer le secours et le relais local', () async {
    final result = <String, Object>{};
    void save() => File(output!).writeAsStringSync(jsonEncode(result));
    final relay = LocalStreamRelay.instance;
    if (!mediaOnly) {
      final urls = await Future.wait(
          List.generate(16, (_) => relay.playUrlFor('http://localhost/test')));
      result['serverPorts'] =
          urls.map((url) => Uri.parse(url).port).toSet().length;
      final catalog = <Map<String, Object>>[];
      for (final size in [5000, 20000]) {
        final channels = List.generate(
            size,
            (i) => Channel(
                id: 'id$i',
                name: 'Mire HD',
                category: 'Tests',
                streamUrl: 'http://localhost/media/$i.ts',
                isLive: true));
        final samples = <int>[];
        for (var i = 0; i < 6; i++) {
          final clock = Stopwatch()..start();
          final found = LiveFallback.backups(channels.first, channels);
          clock.stop();
          expect(
              found, channels.skip(1).take(4).map((c) => c.streamUrl).toList());
          if (i > 0) samples.add(clock.elapsedMicroseconds);
        }
        catalog.add({'size': size, 'us': samples});
      }
      result['fallback'] = catalog;
      save();
    }

    final ts = await File(fixture!).readAsBytes();
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => origin.close(force: true));
    var opens = 0;
    origin.listen((request) async {
      opens++;
      final response = request.response;
      response.bufferOutput = false;
      final clock = Stopwatch()..start();
      try {
        for (var i = 0; i < ts.length; i += 7520) {
          response.add(ts.sublist(i, math.min(i + 7520, ts.length)));
          await response.flush();
          final remaining =
              Duration(microseconds: (i + 7520) * 8000000 ~/ 1504000) -
                  clock.elapsed;
          if (!remaining.isNegative) await Future<void>.delayed(remaining);
        }
      } on IOException {/* Le lecteur a terminé ses 40 images. */} finally {
        try {
          await response.close();
        } on IOException {
          // Le client peut déjà avoir fermé sa connexion de mesure.
        }
      }
    });
    final observations = <Map<String, Object>>[];
    // ABBA répété pour alterner la position des deux chemins de lecture.
    final ticksPerSecond = int.parse(
        (await Process.run('getconf', ['CLK_TCK'])).stdout.toString().trim());
    int processTicks() {
      final stat = File('/proc/self/stat').readAsStringSync();
      final v = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
      return int.parse(v[11]) + int.parse(v[12]);
    }

    for (var i = 0; i < (mediaOnly ? 16 : 4); i++) {
      final upstream = 'http://127.0.0.1:${origin.port}/mire$i.ts';
      final throughRelay = i % 4 == 1 || i % 4 == 2;
      final input = throughRelay ? await relay.playUrlFor(upstream) : upstream;
      final startRequests = opens;
      final cpuStart = processTicks();
      final rssStart = ProcessInfo.currentRss;
      final clock = Stopwatch()..start();
      final ffmpeg = await Process.start('ffmpeg', [
        '-nostdin',
        '-v',
        'error',
        '-threads',
        '1',
        '-probesize',
        '32',
        '-analyzeduration',
        '0',
        '-f',
        'mpegts',
        '-i',
        input,
        '-an',
        '-vf',
        'scale=1:1',
        '-threads',
        '1',
        '-pix_fmt',
        'gray',
        '-frames:v',
        '40',
        '-fps_mode',
        'passthrough',
        '-f',
        'rawvideo',
        '-flush_packets',
        '1',
        'pipe:1'
      ]);
      final errors = ffmpeg.stderr.transform(utf8.decoder).join();
      final times = <int>[];
      await for (final chunk in ffmpeg.stdout) {
        final t = clock.elapsedMicroseconds;
        times.addAll(List.filled(chunk.length, t));
      }
      expect(await ffmpeg.exitCode, 0, reason: await errors);
      expect(times.length, 40);
      observations.add({
        'relay': throughRelay,
        'firstUs': times.first,
        'arrivalsUs': times,
        'originRequests': opens - startRequests,
        'flutterCpuMs': (processTicks() - cpuStart) * 1000 / ticksPerSecond,
        'rssStartBytes': rssStart,
        'rssEndBytes': ProcessInfo.currentRss
      });
    }
    result['decoder'] = observations;
    save();
    if (mediaOnly) return;

    final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => dead.close(force: true));
    final attempts = <int>[];
    final clock = Stopwatch()..start();
    dead.listen((req) async {
      attempts.add(clock.elapsedMilliseconds);
      req.response.contentLength = 0;
      await req.response.close();
    });
    final path = 'http://127.0.0.1:${dead.port}/vide';
    final tmp = await Directory.systemTemp.createTemp('novatube-vide-');
    addTearDown(() => tmp.delete(recursive: true));
    await relay.startRecording(realUrl: path, filePath: '${tmp.path}/vide.ts');
    while (relay.isRecording(path) &&
        attempts.length < 14 &&
        clock.elapsed.inSeconds < 165) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    result['dead'] = {
      'attemptsMs': attempts,
      'endedAutomatically': !relay.isRecording(path),
      'observedMs': clock.elapsedMilliseconds
    };
    save();
    await relay.stopRecording(path);
  },
      skip: output == null || fixture == null || !Platform.isLinux,
      timeout: const Timeout(Duration(minutes: 5)));
}
