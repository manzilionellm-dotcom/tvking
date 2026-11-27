import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tv_king/features/playlists/data/m3u_fetcher.dart';

class _CatalogClient extends http.BaseClient {
  _CatalogClient(this.respond);

  final Future<http.StreamedResponse> Function(http.BaseRequest) respond;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      respond(request);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url = 'http://localhost/catalog';
  const limits = FetchTimeouts(
      headers: Duration(seconds: 1),
      idle: Duration(seconds: 3),
      total: Duration(milliseconds: 80));

  test('un corps refusé est libéré avant la prochaine tentative', () async {
    var attempts = 0;
    var cancelled = false;
    final client = _CatalogClient((_) async {
      if (++attempts == 1) {
        final body =
            StreamController<List<int>>(onCancel: () => cancelled = true);
        addTearDown(() {
          unawaited(body.close());
        });
        return http.StreamedResponse(body.stream, 884);
      }
      expect(cancelled, isTrue);
      return http.StreamedResponse(Stream.value(utf8.encode('#EXTM3U\n')), 200);
    });
    await M3uFetcher.fetchBytes(url, httpClient: client);
    expect(attempts, 2);
  });

  for (final toFile in [false, true]) {
    test('le délai total annule la lecture (fichier=$toFile)', () async {
      var cancelled = false;
      final body =
          StreamController<List<int>>(onCancel: () => cancelled = true);
      final client =
          _CatalogClient((_) async => http.StreamedResponse(body.stream, 200));
      body.add(utf8.encode('#EXTM3U\n'));
      final dir = await Directory.systemTemp.createTemp('catalog-test-');
      try {
        final result = toFile
            ? M3uFetcher.fetchToFile(url, File('${dir.path}/catalog'),
                httpClient: client, timeouts: limits)
            : M3uFetcher.fetchBytes(url, httpClient: client, timeouts: limits);
        await expectLater(result, throwsA(anything));
        expect(cancelled, isTrue);
      } finally {
        unawaited(body.close());
        await dir.delete(recursive: true);
      }
    });
  }
}
