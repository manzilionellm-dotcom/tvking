import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_king/core/app/novatube_content_policy.dart';
import 'package:tv_king/core/app/novatube_private_features.dart';
import 'package:tv_king/core/app/provider_adult_signal.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/cinema/data/catalog_disk.dart';
import 'package:tv_king/features/cinema/data/cinema_parsers.dart';
import 'package:tv_king/features/cinema/data/cinema_repository.dart';
import 'package:tv_king/features/cinema/data/watch_progress.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/playlists/data/m3u_parser.dart';
import 'package:tv_king/features/playlists/data/xtream_client.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_common.dart';
import 'package:tv_king/features/vod/data/download_repository.dart';
import 'package:tv_king/features/vod/domain/vod_movie.dart';

const CinemaSource _source = CinemaSource(
  key: 'p7',
  playlistId: 7,
  server: 'https://example.invalid',
  username: 'fixture',
  password: 'fixture',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final Object value in <Object>[true, 1, '1', 'true', ' TRUE ', 'yes']) {
    test('is_adult positif $value ne dépend pas du nom ni de la catégorie', () {
      expect(
          ProviderAdultSignal.read(<String, Object>{
            'name': 'Titre neutre',
            'category_name': 'Divers',
            'is_adult': value,
          }),
          isTrue);
    });
  }
  for (final Object? value in <Object?>[
    false,
    0,
    '0',
    'false',
    'no',
    '',
    null,
    18
  ]) {
    test('is_adult non positif $value ne classe pas une entrée neutre', () {
      expect(
          ProviderAdultSignal.read(<String, Object?>{
            'name': 'Titre neutre',
            'category_name': 'Divers',
            'is_adult': value,
          }),
          isFalse);
    });
  }

  test('les notes numériques de films ne sont jamais une classification d’âge',
      () {
    for (int rating = 1; rating <= 10; rating++) {
      expect(
          ProviderAdultSignal.fromMetadata(<String, Object>{
            'name': 'Titre neutre',
            'rating': rating,
            'rating_5based': rating / 2,
          }),
          isFalse);
      expect(
          parseVodInfo(<String, Object>{
            'info': <String, Object>{
              'rating': rating,
            }
          }).declaredAdult,
          isFalse);
    }
  });

  test('M3U conserve les libellés, les attributs adultes et le nom alternatif',
      () {
    final List<Channel> channels = M3uParser.parse('''#EXTM3U
#EXTINF:-1 tvg-id="a" group-title="Divers" is_adult="1",Canal Soleil
https://example.invalid/a.ts
#EXTINF:-1 tvg-id="b" group-title="Divers" tvg-adult="true",Canal Horizon
https://example.invalid/b.ts
#EXTINF:-1 tvg-id="c" group-title="Divers" adult="0",Canal Jardin
https://example.invalid/c.ts
#EXTINF:-1 tvg-id="d" group-title="Divers" is-adult="false" tvg-name="XXX Alternatif",Canal Mer
https://example.invalid/d.ts
#EXTINF:-1 tvg-id="e" group-title="+18" is_adult="0",Canal Nuit
https://example.invalid/e.ts
''', playlistId: 7).channels;
    expect(
        channels.map((Channel c) => c.id), <String>['a', 'b', 'c', 'd', 'e']);
    expect(channels.map((Channel c) => c.name), <String>[
      'Canal Soleil',
      'Canal Horizon',
      'Canal Jardin',
      'Canal Mer',
      'Canal Nuit',
    ]);
    expect(channels.map((Channel c) => c.category),
        <String>['Divers', 'Divers', 'Divers', 'Divers', '+18']);
    expect(channels.map((Channel c) => c.isAdult),
        <bool>[true, true, false, true, true]);
    expect(channels[3].declaredAdult, isTrue);
  });

  test('un flag fournisseur est prioritaire sur le genre déjà en cache', () {
    const Channel before = Channel(
        id: 'declared-fixture-cache',
        name: 'Canal',
        category: 'Sports',
        streamUrl: 'https://example.invalid/live.ts',
        isLive: true);
    expect(before.genre, ChannelGenre.sports);
    const Channel after = Channel(
        id: 'declared-fixture-cache',
        name: 'Canal',
        category: 'Sports',
        streamUrl: 'https://example.invalid/live.ts',
        isLive: true,
        declaredAdult: true);
    expect(after.isAdult, isTrue);
    expect(after.genre, ChannelGenre.adult);
    expect(ChannelPrecompute.cachedGenre(after), ChannelGenre.adult);
  });

  test('Xtream Direct et VOD héritent seulement de leur catégorie serveur',
      () async {
    final http.Client httpClient = MockClient((http.Request request) async {
      final String action = request.url.queryParameters['action'] ?? '';
      final Object body = action.endsWith('_categories')
          ? <Object>[
              <String, Object>{
                'category_id': '7',
                'category_name': 'Divers',
                'is_adult': '1'
              },
              <String, Object>{
                'category_id': '8',
                'category_name': 'Divers',
                'is_adult': 0
              },
            ]
          : <Object>[
              <String, Object>{
                'stream_id': 1,
                'name': 'Canal A',
                'category_id': '7',
                'is_adult': 0
              },
              <String, Object>{
                'stream_id': 2,
                'name': 'Canal B',
                'category_id': '8',
                'is_adult': true
              },
              <String, Object>{
                'stream_id': 3,
                'name': 'Canal C',
                'category_id': '8',
                'is_adult': false,
                'rating': 10
              },
            ];
      return http.Response(jsonEncode(body), 200);
    });
    addTearDown(httpClient.close);
    final XtreamClient client = XtreamClient(
        serverUrl: 'https://example.invalid',
        username: 'fixture',
        password: 'fixture',
        httpClient: httpClient);
    final List<Channel> live = await client.fetchLiveChannels(playlistId: 7);
    expect(live.map((Channel c) => c.declaredAdult), <bool>[true, true, false]);
    expect(live.map((Channel c) => c.category),
        <String>['Divers', 'Divers', 'Divers']);
    final List<VodMovie> movies = await client.fetchVodMovies();
    expect(
        movies.map((VodMovie m) => m.declaredAdult), <bool>[true, true, false]);
    expect(movies.last.rating, '10');
    expect(movies.last.isAdult, isFalse);
  });

  for (final CinemaKind kind in CinemaKind.values) {
    test(
        'Cinéma ${kind.name} : flag du titre, catégorie héritée et faux explicite',
        () {
      final List<CinemaTitle> titles = mapTitles(
          <Object>[
            <String, Object>{
              'stream_id': 1,
              'series_id': 1,
              'name': 'Titre A',
              'category_id': '7',
              'is_adult': 0
            },
            <String, Object>{
              'stream_id': 2,
              'series_id': 2,
              'name': 'Titre B',
              'category_id': '8',
              'is_adult': 'true'
            },
            <String, Object>{
              'stream_id': 3,
              'series_id': 3,
              'name': 'Titre C',
              'category_id': '8',
              'is_adult': false,
              'rating': 10
            },
          ],
          kind: kind,
          source: _source,
          categoryKeyById: const <String, String>{'7': 'divers', '8': 'divers'},
          declaredAdultCategoryIds: const <String>{'7'});
      expect(titles.map((CinemaTitle t) => t.declaredAdult),
          <bool>[true, true, false]);
      expect(titles.map((CinemaTitle t) => t.categoryKey),
          <String>['divers', 'divers', 'divers']);
      expect(titles.last.rating, 10);
      expect(titles.last.isAdult, isFalse);
    });
  }

  test(
      'cache de catégories : même libellé sur deux sources, un seul héritage adulte',
      () {
    final a = parseCategoriesWithSignals(<Object>[
      <String, Object>{
        'category_id': '7',
        'category_name': 'Divers',
        'is_adult': true
      },
    ]).single;
    final b = parseCategoriesWithSignals(<Object>[
      <String, Object>{
        'category_id': '7',
        'category_name': 'Divers',
        'is_adult': false
      },
    ]).single;
    final CatalogCategoryRecord record = CatalogCategoryRecord(
      key: 'divers',
      name: 'Divers',
      fileId: 'fixture',
      parts: <CatalogPartRecord>[
        CatalogPartRecord('p7', a.id, declaredAdult: a.declaredAdult),
        CatalogPartRecord('p8', b.id, declaredAdult: b.declaredAdult),
      ],
    );
    final CinemaCategory restored =
        CatalogCategoryRecord.fromJson(jsonDecode(jsonEncode(record.toJson())))!
            .toCinemaCategory();
    expect(restored.name, 'Divers');
    expect(restored.key, 'divers');
    expect(restored.isAdult, isFalse,
        reason: 'Le dossier fusionné n’est pas tout adulte.');
    expect(restored.parts.map((CategoryRef p) => p.declaredAdult),
        <bool>[true, false]);
    for (final CategoryRef part in restored.parts) {
      final CinemaSource source = CinemaSource(
          key: part.sourceKey,
          playlistId: part.sourceKey == 'p7' ? 7 : 8,
          server: 'https://example.invalid',
          username: 'fixture',
          password: 'fixture');
      final CinemaTitle title = mapTitles(
          <Object>[
            <String, Object>{
              'stream_id': 42,
              'name': 'Titre neutre',
              'category_id': '7'
            },
          ],
          kind: CinemaKind.movie,
          source: source,
          categoryKeyById: const <String, String>{'7': 'divers'},
          declaredAdultCategoryIds: <String>{
            if (part.declaredAdult) part.categoryId
          }).single;
      expect(title.declaredAdult, part.sourceKey == 'p7');
      expect(title.categoryKey, 'divers');
      expect(title.id, '${part.sourceKey}:m:42');
    }
  });

  test('fiche film : is_adult ou genre adulte, jamais rating', () {
    expect(
        parseVodInfo(<String, Object>{
          'movie_data': <String, Object>{
            'is_adult': 1,
          }
        }).declaredAdult,
        isTrue);
    expect(
        parseVodInfo(<String, Object>{
          'info': <String, Object>{
            'genre': 'Adult',
            'is_adult': false,
            'rating': 9,
          }
        }).declaredAdult,
        isTrue);
    expect(
        parseVodInfo(<String, Object>{
          'info': <String, Object>{
            'genre': 'Documentaire',
            'is_adult': 0,
            'rating': 10,
          }
        }).declaredAdult,
        isFalse);
  });

  test('fiche série : signal parent et signal propre à un épisode', () {
    SeriesDetails details(bool adultSeries) => parseSeriesInfo(<String, Object>{
          'info': <String, Object>{'is_adult': adultSeries, 'rating': 10},
          'episodes': <String, Object>{
            '1': <Object>[
              <String, Object>{
                'id': '1',
                'season': 1,
                'episode_num': 1,
                'title': 'Premier',
                'is_adult': 0
              },
              <String, Object>{
                'id': '2',
                'season': 1,
                'episode_num': 2,
                'title': 'Second',
                'info': <String, Object>{'is_adult': '1'}
              },
            ]
          },
        }, source: _source, seriesId: 'p7:s:9', seriesName: 'Série neutre');
    expect(details(false).allInOrder.map((CinemaEpisode e) => e.declaredAdult),
        <bool>[false, true]);
    final SeriesDetails inherited = details(true);
    expect(inherited.details.declaredAdult, isTrue);
    expect(inherited.allInOrder.every((CinemaEpisode e) => e.declaredAdult),
        isTrue);
  });

  test('cache titre, reprise, copie et téléchargement conservent le signal',
      () {
    final CinemaTitle title = mapTitles(
        <Object>[
          <String, Object>{
            'stream_id': 42,
            'name': 'Titre neutre',
            'category_id': '8',
            'is_adult': true
          },
        ],
        kind: CinemaKind.movie,
        source: _source,
        categoryKeyById: const <String, String>{'8': 'divers'}).single;
    final CatalogTitleRecord record = CatalogTitleRecord.fromCinemaTitle(title);
    final CinemaTitle restored =
        CatalogTitleRecord.fromJson(jsonDecode(jsonEncode(record.toJson())))!
            .toCinemaTitle(_source);
    expect(restored.isAdult, isTrue);
    expect((restored.id, restored.name, restored.categoryKey),
        (title.id, title.name, title.categoryKey));
    final WatchEntry entry =
        VodPlayItem.movie(restored).toEntry(posMs: 40000, durMs: 600000);
    final WatchEntry resumed =
        WatchEntry.fromJson(entry.copyWith(posMs: 45000).toJson())!;
    expect(resumed.declaredAdult, isTrue);
    expect(VodPlayItem.entry(resumed).declaredAdult, isTrue);
    expect(VodPlayItem.entry(resumed).toVodMovie().declaredAdult, isTrue);
    final Download stored = Download.fromMap(const Download(
      id: 'p7:m:42',
      name: 'Titre neutre',
      category: 'Divers',
      declaredAdult: true,
      sourceUrl: 'https://example.invalid/movie.mp4',
      filePath: '/fixture.mp4',
      status: DownloadStatus.paused,
      receivedBytes: 0,
      totalBytes: 0,
      createdAt: 1,
    ).copyWith().toMap());
    expect(stored.declaredAdult, isTrue);
    expect(stored.category, 'Divers');
    expect(
        NovatubeContentPolicy.canImport(
            name: restored.name,
            category: restored.categoryKey,
            declaredAdult: restored.declaredAdult),
        NovatubePrivateFeatures.adultCatalogs);
    expect(
        NovatubeContentPolicy.allows(
            name: restored.name,
            category: restored.categoryKey,
            declaredAdult: restored.declaredAdult),
        isFalse);
  });

  test('recherche et récents filtrent adulte avant leur limite de résultats',
      () {
    final List<CinemaTitle> titles = <CinemaTitle>[
      for (int i = 0; i < 100; i++)
        CinemaTitle(
            id: 'p7:m:$i',
            kind: CinemaKind.movie,
            sourceKey: 'p7',
            remoteId: '$i',
            name: 'Titre $i',
            categoryKey: 'divers',
            searchKey: 'titre $i',
            addedAt: i + 2),
      const CinemaTitle(
          id: 'p7:m:101',
          kind: CinemaKind.movie,
          sourceKey: 'p7',
          remoteId: '101',
          name: 'Titre discret',
          categoryKey: 'divers',
          searchKey: 'titre discret',
          addedAt: 1,
          declaredAdult: true),
    ];
    final CinemaRepository repo =
        CinemaRepository.forTesting(kind: CinemaKind.movie, titles: titles);
    final List<String> expected = <String>[
      if (NovatubePrivateFeatures.adultCatalogs) 'p7:m:101',
    ];
    expect(
        repo
            .search(CinemaKind.movie, 'titre', max: 1, adultOnly: true)
            .map((CinemaTitle t) => t.id),
        expected);
    expect(
        repo
            .recent(CinemaKind.movie, max: 1, adultOnly: true)
            .map((CinemaTitle t) => t.id),
        expected);
    expect(repo.countFor(CinemaKind.movie, 'divers', adultOnly: true),
        expected.length);
    expect(repo.countFor(CinemaKind.movie, 'divers', adultOnly: false), 100);
    expect(
        repo
            .search(CinemaKind.movie, 'titre', max: 1, adultOnly: false)
            .single
            .isAdult,
        isFalse);
  });

  test(
      'une découverte reclasse les anciennes reprises sans perdre leur position',
      () {
    WatchEntry entry(String id, {String? seriesId}) => WatchEntry(
          id: id,
          isEpisode: seriesId != null,
          title: 'Titre neutre',
          streamUrl: 'https://example.invalid/video.mp4',
          posMs: 45000,
          durMs: 600000,
          updatedAt: 1,
          seriesId: seriesId,
        );
    final WatchEntry movie = entry('p7:m:42');
    final WatchEntry episode = entry('p7:e:1', seriesId: 'p7:s:9');
    final WatchEntry otherSource = entry('p8:m:42');
    final WatchProgressStore store =
        WatchProgressStore(<WatchEntry>[movie, episode, otherSource]);
    expect(store.declareAdult(<String>{movie.id, 'p7:s:9'}), isTrue);
    // L'ancien objet du lecteur ne doit jamais réécraser la preuve par false.
    store.record(movie.copyWith(posMs: 50000));
    final List<WatchEntry> persisted = (jsonDecode(store.encode()) as List)
        .map(WatchEntry.fromJson)
        .whereType<WatchEntry>()
        .toList();
    expect(
        persisted
            .where((WatchEntry e) => e.declaredAdult)
            .map((WatchEntry e) => e.id),
        <String>[movie.id, episode.id]);
    expect(persisted.first.title, movie.title);
    expect(persisted.first.posMs,
        NovatubePrivateFeatures.adultCatalogs ? 50000 : 45000);
    expect(store.get(otherSource.id)?.isAdult, isFalse);
    expect(store.continueWatching().length,
        NovatubePrivateFeatures.adultCatalogs ? 3 : 1);
  });
}
