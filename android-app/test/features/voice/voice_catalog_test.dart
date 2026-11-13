// =========================================================
//  voice_catalog_test.dart — recherche dans la playlist
// =========================================================
//  Adresses factices (example.invalid) : aucune URL de flux réelle.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/voice/domain/voice_catalog.dart';

Channel _ch(String id, String name,
    {String category = 'Test', bool live = true}) {
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

  test('la préparation donne les mêmes chaînes, sans replier à chaque lettre',
      () {
    final Map<String, String> hay = <String, String>{};
    final Set<String> adult = <String>{};
    for (final Channel c in channels) {
      prepareChannelSearch(c, hay, adult);
    }
    final List<VoiceHit> direct = find('journal');
    final List<VoiceHit> prepared = searchCatalog(
      query: 'journal',
      channels: channels,
      movies: movies,
      series: series,
      channelHay: hay,
      adultIds: adult,
    );
    expect(
      prepared.map((VoiceHit h) => h.id),
      direct.map((VoiceHit h) => h.id),
    );
    expect(adult, contains('xxx'));
    expect(
      searchCatalog(
        query: 'xxx',
        channels: channels,
        movies: const <CinemaTitle>[],
        series: const <CinemaTitle>[],
        hideAdult: true,
        channelHay: hay,
        adultIds: adult,
      ),
      isEmpty,
    );
  });

  test('le meilleur nom passe devant, puis le plus court', () {
    final List<Channel> list = <Channel>[
      _ch('a', 'Info Sport Week-end'),
      _ch('b', 'beIN Sports 1'),
      _ch('c', 'Sport 24 Séries Films'),
      _ch('d', 'Sport 24'),
      _ch('e', 'Sportive'),
    ];
    final List<String?> ids = searchCatalog(
      query: 'sport',
      channels: list,
      movies: const <CinemaTitle>[],
      series: const <CinemaTitle>[],
    ).map((VoiceHit h) => h.channel?.id).toList();
    // Mot entier en tête (le plus court d'abord), puis début de nom,
    // puis un mot du nom (le plus court d'abord).
    expect(ids, <String?>['d', 'c', 'e', 'b', 'a']);
    expect(searchRank('sport 24 test', 'sport'), 0);
    expect(searchRank('sportive test', 'sport'), 1);
    expect(searchRank('bein sports 1 test', 'sport'), 2);
    expect(searchRank('test sport', 'spo'), 2);
    expect(searchRank('multisport', 'sport'), 3);
  });

  test('une faute de frappe trouve quand même la chaîne', () {
    final List<Channel> list = <Channel>[
      _ch('euro', 'Eurosport 2'),
      _ch('nf', 'Netflix Action'),
      _ch('tf1', 'TF1'),
    ];
    List<String?> ids(String q) => searchCatalog(
          query: q,
          channels: list,
          movies: const <CinemaTitle>[],
          series: const <CinemaTitle>[],
        ).map((VoiceHit h) => h.channel?.id).toList();
    expect(ids('eurosprt'), <String?>['euro']); // lettre oubliée
    expect(ids('eurospotr'), <String?>['euro']); // lettres inversées
    expect(ids('netflx'), <String?>['nf']);
    expect(ids('nteflix action'), <String?>['nf']);
    // Un mot court ne pardonne rien : « tf2 » n'est pas « TF1 ».
    expect(ids('tf2'), isEmpty);
    // Trop loin : rien.
    expect(ids('zzzzzz'), isEmpty);
    expect(typoBudget(3), 0);
    expect(typoBudget(5), 1);
    expect(typoBudget(9), 2);
    expect(typoDistance('netflx', 'netflix', 1), 1);
    expect(typoDistance('abcd', 'wxyz', 1), 2);
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
