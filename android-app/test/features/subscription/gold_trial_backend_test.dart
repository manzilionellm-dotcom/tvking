import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_king/features/subscription/data/gold_trial_backend.dart';

const GoldTrialIdentity device = GoldTrialIdentity(
  mac: 'MK:11:22:33:44:55', androidId: 'android-test', appVersion: '0.3.7-test.216',
);

void main() {
  test('message public conservé et preuve envoyée sans changer le corps', () async {
    final GoldTrialBackend api = GoldTrialBackend(clientFactory: () => MockClient((request) async {
      expect(request.headers['x-device-secret'], 'device-proof-fixture');
      return http.Response(jsonEncode(<String, Object>{
        'ok': true, 'expire': 1793102400, 'message': 'Votre essai gratuit est prêt.',
      }), 201);
    }));
    final GoldTrialResult result = await api.activate(device,
      headers: <String, String>{'X-Device-Secret': 'device-proof-fixture'});
    expect(result.message, 'Votre essai gratuit est prêt.');
    for (final String value in <String>['https://private.example', 'Strong',
      'cms-8k.net', 'Manzi', 'password=secret', '<html>Erreur</html>']) {
      expect(GoldTrialBackend.publicMessage(value), isNull);
    }
    expect(isGoldTrialPlaylist('Zuno TV Essai'), isTrue);
  });

  test('POST exact : identité stable, versionName et seulement les 3 champs', () async {
    final GoldTrialBackend api = GoldTrialBackend(clientFactory: () => MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), '$kGoldTrialBaseUrl/api/gold-trial');
      expect(request.headers['content-type'], 'application/json');
      expect(request.headers['x-app-brand'], '7motion');
      expect(jsonDecode(request.body), <String, String>{
        'mac': device.mac, 'android_id': device.androidId, 'app_version': device.appVersion,
      });
      return http.Response('{"ok":true,"expire":1793102400,"message":"private provider URL"}', 201);
    }));
    final GoldTrialResult result = await api.activate(device);
    expect(result.outcome, GoldTrialOutcome.activated);
    expect(result.expire, DateTime.fromMillisecondsSinceEpoch(1793102400000, isUtc: true));
  });

  test('Zuno identifie sa marque sans ajouter de champs au contrat POST', () async {
    final GoldTrialBackend api = GoldTrialBackend(clientFactory: () => MockClient((request) async {
      expect(request.headers['x-app-brand'], 'zuno');
      expect((jsonDecode(request.body) as Map<String, dynamic>).length, 3);
      return http.Response('{"error":"trial_disabled"}', 403);
    }));
    await api.activate(GoldTrialIdentity(mac: device.mac, androidId: device.androidId,
      appVersion: device.appVersion, brand: 'zuno'));
  });

  for (final (int status, String code, GoldTrialOutcome outcome) in <(int, String, GoldTrialOutcome)>[
    (409, 'trial_already_used', GoldTrialOutcome.alreadyUsed),
    (409, 'already_customer', GoldTrialOutcome.alreadyCustomer),
    (409, 'in_progress', GoldTrialOutcome.inProgress),
    (403, 'trial_disabled', GoldTrialOutcome.disabled),
    (429, 'daily_cap_reached', GoldTrialOutcome.dailyCap),
    (429, 'rate_limited', GoldTrialOutcome.rateLimited),
    (500, 'private-provider-secret', GoldTrialOutcome.error),
    (200, 'already_customer', GoldTrialOutcome.error),
  ]) {
    test('$status $code est traduit sans exposer le message serveur', () async {
      final GoldTrialBackend api = GoldTrialBackend(clientFactory: () => MockClient((_) async =>
          http.Response(jsonEncode(<String, Object>{'error': code, 'message': 'private-provider-secret'}), status)));
      expect((await api.activate(device)).outcome, outcome);
    });
  }

  test('JSON invalide, timeout et réseau retombent sur une erreur fermée', () async {
    for (final Future<http.Response> Function(http.Request) reply in <Future<http.Response> Function(http.Request)>[
      (_) async => http.Response('<html>private-provider</html>', 500),
      (_) async => throw TimeoutException('private URL'),
      (_) async => throw http.ClientException('private secret'),
      (_) async => http.Response('{"ok":true,"expire":"invalid"}', 201),
      (_) async => http.Response('{"ok":false,"expire":1793102400}', 201),
    ]) {
      final GoldTrialBackend api = GoldTrialBackend(clientFactory: () => MockClient(reply));
      expect((await api.activate(device)).outcome, GoldTrialOutcome.error);
    }
  });

  test('aucun POST avec une identité Android incomplète', () async {
    int calls = 0;
    final GoldTrialBackend api = GoldTrialBackend(clientFactory: () => MockClient((_) async {
      calls++;
      return http.Response('{}', 500);
    }));
    for (final GoldTrialIdentity identity in <GoldTrialIdentity>[
      const GoldTrialIdentity(mac:'bad', androidId:'id', appVersion:'1'),
      const GoldTrialIdentity(mac:'MK:11:22:33:44:55', androidId:'', appVersion:'1'),
      const GoldTrialIdentity(mac:'MK:11:22:33:44:55', androidId:'id', appVersion:''),
    ]) {
      expect((await api.activate(identity)).outcome, GoldTrialOutcome.error);
    }
    expect(calls, 0);
  });

  test('dates ISO, secondes et millisecondes sont conservées', () {
    final DateTime expected = DateTime.utc(2026, 10, 27, 12);
    for (final Object value in <Object>[expected.toIso8601String(), expected.millisecondsSinceEpoch,
      expected.millisecondsSinceEpoch ~/ 1000, '${expected.millisecondsSinceEpoch ~/ 1000}']) {
      expect(GoldTrialBackend.parseExpiration(value), expected);
    }
    expect(GoldTrialBackend.parseExpiration(-1), isNull);
    expect(GoldTrialBackend.parseExpiration('bad'), isNull);
  });

  test('le GET filtre la bonne liste et conserve la preuve appareil', () async {
    Object? responseSource;
    final GoldTrialBackend api = GoldTrialBackend(clientFactory: () => MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.pathSegments.last, device.mac);
      expect(request.url.toString(), '$kGoldTrialBaseUrl/api/device-source/${device.mac}');
      expect(request.headers['x-device-secret'], 'test-proof');
      return http.Response(jsonEncode(responseSource), 200);
    }));
    Future<bool> read() => api.hasAssignedTrial(device.mac,
      headers: <String, String>{'X-Device-Secret': 'test-proof'}, timeout: const Duration(seconds: 2));
    responseSource = <String, Object?>{'source': null};
    expect(await read(), isFalse);
    responseSource = <String, Object?>{'source': <String, Object>{'label': 'Abonnement existant'}};
    expect(await read(), isFalse);
    responseSource = <String, Object?>{'sources': <Object>[
      <String, Object>{'label': 'Abonnement existant'},
      <String, Object>{'label': kGoldTrialPlaylistName, 'enabled': false},
    ]};
    expect(await read(), isFalse);
    responseSource = <String, Object?>{'source': <String, Object>{'label': kGoldTrialPlaylistName}};
    expect(await read(), isTrue);
    responseSource = <String, Object?>{'blocked': 'expired', 'source': <String, Object>{'label': kGoldTrialPlaylistName}};
    expect(await read(), isFalse);
  });
}
