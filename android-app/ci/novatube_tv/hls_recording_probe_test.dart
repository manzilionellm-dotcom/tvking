// Banc Linux. Exécuter avec NOVATUBE_HLS_FIXTURE pointant sur le dossier
// contenant media.m3u8 et ses segments TS ; la capture est écrite à côté.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/local_stream_relay.dart';

void main() {
  final root = Platform.environment['NOVATUBE_HLS_FIXTURE'];
  test('capturer la mire HLS et vérifier les images décodées', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final reads = <String, int>{};
    server.listen((r) async {
      final name = r.uri.pathSegments.last;
      if (!RegExp(r'^(media\.m3u8|p\d+\.ts)$').hasMatch(name)) {
        r.response.statusCode = 404;
      } else {
        reads.update(name, (n) => n + 1, ifAbsent: () => 1);
        r.response.add(await File('$root/$name').readAsBytes());
      }
      await r.response.close();
    });
    final relay = LocalStreamRelay.instance;
    final url = 'http://127.0.0.1:${server.port}/media.m3u8';
    final path = '$root/capture.ts';
    try {
      expect(await relay.startRecording(realUrl: url, filePath: path), isTrue);
      expect(
          await relay
              .recordingFinished(url)
              .timeout(const Duration(seconds: 20)),
          isTrue);
      Future<List<String>> hashes(String input, String map) async {
        final cmd = await Process.run('ffmpeg',
            ['-v', 'error', '-i', input, '-map', map, '-f', 'framemd5', '-']);
        expect(cmd.exitCode, 0, reason: cmd.stderr.toString());
        return cmd.stdout
            .toString()
            .split('\n')
            .where((s) => s.isNotEmpty && !s.startsWith('#'))
            .map((s) => s.split(',').last.trim())
            .toList();
      }

      for (final track in ['0:v:0', '0:a:0']) {
        final original = await hashes('$root/media.m3u8', track);
        expect(original, isNotEmpty);
        expect(await hashes(path, track), original);
        print('P0_HLS track=$track unites=${original.length}');
      }
      expect(reads.values.every((n) => n == 1), isTrue);
      print('P0_HLS requetes=$reads octets=${await File(path).length()}');
    } finally {
      await relay.stopRecording(url);
      await server.close(force: true);
    }
  }, skip: root == null);
}
