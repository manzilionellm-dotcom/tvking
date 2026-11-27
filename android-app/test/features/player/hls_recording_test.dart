import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/local_stream_relay.dart';

void main() {
  test(
      'le lecteur et le fichier reçoivent les mêmes segments HLS, une requête par séquence',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dir = await Directory.systemTemp.createTemp('hls-segments-');
    final relay = LocalStreamRelay.instance;
    final http = HttpClient();
    final root = 'http://127.0.0.1:${server.port}';
    final url = '$root/alias.m3u8';
    final file = File('${dir.path}/capture.ts');
    final allowFirst = Completer<void>();
    final counts = <String, int>{};
    List<int> packet(int seq) => [0x47, ...List.filled(187, seq)];
    server.listen((req) async {
      final path = req.uri.path;
      final n = counts.update(path, (v) => v + 1, ifAbsent: () => 1);
      if (path == '/alias.m3u8') {
        await req.response.redirect(Uri.parse('$root/base/master.m3u8'));
        return;
      } else if (path == '/base/master.m3u8') {
        req.response
            .write('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nlive.m3u8\n');
      } else if (path == '/base/live.m3u8') {
        if (n == 1) await allowFirst.future;
        req.response.write(
            '#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXT-X-MEDIA-SEQUENCE:80\n'
            '#EXTINF:0.05,\n80.ts\n#EXTINF:0.05,\n81.ts\n');
        if (n > 1) req.response.write('#EXTINF:0.05,\n82.ts\n#EXT-X-ENDLIST\n');
      } else {
        req.response
            .add(packet(int.parse(req.uri.pathSegments.last.split('.').first)));
      }
      await req.response.close();
    });
    try {
      final local = await relay.playUrlFor(url);
      expect(await relay.startRecording(realUrl: url, filePath: file.path),
          isTrue);
      final done = relay.recordingFinished(url);
      final response = (await http.getUrl(Uri.parse(local))).close();
      allowFirst.complete();
      final playback = await (await response).fold(
          <int>[], (List<int> out, List<int> bytes) => out..addAll(bytes));
      expect(await done, isTrue);
      final expected = [
        for (final seq in [80, 81, 82]) ...packet(seq)
      ];
      expect(await file.readAsBytes(), expected);
      expect(playback, expected);
      expect(counts, {
        '/alias.m3u8': 1,
        '/base/master.m3u8': 1,
        '/base/live.m3u8': 2,
        '/base/80.ts': 1,
        '/base/81.ts': 1,
        '/base/82.ts': 1
      });
    } finally {
      if (!allowFirst.isCompleted) allowFirst.complete();
      http.close(force: true);
      await relay.stopRecording(url);
      await server.close(force: true);
      await dir.delete(recursive: true);
    }
  });
}
