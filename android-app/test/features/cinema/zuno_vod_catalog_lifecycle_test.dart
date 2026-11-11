// Cycle de vie VOD/Cast : l'item de la feuille existe avant le changement du
// catalogue. Le profil et sa portée restent identiques pendant toute l'action.
// Les transports sont simulés ; la feuille est le vrai widget de production.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/domain/zuno_cast_media.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';
import '../cast/data/cast_parental_fixture.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// Déjà fourni par path_provider ; même adaptateur que les tests Cinéma existants.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/cinema/data/cinema_repository.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_common.dart';
import 'package:tv_king/features/vod/data/download_repository.dart';

class _FixturePaths extends PathProviderPlatform {
  _FixturePaths(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cinema = CinemaRepository.instance;
  late Directory root;
  late PathProviderPlatform originalPaths;
  late Database database;
  late int playlistId;
  int scenario = 0;
  String categoryName = 'Films famille';
  String titleName = 'Quenovar';
  int mediaOffset = 0;
  Completer<http.Response>? wholePending;
  Completer<void>? wholeEntered;

  http.Client client() => MockClient((request) async {
        final action = request.url.queryParameters['action'];
        if (action == 'get_vod_streams' &&
            !request.url.queryParameters.containsKey('category_id') &&
            wholePending != null) {
          if (!wholeEntered!.isCompleted) wholeEntered!.complete();
          return wholePending!.future;
        }
        final Object response;
        if (action == 'get_vod_categories' ||
            action == 'get_series_categories') {
          response = <Object>[
            <String, String>{
              'category_id': '10',
              'category_name': categoryName,
            },
          ];
        } else {
          response = <Object>[
            <String, Object>{
              'stream_id': 101 + mediaOffset,
              'series_id': 201 + mediaOffset,
              'name': titleName,
              'category_id': '10',
              'container_extension': 'mp4',
            },
          ];
        }
        return http.Response(jsonEncode(response), 200,
            headers: <String, String>{'content-type': 'application/json'});
      });

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    root = Directory.systemTemp.createTempSync('zuno-vod-revalidation-');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FixturePaths(root.path);
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = '${root.path}/lists.db';
    database = await PlaylistDatabase.instance.database;
    await DownloadsRepository.instance.initialize();
  });

  setUp(() async {
    AppPlatform.isZuno = false;
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    categoryName = 'Films famille';
    titleName = 'Quenovar';
    mediaOffset = 0;
    wholePending = null;
    wholeEntered = null;
    final profileId = 'vod_revalidation_${++scenario}';
    playlistId = await database.insert(
        'playlists',
        Playlist(
          id: null,
          name: 'Source de test $scenario',
          type: PlaylistType.xtream,
          xtreamServer: 'https://catalogue$scenario.fixture.invalid',
          xtreamUsername: 'fixture',
          xtreamPassword: 'fixture',
          createdAt: scenario,
        ).toMap());
    final profile = FamilyProfile(
      id: profileId,
      name: 'Enfants',
      avatar: 1,
      isKids: true,
      createdAtMs: scenario,
      playlistIds: <int>[playlistId],
    );
    final catalog = ProfileCatalog(
      profiles: <FamilyProfile>[FamilyProfile.origin(), profile],
      activeId: profile.id,
      askOnStartup: false,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      ProfileKeys.catalog: catalog.encode(),
      ProfileKeys.kidsMode(profile.id): true,
    });
    ProfileRepository.instance.resetForTesting(catalog);
    AppPlatform.configureZuno(isAndroidHandset: false);
    await ParentalControls.instance.load();
    cinema.clear();
    CinemaRepository.httpForTesting = client;
  });

  tearDown(() {
    cinema.clear();
    CinemaRepository.httpForTesting = null;
    AppPlatform.isZuno = false;
    AppPlatform.isTv = false;
  });

  tearDownAll(() async {
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    PathProviderPlatform.instance = originalPaths;
    await root.delete(recursive: true);
  });

  Future<VodPlayItem> knownItem(CinemaKind kind) async {
    expect(await cinema.refreshNow(kind), isTrue);
    final category = cinema.peekCategories(kind)!.single;
    final title = (await cinema.titles(kind, category)).single;
    expect(cinema.adultStatusForMedia(title.id, title.name), isFalse);
    final item = kind == CinemaKind.movie
        ? VodPlayItem.movie(title)
        : VodPlayItem.episode(
            CinemaEpisode(
              id: 'p$playlistId:e:301',
              remoteId: '301',
              seriesId: title.id,
              season: 1,
              number: 1,
              title: 'Épisode de test',
              streamUrl: 'https://fixture.invalid/episode.mp4',
              containerExt: 'mp4',
            ),
            title);
    expect(item.adultClassificationKnown, isTrue);
    expect(item.isAdult, isFalse);
    return item;
  }

  test(
      'Cast connu survit à trim et republication normale, puis ferme sur reclassement',
      () async {
    final item = await knownItem(CinemaKind.movie);
    final receiver = ParentalTransport();
    final manager = parentalManager(receiver);
    try {
      await manager.castTo(parentalDevice,
          streamUrl: item.url,
          title: item.title,
          zunoMedia: ZunoCastMedia(
              id: item.id,
              streamUrl: item.url,
              playlistId: item.playlistId,
              isAdult: item.currentAdultStatus,
              isAllowedNow: item.isAllowedNow));
      expect(manager.state, CastState.casting);
      cinema.trim();
      expect(item.isAllowedNow(), isTrue);
      await manager.pause();
      await manager.resume();
      expect(manager.state, CastState.casting);
      expect(receiver.stops, 0);
      expect(await cinema.refreshNow(CinemaKind.movie), isTrue);
      expect(manager.state, CastState.casting,
          reason:
              'La publication normale ne passe pas par un faux état inconnu.');
      expect(receiver.stops, 0);
      categoryName = 'XXX';
      expect(await cinema.refreshNow(CinemaKind.movie), isTrue);
      expect(manager.state, CastState.idle);
      expect(receiver.played, hasLength(1));
      expect(receiver.stops, 1);
    } finally {
      await manager.disconnect();
      manager.dispose();
    }
  });

  test('relecture réseau normale remplace le classement détenu après trim',
      () async {
    final item = await knownItem(CinemaKind.movie);
    final category = cinema.peekCategories(CinemaKind.movie)!.single;
    cinema.trim();
    // Seul le cache de cette fixture temporaire est supprimé. Le scénario
    // représente un cache absent, jamais l'effacement des données d'un client.
    await Directory('${root.path}/zuno_catalog').delete(recursive: true);
    titleName = 'XXX';
    final fresh = await cinema.loadTitles(CinemaKind.movie, category);
    expect(fresh.fromCache, isFalse);
    expect(fresh.titles.single.name, 'XXX');
    expect(item.isAllowedNow(), isFalse,
        reason: 'Une publication réelle prime sur la preuve avant trim.');
  });

  test('Cast film maintenu pendant index Séries et republication normale Films',
      () async {
    final item = await knownItem(CinemaKind.movie);
    final receiver = ParentalTransport();
    final manager = parentalManager(receiver);
    try {
      await manager.castTo(parentalDevice,
          streamUrl: item.url,
          title: item.title,
          zunoMedia: ZunoCastMedia(
              id: item.id,
              streamUrl: item.url,
              playlistId: item.playlistId,
              isAdult: item.currentAdultStatus,
              isAllowedNow: item.isAllowedNow));
      expect(manager.state, CastState.casting);
      await knownItem(CinemaKind.series);
      await cinema.ensureIndex(CinemaKind.series);
      expect(cinema.indexReady(CinemaKind.series), isTrue);
      expect(await cinema.refreshNow(CinemaKind.movie), isTrue);
      expect(cinema.indexReady(CinemaKind.series), isTrue);
      expect(manager.state, CastState.casting);
      expect(receiver.stops, 0);
      categoryName = 'XXX';
      expect(await cinema.refreshNow(CinemaKind.movie), isTrue);
      expect(manager.state, CastState.idle);
      expect(receiver.played, hasLength(1));
      expect(receiver.stops, 1);
    } finally {
      await manager.disconnect();
      manager.dispose();
    }
  });

  test('une autre catégorie ne réautorise pas un jeton déjà invalidé',
      () async {
    final item = await knownItem(CinemaKind.movie);
    cinema.dropKindMemory(CinemaKind.movie);
    expect(item.isAllowedNow(), isFalse);
    mediaOffset = 1;
    final other = CinemaCategory(
        key: 'autres',
        name: 'Autres',
        parts: <CategoryRef>[CategoryRef('p$playlistId', '20')]);
    final fresh = await cinema.loadTitles(CinemaKind.movie, other);
    expect(fresh.titles.single.id, isNot(item.id));
    final receiver = ParentalTransport();
    final manager = parentalManager(receiver);
    try {
      await manager.castTo(parentalDevice,
          streamUrl: item.url,
          title: item.title,
          zunoMedia: ZunoCastMedia(
              id: item.id,
              streamUrl: item.url,
              playlistId: item.playlistId,
              isAdult: item.currentAdultStatus,
              isAllowedNow: item.isAllowedNow));
      expect(receiver.played, isEmpty,
          reason: 'La source du média invalidé ne doit jamais être envoyée.');
      expect(item.isAllowedNow(), isFalse);
    } finally {
      await manager.disconnect();
      manager.dispose();
    }
  });

  for (final reclassified in <bool>[false, true]) {
    test(
        reclassified
            ? 'un ancien index normal ne réautorise pas la page reclassée adulte'
            : 'une page normale ne laisse pas la construction de l’index abandonnée',
        () async {
      final item = await knownItem(CinemaKind.movie);
      final oldIndexTitle = cinema.search(CinemaKind.movie, 'quenovar').single;
      final category = cinema.peekCategories(CinemaKind.movie)!.single;
      cinema.trim();
      await Directory('${root.path}/zuno_catalog').delete(recursive: true);
      wholePending = Completer<http.Response>();
      wholeEntered = Completer<void>();
      final building = cinema.ensureIndex(CinemaKind.movie);
      await wholeEntered!.future;
      if (reclassified) titleName = 'XXX';
      await cinema.loadTitles(CinemaKind.movie, category);
      if (reclassified) expect(item.isAllowedNow(), isFalse);
      wholePending!.complete(http.Response(
          jsonEncode(<Object>[
            <String, Object>{
              'stream_id': 101,
              'name': 'Quenovar',
              'category_id': '10',
              'container_extension': 'mp4'
            },
            <String, Object>{
              'stream_id': 102,
              'name': 'Deuxième titre',
              // Une autre catégorie doit encore finir d'être indexée.
              'category_id': '20',
              'container_extension': 'mp4'
            },
          ]),
          200,
          headers: <String, String>{'content-type': 'application/json'}));
      await building;
      expect(cinema.indexReady(CinemaKind.movie), isTrue);
      expect(cinema.search(CinemaKind.movie, 'deuxième'), hasLength(1));
      if (reclassified) {
        expect(item.isAllowedNow(), isFalse);
        titleName = 'Autre série';
        // Éviction réelle du cache borné à 30 pages, sans libérer l'index Films.
        for (int page = 0; page < 31; page++) {
          mediaOffset = 100 + page;
          await cinema.loadTitles(
              CinemaKind.series,
              CinemaCategory(
                  key: 'autres_$page',
                  name: 'Autres $page',
                  parts: <CategoryRef>[
                    CategoryRef('p$playlistId', '${20 + page}')
                  ]));
        }
        final hiddenBeforeSelection = cinema.isHiddenTitle(oldIndexTitle);
        final selected = VodPlayItem.movie(oldIndexTitle);
        final receiver = ParentalTransport();
        final manager = parentalManager(receiver);
        try {
          await manager.castTo(parentalDevice,
              streamUrl: selected.url,
              title: selected.title,
              zunoMedia: ZunoCastMedia(
                  id: selected.id,
                  streamUrl: selected.url,
                  playlistId: selected.playlistId,
                  isAdult: selected.currentAdultStatus,
                  isAllowedNow: selected.isAllowedNow));
          expect(receiver.played, isEmpty,
              reason: 'Une nouvelle sélection ne réautorise pas le jeton.');
          expect(hiddenBeforeSelection, isTrue,
              reason: 'L’ancien titre et sa miniature restent filtrés.');
          expect(item.isAllowedNow(), isFalse);
        } finally {
          await manager.disconnect();
          manager.dispose();
        }
      }
    });
  }

  testWidgets('une feuille déjà ouverte retire son titre après reclassement',
      (tester) async {
    final item = (await tester.runAsync(() => knownItem(CinemaKind.movie)))!;
    late BuildContext context;
    int actions = 0;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (value) {
        context = value;
        return const Text('Origine de la feuille');
      }),
    ));
    final pending = showCinemaSheet(context,
        title: item.title,
        isAllowed: () => item.isAllowedNow(),
        actions: <CinemaSheetAction>[
          CinemaSheetAction(Icons.play_arrow, 'Lire', () {
            actions++;
          }),
        ]);
    try {
      await tester.pumpAndSettle();
      expect(find.text(item.title), findsOneWidget);
      categoryName = 'XXX';
      await tester.runAsync(() => cinema.refreshNow(CinemaKind.movie));
      await tester.pump();
      expect(find.text(item.title), findsNothing);
      expect(actions, 0);
      await tester.pump();
      await pending;
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}
