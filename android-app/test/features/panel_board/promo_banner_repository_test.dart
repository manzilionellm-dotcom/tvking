// =========================================================
//  promo_banner_repository_test.dart — /api/banners : 404, 200, panne
// =========================================================
//  Client http simulé (aucun réseau), préférences en mémoire.
//  Les adresses sont des exemples invalides, jamais de vrai flux.
// =========================================================
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/panel_board/data/promo_banner_repository.dart';
import 'package:tv_king/features/panel_board/domain/panel_board.dart';

const String _base = 'https://panel.example.invalid';

String _body(List<String> ids) => jsonEncode(<String, Object?>{
      'items': <Object?>[
        for (final String id in ids)
          <String, Object?>{
            'id': id,
            'image': 'https://img.example.invalid/$id.png',
            'title': 'Bannière $id',
          },
      ],
      'version': 1,
    });

void main() {
  late PromoBannerRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repo = PromoBannerRepository.instance;
    repo.resetForTesting();
    repo.baseUrl = _base;
  });

  tearDown(() => repo.resetForTesting());

  test('404 (route absente ou rien publié) : liste vide, rien ne casse', () async {
    repo.client = MockClient((http.Request r) async {
      expect(r.url.toString(), '$_base/api/banners');
      return http.Response('not found', 404);
    });
    await repo.refresh();
    expect(repo.banners, isEmpty);
  });

  test('200 : la liste arrive, prévient, et survit en cache', () async {
    int notified = 0;
    repo.addListener(() => notified++);
    repo.client = MockClient((_) async => http.Response(_body(<String>['a', 'b']), 200));
    await repo.refresh();
    expect(repo.banners.map((PromoBanner b) => b.id), <String>['a', 'b']);
    expect(notified, 1);

    // Même liste à nouveau : pas de redessin inutile.
    await repo.refresh();
    expect(notified, 1);

    // Nouveau démarrage : le cache local parle avant le réseau.
    repo.resetForTesting();
    repo.baseUrl = _base;
    repo.client = MockClient((_) async => http.Response('boom', 500));
    await repo.initialize();
    expect(repo.banners.map((PromoBanner b) => b.id), <String>['a', 'b']);
  });

  test('panne réseau ou 500 : on garde ce qu\'on a', () async {
    repo.client = MockClient((_) async => http.Response(_body(<String>['a']), 200));
    await repo.refresh();
    repo.client = MockClient((_) async => throw Exception('coupé'));
    await repo.refresh();
    expect(repo.banners.map((PromoBanner b) => b.id), <String>['a']);
    repo.client = MockClient((_) async => http.Response('erreur', 500));
    await repo.refresh();
    expect(repo.banners.map((PromoBanner b) => b.id), <String>['a']);
  });

  test('compteurs du jour et fermeture 7 jours, persistants', () async {
    final DateTime d1 = DateTime(2026, 10, 4, 20);
    await repo.noteShown('a', now: d1);
    await repo.noteShown('a', now: d1);
    expect(repo.shownToday(d1)['a'], 2);
    // Le lendemain, les compteurs repartent.
    expect(repo.shownToday(d1.add(const Duration(days: 1)))['a'], isNull);

    final DateTime d2 = DateTime(2026, 10, 5, 9);
    await repo.dismiss('b', now: d2);
    expect(repo.dismissedAt(d2.millisecondsSinceEpoch), <String>{'b'});
    expect(
      repo.dismissedAt(d2.add(const Duration(days: 6)).millisecondsSinceEpoch),
      <String>{'b'},
    );
    expect(
      repo.dismissedAt(d2.add(const Duration(days: 7, minutes: 1)).millisecondsSinceEpoch),
      isEmpty,
    );

    // Redémarrage : la fermeture est relue depuis le disque.
    repo.resetForTesting();
    repo.baseUrl = _base;
    repo.client = MockClient((_) async => http.Response('x', 404));
    await repo.initialize();
    expect(repo.dismissedAt(d2.millisecondsSinceEpoch), <String>{'b'});
  });
}
