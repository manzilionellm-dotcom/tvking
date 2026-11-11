// Régression portable : l'item de la feuille existe avant le changement du
// catalogue. Le profil et sa portée restent identiques pendant toute l'action.
// Aucun moteur natif ne joue : l'observateur ferme immédiatement toute route
// poussée, mais compte cette tentative réelle d'ouverture par openVod.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:tv_king/features/profiles/data/active_profile.dart';
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

class _OpeningObserver extends NavigatorObserver {
  int playerAttempts = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (previousRoute == null) return;
    playerAttempts++;
    // Attend la sortie du verrou interne de Navigator, sans monter le lecteur.
    scheduleMicrotask(() => navigator?.pop());
  }
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

  http.Client client() => MockClient((request) async {
        final action = request.url.queryParameters['action'];
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
              'stream_id': 101,
              'series_id': 201,
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

  Future<void> adultProfile() async {
    final profile = FamilyProfile(
      id: ActiveProfile.instance.id,
      name: 'Adulte',
      avatar: 1,
      isKids: false,
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
      ProfileKeys.kidsMode(profile.id): false,
    });
    ProfileRepository.instance.resetForTesting(catalog);
    await ParentalControls.instance.load();
  }

  Future<int> attemptedOpen(WidgetTester tester, VodPlayItem item) async {
    final observer = _OpeningObserver();
    late BuildContext entryContext;
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: <NavigatorObserver>[observer],
      home: Builder(builder: (context) {
        entryContext = context;
        return const Text('Catalogue de test');
      }),
    ));
    try {
      await tester.runAsync(() =>
          openVod(entryContext, item).timeout(const Duration(seconds: 5)));
      expect(tester.takeException(), isNull);
      return observer.playerAttempts;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  }

  for (final kind in CinemaKind.values) {
    for (final unknown in <bool>[false, true]) {
      testWidgets(
          '${kind.name} : item normal ancien refusé après '
          '${unknown ? 'catalogue devenu inconnu' : 'reclassement adulte'}',
          (tester) async {
        final item = (await tester.runAsync(() => knownItem(kind)))!;
        final profile = ActiveProfile.instance.id;
        final scope = ActiveProfile.instance.scopeListenable.value;
        final mediaId = item.isEpisode ? item.seriesId! : item.id;
        await tester.runAsync(() async {
          if (unknown) {
            cinema.clear();
          } else {
            categoryName = 'XXX';
            expect(await cinema.refreshNow(kind), isTrue);
          }
        });
        expect(ActiveProfile.instance.id, profile);
        expect(ActiveProfile.instance.scopeListenable.value, scope);
        expect(ParentalControls.instance.kidsMode.value, isTrue);
        if (unknown) {
          expect(cinema.adultStatusForMedia(mediaId, item.title), isNull);
        } else {
          expect(cinema.peekCategories(kind)!.single.name, 'XXX');
        }
        // Les champs historiques ne sont pas une autorisation actuelle.
        expect(item.adultClassificationKnown, isTrue);
        expect(item.isAdult, isFalse);
        expect(await attemptedOpen(tester, item), 0,
            reason: 'Le callback de la feuille doit relire le droit courant.');
      });
    }
  }

  testWidgets('recharge de catégorie : même identifiant renommé adulte refusé',
      (tester) async {
    final item = (await tester.runAsync(() => knownItem(CinemaKind.movie)))!;
    final category = cinema.peekCategories(CinemaKind.movie)!.single;
    titleName = 'XXX';
    final fresh = await tester.runAsync(() =>
        cinema.loadTitles(CinemaKind.movie, category, forceNetwork: true));
    expect(fresh!.titles.single.id, item.id);
    expect(fresh.titles.single.name, 'XXX');
    expect(await attemptedOpen(tester, item), 0);
  });

  testWidgets('Enfants : média connu avec catalogue inchangé reste ouvrable',
      (tester) async {
    final item = (await tester.runAsync(() => knownItem(CinemaKind.movie)))!;
    expect(await attemptedOpen(tester, item), 1);
  });

  testWidgets(
      'Enfants : libération de l’index seule ne révoque pas le média connu',
      (tester) async {
    final item = (await tester.runAsync(() => knownItem(CinemaKind.movie)))!;
    final categories = cinema.peekCategories(CinemaKind.movie);
    cinema.trim();
    expect(
        identical(cinema.peekCategories(CinemaKind.movie), categories), isTrue);
    expect(cinema.adultStatusForMedia(item.id, item.title), isNull,
        reason:
            'Le catalogue est inchangé ; seule sa liste lourde est libérée.');
    expect(await attemptedOpen(tester, item), 1);
  });

  testWidgets('adulte : nouveau film autorisé avant chargement des catégories',
      (tester) async {
    await tester.runAsync(adultProfile);
    cinema.clear();
    final item = VodPlayItem.movie(CinemaTitle(
      id: 'p$playlistId:m:701',
      kind: CinemaKind.movie,
      sourceKey: 'p$playlistId',
      remoteId: '701',
      name: 'Film nouveau',
      categoryKey: 'categorie-pas-encore-chargee',
      searchKey: 'film nouveau',
      streamUrl: 'https://fixture.invalid/new-film.mp4',
    ));
    expect(cinema.adultStatusForMedia(item.id, item.title), isNull);
    expect(await attemptedOpen(tester, item), 1,
        reason: 'Un état parental adulte prêt conserve son accès historique.');
  });

  testWidgets(
      'adulte : ancien téléchargement normal de sa source reste ouvrable',
      (tester) async {
    await tester.runAsync(adultProfile);
    cinema.clear();
    final item = VodPlayItem(
      id: 'p$playlistId:m:702',
      isEpisode: false,
      title: 'Téléchargement connu',
      url: 'https://fixture.invalid/download.mp4',
    );
    expect(item.sourceKey, isEmpty);
    expect(item.adultClassificationKnown, isTrue);
    expect(await attemptedOpen(tester, item), 1);
  });

  for (final id in <String>['p99999:m:703', 'ancien-id-sans-source']) {
    testWidgets('sourceKey vide ne contourne pas la source autorisée : $id',
        (tester) async {
      await tester.runAsync(adultProfile);
      cinema.clear();
      final item = VodPlayItem(
        id: id,
        isEpisode: false,
        title: 'Ancienne sélection',
        url: 'https://fixture.invalid/old-selection.mp4',
      );
      expect(await attemptedOpen(tester, item), 0);
    });
  }

  testWidgets('7 MOTION conserve la décision historique de son item',
      (tester) async {
    final item = (await tester.runAsync(() => knownItem(CinemaKind.movie)))!;
    cinema.clear();
    AppPlatform.isZuno = false;
    AppPlatform.isTv = false;
    expect(await attemptedOpen(tester, item), 1);
  });
}
