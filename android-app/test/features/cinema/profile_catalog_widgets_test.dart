// Les vrais écrans restent montés pendant le choix d'un autre profil.
// Le réseau répond volontairement dans le mauvais ordre : seules les cartes
// de la sélection courante doivent rester visibles, sans changer le layout.
import 'dart:async';
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
import 'package:tv_king/features/cinema/data/watch_progress.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/tv/core/tv_activity.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_detail_screen.dart';
import 'package:tv_king/features/vod/data/download_repository.dart';
import 'package:tv_king/features/vod/presentation/movies_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

class _WidgetPaths extends PathProviderPlatform {
  _WidgetPaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

http.Response _response(http.Request request) {
  final String source = request.url.host == 'a.widget.test' ? 'A' : 'B';
  final Object body = request.url.queryParameters['action'] == 'get_vod_categories'
      ? <Object>[
          <String, String>{'category_id': '10', 'category_name': 'Catalogue $source'},
        ]
      : <Object>[
          <String, Object>{
            'stream_id': 101,
            'name': 'Film du profil $source',
            'category_id': '10',
            'container_extension': 'mp4',
          },
        ];
  return http.Response(jsonEncode(body), 200,
      headers: <String, String>{'content-type': 'application/json'});
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() ready,
  String reason,
) async {
  for (int attempt = 0; attempt < 100 && !ready(); attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    // SQLite FFI, lecture du cache disque et l'isolate de décodage sont réels.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
  }
  await tester.pump();
  expect(ready(), isTrue, reason: reason);
}

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData.dark(),
      home: Scaffold(body: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final profile = ActiveProfile.instance;
  final cinema = CinemaRepository.instance;
  late Directory root;
  late int a;
  late int b;
  int scenario = 0;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    root = Directory.systemTemp.createTempSync('zuno-profile-widgets-');
    PathProviderPlatform.instance = _WidgetPaths(root.path);
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = '${root.path}/lists.db';
    final Database db = await PlaylistDatabase.instance.database;
    Future<int> insert(String name) => db.insert(
          'playlists',
          Playlist(
            id: null,
            name: name,
            type: PlaylistType.xtream,
            xtreamServer: 'http://${name.toLowerCase()}.widget.test',
            xtreamUsername: 'fixture',
            xtreamPassword: 'fixture',
            createdAt: 1,
          ).toMap(),
        );
    a = await insert('A');
    b = await insert('B');
    await DownloadsRepository.instance.initialize();
  });
  setUp(() {
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    profile.set('widget-start-${++scenario}', playlistIds: <int>[]);
    cinema.clear();
  });
  tearDown(() {
    profile.set('widget-finished-$scenario', playlistIds: <int>[]);
    cinema.clear();
    CinemaRepository.httpForTesting = null;
  });
  tearDownAll(() async {
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    await root.delete(recursive: true);
  });

  testWidgets('Films mobile : B remplace A, puis ignore sa réponse tardive', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final entered = Completer<void>();
    final release = Completer<void>();
    bool holdA = false;
    http.Client client() => MockClient((request) async {
          if (holdA && request.url.host == 'a.widget.test' &&
              request.url.queryParameters['action'] == 'get_vod_streams') {
            if (!entered.isCompleted) entered.complete();
            await release.future;
          }
          return _response(request);
        });
    CinemaRepository.httpForTesting = client;
    await http.runWithClient(() async {
      try {
        profile.set('mobile-a', playlistIds: <int>[a]);
        await tester.pumpWidget(_app(const MoviesScreen()));
        await _pumpUntil(tester, () => find.text('Film du profil A').evaluate().isNotEmpty,
            'Le catalogue A doit être affiché avant le changement.');
        holdA = true;
        await tester.tap(find.byIcon(Icons.refresh_rounded));
        await _pumpUntil(tester, () => entered.isCompleted,
            'L’ancienne actualisation doit être en attente.');
        profile.set('mobile-b', playlistIds: <int>[b]);
        await tester.pump();
        expect(find.text('Film du profil A'), findsNothing);
        await _pumpUntil(tester, () => find.text('Film du profil B').evaluate().isNotEmpty,
            'Le même écran doit charger le catalogue B.');
        release.complete();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Film du profil A'), findsNothing);
        expect(find.text('Film du profil B'), findsOneWidget);

        profile.set('mobile-empty', playlistIds: <int>[]);
        await tester.pump();
        final emptyMessage = AppLocalizations.of(
          tester.element(find.byType(MoviesScreen)),
        ).moviesEmptyCatalogue;
        await _pumpUntil(tester, () => find.text(emptyMessage).evaluate().isNotEmpty,
            'Le profil sans liste termine en catalogue vide.');
        expect(find.text('Film du profil A'), findsNothing);
        expect(find.text('Film du profil B'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        if (!release.isCompleted) release.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    }, client);
  });

  testWidgets('Cinéma TV : catégories A tardives ne repeuplent jamais B ni []', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final entered = Completer<void>();
    final release = Completer<void>();
    http.Client client() => MockClient((request) async {
          if (request.url.host == 'a.widget.test' &&
              request.url.queryParameters['action'] == 'get_vod_categories') {
            if (!entered.isCompleted) entered.complete();
            await release.future;
          }
          return _response(request);
        });
    CinemaRepository.httpForTesting = client;
    // Garde le rafraîchissement catalogue de fond au repos. La sélection
    // de catégorie reste réelle et utilise son réseau, son parser et sa grille.
    TvActivity.enter();
    await http.runWithClient(() async {
      try {
        profile.set('tv-a', playlistIds: <int>[a]);
        await tester.pumpWidget(_app(const TvCinemaScreen(kind: CinemaKind.movie)));
        await _pumpUntil(tester, () => entered.isCompleted,
            'Le chargement A doit être en attente avant le changement.');
        profile.set('tv-b', playlistIds: <int>[b]);
        await _pumpUntil(tester, () => find.text('Film du profil B').evaluate().isNotEmpty,
            'Le vrai écran TV doit sélectionner et afficher une catégorie de B.');
        expect(find.text('Catalogue B'), findsWidgets);
        expect(find.text('Catalogue A'), findsNothing);
        release.complete();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Catalogue A'), findsNothing);
        expect(find.text('Film du profil A'), findsNothing);
        expect(find.text('Film du profil B'), findsWidgets);

        profile.set('tv-empty', playlistIds: <int>[]);
        await tester.pump();
        expect(find.text('Catalogue B'), findsNothing);
        expect(find.text('Film du profil B'), findsNothing);
        await _pumpUntil(tester, () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
            'Un profil sans liste ne réutilise aucune catégorie en mémoire.');
        expect(find.text('Catalogue A'), findsNothing);
        expect(find.text('Catalogue B'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        if (!release.isCompleted) release.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        cinema.clear();
        TvActivity.leave();
        // Termine les délais de fond invalidés et les appels différés d'index.
        await tester.pump(const Duration(seconds: 6));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
    }, client);
  });

  testWidgets('Même profil réaffecté : la reprise de A disparaît, son historique reste', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    http.Client client() => MockClient((request) async => _response(request));
    CinemaRepository.httpForTesting = client;
    TvActivity.enter();
    await http.runWithClient(() async {
      try {
        profile.set('same-cinema-viewer', playlistIds: <int>[a]);
        await WatchProgressRepository.instance.load();
        final entry = WatchEntry(
          id: 'p$a:m:resumable',
          isEpisode: false,
          title: 'Reprise propre à la source A',
          streamUrl: 'http://a.widget.test/movie/fixture/fixture/101.mp4',
          sourceKey: 'p$a',
          remoteId: '101',
          posMs: 60000,
          durMs: 600000,
          updatedAt: 1,
        );
        WatchProgressRepository.instance.record(entry, flushNow: true);
        await tester.pumpWidget(_app(const TvCinemaScreen(kind: CinemaKind.movie)));
        await _pumpUntil(tester,
            () => find.text('Reprise propre à la source A').evaluate().isNotEmpty,
            'Le profil A doit afficher sa reprise mémorisée.');

        // Même ID : seul scopeListenable bouge, le tiroir d’historique reste.
        profile.set('same-cinema-viewer', playlistIds: <int>[b]);
        await tester.pump();
        expect(find.text('Reprise propre à la source A'), findsNothing);
        await _pumpUntil(tester,
            () => find.text('Film du profil B').evaluate().isNotEmpty,
            'La reprise non sélectionnée ne doit pas détourner du catalogue B.');
        expect(find.text('Reprise propre à la source A'), findsNothing);
        expect(WatchProgressRepository.instance.get(entry.id), isNotNull,
            reason: 'Le choix de catalogue ne détruit pas l’historique.');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        cinema.clear();
        TvActivity.leave();
        await tester.pump(const Duration(seconds: 6));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
    }, client);
  });

  for (final CinemaKind kind in CinemaKind.values) {
    testWidgets('Fiche ${kind.name} ouverte : le scope change, la route se ferme', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final entered = Completer<void>();
      final release = Completer<void>();
      http.Client client() => MockClient((request) async {
            if (request.url.queryParameters['action']?.endsWith('_info') == true) {
              if (!entered.isCompleted) entered.complete();
              await release.future;
              return http.Response(jsonEncode(<String, Object>{
                'info': <String, String>{'plot': 'Ancien résumé du profil A'},
                'seasons': <Object>[],
                'episodes': <String, Object>{},
              }), 200);
            }
            return _response(request);
          });
      CinemaRepository.httpForTesting = client;
      final navigator = GlobalKey<NavigatorState>();
      final title = CinemaTitle(
        id: 'p$a:${kind == CinemaKind.movie ? 'm' : 's'}:101',
        kind: kind,
        sourceKey: 'p$a',
        remoteId: '101',
        name: 'Fiche du profil A',
        categoryKey: 'catalogue a',
        searchKey: 'fiche du profil a',
        streamUrl: 'http://a.widget.test/movie/fixture/fixture/101.mp4',
      );
      await http.runWithClient(() async {
        try {
          profile.set('details-a-${kind.name}', playlistIds: <int>[a]);
          await tester.pumpWidget(MaterialApp(
            navigatorKey: navigator,
            locale: const Locale('fr'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData.dark(),
            home: const Scaffold(body: Text('Accueil de la fixture')),
          ));
          navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) =>
            Scaffold(body: kind == CinemaKind.movie
                ? TvMovieDetailScreen(title: title)
                : TvSeriesScreen(title: title)),
          ));
          await _pumpUntil(tester, () => entered.isCompleted,
              'La fiche doit avoir commencé sa lecture du profil A.');
          expect(find.text('Fiche du profil A'), findsOneWidget);
          profile.set('details-b-${kind.name}', playlistIds: <int>[b]);
          await tester.pump();
          expect(find.text('Fiche du profil A'), findsNothing,
              reason: 'La fiche périmée devient inerte dès le changement.');
          await tester.pump(const Duration(milliseconds: 650));
          await tester.pump();
          expect(find.text('Accueil de la fixture'), findsOneWidget);
          expect(find.byType(TvMovieDetailScreen), findsNothing);
          expect(find.byType(TvSeriesScreen), findsNothing);
          release.complete();
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('Ancien résumé du profil A'), findsNothing);
          expect(find.text('Accueil de la fixture'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          if (!release.isCompleted) release.complete();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      }, client);
    });
  }
}
