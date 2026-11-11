// Un dossier fournisseur neutre peut contenir des titres +18. Ces tests
// utilisent le vrai écran, avec un catalogue local et une biométrie factice.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/novatube_private_features.dart';
import 'package:tv_king/core/app/zuno_edition.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/cinema/data/catalog_cache_policy.dart';
import 'package:tv_king/features/cinema/data/cinema_repository.dart';
import 'package:tv_king/features/cinema/data/watch_progress.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/security/data/adult_access.dart';
import 'package:tv_king/features/security/data/adult_biometric_auth.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_common.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_shell.dart';
import 'package:tv_king/features/tv/presentation/tv_touch_components.dart';
import 'package:tv_king/features/vod/data/download_repository.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

const bool _private = NovatubePrivateFeatures.adultCatalogs;
final _android = TargetPlatformVariant.only(TargetPlatform.android);
const String _ordinaryName = 'Film nature';
const String _adultName = 'Film XXX';
const String _declaredName = 'Film mystère';

class _Biometrics implements AdultBiometricAuthenticator {
  int calls = 0;

  @override
  Future<AdultBiometricResult> authenticate({required String reason}) async {
    calls++;
    return AdultBiometricResult.authenticated;
  }

  @override
  Future<void> cancel() async {}
}

class _Catalog implements CinemaRepository {
  _Catalog(this.kind, {bool manyOrdinary = false}) {
    fixtureTitles = <CinemaTitle>[
      for (int i = 0; i < (manyOrdinary ? 81 : 1); i++)
        _title('normal$i', i == 0 ? _ordinaryName : 'Film nature $i'),
      _title('named', _adultName),
      _title('declared', _declaredName, declaredAdult: true),
    ];
  }

  final CinemaKind kind;
  late final List<CinemaTitle> fixtureTitles;
  final List<String> loadedCategories = <String>[];
  final List<bool?> searchModes = <bool?>[];
  final List<bool?> recentModes = <bool?>[];
  int indexRequests = 0;

  static const List<CinemaCategory> folders = <CinemaCategory>[
    CinemaCategory(
      key: 'general',
      name: 'Collection',
      parts: <CategoryRef>[CategoryRef('p1', '1')],
      isKids: true,
    ),
    CinemaCategory(
      key: 'another',
      name: 'Autre collection',
      parts: <CategoryRef>[CategoryRef('p1', '2')],
    ),
  ];

  CinemaTitle _title(String id, String name, {bool declaredAdult = false}) =>
      CinemaTitle(
        id: 'p1:${kind == CinemaKind.movie ? "m" : "s"}:$id',
        kind: kind,
        sourceKey: 'p1',
        remoteId: id,
        name: name,
        categoryKey: 'general',
        searchKey: name.toLowerCase(),
        declaredAdult: declaredAdult,
        addedAt: 1,
      );

  @override
  final ValueNotifier<int> indexVersion = ValueNotifier<int>(0);

  @override
  void refreshIfStale() {}

  @override
  Future<List<CinemaSource>> sources() async => const <CinemaSource>[
        CinemaSource(
          key: 'p1',
          playlistId: 1,
          server: 'https://example.invalid',
          username: 'fixture',
          password: 'fixture',
        ),
      ];

  @override
  Future<List<CinemaCategory>> categories(CinemaKind kind) async => folders;

  @override
  List<CinemaCategory>? peekCategories(CinemaKind kind) => folders;

  @override
  Future<CinemaTitleLoad> loadTitles(CinemaKind kind, CinemaCategory category,
      {bool forceNetwork = false}) async {
    loadedCategories.add(category.key);
    return CinemaTitleLoad(
      titles: fixtureTitles
          .where((title) => title.categoryKey == category.key)
          .toList(),
      failed: false,
    );
  }

  @override
  Future<void> ensureIndex(CinemaKind kind) async {
    indexRequests++;
  }

  @override
  bool indexReady(CinemaKind kind) => true;

  @override
  CatalogAge? catalogAgeAt(CinemaKind kind, DateTime now) => null;

  Iterable<CinemaTitle> _selection(Set<String>? allowedCats, bool? adultOnly) =>
      fixtureTitles.where((title) =>
          (allowedCats == null || allowedCats.contains(title.categoryKey)) &&
          (adultOnly == null || title.isAdult == adultOnly));

