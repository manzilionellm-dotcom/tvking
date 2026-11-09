import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/box_memory_budget.dart';
import 'package:tv_king/core/theme/app_colors.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/core/tv_ambient_director.dart';
import 'package:tv_king/features/tv/core/tv_look.dart';
import 'package:tv_king/features/tv/presentation/tv_cinematic_home.dart';
import 'package:tv_king/features/tv/presentation/tv_stealth_chrome.dart';
import 'package:tv_king/features/tv/presentation/tv_stealth_home.dart';
import 'package:tv_king/features/tv/presentation/tv_tonight.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

TonightPiece piece(
  String id,
  String name, {
  String category = 'Info',
  String? art,
}) =>
    TonightPiece(
      title: name,
      artworkUrl: art,
      meta: streamQualityLabel(name) ?? '',
      channel: Channel(
        id: id,
        name: name,
        category: category,
        streamUrl: 'https://example.test/$id',
        isLive: true,
      ),
    );

Widget stage({
  required TonightBoard board,
  required ValueChanged<TonightPiece> play,
  VoidCallback? live,
  VoidCallback? settings,
  bool blur = false,
  bool reduced = false,
  Locale locale = const Locale('fr'),
  double textScale = 1,
  GlobalKey? capture,
}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.stealthBlack,
        extensions: const <ThemeExtension<dynamic>>[TvAppTokens(ghost: true)],
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduced,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: RepaintBoundary(
          key: capture,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 24, 40, 20),
            child: Column(
              children: <Widget>[
                TvStealthHeader(
                  profileName: 'Profil 1',
                  profileIcon: Icons.person_outline,
                  profileColor: AppColors.stealthIce,
                  onProfile: () {},
                  onSearch: () {},
                  searchLabel: 'Recherche',
                  time: '21:56',
                  date: 'lun. 9 nov.',
                  networkIcon: Icons.wifi,
                  greeting: 'Aperçu de démonstration · Stockholm',
                  status: 'Mode démonstration',
                ),
                Expanded(
                  child: TvCinematicHome(
                    board: board,
                    blur: blur,
                    onPlay: play,
                    onLive: live ?? () {},
                    onFilms: () {},
                    onSeries: () {},
                    onServer: () {},
                    onSettings: settings ?? () {},
                  ),
                ),
                const TvStealthFooter(
                  activationLabel: 'Code de démonstration',
                  activationCode: 'XX:XX:XX:XX:XX:XX',
                  status: 'Démonstration',
                  statusColor: AppColors.stealthMuted,
                  source: 'Catalogue de démonstration',
                ),
              ],
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Le moteur de tests ne charge pas les icônes automatiquement.
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    BoxMemoryBudget.debugTier = BoxRamTier.balanced;
    TvAmbientDirector.instance.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  tearDown(() => BoxMemoryBudget.debugTier = null);

  test('Noir Fantôme par défaut, choix Confort sauvegardé conservé', () async {
    await TvLook.instance.load();
    expect(TvLook.instance.ghost, isTrue);
    await TvLook.instance.choose(TvLookChoice.comfort);
    await TvLook.instance.load();
    expect(TvLook.instance.ghost, isFalse);
    TvLook.instance.debugChoose(TvLookChoice.ghost);
  });

  test('qualité déclarée uniquement, le halo distingue les catégories', () {
    expect(streamQualityLabel('Actualités HD'), 'HD');
    expect(streamQualityLabel('Film 1080p'), 'FHD');
    expect(streamQualityLabel('Cinéma Premium'), isNull);
    expect(
      stealthAmbientFor(piece('s', 'Sport', category: 'Sports')),
      isNot(stealthAmbientFor(piece('m', 'Cinéma', category: 'Films'))),
    );
  });

  testWidgets('OK lit uniquement le contenu du hero, jamais au focus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final hero = piece('journal', 'Journal du soir');
    final calls = <TonightPiece>[];
    await tester.pumpWidget(
      stage(
        board: TonightBoard(hero: hero),
        play: calls.add,
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    final viewport = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const PageStorageKey<String>('stealth-home-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(viewport.position.pixels, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(calls, <TonightPiece>[hero]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sans source le D-pad atteint Direct puis Réglages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var live = 0, settings = 0;
    await tester.pumpWidget(
      stage(
        board: const TonightBoard(),
        play: (_) {},
        live: () => live++,
        settings: () => settings++,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stealth-hero-play')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(live, 1);
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(settings, 1);
  });

  testWidgets('D-pad : la dernière carte hors écran reste accessible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final hero = piece('hero', 'Le programme du soir');
    final items = List.generate(8, (i) => piece('card-$i', 'Chaîne $i'));
    final calls = <TonightPiece>[];
    await tester.pumpWidget(stage(
      board: TonightBoard(hero: hero, recommendations: items),
      play: calls.add,
    ));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    for (var i = 0; i < 7; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(calls, <TonightPiece>[items.last]);
    final card = tester.getRect(find.text(items.last.title));
    expect(card.right, lessThanOrEqualTo(1280));
    expect(card.bottom, lessThanOrEqualTo(720));
    for (var i = 0; i < 7; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(calls.last, hero);
    expect(tester.takeException(), isNull);
  });

  for (final locale in <Locale>[const Locale('fr'), const Locale('ar')]) {
    testWidgets(
      'petit écran / texte agrandi / ${locale.languageCode} sans débordement',
      (tester) async {
        tester.view.physicalSize = const Size(960, 540);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final items = List.generate(
          8,
          (i) => piece('$i', 'Actualités internationales $i HD'),
        );
        final board = TonightBoard(
          hero: items.first,
          heroDetail: 'Un programme avec un titre très long',
          recommendations: items.skip(1).toList(),
          discover: items,
        );
        await tester.pumpWidget(
          stage(
            board: board,
            play: (_) {},
            locale: locale,
            textScale: 1.5,
            reduced: true,
            blur: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BackdropFilter), findsNothing);
        expect(tester.takeException(), isNull);
        // Rejoindre une carte en bas oblige le scroll vertical et horizontal.
        for (var i = 0; i < 5; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('halo désactivable, aperçu réel sans images disponibles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final hero = piece('news', 'Le monde ce soir');
    final items = <TonightPiece>[
      piece('sport', 'Sports HD', category: 'Sports'),
      piece('cine', 'Cinéma 4K', category: 'Films'),
      piece('doc', 'Découverte'),
      piece('music', 'Musique'),
      piece('kids', 'Jeunesse'),
    ];
    await tester.pumpWidget(
      stage(
        board: TonightBoard(
          hero: hero,
          heroDetail: 'Votre sélection',
          recommendations: items,
          discover: items.reversed.toList(),
        ),
        play: (_) {},
        capture: key,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('DOLBY ATMOS'), findsNothing);
    expect(tester.takeException(), isNull);
    final directory = Platform.environment['STEALTH_CAPTURE_DIR'];
    if (directory != null) {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(directory).createSync(recursive: true);
        File('$directory/zuno-noir-fantome-apercu.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await TvAmbientDirector.instance.choose(TvAmbientChoice.off);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stealth-ambient')), findsNothing);
  });
}
