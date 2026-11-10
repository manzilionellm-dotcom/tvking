// Vrais écrans + dépôt Xtream : la catégorie suffit à classer un titre neutre.
// L'accès adulte est une autorisation révocable, jamais un ancien état de focus.
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
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/adult_access.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/tv/core/tv_activity.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_common.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_vod_player_screen.dart';
import 'package:tv_king/features/vod/data/download_repository.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

const _publicCategory = 'Films famille';
const _adultCategory = 'XXX';
const _publicTitle = 'Voyage en montagne';
const _adultTitle = 'Programme du soir';
const _publicResume = 'Promenade au parc';
const _adultResume = 'Rendez-vous du jeudi';

class _AdultWidgetPaths extends PathProviderPlatform {
  _AdultWidgetPaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

class _RouteObserver extends NavigatorObserver {
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
          <String, String>{'category_id': '10', 'category_name': _publicCategory},
          <String, String>{'category_id': '20', 'category_name': _adultCategory},
        ];
      } else {
        body = <Object>[
          if (category == null || category == '10')
            <String, Object>{
              'stream_id': 101,
              'name': _publicTitle,
              'category_id': '10',
              'container_extension': 'mp4',
            },
          if (category == null || category == '20')
            <String, Object>{
              'stream_id': 201,
              'name': _adultTitle,
              'category_id': '20',
              'container_extension': 'mp4',
            },
        ];
      }
      return http.Response(jsonEncode(body), 200,
          headers: <String, String>{'content-type': 'application/json'});
    });

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() ready,
  String reason,
) async {
  for (int attempt = 0; attempt < 100 && !ready(); attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
  }
  await tester.pump();
  expect(ready(), isTrue, reason: reason);
}

