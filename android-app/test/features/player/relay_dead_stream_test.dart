import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/local_stream_relay.dart';

void main() {
  test('seize demandes simultanées ouvrent un unique serveur local', () async {
    final relay = LocalStreamRelay.instance;
    final urls = await Future.wait(
        List.generate(16, (_) => relay.playUrlFor('http://localhost/mire.ts')));
    expect(urls.toSet(), hasLength(1));
  });

  test('un fichier impossible à ouvrir ne démarre aucun amont', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((req) {
      requests++;
      req.response.close();
    });
    final dir = await Directory.systemTemp.createTemp('relay-disque-');
    try {
      final relay = LocalStreamRelay.instance;
      final url = 'http://127.0.0.1:${server.port}/test';
      expect(await relay.startRecording(realUrl: url, filePath: dir.path),
          isFalse);
      expect(relay.isRecording(url), isFalse);
      expect(requests, 0);
    } finally {
      await server.close(force: true);
      await dir.delete();
    }
  });

  test('trois réponses vides ferment le fichier et la session', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dir = await Directory.systemTemp.createTemp('relay-vide-');
    var requests = 0;
    server.listen((req) {
      requests++;
      req.response.close();
    });
    final relay = LocalStreamRelay.instance;
    final url = 'http://127.0.0.1:${server.port}/empty';
    try {
      expect(
          await relay.startRecording(
              realUrl: url, filePath: '${dir.path}/vide.ts'),
          isTrue);
      await relay.recordingFinished(url).timeout(const Duration(seconds: 12));
      expect(requests, 3);
      expect(relay.isRecording(url), isFalse);
      expect(await File('${dir.path}/vide.ts').length(), 0);
    } finally {
      await relay.stopRecording(url);
      await server.close(force: true);
      await dir.delete(recursive: true);
    }
  });

  test('un amont muet aux en-têtes ou dans le corps est remplacé', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dir = await Directory.systemTemp.createTemp('relay-reprise-');
    final counts = <String, int>{};
    final recovered = <String, Completer<void>>{
      for (final mode in ['headers', 'body']) mode: Completer<void>(),
    };
    server.listen((req) async {
      final mode = req.uri.path.substring(1);
      final number = counts.update(mode, (n) => n + 1, ifAbsent: () => 1);
      final response = req.response;
      response.bufferOutput = false;
      if (number == 1 && mode == 'headers') return;
      response.add([0x47]);
      await response.flush();
      if (number == 2) recovered[mode]!.complete();
    });
    final relay = LocalStreamRelay.instance;
    final urls = [
      for (final mode in recovered.keys) 'http://127.0.0.1:${server.port}/$mode'
    ];
    try {
      for (final url in urls) {
        final file = '${dir.path}/${Uri.parse(url).pathSegments.last}.ts';
        expect(
            await relay.startRecording(realUrl: url, filePath: file), isTrue);
      }
      await Future.wait(recovered.values.map((event) => event.future))
          .timeout(const Duration(seconds: 38));
      expect(counts, {'body': 2, 'headers': 2});
    } finally {
      for (final url in urls) {
        await relay.stopRecording(url);
      }
      await server.close(force: true);
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 45)));
}
