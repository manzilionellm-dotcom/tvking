// Les entrées Guide/Catégories normales ne montrent jamais les listes
// Adultes, ni leurs programmes, compteurs, logos ou aperçus vidéo.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/channels/presentation/category_section_screen.dart';
import 'package:tv_king/features/channels/presentation/widgets/channel_card.dart';
import 'package:tv_king/features/channels/presentation/widgets/channel_logo.dart';
import 'package:tv_king/features/channels/presentation/widgets/compact_channel_row.dart';
import 'package:tv_king/features/epg/data/epg_repository.dart';
import 'package:tv_king/features/epg/domain/epg_program.dart';
import 'package:tv_king/features/epg/presentation/tv_guide_screen.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/tv/presentation/tv_epg_preview_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

const _normalId = 'normal-guide-public';
const _adultNameId = 'normal-guide-adult-name';
const _adultCategoryId = 'normal-guide-adult-category';

EpgProgram _program(String id, String title) => EpgProgram(
      channelId: id,
      title: title,
      startTime: DateTime.now()
          .subtract(const Duration(minutes: 10))
          .millisecondsSinceEpoch,
      stopTime: DateTime.now()
          .add(const Duration(minutes: 40))
          .millisecondsSinceEpoch,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = PlaylistRepository.instance;
  late Database db;

  setUpAll(() async {
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final entry in <String, String>{
      'Inter_regular': 'Inter-Regular.ttf',
      'Inter_500': 'Inter-Medium.ttf',
      'Inter_600': 'Inter-SemiBold.ttf',
      'Inter_700': 'Inter-Bold.ttf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(rootBundle.load('assets/fonts/${entry.value}'));
      await loader.load();
    }
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    PlaylistDatabase.debugFilePath = inMemoryDatabasePath;
    db = await PlaylistDatabase.instance.database;
    await EpgRepository.instance.initialize();
    PlaylistRepository.mergeAllPlaylists = true;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ProfileRepository.instance.resetForTesting(ProfileCatalog.fresh());
    await ParentalControls.instance.load();
    await db.delete('channels');
    await db.delete('playlists');
    await EpgRepository.instance.clearAll();
    await repo.initialize();
  });

  tearDownAll(() async {
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    PlaylistRepository.mergeAllPlaylists = false;
  });

  Future<void> seed({bool publish = true}) async {
    final int id = await db.insert('playlists', <String, Object?>{
      'name': 'Fixture',
      'type': 'm3u',
      'created_at': 1,
      'is_active': 1,
      'channel_count': 3,
    });
    for (final item in <({String id, String name, String category})>[
      (id: _adultNameId, name: 'DORCEL Fixture', category: 'FR'),
      (id: _normalId, name: 'Journal Public', category: 'Actualités'),
      (id: _adultCategoryId, name: 'Canal Secret', category: 'FR | XXX'),
    ]) {
      await db.insert('channels', <String, Object?>{
        'playlist_id': id,
        'external_id': item.id,
        'name': item.name,
        'category': item.category,
        'stream_url': 'https://fixture.invalid/${item.id}',
        'is_live': 1,
      });
      final program = _program(item.id,
          item.id == _normalId ? 'Programme public' : 'Programme réservé');
      await db.insert('epg_programs', <String, Object?>{
        'channel_id': item.id,
        'title': program.title,
        'start_time': program.startTime,
        'stop_time': program.stopTime,
      });
    }
    if (publish) await repo.initialize();
  }

  // Le badge Live pulse sans fin : pumpAndSettle attendrait une animation
  // qui ne doit justement jamais s'arrêter. On draine les vraies lectures
  // SQLite puis les transitions bornées, en gardant toutes les assertions.
  Future<void> drain(WidgetTester tester) async {
    for (int frame = 0; frame < 3; frame++) {
      await tester.runAsync(() async {
        await db.rawQuery('SELECT 1');
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: screen,
    ));
    await tester.runAsync(GoogleFonts.pendingFonts);
    await drain(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
      'aperçu EPG normal : aucun programme ni vidéo adulte, mode enfants coupé',
      (tester) async {
    await seed();
    final List<String> loaded = <String>[];
    final List<String> previews = <String>[];
    expect(ParentalControls.instance.kidsMode.value, isFalse);
    await show(
        tester,
        Scaffold(
            body: TvEpgPreviewScreen(
          channels: repo.currentChannels,
          loadWindow: (String id) async {
            loaded.add(id);
            return TvEpgWindow(now: _program(id, 'Fenêtre publique'));
          },
          preview: (Channel channel) {
            previews.add(channel.id);
            return const Text('Aperçu public');
          },
        )));
    expect(loaded, isNotEmpty);
    expect(loaded.every((id) => id == _normalId), isTrue);
    expect(previews.every((id) => id == _normalId), isTrue);
    expect(find.text('Canal Secret'), findsNothing);
    expect(find.text('Fenêtre publique'), findsOneWidget);
    await close(tester);
  });

  testWidgets(
      'aperçu : retrait de la chaîne publique laisse vide même avec réponse EPG tardive',
      (tester) async {
    await seed();
    final pending = Completer<TvEpgWindow>();
    await show(
        tester,
        Scaffold(
            body: TvEpgPreviewScreen(
          loadWindow: (_) => pending.future,
          preview: (Channel channel) => Text('preview:${channel.id}'),
        )));
    expect(find.text('preview:$_normalId'), findsOneWidget);
    await db.delete('channels',
        where: 'external_id = ?', whereArgs: <Object>[_normalId]);
    await repo.initialize();
    await drain(tester);
    pending.complete(TvEpgWindow(now: _program(_normalId, 'Ancien programme')));
    await drain(tester);
    expect(find.text('preview:$_normalId'), findsNothing);
    expect(find.text('Ancien programme'), findsNothing);
    expect(find.text('Canal Secret'), findsNothing);
    expect(repo.currentChannels, hasLength(2),
        reason: 'inventaire conservé pour espace Adultes');
    await close(tester);
  });

  for (final bool cached in <bool>[true, false]) {
    testWidgets('guide grille filtre chaînes/programmes (cache=$cached)',
        (tester) async {
      await seed(publish: cached);
      await show(tester, const TvGuideScreen());
      final logos = tester.widgetList<ChannelLogo>(find.byType(ChannelLogo));
      expect(logos, isNotEmpty);
      expect(logos.every((logo) => logo.channel.id == _normalId), isTrue);
      expect(find.text('Programme réservé'), findsNothing);
      expect(find.text('Canal Secret'), findsNothing);
      await db.delete('channels',
          where: 'external_id = ?', whereArgs: <Object>[_normalId]);
      await repo.initialize();
      await drain(tester);
      expect(find.byType(ChannelLogo), findsNothing);
      expect(find.text('Programme réservé'), findsNothing);
      await close(tester);
    });

    testWidgets(
        'catégories filtre lignes, grille, compteurs et recherche (cache=$cached)',
        (tester) async {
      await seed(publish: cached);
      await show(tester, const CategorySectionScreen(title: 'Direct'));
      final rows =
          tester.widgetList<CompactChannelRow>(find.byType(CompactChannelRow));
      expect(rows, hasLength(1));
      expect(rows.single.channel.id, _normalId);
      expect(find.text('1 / 1'), findsOneWidget);
      expect(find.textContaining('XXX'), findsNothing);
      expect(find.text('Canal Secret'), findsNothing);
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await drain(tester);
      final cards = tester.widgetList<ChannelCard>(find.byType(ChannelCard));
      expect(cards, hasLength(1));
      expect(cards.single.channel.id, _normalId);
      await tester.enterText(find.byType(TextField), 'Secret');
      await drain(tester);
      expect(find.byType(ChannelCard), findsNothing);
      expect(find.text('0 / 1'), findsOneWidget);
      await close(tester);
    });
  }

  testWidgets(
      'lien direct vers le filtre Adulte normal ne contourne pas l’espace dédié',
      (tester) async {
    await seed();
    await show(
        tester,
        const CategorySectionScreen(
            title: 'Direct', genreFilter: ChannelGenre.adult));
    expect(find.byType(CompactChannelRow), findsNothing);
    expect(find.byType(ChannelCard), findsNothing);
    expect(find.text('Canal Secret'), findsNothing);
    await close(tester);
  });
}