Widget _app(Widget child, {
  GlobalKey<NavigatorState>? navigator,
  NavigatorObserver? observer,
}) => MaterialApp(
      navigatorKey: navigator,
      navigatorObservers: <NavigatorObserver>[if (observer != null) observer],
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData.dark(),
      home: Scaffold(body: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final CinemaRepository cinema = CinemaRepository.instance;
  final WatchProgressRepository progress = WatchProgressRepository.instance;
  late Directory root;
  late int playlistId;
  int scenario = 0;
  final List<AdultAccessGrant> grants = <AdultAccessGrant>[];

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    root = Directory.systemTemp.createTempSync('zuno-adult-cinema-widgets-');
    PathProviderPlatform.instance = _AdultWidgetPaths(root.path);
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = '${root.path}/lists.db';
    await DownloadsRepository.instance.initialize();
  });

  setUp(() async {
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    final Database db = await PlaylistDatabase.instance.database;
    final String profileId = 'adult_widgets_${++scenario}';
    playlistId = await db.insert('playlists', Playlist(
      id: null,
      name: 'Catalogue $scenario',
      type: PlaylistType.xtream,
      xtreamServer: 'http://source$scenario.adult-widget.test',
      xtreamUsername: 'fixture',
      xtreamPassword: 'fixture',
      createdAt: scenario,
    ).toMap());
    ProfileRepository.instance.resetForTesting(ProfileCatalog(
      profiles: <FamilyProfile>[
        FamilyProfile.origin(),
        FamilyProfile(
          id: profileId,
          name: 'Parent',
          avatar: 1,
          isKids: false,
          createdAtMs: scenario,
          playlistIds: <int>[playlistId],
        ),
      ],
      activeId: profileId,
      askOnStartup: false,
    ));
    await ParentalControls.instance.load();
    await progress.load();
    cinema.clear();
    CinemaRepository.httpForTesting = _client;
  });

  tearDown(() {
    for (final AdultAccessGrant grant in grants) {
      grant.dispose();
    }
    grants.clear();
    ActiveProfile.instance.set('adult_widget_finished_$scenario', playlistIds: <int>[]);
    cinema.clear();
    CinemaRepository.httpForTesting = null;
  });

  tearDownAll(() async {
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    await root.delete(recursive: true);
  });

  void recordResume({required bool adult}) {
    progress.record(WatchEntry(
      id: 'p$playlistId:m:${adult ? 202 : 102}',
      isEpisode: false,
      isAdult: adult,
      title: adult ? _adultResume : _publicResume,
      streamUrl: 'http://source$scenario.adult-widget.test/movie/fixture/fixture/${adult ? 202 : 102}.mp4',
      sourceKey: 'p$playlistId',
      remoteId: adult ? '202' : '102',
      posMs: 60000,
      durMs: 600000,
      updatedAt: scenario,
    ), flushNow: true);
  }

  Future<AdultAccessGrant> grantAccess() async {
    int pinRequests = 0;
    final AdultAccessGrant? grant = await authenticateAdultAccess(
      reason: 'fixture',
      confirmPin: () async {
        pinRequests++;
        return true;
      },
    );
    expect(pinRequests, 1);
    expect(grant, isNotNull);
    expect(grant!.isValid, isTrue);
    grants.add(grant);
    return grant;
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    cinema.clear();
    TvActivity.leave();
    await tester.pump(const Duration(seconds: 6));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }

  void configureView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // L'index de fond attend ; la sélection et le vrai dépôt restent actifs.
    TvActivity.enter();
  }

  testWidgets('Cinéma normal : aucun titre, catégorie ou reprise adulte', (tester) async {
    configureView(tester);
    recordResume(adult: true);
    await http.runWithClient(() async {
      try {
        await tester.pumpWidget(_app(const TvCinemaScreen(kind: CinemaKind.movie)));
        await _pumpUntil(tester, () => find.text(_publicTitle).evaluate().isNotEmpty,
            'Le catalogue normal doit charger directement son film public.');
        expect(find.text(_publicCategory), findsWidgets);
        expect(find.text(_adultCategory), findsNothing);
        expect(find.text(_adultTitle), findsNothing);
        expect(find.text(_adultResume), findsNothing);
        expect(find.byType(Dialog), findsNothing,
            reason: 'Naviguer dans le catalogue normal ne demande pas le PIN.');
        expect(tester.takeException(), isNull);
      } finally {
        await cleanup(tester);
      }
    }, _client);
  });

  testWidgets('Espace autorisé : catégorie neutre et reprises adultes seulement', (tester) async {
    configureView(tester);
    recordResume(adult: false);
    final AdultAccessGrant grant = (await tester.runAsync(grantAccess))!;
    await http.runWithClient(() async {
      try {
        await tester.pumpWidget(_app(TvCinemaScreen(
          kind: CinemaKind.movie,
          adultAccess: grant,
        )));
        await _pumpUntil(tester, () => find.text(_adultTitle).evaluate().isNotEmpty,
            'Le titre neutre de la catégorie XXX appartient à l’espace Adultes.');
        expect(find.text(_adultCategory), findsWidgets);
        expect(find.text(_publicCategory), findsNothing);
        expect(find.text(_publicTitle), findsNothing);
        expect(find.text(_publicResume), findsNothing);

        recordResume(adult: true);
        await tester.pump();
        final String resumeLabel = AppLocalizations.of(
          tester.element(find.byType(TvCinemaScreen)),
        ).sectionResumeWhereYouLeftOff;
        await tester.tap(find.text(resumeLabel));
        await _pumpUntil(tester, () => find.text(_adultResume).evaluate().isNotEmpty,
            'La rangée Reprendre adulte ne mélange pas la reprise publique.');
        expect(find.text(_publicResume), findsNothing);
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await cleanup(tester);
      }
    }, _client);
  });

  testWidgets('Autorisation révoquée : fermeture et ancien geste de lecture inerte', (tester) async {
    configureView(tester);
    recordResume(adult: true);
    final AdultAccessGrant grant = (await tester.runAsync(grantAccess))!;
    final navigator = GlobalKey<NavigatorState>();
    final observer = _RouteObserver();
    await http.runWithClient(() async {
      try {
        await tester.pumpWidget(_app(
          const Text('Accueil de la fixture'),
          navigator: navigator,
          observer: observer,
        ));
        navigator.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(body: TvCinemaScreen(
            kind: CinemaKind.movie,
            adultAccess: grant,
          )),
        ));
        await _pumpUntil(tester, () => find.text(_adultResume).evaluate().isNotEmpty,
            'La reprise doit être présente avant de révoquer son autorisation.');
        final CinemaPoster poster = tester.widget<CinemaPoster>(
          find.byWidgetPredicate((widget) =>
              widget is CinemaPoster && widget.title == _adultResume),
        );
        final int priorPushes = observer.pushes;

        grant.revoke();
        expect(grant.isValid, isFalse);
        // Un événement déjà reçu avant la prochaine frame doit être refusé.
        poster.onSelect();
        await tester.pump();
        expect(find.text(_adultResume), findsNothing);
        expect(find.text(_adultTitle), findsNothing);
        expect(find.byType(TvVodPlayerScreen), findsNothing);
        expect(observer.pushes, priorPushes,
            reason: 'L’ancien callback ne doit ouvrir ni fiche ni lecteur.');
        await tester.pump(const Duration(milliseconds: 650));
        await tester.pump();
        expect(find.byType(TvCinemaScreen), findsNothing);
        expect(find.text('Accueil de la fixture'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await cleanup(tester);
      }
    }, _client);
  });
}
