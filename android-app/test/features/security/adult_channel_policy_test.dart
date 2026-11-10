import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/adult_channel_policy.dart';
import 'package:tv_king/features/channels/domain/channel.dart';

void main() {
  test('prédicat rapide identique au classificateur existant, bornes comprises',
      () {
    const words = <String>[
      'xxx',
      'adult',
      'adulte',
      'adultes',
      'porn',
      'porno',
      '18+',
      '+18',
      'x-rated',
      'xrated',
      'erotic',
      'erotik',
      'erotica',
      'érotique',
      'sex',
      'sexe',
      'sexy',
      'sexo',
      'playboy',
      'penthouse',
      'hustler',
      'brazzers',
      'dorcel',
      'vixen',
      'vivid',
      'redlight',
      'colmax',
      'pinko',
      'naughty',
      'nubile',
      'sports',
      'BBC News',
      'Essex',
      'Sussex',
      'transport',
      'children',
      'Film familial',
      '18 heures',
      'Sextant',
    ];
    const borders = <String>['', ' ', '|', '-', 'FR ', '1', 'x', '+', '.'];
    for (final word in words) {
      for (final before in borders) {
        for (final after in borders) {
          final name = '$before${word.toUpperCase()}$after';
          final expected = ChannelClassifier.classifyGenre(name, 'Fixture') ==
              ChannelGenre.adult;
          expect(ChannelClassifier.isAdult(name, 'Fixture'), expected,
              reason: name);
          expect(ChannelClassifier.isAdult('Fixture', name), expected,
              reason: name);
        }
      }
    }
  });

  test('cache objet distingue deux listes utilisant le même identifiant froid',
      () {
    const adult = Channel(
        id: 'same-cold-id',
        name: 'XXX',
        category: 'Fixture',
        streamUrl: 'https://fixture.invalid/adult',
        isLive: true);
    const ordinary = Channel(
        id: 'same-cold-id',
        name: 'Journal',
        category: 'Actualités',
        streamUrl: 'https://fixture.invalid/news',
        isLive: true);
    expect(isAdultChannel(adult), isTrue);
    expect(isAdultChannel(ordinary), isFalse);
    expect(isAdultChannel(adult), isTrue);
  });

  test('résultat après pré-calcul conserve la même classification', () async {
    const item = Channel(
        id: 'adult-precomputed-fixture',
        name: 'Canal',
        category: 'FR | ADULTES',
        streamUrl: 'https://fixture.invalid/item',
        isLive: true);
    expect(isAdultChannel(item), isTrue);
    expect(item.genre, ChannelGenre.adult);
    expect(isAdultChannel(item), isTrue);
  });
}
