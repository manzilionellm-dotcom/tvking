import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/theme/app_colors.dart';
import 'package:tv_king/core/theme/remote_palette.dart';
import 'package:tv_king/features/tv/core/tv_tokens.dart';
import 'package:tv_king/features/theme/data/remote_theme_repository.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/simple_home/data/home_sections.dart';
import 'package:tv_king/features/simple_home/data/home_layout_repository.dart';
import 'package:tv_king/features/country_home/data/featured_repository.dart';

Channel channel(String id, String name, String category) => Channel(
    id: id,
    name: name,
    category: category,
    streamUrl: 'https://example.invalid/video',
    isLive: true);

class Probe extends StatefulWidget {
  const Probe({super.key});
  @override
  State<Probe> createState() => ProbeState();
}

class ProbeState extends State<Probe> {
  int builds = 0;
  @override
  Widget build(BuildContext context) {
    RemotePalette.watch(context);
    builds++;
    return ColoredBox(
        color: AppColors.background,
        child: Text('probe', style: TextStyle(color: TvTokens.text)));
  }
}

void main() {
  setUp(() {
    RemotePalette.instance.apply(background: 'dark');
    HomeLayoutRepository.instance.applySnapshot(<Object>[]);
    FeaturedRepository.instance.applySnapshot(<String, Object>{});
  });
  tearDown(() {
    RemotePalette.instance.apply(background: 'dark');
    HomeLayoutRepository.instance.applySnapshot(<Object>[]);
    FeaturedRepository.instance.applySnapshot(<String, Object>{});
  });
  testWidgets(
      'light/accent events repaint mobile and TV tokens without remount',
      (WidgetTester tester) async {
    final GlobalKey<ProbeState> key = GlobalKey<ProbeState>();
    await tester.pumpWidget(AnimatedBuilder(
        animation: RemotePalette.instance,
        builder: (BuildContext context, Widget? child) => MaterialApp(
            theme: RemotePalette.instance.decorate(ThemeData.dark()),
            home: Probe(key: key))));
    final ProbeState initial = key.currentState!;
    final Color old = AppColors.background, oldTv = TvTokens.bg;
    RemoteThemeRepository.applySnapshot(
        <String, Object>{'bg': 'light', 'accent': '#126AC4'});
    await tester.pumpAndSettle();
    expect(identical(key.currentState, initial), isTrue);
    expect(initial.builds, greaterThan(1));
    expect(AppColors.background, isNot(old));
    expect(TvTokens.bg, isNot(oldTv));
    expect(TvTokens.gold, const Color(0xFF126AC4));
    expect(AppColors.accent, TvTokens.gold);
    expect(AppColors.textPrimary, TvTokens.text);
    expect(
        tester
            .widget<ColoredBox>(find.descendant(
                of: find.byKey(key), matching: find.byType(ColoredBox)))
            .color,
        AppColors.background);
    RemoteThemeRepository.applySnapshot(
        <String, Object>{'bg': 'dark', 'accent': ''});
    await tester.pumpAndSettle();
    expect(AppColors.background, old);
    expect(TvTokens.bg, oldTv);
    expect(RemotePalette.instance.accent, isNull);
  });
  test('invalid remote accent never overwrites the local choice', () {
    RemoteThemeRepository.applySnapshot(
        <String, Object>{'bg': 'bogus', 'accent': 'invalid'});
    expect(RemotePalette.instance.light, isFalse);
    expect(RemotePalette.instance.accent, isNull);
  });
  test('layout snapshot orders, hides, ribbons and promotes real home sections',
      () {
    final HomeLayoutRepository layout = HomeLayoutRepository.instance;
    layout.applySnapshot(<Object>[
      <String, Object>{
        'key': 'cinema',
        'position': 0,
        'enabled': true,
        'ribbon': 'NOUVEAU',
        'featured': true
      },
      <String, Object>{'key': 'sport', 'position': 1, 'enabled': false},
      <String, Object>{'key': 'recent', 'position': 2, 'enabled': true},
    ]);
    final List<Channel> channels = <Channel>[
      channel('s', 'Sport TV', 'Sports'),
      channel('m', 'Cinema', 'Movies'),
      channel('v', 'Netflix', 'Series'),
      channel('a', 'XXX', 'Adult')
    ];
    final List<HomeSectionView> sections = buildHomeSections(
        channels: channels,
        order: layout.orderedVisibleKeys(kDefaultHomeOrder),
        config: layout.config,
        favorites: <String>{'s', 'a'},
        recentIds: <String>['v', 'm', 'a']);
    expect(sections.first.key, 'cinema');
    expect(
        sections.first.channels.map((Channel c) => c.id), <String>['m', 'v']);
    expect(sections.first.ribbon, 'NOUVEAU');
    expect(sections.first.promoted, isTrue);
    expect(sections.any((HomeSectionView s) => s.key == 'sport'), isFalse);
    expect(
        sections
            .firstWhere((HomeSectionView s) => s.key == 'recent')
            .channels
            .map((Channel c) => c.id),
        <String>['v', 'm']);
    expect(
        sections
            .firstWhere((HomeSectionView s) => s.key == 'favorites')
            .channels
            .map((Channel c) => c.id),
        <String>['s']);
    expect(
        sections
            .expand((HomeSectionView s) => s.channels)
            .any((Channel c) => c.id == 'a'),
        isFalse);
    layout.applySnapshot(<Object>[]);
    expect(layout.orderedVisibleKeys(kDefaultHomeOrder), kDefaultHomeOrder);
    expect(layout.config('cinema'), isNull);
  });
  test(
      'featured changes and clear notify immediately; matching cannot bypass parental gate',
      () {
    final FeaturedRepository repo = FeaturedRepository.instance;
    int notifications = 0;
    void listener() {
      notifications++;
    }

    repo.addListener(listener);
    addTearDown(() => repo.removeListener(listener));
    repo.applySnapshot(<String, Object>{'name': 'BBC', 'note': 'Live'});
    expect(repo.name, 'BBC');
    expect(notifications, 1);
    repo.applySnapshot(<String, Object>{'name': 'BBC', 'note': 'Live'});
    expect(notifications, 1);
    repo.applySnapshot(<String, Object>{'name': 'Cinema', 'note': 'New'});
    expect(repo.name, 'Cinema');
    expect(notifications, 2);
    repo.applySnapshot(<String, Object>{});
    expect(repo.name, '');
    expect(repo.note, '');
    expect(notifications, 3);
    final List<Channel> channels = <Channel>[
      channel('1', 'BBC World', 'News'),
      channel('2', 'BBC', 'News'),
      channel('3', 'XXX', 'Adult')
    ];
    expect(matchFeatured(channels, 'BBC')?.id, '2');
    expect(matchFeatured(channels, 'World')?.id, '1');
    expect(matchFeatured(channels, 'XXX'), isNull);
    expect(matchFeatured(channels, ''), isNull);
  });
}
