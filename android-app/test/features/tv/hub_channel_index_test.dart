import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/data/home_shelves.dart';
import 'package:tv_king/features/tv/data/hub_channel_index.dart';

Channel channel(String id, {String? name}) => Channel(
      id: id,
      name: name ?? id,
      category: 'Info',
      streamUrl: '',
      isLive: true,
      playlistId: 1,
    );

// Compte les accès réels au catalogue, sans regarder l'implémentation du cache.
class CountedCatalog extends ListBase<Channel> {
  CountedCatalog(this.items);
  final List<Channel> items;
  int reads = 0;

  @override
  int get length => items.length;
  @override
  set length(int value) => throw UnsupportedError('Catalogue fixe');
  @override
  Channel operator [](int index) {
    reads++;
    return items[index];
  }

  @override
  void operator []=(int index, Channel value) => items[index] = value;
}

void main() {
  late HubChannelIndex cache;
  late CountedCatalog catalog;

  Map<String, Channel> read({
    List<Channel>? source,
    int generation = 1,
    int catalogScope = 1,
    int scope = 1,
    String profile = 'p1',
    bool kids = false,
    bool kidsProfile = false,
    bool memoize = true,
  }) =>
      cache.read(
        catalog: source ?? catalog,
        catalogGeneration: generation,
        catalogScope: catalogScope,
        currentScope: scope,
        profileId: profile,
        kidsMode: kids,
        kidsProfile: kidsProfile,
        memoize: memoize,
      );

  setUp(() {
    cache = HubChannelIndex();
    catalog = CountedCatalog([channel('a'), channel('b'), channel('c')]);
  });

  test('L1-02 : cent assemblages ne relisent qu’une fois le catalogue', () {
    final first = read();
    expect(catalog.reads, 3);
    for (int i = 0; i < 100; i++) {
      expect(read(), same(first));
      expect(read()['b'], same(catalog.items[1]));
    }
    expect(catalog.reads, 3);
  });

  test('L1-02 : remplacer le catalogue remplace les objets du même id', () {
    final first = read();
    final next = channel('b', name: 'Nouvelle chaîne');
    final replacement = read(source: [next]);
    expect(replacement, isNot(same(first)));
    expect(replacement.keys, ['b']);
    expect(replacement['b'], same(next));
    expect(replacement.containsKey('a'), isFalse);
  });

  test('L1-02 : une nouvelle génération invalide une liste réemployée', () {
    final first = read();
    final replacement = channel('b', name: 'Version remplacée');
    catalog[1] = replacement;
    final second = read(generation: 2);
    expect(second, isNot(same(first)));
    expect(second['b'], same(replacement));
    expect(catalog.reads, 6);
  });

  test('L1-02 : identité et portée du profil invalident séparément', () {
    final first = read();
    final profile = read(profile: 'p2');
    expect(profile, isNot(same(first)));
    final scoped = read(profile: 'p2', scope: 2, catalogScope: 2);
    expect(scoped, isNot(same(profile)));
    expect(catalog.reads, 9);
  });

  test('L1-02 : mode Enfants et nature du profil invalident séparément', () {
    final first = read();
    final restricted = read(kids: true);
    expect(restricted, isNot(same(first)));
    final kidsProfile = read(kids: true, kidsProfile: true);
    expect(kidsProfile, isNot(same(restricted)));
    expect(catalog.reads, 9);
  });

  for (final memoize in [true, false]) {
    test('L1-02 : un catalogue d’ancienne portée est refusé (cache=$memoize)',
        () {
      read();
      expect(read(scope: 2, memoize: memoize), isEmpty);
      expect(catalog.reads, 3);
      final current = channel('d');
      expect(
        read(source: [current], scope: 2, catalogScope: 2, memoize: memoize),
        {'d': current},
      );
    });
  }

  test('L1-02 : une invalidation explicite oblige une nouvelle lecture', () {
    final first = read();
    cache.invalidate();
    expect(read(), isNot(same(first)));
    expect(catalog.reads, 6);
  });

  test('L1-02 : le repli relit le catalogue et garde le même contenu', () {
    final first = read(memoize: false);
    final second = read(memoize: false);
    expect(second, equals(first));
    expect(second, isNot(same(first)));
    expect(catalog.reads, 6);
  });

  test('L1-02 : ordres historique/favoris, doublons et filtres sont conservés',
      () {
    final a = channel('a');
    final b = channel('b');
    final replacement = channel('a', name: 'Dernière occurrence');
    final c = channel('c');
    final source = [a, b, replacement, c];
    final index = read(source: source);
    expect(index.keys, ['a', 'b', 'c']);
    expect(index['a'], same(replacement));
    final ordered = channelsInIdOrder(
      ['c', 'absent', 'a', 'b'],
      index,
      hide: (item) => item.id == 'b',
    );
    expect(ordered, [c, replacement]);
    expect(favoriteChannels(source, {'b', 'a'}), [a, b, replacement]);
    expect(() => index.clear(), throwsUnsupportedError);
  });
}
