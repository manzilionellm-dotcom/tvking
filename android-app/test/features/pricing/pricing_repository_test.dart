import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_king/features/pricing/data/pricing_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(PricingRepository.resetForTesting);
  tearDown(PricingRepository.resetForTesting);
  final Map<String, Object> payload = <String, Object>{
    'configured': true, 'currency': 'SEK', 'lifetime': '99', 'yearly': '45,50',
    'trialDays': 0, 'promoEnabled': true, 'promoMessage': 'Offre du panel',
    'blockTitleFr': 'Titre FR', 'blockBodyFr': 'Texte FR',
    'blockTitleEn': 'Title EN', 'blockBodyEn': 'Text EN',
    'payUrl': 'https://fixture.invalid/offers',
  };

  test('aucun prix avant une configuration serveur confirmée', () {
    expect(PricingRepository.current.hasOffers, isFalse);
    expect(PricingRepository.current.lifetime, isEmpty);
    expect(PricingConfig.fromJson(<String, Object>{'lifetime': '9,9', 'yearly': '4,9'}).hasOffers, isFalse);
    expect(PricingConfig.fromJson(<String, Object>{...payload, 'configured': false}).hasOffers, isFalse);
  });

  test('contrat prix et textes FR/EN, lien HTTPS sans décision de licence', () async {
    PricingRepository.client = MockClient((request) async {
      expect(request.url.path, '/api/pricing');
      return http.Response(jsonEncode(payload), 200);
    });
    await PricingRepository.fetch(strict: true);
    final PricingConfig config = PricingRepository.current;
    expect(config.hasOffers, isTrue);
    expect(config.lifetimeLabel, '99 SEK');
    expect(config.yearlyLabel, '45,50 SEK');
    expect(config.blockTitle('fr'), 'Titre FR');
    expect(config.blockTitle('sv'), 'Title EN');
    expect(config.blockBody('en'), 'Text EN');
    expect(config.payUrl, 'https://fixture.invalid/offers');
  });

  test('champs malformés et URL non HTTPS ne deviennent pas des offres', () {
    final PricingConfig config = PricingConfig.fromJson(<String, Object>{
      ...payload, 'lifetime': <String>['99'], 'yearly': '-30', 'currency': '<bad>',
      'payUrl': 'https://private:secret@fixture.invalid/', 'blockTitleFr': 77,
    });
    expect(config.hasOffers, isFalse);
    expect(config.lifetime, isEmpty); expect(config.yearly, isEmpty);
    expect(config.payUrl, isEmpty); expect(config.blockTitleFr, isEmpty);
    expect(PricingConfig.fromJson(<String, Object>{...payload, 'payUrl': 'http://fixture.invalid/'}).payUrl, isEmpty);
    expect(PricingConfig.fromJson(<String, Object>{...payload, 'payUrl': 'javascript:alert(1)'}).payUrl, isEmpty);
  });

  test('erreurs strictes visibles, ancien cache réel conservé, configuration retirée masquée', () async {
    var response = http.Response(jsonEncode(payload), 200);
    PricingRepository.client = MockClient((_) async => response);
    await PricingRepository.fetch(strict: true);
    for (final http.Response failure in <http.Response>[
      http.Response('unavailable', 503), http.Response('not-json', 200),
      http.Response('{}', 200), http.Response('[]', 200),
    ]) {
      response = failure;
      await expectLater(PricingRepository.fetch(strict: true), throwsA(anything));
      expect(PricingRepository.current.lifetime, '99');
      await PricingRepository.fetch();
    }
    response = http.Response('{"configured":false}', 200);
    await PricingRepository.fetch(strict: true);
    expect(PricingRepository.current.hasOffers, isFalse);
  });

  test('lecture coalescée, remise à zéro ignore une réponse tardive', () async {
    final Completer<http.Response> response = Completer<http.Response>();
    int calls = 0;
    PricingRepository.client = MockClient((_) { calls++; return response.future; });
    final Future<void> first = PricingRepository.fetch(strict: true);
    final Future<void> second = PricingRepository.fetch(strict: true);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    PricingRepository.resetForTesting();
    response.complete(http.Response(jsonEncode(payload), 200));
    await Future.wait(<Future<void>>[first, second]);
    expect(PricingRepository.current.hasOffers, isFalse);
  });
}