  @override
  List<CinemaTitle> recent(CinemaKind kind,
      {Set<String>? allowedCats, int max = 80, bool? adultOnly}) {
    recentModes.add(adultOnly);
    return _selection(allowedCats, adultOnly).take(max).toList();
  }

  @override
  List<CinemaTitle> search(CinemaKind kind, String query,
      {Set<String>? allowedCats, int max = 80, bool? adultOnly}) {
    searchModes.add(adultOnly);
    return _selection(allowedCats, adultOnly)
        .where((title) => title.searchKey.contains(query.toLowerCase()))
        .take(max)
        .toList();
  }

  @override
  int? countFor(CinemaKind kind, String catKey, {bool? adultOnly}) =>
      _selection(<String>{catKey}, adultOnly).length;

  @override
  void trim() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _installTestFonts() async {
  final String? root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) throw StateError('FLUTTER_ROOT nécessaire pour Ahem');
  final ByteData bytes = ByteData.sublistView(
    File('$root/packages/flutter_tools/static/Ahem.ttf').readAsBytesSync(),
  );
  final Map<String, ByteData> fonts = <String, ByteData>{};
  for (final String family in <String>['Inter', 'Oswald', 'JetBrainsMono']) {
    for (final String weight in <String>[
      'Thin',
      'ExtraLight',
      'Light',
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
      'Black',
    ]) {
      fonts['fonts/$family-$weight.ttf'] = bytes;
    }
  }
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMessageHandler('flutter/assets', (ByteData? message) async {
    final String key = utf8.decode(message!.buffer.asUint8List(
      message.offsetInBytes,
      message.lengthInBytes,
    ));
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object>{
        for (final String asset in fonts.keys)
          asset: <Map<String, String>>[
            <String, String>{'asset': asset}
          ],
      });
    }
    if (key == 'AssetManifest.json') {
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode(
        <String, List<String>>{
          for (final String asset in fonts.keys) asset: <String>[asset],
        },
      ))));
    }
    if (fonts.containsKey(key)) return fonts[key];
    return messenger.delegate.send('flutter/assets', message);
  });
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, _Catalog repository,
    {bool adultOnly = false}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: TvShell(
        child: TvCinemaScreen(
          kind: repository.kind,
          adultOnly: adultOnly,
          repository: repository,
        ),
      ),
    ),
  ));
  await _settle(tester);
  await tester.runAsync(GoogleFonts.pendingFonts);
  await _settle(tester);
}

Future<void> _unmount(WidgetTester tester, _Catalog repository) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // L'index différé existant ne doit pas survivre à la fixture.
  await tester.pump(const Duration(seconds: 3));
  await _settle(tester);
  repository.indexVersion.dispose();
}

