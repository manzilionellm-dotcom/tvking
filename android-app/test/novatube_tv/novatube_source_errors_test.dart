import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_king/core/app/novatube_tv_edition.dart';
import 'package:tv_king/features/playlists/data/m3u_fetcher.dart';
import 'package:tv_king/features/playlists/data/xtream_client.dart';
import 'package:tv_king/features/playlists/domain/source_import_problem.dart';
import 'package:tv_king/features/tv/presentation/tv_source_error_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final Uri source = Uri.http('localhost', '/liste.m3u');

  for (final exemple in [
    (403, '', SourceImportProblem.denied),
    (401, '', SourceImportProblem.denied),
    (200, '<html><a href="http://localhost/">', SourceImportProblem.webPage),
    (200, '', SourceImportProblem.empty),
    (503, '', SourceImportProblem.network),
  ]) {
    test('M3U HTTP ${exemple.$1}, ${exemple.$3.name}', () async {
      final client = MockClient((_) async => http.Response(exemple.$2, exemple.$1));
      addTearDown(client.close);
      final chargement = M3uFetcher.fetchBytes(source.toString(), httpClient: client);
      if (kNovatubeTv) {
        await expectLater(chargement, throwsA(exemple.$3));
      } else if (exemple.$3 == SourceImportProblem.webPage) {
        expect(utf8.decode(await chargement), exemple.$2);
      } else {
        await expectLater(chargement, throwsException);
      }
    });
  }

  test('le délai et un compte expiré ont deux messages distincts', () async {
    expect(sourceFailureCode(TimeoutException('')), SourceImportProblem.timeout.name);
    final client = MockClient((_) async => http.Response(
      '{"user_info":{"auth":0,"status":"Expired"}}', 200));
    final api = XtreamClient(serverUrl: source.origin, username: 'fixture',
        password: 'fixture', httpClient: client);
    addTearDown(client.close);
    await expectLater(api.verifyCredentials(), throwsA(kNovatubeTv
        ? SourceImportProblem.expired : isA<XtreamAuthException>()));
  });
}
