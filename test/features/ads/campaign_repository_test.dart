// Tests du modèle Campaign + sélection pickForHome (pur, sans réseau) :
// parsing tolérant, fenêtre horaire (y compris enjambant minuit),
// rotation quotidienne et respect des fermetures utilisateur.

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/ads/data/campaign_repository.dart';

Campaign _c(int id, {int? from, int? to, String placement = 'home'}) {
  return Campaign(
    id: id,
    kind: 'banner',
    title: 'T$id',
    body: '',
    imageUrl: '',
    targetUrl: 'https://ex.com/$id',
    cta: '',
    placement: placement,
    startHour: from,
    endHour: to,
  );
}

void main() {
  group('Campaign.fromJson', () {
    test('parse complet', () {
      final Campaign? c = Campaign.fromJson(<String, dynamic>{
        'id': 3,
        'kind': 'product',
        'title': 'Maillot',
        'body': 'Officiel',
        'image_url': 'https://img',
        'target_url': 'https://aff',
        'cta': 'Acheter',
        'placement': 'home',
        'start_hour': 18,
        'end_hour': 23,
      });
      expect(c, isNotNull);
      expect(c!.kind, 'product');
      expect(c.startHour, 18);
      expect(c.endHour, 23);
    });

    test('rejette sans lien ou sans id', () {
      expect(Campaign.fromJson(<String, dynamic>{'id': 1}), isNull);
      expect(
        Campaign.fromJson(<String, dynamic>{'target_url': 'https://x'}),
        isNull,
      );
    });

    test('heures invalides → null (toujours visible)', () {
      final Campaign? c = Campaign.fromJson(<String, dynamic>{
        'id': 2,
        'target_url': 'https://x',
        'start_hour': 99,
        'end_hour': 'abc',
      });
      expect(c!.startHour, isNull);
      expect(c.endHour, isNull);
      expect(c.visibleAtHour(3), isTrue);
    });
  });

  group('visibleAtHour', () {
    test('fenêtre simple 18-23', () {
      final Campaign c = _c(1, from: 18, to: 23);
      expect(c.visibleAtHour(17), isFalse);
      expect(c.visibleAtHour(18), isTrue);
      expect(c.visibleAtHour(23), isTrue);
      expect(c.visibleAtHour(0), isFalse);
    });

    test('fenêtre qui enjambe minuit 22-2', () {
      final Campaign c = _c(1, from: 22, to: 2);
      expect(c.visibleAtHour(23), isTrue);
      expect(c.visibleAtHour(0), isTrue);
      expect(c.visibleAtHour(2), isTrue);
      expect(c.visibleAtHour(3), isFalse);
      expect(c.visibleAtHour(12), isFalse);
    });
  });

  group('pickForHome', () {
    test('filtre placement, heure et fermetures', () {
      final List<Campaign> all = <Campaign>[
        _c(1, placement: 'movies'), // mauvais placement
        _c(2, from: 0, to: 5), // hors fenêtre à 12 h
        _c(3), // fermée par l'utilisateur
        _c(4), // la bonne
      ];
      final Campaign? pick = CampaignRepository.pickForHome(
        all,
        dismissed: <int>{3},
        now: DateTime(2026, 7, 31, 12),
      );
      expect(pick?.id, 4);
    });

    test('rotation quotidienne entre plusieurs éligibles', () {
      final List<Campaign> all = <Campaign>[_c(1), _c(2)];
      final Campaign? day1 = CampaignRepository.pickForHome(
        all,
        dismissed: <int>{},
        now: DateTime(2026, 7, 30, 12),
      );
      final Campaign? day2 = CampaignRepository.pickForHome(
        all,
        dismissed: <int>{},
        now: DateTime(2026, 7, 31, 12),
      );
      expect(day1, isNotNull);
      expect(day2, isNotNull);
      expect(day1!.id == day2!.id, isFalse); // change d'un jour à l'autre
    });

    test('aucune éligible → null', () {
      expect(
        CampaignRepository.pickForHome(
          <Campaign>[],
          dismissed: <int>{},
          now: DateTime(2026, 7, 31, 12),
        ),
        isNull,
      );
    });
  });
}
