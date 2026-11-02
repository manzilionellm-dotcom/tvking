import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/simple_home/data/home_layout_repository.dart';
import 'package:tv_king/features/tv/data/home_shelves.dart';
import 'package:tv_king/features/tv/data/tv_home_genres.dart';
import 'package:tv_king/features/tv/data/tv_home_layout.dart';
import 'package:tv_king/features/tv/presentation/tv_home_rails.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

Channel channel(String id, String category, {bool live = true}) => Channel(
    id: id,
    name: id,
    category: category,
    streamUrl: 'https://fixture.invalid/$id',
    isLive: live);
HomeSectionConfig cfg(String key, int position, {bool enabled = true}) =>
    HomeSectionConfig(
        key: key,
        position: position,
        enabled: enabled,
        ribbon: 'PANEL-$key',
        featured: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  final fixture = <Channel>[
    channel('Football', 'Sports'),
    channel('Concert', 'Music'),
    channel('Journal', 'News'),
    channel('Cartoon', 'Kids'),
    channel('Local', 'Divers'),
    channel('Film direct', 'Cinema'),
    channel('Interdit', 'Adult movies'),
    channel('VOD', 'Cinema', live: false),
  ];
  test(
      'les six genres utilisent uniquement les chaînes importées, sans adulte ni VOD',
      () async {
    final shelves = await tvGenreShelves(fixture);
    expect(shelves.keys.toSet(), kTvGenreHomeSections.toSet());
    expect(shelves['sport']!.single.id, 'Football');
    expect(shelves['cinema']!.single.id, 'Film direct');
    expect(shelves.values.expand((channels) => channels).map((c) => c.id),
        isNot(contains(anyOf('Interdit', 'VOD'))));
    expect(
        hasVisibleTvHomeShelves(const HomeShelfModel(), const {},
            genreShelves: shelves),
        isTrue);
  });
  test(
      'un id dupliqué ne remplace jamais la carte classée par du VOD ou adulte',
      () async {
    final safe = channel('Chaîne', 'Kids');
    final forbidden = channel('Chaîne', 'Adult');
    final vod = channel('Chaîne', 'Cinema', live: false);
    final shelves = await tvGenreShelves([vod, safe, forbidden]);
    expect(shelves.keys, ['kids']);
    expect(shelves['kids']!.single, same(safe));
    expect(await tvGenreShelves([forbidden, safe, vod]), isEmpty);
  });
  test(
      'grosses listes : isolate, huit cartes au maximum et aucune URL inventée',
      () async {
    final input =
        List<Channel>.generate(550, (i) => channel('Sport-$i', 'Sports'));
    final shelves = await tvGenreShelves(input);
    expect(shelves['sport'], hasLength(kHomeShelfMax));
    expect(shelves['sport']!.first, same(input.first));
    expect(shelves['sport']!.last.id, 'Sport-7');
  });
  test('toutes les clés respectent ordre et visibilité, reprises VOD intactes',
      () {
    final keys = <String>[
      'recent',
      'continue-watching',
      'favorites',
      ...kTvGenreHomeSections
    ];
    final settings = <String, HomeSectionConfig>{
      for (int i = 0; i < kDefaultHomeOrder.length; i++)
        kDefaultHomeOrder[i]: cfg(kDefaultHomeOrder[i], 7 - i),
    };
    final result = tvHomeSectionOrder(keys, settings);
    expect(result[1], 'continue-watching');
    expect(result.where((k) => k != 'continue-watching'),
        kDefaultHomeOrder.reversed);
    settings['cinema'] = cfg('cinema', 0, enabled: false);
    expect(tvHomeSectionOrder(keys, settings), isNot(contains('cinema')));
    expect(tvHomeSectionOrder(keys, settings), contains('continue-watching'));
  });
  testWidgets(
      'vraies cartes cinéma/sport : ordre, ruban, masquage et sélection explicite',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selected;
    final shelves = await tvGenreShelves(fixture);
    Future<void> show(bool cinemaEnabled) async {
      await tester.pumpWidget(MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
              body: TvHomeRails(
                  model: const HomeShelfModel(),
                  nowMs: 0,
                  genreShelves: {
                    'sport': shelves['sport']!,
                    'cinema': shelves['cinema']!
                  },
                  layout: {
                    'cinema': cfg('cinema', 0, enabled: cinemaEnabled),
                    'sport': cfg('sport', 1)
                  },
                  onPlayChannel: (list, index) => selected = list[index].id,
                  onPlayContinue: (_) {},
                  onPlayReminder: (_) {}))));
      await tester.pumpAndSettle();
    }

    await show(true);
    final cinema = find.byKey(const ValueKey<String>('home-section-cinema'));
    final sport = find.byKey(const ValueKey<String>('home-section-sport'));
    expect(tester.getTopLeft(cinema).dy, lessThan(tester.getTopLeft(sport).dy));
    expect(find.text('PANEL-cinema'), findsOneWidget);
    expect(selected, isNull);
    await tester.tap(find.text(shelves['cinema']!.single.cleanName));
    expect(selected, 'Film direct');
    await show(false);
    expect(cinema, findsNothing);
    expect(sport, findsOneWidget);
  });
}
