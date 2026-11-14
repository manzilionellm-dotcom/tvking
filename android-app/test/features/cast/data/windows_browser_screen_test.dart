import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/local_cast_server.dart';

void main() {
  test('browser screen and current session use existing LAN HTTP server',
      () async {
    final LocalCastServer server = LocalCastServer.instance;
    final HttpClient client = HttpClient();
    final int port = await server.start();
    Future<String> get(String path) async {
      final HttpClientRequest req =
          await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
      final HttpClientResponse response = await req.close();
      expect(response.statusCode, 200);
      return utf8.decoder.bind(response).join();
    }

    try {
      expect(await get('/screen'), contains('<video'));
      await server.serveBrowser(
          upstreamUrl: 'https://example.invalid/own-video.mp4', title: 'A & B');
      final Map<String, dynamic> current =
          jsonDecode(await get('/current')) as Map<String, dynamic>;
      expect(current['title'], 'A & B');
      expect(current['url'], contains('/relay/'));
      server.stopBrowser();
      expect((jsonDecode(await get('/current')) as Map)['url'], isNull);
    } finally {
      client.close(force: true);
      await server.stop();
    }
  });
}
