import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/simple_home/data/home_layout_repository.dart';
import 'package:tv_king/features/tv/core/tv_focusable.dart';
import 'package:tv_king/features/tv/data/home_shelves.dart';
import 'package:tv_king/features/tv/data/tv_home_layout.dart';
import 'package:tv_king/features/tv/presentation/tv_home_rails.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

HomeSectionConfig section(
  String key, {
  int position = 0,
  bool enabled = true,
  String ribbon = '',
  bool featured = false,
}) =>
    HomeSectionConfig(
      key: key,
      position: position,
      enabled: enabled,
      ribbon: ribbon,
      featured: featured,
    );

Channel channel(String id) => Channel(
      id: id,
      name: id,
      category: 'FR',
      streamUrl: 'https://example.invalid/$id',
      isLive: true,
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  final model = HomeShelfModel(
    resume: <Channel>[channel('Recent fixture')],
    favorites: <Channel>[channel('Favorite fixture')],
  );

  test('sans réglage, mêmes rangées et même ordre', () {
    const keys = <String>[
      'reminders',
      'recent',
      'continue-watching',
      'favorites',
      'popular',
    ];
    expect(tvHomeSectionOrder(keys, const {}), keys);
    expect(hasVisibleTvHomeShelves(model, const {}), isTrue);
  });

  test(
    'ordre appliqué entre rangées compatibles, rappels et films conservés',
    () {
      expect(
        tvHomeSectionOrder(
          <String>[
            'reminders',
            'recent',
            'continue-watching',
            'favorites',
            'popular',
          ],
          <String, HomeSectionConfig>{
            'recent': section('recent', position: 6),
            'favorites': section('favorites', position: 1),
            'cinema': section('cinema', enabled: false),
            'popular': section('popular', enabled: false),
          },
        ),
        <String>[
          'reminders',
          'favorites',
          'continue-watching',
          'recent',
          'popular',
        ],
      );
    },
  );

  test('masquage réel sans inventer une section absente', () {
    final layout = <String, HomeSectionConfig>{
      'recent': section('recent', enabled: false),
      'favorites': section('favorites', enabled: false),
      'sport': section('sport'),
    };
    expect(
      tvHomeSectionOrder(<String>['recent', 'favorites'], layout),
      isEmpty,
    );
    expect(hasVisibleTvHomeShelves(model, layout), isFalse);
    expect(
      hasVisibleTvHomeShelves(
        HomeShelfModel(popular: <Channel>[channel('Popular fixture')]),
        layout,
      ),
      isTrue,
    );
  });

  test('le focus quitte une rangée masquée sans lancer une chaîne', () {
    final layout = <String, HomeSectionConfig>{
      'recent': section('recent', enabled: false),
    };
    expect(
      visibleTvInitialShelf(HomeShelfKind.resume, model, layout),
      HomeShelfKind.favorites,
    );
    expect(visibleTvInitialShelf(null, model, layout), isNull);
    expect(
      visibleTvInitialShelf(HomeShelfKind.resume, model, {
        ...layout,
        'favorites': section('favorites', enabled: false),
      }),
      isNull,
    );
  });

  final recent = find.byKey(const ValueKey<String>('home-section-recent'));
  final favorites = find.byKey(
    const ValueKey<String>('home-section-favorites'),
  );

  Future<void> show(
    WidgetTester tester,
    Map<String, HomeSectionConfig> layout, {
    void Function(List<Channel>, int)? onPlay,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TvHomeRails(
            model: model,
            nowMs: 0,
            layout: layout,
            initialShelf: HomeShelfKind.resume,
            onPlayChannel: onPlay ?? (_, __) {},
            onPlayContinue: (_) {},
            onPlayReminder: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ordre, ruban et vedette arrivent dans les vraies rangées', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await show(tester, const {});
    expect(
      tester.getTopLeft(recent).dy,
      lessThan(tester.getTopLeft(favorites).dy),
    );
    await show(tester, <String, HomeSectionConfig>{
      'recent': section('recent', position: 2),
      'favorites': section(
        'favorites',
        position: 0,
        ribbon: 'VIP',
        featured: true,
      ),
    });
    expect(
      tester.getTopLeft(favorites).dy,
      lessThan(tester.getTopLeft(recent).dy),
    );
    expect(
      find.descendant(of: favorites, matching: find.text('VIP')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: favorites, matching: find.byIcon(Icons.star_rounded)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rangée masquée retirée, sélection conservée sur les favoris', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final played = <String>[];
    await show(
        tester,
        <String, HomeSectionConfig>{
          'recent': section('recent', enabled: false),
        },
        onPlay: (shelf, index) => played.add(shelf[index].id));
    expect(recent, findsNothing);
    expect(favorites, findsOneWidget);
    expect(played, isEmpty);
    final card = tester.widget<TvFocusBuilder>(
      find
          .descendant(of: favorites, matching: find.byType(TvFocusBuilder))
          .first,
    );
    expect(card.autofocus, isTrue);
    await tester.tap(find.text(model.favorites.single.cleanName));
    await tester.pumpAndSettle();
    expect(played, <String>[model.favorites.single.id]);
    expect(tester.takeException(), isNull);
  });
}
