// Isolation réelle : vrais repositories et SQLite, réseaux uniquement simulés.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/novatube_private_features.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/cinema/data/cinema_repository.dart';
import 'package:tv_king/features/epg/data/epg_repository.dart';
import 'package:tv_king/features/playlists/data/deleted_sources.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';

String _m3u(String name) => '#EXTM3U\n'
    '#EXTINF:-1 tvg-id="shared" group-title="Documentaires",$name\n'
    'https://example.invalid/fixture.ts\n';

String _stamp(DateTime date) {
  final DateTime t = date.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}${two(t.hour)}'
      '${two(t.minute)}${two(t.second)} +0000';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ProfileRepository profiles = ProfileRepository.instance;
  final PlaylistRepository sources = PlaylistRepository.instance;
  final FavoritesRepository favorites = FavoritesRepository.instance;
  final EpgRepository epg = EpgRepository.instance;
  late Directory directory;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    directory = await Directory.systemTemp.createTemp('novatube-profiles-');
    PlaylistDatabase.debugFilePath = '${directory.path}/profiles.db';
    PlaylistRepository.mergeAllPlaylists = true;
    FlavorConfig.setCurrent(FlavorConfig.novatube);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await profiles.resetForTesting();
    await epg.initialize();
    final Database db = await PlaylistDatabase.instance.database;
    for (final String table in <String>[
      'channels', 'playlists', 'deleted_sources', 'favorites',
      'favorites_by_profile', 'recently_watched', 'recently_watched_by_profile',
      'epg_programs',
    ]) {
      await db.delete(table);
    }
    await profiles.load();
  });

  tearDownAll(() async {
    await sources.reloadForActiveProfile();
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    await directory.delete(recursive: true);
  });

  Future<Playlist> addM3u(String name) async {
    final http.Client client = MockClient((_) async => http.Response(_m3u(name), 200));
    try {
      return await sources.addM3uPlaylist(name: name,
          url: 'https://example.invalid/$name.m3u', httpClient: client);
    } finally {
      client.close();
    }
  }

  Future<Playlist> addXtream(String name) async {
    final http.Client client = MockClient((request) async {
      final Object body = switch (request.url.queryParameters['action'] ?? '') {
        '' => <String, Object>{'user_info': <String, Object>{'auth': 1}},
        'get_live_categories' => <Object>[
          <String, Object>{'category_id': '1', 'category_name': 'Documentaires'},
        ],
        'get_live_streams' => <Object>[
          <String, Object>{'stream_id': 7, 'name': name, 'category_id': '1'},
        ],
        _ => <Object>[],
      };
      return http.Response(jsonEncode(body), 200);
    });
    try {
      return await sources.addXtreamPlaylist(name: name,
          serverUrl: 'https://example.invalid', username: 'fixture-$name',
          password: 'fixture', httpClient: client);
    } finally {
      client.close();
    }
  }

  Future<FamilyProfile> newProfile(String name) async {
    final FamilyProfile? profile = await profiles.addProfile(name: name, isKids: false);
    expect(profile, isNotNull);
    return profile!;
  }

  Future<void> guide(String title) async {
    final DateTime now = DateTime.now();
    final String body = '<tv><programme channel="shared-guide" '
        'start="${_stamp(now.subtract(const Duration(minutes: 5)))}" '
        'stop="${_stamp(now.add(const Duration(hours: 1)))}">'
        '<title>$title</title></programme></tv>';
    final http.Client client = MockClient((_) async => http.Response(body, 200));
    try {
      expect(await epg.downloadAndImport(url: 'https://example.invalid/guide.xml',
          httpClient: client), 1);
    } finally {
      client.close();
    }
  }

  test('dix profils sont créés et relus, le onzième est refusé', () async {
    for (int i = 2; i <= 10; i++) {
      await newProfile('Personne $i');
    }
    expect(profiles.catalog.profiles, hasLength(10));
    expect(await profiles.addProfile(name: 'Onzième', isKids: false), isNull);
    final String last = profiles.catalog.profiles.last.id;
    expect(await profiles.activate(last, leaveAllowed: true), isTrue);
    await profiles.resetForTesting();
    await profiles.load();
    expect(profiles.catalog.profiles, hasLength(10));
    expect(profiles.active.id, last);
  });

  test('dix sources mixtes par profil, quota avant tout réseau de la onzième', () async {
    for (int i = 0; i < 10; i++) {
      if (i.isEven) {
        await addM3u('M$i');
      } else {
        await addXtream('X$i');
      }
    }
    expect(await sources.sourceCount(), 10);
    expect(sources.currentPlaylists.map((Playlist p) => p.type).toSet(),
        <PlaylistType>{PlaylistType.m3u, PlaylistType.xtream});
    expect(sources.currentChannels, hasLength(10));
    expect(sources.currentChannels.map((Channel c) => c.id).toSet(), hasLength(10));
    expect(await sources.canAddSource(), isFalse);
    int requests = 0;
    final http.Client forbidden = MockClient((_) async {
      requests++;
      return http.Response('', 500);
    });
    addTearDown(forbidden.close);
    await expectLater(sources.addM3uPlaylist(name: 'Trop',
        url: 'https://example.invalid/extra.m3u', httpClient: forbidden),
        throwsA(isA<SourceLimitReachedException>()));
    await expectLater(sources.addXtreamPlaylist(name: 'Trop',
        serverUrl: 'https://example.invalid', username: 'fixture', password: 'fixture',
        httpClient: forbidden), throwsA(isA<SourceLimitReachedException>()));
    expect(requests, 0);
    final FamilyProfile other = await newProfile('Autre');
    await profiles.activate(other.id, leaveAllowed: true);
    expect(await sources.sourceCount(), 0);
    expect(await sources.canAddSource(), isTrue);
    await addXtream('Personnel');
    expect(sources.currentPlaylists.single.profileId, other.id);
    await profiles.activate(ProfileIds.origin, leaveAllowed: true);
    expect(await sources.sourceCount(), 10);
  });

  test('changer puis revenir restaure sources, favoris, guide et comptes cinéma', () async {
    final Playlist original = await addXtream('Origine');
    final String originalChannel = sources.currentChannels.single.id;
    await favorites.toggle(originalChannel);
    await guide('Guide Origine');
    expect((await CinemaRepository.instance.sources()).single.key, 'p${original.id}');
    final FamilyProfile other = await newProfile('Autre');
    await profiles.activate(other.id, leaveAllowed: true);
    expect(sources.currentChannels, isEmpty);
    expect(sources.currentPlaylists, isEmpty);
    expect(favorites.current, isEmpty);
    expect(await epg.currentProgram('shared-guide'), isNull);
    expect(await CinemaRepository.instance.sources(), isEmpty);

    final Playlist personal = await addXtream('Personnel');
    final String personalChannel = sources.currentChannels.single.id;
    expect(personalChannel, isNot(originalChannel));
    await favorites.toggle(personalChannel);
    await guide('Guide Personnel');
    expect((await CinemaRepository.instance.sources()).single.key, 'p${personal.id}');
    expect(CinemaRepository.instance.sourceByKey('p${original.id}'), isNull);
    expect((await epg.currentProgram('shared-guide'))!.title, 'Guide Personnel');

    await profiles.activate(ProfileIds.origin, leaveAllowed: true);
    expect(sources.currentPlaylists.single.id, original.id);
    expect(sources.currentChannels.single.id, originalChannel);
    expect(favorites.current, <String>{originalChannel});
    expect((await epg.currentProgram('shared-guide'))!.title, 'Guide Origine');
    expect((await CinemaRepository.instance.sources()).single.key, 'p${original.id}');
    await profiles.activate(other.id, leaveAllowed: true);
    expect(sources.currentPlaylists.single.id, personal.id);
    expect(favorites.current, <String>{personalChannel});
  });

  test('une source mixte garde ses données +18 seulement dans l’APK privé et dans son profil', () async {
    // Le nom reste neutre : c'est la catégorie du fournisseur qui classe
    // cette seconde chaîne. Même fixture pour le build Play et l'APK privé.
    const String mixed = '''#EXTM3U
#EXTINF:-1 tvg-id="mixed-normal" group-title="Documentaires",Canal Horizon
https://example.invalid/normal.ts
#EXTINF:-1 tvg-id="mixed-private" group-title="+18",Canal Soleil
https://example.invalid/private.ts
''';
    int requests = 0;
    final http.Client client = MockClient((_) async {
      requests++;
      return http.Response(mixed, 200);
    });
    addTearDown(client.close);
    final Playlist saved = await sources.addM3uPlaylist(
      name: 'Source mixte personnelle',
      url: 'https://example.invalid/mixed.m3u',
      httpClient: client,
    );
    final List<(String, int?, String, String, String)> expected =
        <(String, int?, String, String, String)>[
      (saved.channelId('mixed-normal'), saved.id, 'Canal Horizon',
          'Documentaires', 'https://example.invalid/normal.ts'),
      if (NovatubePrivateFeatures.adultCatalogs)
        (saved.channelId('mixed-private'), saved.id, 'Canal Soleil',
            '+18', 'https://example.invalid/private.ts'),
    ];
    List<(String, int?, String, String, String)> snapshot() =>
        sources.currentChannels.map((Channel c) =>
            (c.id, c.playlistId, c.name, c.category, c.streamUrl)).toList();

    expect(snapshot(), expected);
    expect(sources.currentChannels.where((Channel c) =>
        c.genre == ChannelGenre.adult),
        hasLength(NovatubePrivateFeatures.adultCatalogs ? 1 : 0));
    expect(saved.profileId, ProfileIds.origin);

    final FamilyProfile other = await newProfile('Autre');
    await profiles.activate(other.id, leaveAllowed: true);
    expect(sources.currentChannels, isEmpty);
    expect(sources.currentPlaylists, isEmpty);
    final Playlist personal = await addM3u('Personnel');
    expect(sources.currentChannels.single.id, personal.channelId('shared'));
    expect(sources.currentChannels.single.name, 'Personnel');
    expect(sources.currentChannels.any((Channel c) => c.playlistId == saved.id), isFalse);

    await profiles.activate(ProfileIds.origin, leaveAllowed: true);
    expect(sources.currentPlaylists.single.id, saved.id);
    expect(snapshot(), expected);
    await sources.reloadForActiveProfile();
    expect(snapshot(), expected);
    expect(requests, 1); // Retour au profil : données relues, sans réimport.
  });

  test('un identifiant de source étranger ne permet aucune modification', () async {
    final Playlist original = await addM3u('Origine');
    final FamilyProfile other = await newProfile('Autre');
    await profiles.activate(other.id, leaveAllowed: true);
    await expectLater(sources.setActivePlaylist(original.id!),
        throwsA(isA<PlaylistDeletedException>()));
    await expectLater(sources.setPlaylistHidden(original.id!, true),
        throwsA(isA<PlaylistDeletedException>()));
    await expectLater(sources.deletePlaylist(original.id!),
        throwsA(isA<PlaylistDeletedException>()));
    expect(await sources.refreshPlaylist(original), isFalse);
    expect(await DeletedSources.read(), isEmpty);
    await profiles.activate(ProfileIds.origin, leaveAllowed: true);
    expect(sources.currentPlaylists.single.id, original.id);
    expect(sources.currentPlaylists.single.hidden, isFalse);
  });

  test('un import en vol reste dans son profil de départ après changement', () async {
    final Completer<void> started = Completer<void>();
    final Completer<http.Response> response = Completer<http.Response>();
    final http.Client client = MockClient((_) {
      started.complete();
      return response.future;
    });
    addTearDown(client.close);
    final Future<Playlist> pending = sources.addM3uPlaylist(name: 'En cours',
        url: 'https://example.invalid/pending.m3u', httpClient: client);
    await started.future;
    final FamilyProfile other = await newProfile('Autre');
    await profiles.activate(other.id, leaveAllowed: true);
    response.complete(http.Response(_m3u('Import Origine'), 200));
    final Playlist saved = await pending;
    expect(saved.profileId, ProfileIds.origin);
    expect(ActiveProfile.instance.id, other.id);
    expect(sources.currentPlaylists, isEmpty);
    expect(sources.currentChannels, isEmpty);
    await profiles.activate(ProfileIds.origin, leaveAllowed: true);
    expect(sources.currentPlaylists.single.id, saved.id);
  });

  test('deux ajouts simultanés à neuf sources ne dépassent pas le quota', () async {
    for (int i = 0; i < 9; i++) {
      await addM3u('M$i');
    }
    final List<Object> results = await Future.wait(<Future<Object>>[
      for (final String name in <String>['ConcurrentA', 'ConcurrentB'])
        addM3u(name).then<Object>((Playlist value) => value,
            onError: (Object error, StackTrace _) => error),
    ]);
    expect(results.whereType<Playlist>(), hasLength(1));
    expect(results.whereType<SourceLimitReachedException>(), hasLength(1));
    expect(await sources.sourceCount(), 10);
  });

  test('supprimer un profil retire seulement ses sources et son guide', () async {
    final Playlist original = await addM3u('Origine');
    await guide('Guide Origine');
    final FamilyProfile other = await newProfile('Autre');
    await profiles.activate(other.id, leaveAllowed: true);
    final Playlist personal = await addM3u('Personnel');
    await guide('Guide Personnel');
    expect(await profiles.remove(other.id, leaveAllowed: true), isTrue);
    expect(profiles.active.id, ProfileIds.origin);
    expect(sources.currentPlaylists.single.id, original.id);
    expect((await epg.currentProgram('shared-guide'))!.title, 'Guide Origine');
    final Database db = await PlaylistDatabase.instance.database;
    expect(await db.query('playlists', where: 'id = ?', whereArgs: <Object>[personal.id!]), isEmpty);
    expect(await db.query('epg_programs', where: 'profile_id = ?', whereArgs: <Object>[other.id]), isEmpty);
  });
}
