// =========================================================
//  quality_ladder_test.dart — Déclinaisons de qualité d'une même chaîne
// =========================================================
//  Noms RÉALISTES de panels IPTV : préfixes pays, séparateurs variés,
//  jetons codec. La barre : retrouver « la même chaîne en moins lourd »
//  sans JAMAIS confondre deux chaînes différentes.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/data/quality_ladder.dart';

Channel ch(String id, String name, {int? playlistId = 1, String? url}) =>
    Channel(
      id: id,
      name: name,
      category: 'FR | GÉNÉRALISTES',
      streamUrl: url ?? 'http://p.tv/live/u/p/$id.ts',
      isLive: true,
      playlistId: playlistId,
    );

void main() {
  group('baseNameOf', () {
    test('retire les jetons de qualité et normalise les séparateurs', () {
      expect(QualityLadder.baseNameOf('FR| TF1 UHD'), 'fr tf1');
      expect(QualityLadder.baseNameOf('FR - TF1 FHD (HEVC)'), 'fr tf1');
      expect(QualityLadder.baseNameOf('fr : tf1 sd'), 'fr tf1');
      expect(QualityLadder.baseNameOf('TF1 ᴴᴰ'), 'tf1');
    });

    test('ne mange pas un jeton de qualité DANS un mot', () {
      // « HDTV Golf » : « hdtv » n'est pas le jeton « hd ».
      expect(QualityLadder.baseNameOf('HDTV Golf'), 'hdtv golf');
    });

    test('deux chaînes différentes ne partagent pas de nom de base', () {
      expect(QualityLadder.baseNameOf('FR| TF1 HD'),
          isNot(QualityLadder.baseNameOf('FR| TF1 Séries Films HD')));
    });
  });

  group('lowerQualitySibling', () {
    final List<Channel> list = <Channel>[
      ch('1', 'FR| TF1 UHD'),
      ch('2', 'FR| TF1 FHD'),
      ch('3', 'FR| TF1 HD'),
      ch('4', 'FR| TF1 SD'),
      ch('5', 'FR| FRANCE 2 FHD'),
      ch('6', 'FR| FRANCE 2 SD'),
      ch('7', 'FR| TF1 Séries Films HD'),
    ];

    test('descend d\'UNE marche (UHD → FHD, pas UHD → SD)', () {
      final Channel? down =
          QualityLadder.lowerQualitySibling(list[0], list);
      expect(down?.id, '2');
    });

    test('FHD → HD, HD → SD, SD → rien', () {
      expect(QualityLadder.lowerQualitySibling(list[1], list)?.id, '3');
      expect(QualityLadder.lowerQualitySibling(list[2], list)?.id, '4');
      expect(QualityLadder.lowerQualitySibling(list[3], list), isNull);
    });

    test('saute les rangs absents (FRANCE 2 FHD → SD direct)', () {
      expect(QualityLadder.lowerQualitySibling(list[4], list)?.id, '6');
    });

    test('ne confond jamais deux chaînes au nom proche', () {
      // « TF1 Séries Films HD » ne doit JAMAIS matcher « TF1 SD ».
      expect(QualityLadder.lowerQualitySibling(list[6], list), isNull);
    });

    test('refuse une déclinaison d\'une AUTRE source (playlistId)', () {
      final Channel current = ch('a', 'FR| TF1 FHD', playlistId: 1);
      final Channel other = ch('b', 'FR| TF1 HD', playlistId: 2);
      expect(
        QualityLadder.lowerQualitySibling(
            current, <Channel>[current, other]),
        isNull,
      );
    });

    test('refuse une « déclinaison » qui pointe sur le même flux', () {
      final Channel current =
          ch('a', 'FR| TF1 FHD', url: 'http://p.tv/1.ts');
      final Channel same = ch('b', 'FR| TF1 HD', url: 'http://p.tv/1.ts');
      expect(
        QualityLadder.lowerQualitySibling(current, <Channel>[current, same]),
        isNull,
      );
    });
  });
}