Finder _poster(String title) => find.byWidgetPredicate(
    (widget) => widget is CinemaPoster && widget.title == title);

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.byType(TvTouchMenuButton<String>));
  await _settle(tester);
  await tester.tap(find.widgetWithText(ListTile, label));
  await _settle(tester);
}

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();
  final AdultAccess access = AdultAccess.instance;
  late _Biometrics biometrics;

  setUpAll(() async {
    await _installTestFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    PlaylistDatabase.debugFilePath = inMemoryDatabasePath;
    await PlaylistDatabase.instance.database;
    // Initialise SQLite hors de l'horloge simulée du premier widget.
    await DownloadsRepository.instance.initialize();
  });
  setUp(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    FlavorConfig.setCurrent(FlavorConfig.novatube);
    CastPlatform.configureZuno(ZunoEdition.touch);
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ParentalControls.instance.load();
    await WatchProgressRepository.instance.load();
    await access.disable();
    biometrics = _Biometrics();
    access.setBiometricsForTesting(biometrics);
    await access.load();
  });
  tearDown(() {
    access.lock();
    access.setBiometricsForTesting(null);
    CastPlatform.resetForTesting();
  });
  tearDownAll(() async {
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  for (final CinemaKind kind in CinemaKind.values) {
    for (final bool kids in <bool>[false, true]) {
      testWidgets(
          '${kind.name} : les listes ${kids ? "enfants" : "ordinaires"} '
          'excluent le titre et le signal fournisseur adultes', (tester) async {
        if (_private) {
          expect(
              await access.enableWithBiometrics(
                  consent: true, reason: 'fixture'),
              isTrue);
        }
        await ParentalControls.instance.setKidsMode(kids);
        final _Catalog repository = _Catalog(kind);
        await _pump(tester, repository);
        expect(_poster(_ordinaryName), findsOneWidget);
        expect(_poster(_adultName), findsNothing);
        expect(_poster(_declaredName), findsNothing);
        expect(repository.loadedCategories, <String>['general']);
        expect(tester.takeException(), isNull);
        await _unmount(tester, repository);
      }, variant: _android);
    }

    if (_private) {
      testWidgets('${kind.name} : +18 trie un dossier neutre à la demande',
          (tester) async {
        expect(
            await access.enableWithBiometrics(consent: true, reason: 'fixture'),
            isTrue);
        expect(biometrics.calls, 1);
        final _Catalog repository = _Catalog(kind);
        await _pump(tester, repository, adultOnly: true);
        final AppLocalizations words = AppLocalizations.of(
          tester.element(find.byType(TvCinemaScreen)),
        );
        expect(
            find.text(words.tvAdultSourceFolder('Collection')), findsOneWidget);
        expect(_poster(_adultName), findsOneWidget);
        expect(_poster(_declaredName), findsOneWidget);
        expect(_poster(_ordinaryName), findsNothing);
        expect(repository.loadedCategories, <String>['general']);
        expect(repository.indexRequests, 0);
        await tester.pump(const Duration(seconds: 2));
        await _settle(tester);
        expect(repository.indexRequests, 1);
        expect(repository.loadedCategories, <String>['general']);

        await _choose(tester, words.tvAdultSourceFolder('Autre collection'));
        expect(repository.loadedCategories, <String>['general', 'another']);
        expect(find.byType(CinemaPoster), findsNothing);
        await _choose(tester, words.tvAdultSourceFolder('Collection'));
        expect(repository.loadedCategories,
            <String>['general', 'another', 'general']);
        expect(_poster(_adultName), findsOneWidget);
        expect(_poster(_declaredName), findsOneWidget);
        expect(_poster(_ordinaryName), findsNothing);

        // La biométrie n'autorise que la session : verrouiller masque aussitôt.
        access.lock();
        await _settle(tester);
        expect(find.byType(CinemaPoster), findsNothing);
        expect(find.text(words.tvAdultLocked), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _unmount(tester, repository);
      }, variant: _android);
    }
  }

  if (_private) {
    testWidgets(
        '+18 : recherche et récents atteignent les titres après '
        '81 résultats ordinaires', (tester) async {
      expect(
          await access.enableWithBiometrics(consent: true, reason: 'fixture'),
          isTrue);
      final _Catalog repository =
          _Catalog(CinemaKind.movie, manyOrdinary: true);
      await _pump(tester, repository, adultOnly: true);
      final AppLocalizations words = AppLocalizations.of(
        tester.element(find.byType(TvCinemaScreen)),
      );
      await _choose(tester, words.tvCinemaRecent);
      expect(_poster(_adultName), findsOneWidget);
      expect(_poster(_declaredName), findsOneWidget);
      expect(_poster(_ordinaryName), findsNothing);
      expect(repository.recentModes, isNotEmpty);
      expect(repository.recentModes.every((mode) => mode == true), isTrue);

      await _choose(tester, words.tvCinemaSearch);
      await tester.enterText(
          find.byKey(const ValueKey<String>('zuno-touch-cinema-search')),
          'Film');
      await tester.pump(const Duration(milliseconds: 300));
      await _settle(tester);
      expect(repository.searchModes, <bool>[true]);
      expect(_poster(_adultName), findsOneWidget);
      expect(_poster(_declaredName), findsOneWidget);
      expect(_poster(_ordinaryName), findsNothing);
      expect(repository.loadedCategories, <String>['general']);
      expect(tester.takeException(), isNull);
      await _unmount(tester, repository);
    }, variant: _android);
  }

  test(
      'le signal découvert dans la fiche suit la lecture, la reprise '
      'et le téléchargement', () {
    final CinemaTitle neutral = _Catalog(CinemaKind.movie).fixtureTitles.first;
    final VodPlayItem item = VodPlayItem.movie(neutral,
        details: const CinemaDetails(declaredAdult: true));
    expect(item.title, neutral.name);
    expect(item.categoryKey, neutral.categoryKey);
    expect(item.declaredAdult, isTrue);
    expect(item.isAllowedInPlay, isFalse);
    expect(item.toVodMovie().declaredAdult, isTrue);
    final WatchEntry saved = item.toEntry(posMs: 40000, durMs: 600000);
    expect(saved.declaredAdult, isTrue);
    expect(VodPlayItem.entry(saved).isAllowedInPlay, isFalse);
  });

  test('le signal épisode ou fiche série reste attaché à la reprise série', () {
    final CinemaTitle series = _Catalog(CinemaKind.series).fixtureTitles.first;
    CinemaEpisode episode({bool declaredAdult = false}) => CinemaEpisode(
          id: 'p1:e:1',
          remoteId: '1',
          seriesId: series.id,
          season: 1,
          number: 1,
          title: 'Épisode premier',
          streamUrl: 'https://example.invalid/episode.mp4',
          containerExt: 'mp4',
          declaredAdult: declaredAdult,
        );
    for (final VodPlayItem item in <VodPlayItem>[
      VodPlayItem.episode(episode(declaredAdult: true), series),
      VodPlayItem.episode(episode(), series,
          details: const CinemaDetails(declaredAdult: true)),
    ]) {
      final WatchEntry saved = item.toEntry(posMs: 40000, durMs: 600000);
      expect(saved.declaredAdult, isTrue);
      expect(item.toVodMovie().declaredAdult, isTrue);
      final CinemaTitle resumed = seriesTitleFromEntry(saved);
      expect(resumed.id, series.id);
      expect(resumed.categoryKey, series.categoryKey);
      expect(resumed.declaredAdult, isTrue);
      expect(resumed.isAdult, isTrue);
      expect(VodPlayItem.entry(saved).isAllowedInPlay, isFalse);
    }
  });

  test('un signal adulte ajouté conserve l’épisode et ne peut être retiré', () {
    const VodPlayItem original = VodPlayItem(
      id: 'p4:e:72',
      isEpisode: true,
      title: 'Une série',
      subtitle: 'S3 · E2 · Le voyage',
      url: 'https://example.invalid/series/72.mkv',
      posterUrl: 'https://example.invalid/poster.jpg',
      containerExt: 'mkv',
      sourceKey: 'p4',
      remoteId: '72',
      categoryKey: 'collection',
      seriesId: 'p4:s:9',
      season: 3,
      episode: 2,
    );
    expect(identical(original.withDeclaredAdult(false), original), isTrue);
    final VodPlayItem protected = original.withDeclaredAdult(true);
    expect(protected.declaredAdult, isTrue);
    expect(original.declaredAdult, isFalse);
    expect(protected.id, original.id);
    expect(protected.url, original.url);
    expect(protected.categoryKey, original.categoryKey);
    expect(protected.sourceKey, original.sourceKey);
    expect(protected.remoteId, original.remoteId);
    expect(protected.title, original.title);
    expect(protected.subtitle, original.subtitle);
    expect(protected.posterUrl, original.posterUrl);
    expect(protected.containerExt, original.containerExt);
    expect(protected.isEpisode, isTrue);
    expect(protected.seriesId, original.seriesId);
    expect(protected.season, original.season);
    expect(protected.episode, original.episode);
    expect(identical(protected.withDeclaredAdult(false), protected), isTrue);
    expect(identical(protected.withDeclaredAdult(true), protected), isTrue);
    final WatchEntry resumed = protected
        .withDeclaredAdult(false)
        .toEntry(posMs: 91000, durMs: 1800000);
    expect(resumed.posMs, 91000);
    expect(resumed.durMs, 1800000);
    expect(resumed.seriesId, original.seriesId);
    expect(resumed.season, 3);
    expect(resumed.episode, 2);
    expect(resumed.declaredAdult, isTrue);
    expect(VodPlayItem.entry(resumed).isAllowedInPlay, isFalse);
  });
}
