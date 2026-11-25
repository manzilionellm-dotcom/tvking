import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/ads/data/startup_ad_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = StartupAdRepository.instance;
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repo.resetForTesting();
    repo.baseUrl = 'https://fixture.invalid';
    repo.clock = () => DateTime(2026, 11, 2);
  });
  tearDown(repo.resetForTesting);

  test('contrat panel actif, fréquence quotidienne et désactivation', () async {
    var payload = <String, Object>{
      'enabled': true,
      'url': 'https://fixture.invalid/ad.mp4',
      'freq': 'daily',
      'skip': 3,
    };
    repo.client = MockClient((request) async {
      expect(request.url.path, '/api/ad');
      return http.Response(jsonEncode(payload), 200);
    });
    await repo.fetch();
    expect(await repo.shouldShow(), isTrue);
    await repo.markShown();
    expect(await repo.shouldShow(), isFalse);
    repo.clock = () => DateTime(2026, 11, 3);
    expect(await repo.shouldShow(), isTrue);
    payload = <String, Object>{...payload, 'enabled': false};
    await repo.fetch();
    expect(await repo.shouldShow(), isFalse);
  });

  test('une autre pub le même jour n’est pas la quotidienne déjà vue', () async {
    var url = 'https://fixture.invalid/ad.mp4';
    repo.client = MockClient((_) async {
      return http.Response(
        jsonEncode(<String, Object>{
          'enabled': true,
          'url': url,
          'freq': 'daily',
          'skip': 1,
        }),
        200,
      );
    });
    await repo.fetch();
    await repo.markShown();
    expect(await repo.shouldShow(), isFalse);
    url = 'https://fixture.invalid/autre.mp4';
    await repo.fetch();
    expect(await repo.shouldShow(), isTrue);
  });

  test(
    'URL non HTTP rejetée, délai borné et erreur sans ancienne pub',
    () async {
      var response = http.Response(
        jsonEncode(<String, Object>{
          'enabled': true,
          'url': 'https://fixture.invalid/ad.mp4',
          'skip': 999,
        }),
        200,
      );
      repo.client = MockClient((_) async => response);
      expect((await repo.fetch()).skip, 60);
      expect(await repo.shouldShow(), isTrue);
      response = http.Response('erreur', 503);
      await expectLater(repo.fetch(strict: true), throwsStateError);
      expect(repo.config.enabled, isTrue);
      await repo.fetch();
      expect(await repo.shouldShow(), isFalse);
      response = http.Response(
        jsonEncode(<String, Object>{
          'enabled': true,
          'url': 'javascript:alert(1)',
        }),
        200,
      );
      expect((await repo.fetch()).enabled, isFalse);
    },
  );
}
