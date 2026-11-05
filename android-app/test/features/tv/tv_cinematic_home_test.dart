import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/cinema/data/watch_progress.dart';
import 'package:tv_king/features/followed/domain/show_clock.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/presentation/tv_cinematic_home.dart';
import 'package:tv_king/features/tv/presentation/tv_glass.dart';
import 'package:tv_king/features/tv/presentation/tv_tonight.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

Channel _ch(String id, String name, {String? logo}) => Channel(
      id: id,
      name: name,
      category: 'Général',
      streamUrl: 'http://example.test/$id',
      isLive: true,
      logoUrl: logo,
    );

WatchEntry _watch(String id, String title, {String? poster}) => WatchEntry(
      id: id,
      isEpisode: false,
      title: title,
      streamUrl: 'http://example.test/vod/$id',
      posMs: 60000,
      durMs: 5400000,
      updatedAt: 1,
      posterUrl: poster,
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('4K et la note n\'apparaissent que s\'ils sont dans la source', () {
    expect(streamQualityLabel('Info 4K HDR'), '4K HDR');
    expect(streamQualityLabel('Docu UHD'), '4K');
    expect(streamQualityLabel('Film HDR'), 'HDR');
    expect(streamQualityLabel('VIP 9.9'), isNull);
    expect(ratingLabel(8.4), '8.4');
    expect(ratingLabel(null), isNull);
    expect(ratingLabel(99), isNull);
    expect(
      joinCrispMeta(duration: '90 min', quality: streamQualityLabel('x 4K')),
      '90 min · 4K',
    );
  });

  test('le flou est réservé aux box au-dessus de 2 Go', () {
    expect(tvGlassBlurAllowed(totalMb: 1024, lowRam: false), isFalse);
    expect(tvGlassBlurAllowed(totalMb: 2048, lowRam: false), isFalse);
    expect(tvGlassBlurAllowed(totalMb: 4096, lowRam: true), isFalse);
    expect(tvGlassBlurAllowed(totalMb: 0, lowRam: false), isFalse);
    expect(tvGlassBlurAllowed(totalMb: 3072, lowRam: false), isTrue);
  });

  test('le héros reprend la jaquette déjà enregistrée, sans en inventer', () {
    final TonightBoard board = composeTonight(
      watching: <WatchEntry>[
        _watch('f1', 'Soirée', poster: 'https://cdn.example/a.jpg'),
      ],
      favorites: <Channel>[_ch('c1', 'Info', logo: 'https://cdn.example/logo.png')],
      popular: const <Channel>[],
      resume: const <Channel>[],
      guide: const <GuideSlot>[],
      reminders: const [],
      also: const <Channel>[],
      nowMs: 0,
      channelsById: const <String, Channel>{},
    );
    expect(board.hero?.title, 'Soirée');
    expect(board.hero?.artworkUrl, 'https://cdn.example/a.jpg');
    expect(board.hero?.meta, '90 min');
    expect(board.recommendations.single.title, 'Info');
    expect(board.recommendations.single.artworkUrl, 'https://cdn.example/logo.png');
  });

  test('sans jaquette, le héros du guide n\'a pas d\'image inventée', () {
    final Channel info = _ch('c1', 'Info');
    final TonightBoard board = composeTonight(
      watching: const <WatchEntry>[],
      favorites: const <Channel>[],
      popular: <Channel>[info],
      resume: const <Channel>[],
      guide: const <GuideSlot>[
        GuideSlot(
          channelId: 'c1',
          channelName: 'Info',
          title: 'Journal',
          startMs: 0,
          stopMs: 3600000,
          catchupDeclared: false,
        ),
      ],
      reminders: const [],
      also: const <Channel>[],
      nowMs: 1000,
      channelsById: <String, Channel>{'c1': info},
    );
    expect(board.hero?.title, 'Journal');
    expect(board.hero?.artworkUrl, isNull);
    expect(board.heroDetail, 'Info');
    expect(board.discover, isEmpty);
  });

  test('une chaîne déjà à gauche ne revient pas à droite', () {
    final Channel a = _ch('a', 'Une');
    final Channel b = _ch('b', 'Deux');
    final TonightBoard board = composeTonight(
      watching: const <WatchEntry>[],
      favorites: <Channel>[a],
      popular: <Channel>[a, b],
      resume: const <Channel>[],
      guide: const <GuideSlot>[],
      reminders: const [],
      also: const <Channel>[],
      nowMs: 0,
      channelsById: const <String, Channel>{},
    );
    expect(board.hero?.title, 'Une');
    expect(board.recommendations.single.title, 'Deux');
    expect(board.discover, isEmpty);
  });

  testWidgets('l\'accueil verre montre le titre réel et le Direct',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final Channel info = _ch('c1', 'Info');
    final TonightBoard board = composeTonight(
      watching: const <WatchEntry>[],
      favorites: const <Channel>[],
      popular: const <Channel>[],
      resume: const <Channel>[],
      guide: const <GuideSlot>[
        GuideSlot(
          channelId: 'c1',
          channelName: 'Info',
          title: 'Journal du soir',
          startMs: 0,
          stopMs: 3600000,
          catchupDeclared: false,
        ),
      ],
      reminders: const [],
      also: const <Channel>[],
      nowMs: 1000,
      channelsById: <String, Channel>{'c1': info},
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          extensions: const <ThemeExtension<dynamic>>[TvAppTokens()],
        ),
        home: Scaffold(
          body: TvCinematicHome(
            board: board,
            blur: false,
            onPlay: (_) {},
            onLive: () {},
            onFilms: () {},
            onSeries: () {},
            onServer: () {},
            onSettings: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Journal du soir'), findsOneWidget);
    expect(find.text('Direct'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
