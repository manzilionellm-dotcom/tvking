// La recherche normale ne devient jamais une entrée détournée vers Adultes.
// Le vrai écran lit le catalogue SQLite/Xtream et revalide aussi un ancien clic.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/cinema/data/cinema_repository.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/tv/core/tv_activity.dart';
import 'package:tv_king/features/tv/core/tv_focusable.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_detail_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_search_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

const _channelPublic = 'Voyage Nature';
const _channelAdult = 'Voyage Prive';
const _moviePublic = 'Voyage au soleil';
const _movieAdult = 'Voyage de minuit';

class _SearchPaths extends PathProviderPlatform {
  _SearchPaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

class _SearchObserver extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

http.Client _client() => MockClient((request) async {
      final String? action = request.url.queryParameters['action'];
      final String? category = request.url.queryParameters['category_id'];
      final Object body;
      if (action == 'get_vod_categories') {
        body = <Object>[
          <String, String>{'category_id': '10', 'category_name': 'Famille'},
          <String, String>{'category_id': '20', 'category_name': 'XXX'},
        ];
      } else if (action == 'get_vod_info') {
        body = <String, Object>{'info': <String, Object>{}};
      } else if (action == 'get_vod_streams') {
        body = <Object>[
          if (category == null || category == '10')
            <String, Object>{
              'stream_id': 101,
              'name': _moviePublic,
              'category_id': '10',
              'container_extension': 'mp4',
            },
          if (category == null || category == '20')
            <String, Object>{
              'stream_id': 201,
              'name': _movieAdult,
              'category_id': '20',
              'container_extension': 'mp4',
            },
        ];
      } else {
        body = <Object>[];
      }
      return http.Response(jsonEncode(body), 200,
          headers: <String, String>{'content-type': 'application/json'});
    });

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (int i = 0; i < 100 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)));
  }
  await tester.pump();
  expect(ready(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final profile = ActiveProfile.instance;
  final cinema = CinemaRepository.instance;
  final playlists = PlaylistRepository.instance;
  late Directory root;
  late int playlistId;
  int scenario = 0;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    root = Directory.systemTemp.createTempSync('zuno-search-adult-');
    PathProviderPlatform.instance = _SearchPaths(root.path);
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = '${root.path}/lists.db';
    PlaylistRepository.mergeAllPlaylists = true;
    final Database db = await PlaylistDatabase.instance.database;
    playlistId = await db.insert('playlists', Playlist(
      id: null,
      name: 'Recherche fixture',
      type: PlaylistType.xtream,
      xtreamServer: 'http://search.fixture.invalid',
      xtreamUsername: 'fixture',
      xtreamPassword: 'fixture',
      createdAt: 1,
      channelCount: 2,
    ).toMap());
    for (final (id, name, category) in <(String, String, String)>[
      ('public', _channelPublic, 'Documentaires'),
      ('private', _channelAdult, 'XXX'),
    ]) {
      await db.insert('channels', <String, Object>{
        'playlist_id': playlistId,
        'external_id': id,
        'name': name,
        'category': category,
        'stream_url': 'http://search.fixture.invalid/$id.ts',
        'is_live': 1,
      });
    }
  });

  setUp(() async {
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    profile.set('search-normal-${++scenario}', playlistIds: <int>[playlistId]);
    ParentalControls.instance.kidsMode.value = false;
    await playlists.initialize();
    cinema.clear();
    CinemaRepository.httpForTesting = _client;
  });

  tearDown(() {
    profile.set('search-finished-$scenario', playlistIds: <int>[]);
    cinema.clear();
    CinemaRepository.httpForTesting = null;
  });

  tearDownAll(() async {
    // Termine la dernière émission SQL déclenchée par la portée vide.
    await playlists.initialize();
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    await root.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester, _SearchObserver observer) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    TvActivity.enter();
    // Les catégories et les titres sont ceux du serveur fictif, pas des
    // résultats injectés dans l'état privé du widget de recherche.
    await tester.runAsync(() async {
      final categories = await cinema.categories(CinemaKind.movie);
      for (final category in categories) {
        await cinema.titles(CinemaKind.movie, category);
      }
    });
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: <NavigatorObserver>[observer],
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData.dark(),
      home: const Scaffold(body: TvSearchScreen(initialQuery: 'Voyage')),
    ));
    await _pumpUntil(tester,
        () => find.text(_channelPublic).evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    cinema.clear();
    TvActivity.leave();
    // Le rafraîchissement de fond attendait la fin de lecture simulée.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(seconds: 6));
  }

  testWidgets('Recherche normale : chaîne et film Adultes restent absents',
      (tester) async {
    final observer = _SearchObserver();
    await http.runWithClient(() async {
      try {
        await mount(tester, observer);
        expect(find.text(_channelPublic), findsOneWidget);
        expect(find.text(_moviePublic), findsOneWidget);
        expect(find.text(_channelAdult), findsNothing);
        expect(find.text(_movieAdult), findsNothing);
        // Les deux titres neutres ont réellement été chargés : la catégorie,
        // et non une absence du serveur, explique le filtre dans l'écran.
        expect(cinema.search(CinemaKind.movie, 'Voyage'), hasLength(2));
        final int before = observer.pushes;
        await tester.tap(find.text(_moviePublic));
        await _pumpUntil(tester,
            () => find.byType(TvMovieDetailScreen).evaluate().isNotEmpty);
        await tester.pump(const Duration(milliseconds: 350));
        expect(observer.pushes, before + 1);
        expect(find.byType(TvMovieDetailScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await cleanup(tester);
      }
    }, _client);
  });

  testWidgets('Recherche : anciens clics inertes dès le retrait des listes',
      (tester) async {
    final observer = _SearchObserver();
    await http.runWithClient(() async {
      try {
        await mount(tester, observer);
        VoidCallback selected(String label) => tester.widget<TvFocusable>(
          find.ancestor(of: find.text(label), matching: find.byType(TvFocusable)),
        ).onSelect!;
        final VoidCallback oldChannelClick = selected(_channelPublic);
        final VoidCallback oldMovieClick = selected(_moviePublic);
        final int before = observer.pushes;
        // Même personne, mais ses listes ont été retirées. L'ancien geste
        // peut encore être dans la file d'événements avant le prochain cadre.
        profile.set(profile.id, playlistIds: <int>[]);
        oldChannelClick();
        oldMovieClick();
        await tester.pump();
        expect(observer.pushes, before);
        await _pumpUntil(tester, () =>
            find.text(_channelPublic).evaluate().isEmpty &&
            find.text(_moviePublic).evaluate().isEmpty);
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text(_channelAdult), findsNothing);
        expect(find.text(_movieAdult), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await cleanup(tester);
      }
    }, _client);
  });
}
