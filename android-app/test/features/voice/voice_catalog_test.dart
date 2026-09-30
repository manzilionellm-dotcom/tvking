// =========================================================
//  voice_catalog_test.dart — recherche dans la playlist
// =========================================================
//  Adresses factices (example.invalid) : aucune URL de flux réelle.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/voice/domain/voice_catalog.dart';

Channel _ch(String id, String name, {String category = 'Test', bool live = true}) {
  return Channel(
    id: id,
    name: name,
    category: category,
    streamUrl: 'http://example.invalid/$id',
    isLive: live,
  );
}

CinemaTitle _movie(String name) => CinemaTitle(
      id: 'm:$name',
      kind: CinemaKind.movie,
      sourceKey: 'p1',
      remoteId: '1',
      name: name,
      categoryKey: 'cinema',
      searchKey: name.toLowerCase(),
    );

CinemaTitle _series(String name) => CinemaTitle(
      id: 's:$name',
      kind: CinemaKind.series,
      sourceKey: 'p1',
      remoteId: '2',
      name: name,
      categoryKey: 'series',
      searchKey: name.toLowerCase(),
    );

void main() {
  final List<Channel> channels = <Channel>[
    _ch('tf1', 'TF1'),
    _ch('journal', 'Journal'),
    _ch('grand', 'Le Grand Journal'),
    _ch('cine', 'Ciné+ Premier'),
    _ch('xxx', 'XXX HD', category: 'ADULT'),
    _ch('matrix', 'Matrix 1999', category: 'VOD FILM', live: false),
  ];
  final List<CinemaTitle> movies = <CinemaTitle>[_movie('Amélie')];
  final List<CinemaTitle> series = <CinemaTitle>[_series('The Office')];

  List<VoiceHit> find(String q, {bool hideAdult = false}) => searchCatalog(
        query: q,
        channels: channels,
        movies: movies,
        series: series,
        hideAdult: hideAdult,
      );

  test('chaîne, film et série, accents compris', () {
    expect(find('tf1').single.kind, VoiceHitKind.channel);
    expect(find('tf1').single.channel?.id, 'tf1');

    // Ciné+ est une chaîne en direct, pas un film du catalogue.
    expect(find('premier').single.kind, VoiceHitKind.channel);
    expect(find('premier').single.channel?.id, 'cine');

    final VoiceHit amelie = find('amelie').single;
    expect(amelie.kind, VoiceHitKind.movie);
    expect(amelie.cinema?.name, 'Amélie');

    expect(find('office').single.kind, VoiceHitKind.series);

    // VOD de la playlist (pas le cinéma Xtream) : rangé en film.
    expect(find('matrix').single.kind, VoiceHitKind.movie);
    expect(find('matrix').single.channel?.id, 'matrix');
  });

  test('tous les mots doivent être présents', () {
    expect(find('grand journal').single.channel?.id, 'grand');
    expect(find('grand journal').map((VoiceHit h) => h.channel?.id),
        isNot(contains('journal')));
  });

  test('mode enfants : le contenu adulte disparaît', () {
    expect(find('xxx'), isNotEmpty);
    expect(find('xxx', hideAdult: true), isEmpty);
    expect(find('tf1', hideAdult: true).single.channel?.id, 'tf1');
  });

  test('aide distante vide : on garde la recherche locale', () {
    final List<VoiceHit> local = find('tf1');
    expect(mergeRemoteChannels(local: local, remoteChannels: null), local);
    expect(
      mergeRemoteChannels(local: local, remoteChannels: const <VoiceHit>[]),
      local,
    );
  });

  test('aide distante : ses chaînes passent devant, films locaux gardés', () {
    final List<VoiceHit> local = <VoiceHit>[
      VoiceHit.fromChannel(_ch('old', 'Ancienne')),
      VoiceHit.fromCinema(_movie('Amélie')),
    ];
    final List<VoiceHit> remote = <VoiceHit>[
      VoiceHit.fromChannel(_ch('new', 'Nouvelle')),
    ];
    final List<VoiceHit> merged =
        mergeRemoteChannels(local: local, remoteChannels: remote);
    expect(merged.first.channel?.id, 'new');
    expect(merged.map((VoiceHit h) => h.kind), <VoiceHitKind>[
      VoiceHitKind.channel,
      VoiceHitKind.movie,
    ]);
    expect(merged.any((VoiceHit h) => h.channel?.id == 'old'), isFalse);
  });
}
