import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Le journal SQL n'est utilisé que dans ce banc de widget.
// ignore: depend_on_referenced_packages
import 'package:sqflite_common/sqflite_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/features/epg/data/epg_repository.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/core/tv_provider_channel_name.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/tv/presentation/tv_live_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_player_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_search_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

import 'fixtures/ahem_fonts.dart';

const names = ['Mire Sport', 'Mire Sport RAW', 'Mire Sport UHD'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final guideReads = <String>[];
  setUpAll(() async {
    AppPlatform.configureZuno(isAndroidHandset: false);
    installAhemFonts();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    // Le journal SQL expérimental est utilisé uniquement par ce banc local.
    // ignore: experimental_member_use
    databaseFactory = SqfliteDatabaseFactoryLogger(
      databaseFactoryFfiNoIsolate,
      options: SqfliteLoggerOptions(log: (event) {
        if (event is SqfliteLoggerSqlEvent &&
            event.sql.contains('FROM epg_programs WHERE channel_id = ? AND start_time <= ?')) {
          guideReads.add((event.arguments as List).first as String);
        }
      }),
    );
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    dir = await Directory.systemTemp.createTemp('direct-variantes-');
    PlaylistDatabase.debugFilePath = '${dir.path}/catalogue.db';
    // Comme au démarrage de ZUNO, la migration des favoris est terminée
    // avant d'ouvrir le lecteur avec la télécommande.
    await FavoritesRepository.instance.initialize();
    await EpgRepository.instance.initialize();
    final server = MockClient((req) async {
      final action = req.url.queryParameters['action'];
      final Object payload = switch (action) {
        'get_live_categories' => [
          {'category_id': '1', 'category_name': 'Sports'},
        ],
        'get_live_streams' => [
          for (final (i, name) in names.indexed)
            {'stream_id': i + 1, 'name': name, 'category_id': '1'},
        ],
        _ => {
          'user_info': {'auth': 1, 'status': 'Active'},
        },
      };
      return http.Response(jsonEncode(payload), 200);
    });
    try {
      await PlaylistRepository.instance.addXtreamPlaylist(
        name: 'Essai',
        serverUrl: 'http://example.invalid',
        username: 'test',
        password: 'test',
        httpClient: server,
      );
    } finally {
      server.close();
    }
    expect(
      PlaylistRepository.instance.currentChannels
          .map((c) => c.streamUrl)
          .toSet(),
      hasLength(3),
    );
  });
  tearDownAll(() async {
    removeAhemFonts();
    AppPlatform.isZuno = false;
    AppPlatform.isTv = false;
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    await dir.delete(recursive: true);
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: screen),
      ),
    );
    await tester.pump();
  }

  test('un libellé de fournisseur vide ou porteur de secrets utilise le texte de repli', () {
    Channel channel(String name) => Channel(
      id: 'id',
      name: name,
      category: 'Sports',
      streamUrl: 'https://example.invalid/fixture',
      isLive: true,
    );
    for (final value in [
      '',
      '  ',
      'https://example.invalid/?username=secret',
      'Sports password=secret',
    ]) {
      expect(tvProviderChannelName(channel(value), 'Chaîne'), 'Chaîne');
    }
    expect(tvProviderChannelName(channel('قناة HD'), 'Chaîne'), 'قناة HD');
  });

  testWidgets('une seule lecture du guide par chaîne ouverte au zapping', (tester) async {
    final channels = PlaylistRepository.instance.currentChannels;
    await tester.runAsync(() async {
      final db = await PlaylistDatabase.instance.database;
      final now = DateTime.now();
      for (final ch in channels) {
        await db.insert('epg_programs', {
          'channel_id': ch.id,
          'start_time': now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
          'stop_time': now.add(const Duration(days: 1)).millisecondsSinceEpoch,
          'title': 'Programme de ${ch.name}',
        });
      }
    });
    guideReads.clear();
    try {
      await show(tester, TvPlayerScreen(channels: channels, startIndex: 0));
      await tester.pump();
      expect(find.textContaining('Programme de ${channels[0].name}'), findsOneWidget);
      expect(find.text('Suivre'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(find.textContaining('Programme de '), findsNothing);
      final ancienneCommandeVisible = find.text('Suivre').evaluate().isNotEmpty;
      await tester.pump(const Duration(milliseconds: 50));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.textContaining('Programme de ${channels[2].name}'), findsOneWidget);
      expect(find.text('Suivre'), findsOneWidget);
      final indexes = guideReads.map((id) => channels.indexWhere((c) => c.id == id)).toList();
      debugPrint('ZUNO_GUIDE_TRACE reads=$indexes staleControl=$ancienneCommandeVisible');
      expect(indexes, [0, 2], reason: 'ZUNO_GUIDE_READ_COUNT');
      expect(ancienneCommandeVisible, isFalse, reason: 'ZUNO_GUIDE_STALE_CONTROL');
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'le Direct distingue les variantes sélectionnables à la télécommande',
    (tester) async {
      await show(tester, const TvLiveScreen());
      try {
        final list = find.byType(ListView).last;
        final rows = find.descendant(of: list, matching: find.byType(Text));
        final titles = tester
            .widgetList<Text>(rows)
            .map((w) => w.data)
            .toList();
        expect(titles, containsAllInOrder(names));
        Focus.of(tester.element(find.text(names[1]).first)).requestFocus();
        await tester.pump();
        expect(
          Focus.of(tester.element(find.text(names[1]).first)).hasFocus,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(
          Focus.of(tester.element(find.text(names[2]).first)).hasFocus,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final player = tester.widget<TvPlayerScreen>(
          find.byType(TvPlayerScreen),
        );
        final selected = player.channels[player.startIndex];
        expect(selected.name, names[2]);
        expect(
          selected.streamUrl,
          PlaylistRepository.instance.currentChannels[2].streamUrl,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 10));
      }
    },
  );
  testWidgets(
    'double OK dans Direct ouvre un seul lecteur et autorise sa réouverture',
    (tester) async {
      await show(tester, const TvLiveScreen());
      try {
        final row = find.text(names[1]).first;
        Focus.of(tester.element(row)).requestFocus();
        await tester.pump();

        // Deux paires appui/relâchement avant la fin de la libération
        // asynchrone de l’aperçu. Le système de focus les envoie à la vraie
        // ligne du Direct, même si aucun nouveau frame n’a encore été tracé.
        void pressOk() {
          const key = LogicalKeyboardKey.select;
          const physical = PhysicalKeyboardKey.select;
          HardwareKeyboard.instance.handleKeyEvent(
            const KeyDownEvent(
              logicalKey: key,
              physicalKey: physical,
              timeStamp: Duration.zero,
            ),
          );
          HardwareKeyboard.instance.handleKeyEvent(
            const KeyUpEvent(
              logicalKey: key,
              physicalKey: physical,
              timeStamp: Duration.zero,
            ),
          );
        }

        pressOk();
        pressOk();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final players = find.byType(TvPlayerScreen, skipOffstage: false);
        debugPrint('ZUNO_DOUBLE_OK routes=${players.evaluate().length}');
        expect(players, findsOneWidget, reason: 'ZUNO_DOUBLE_OK_ROUTES');
        final player = tester.widget<TvPlayerScreen>(players);
        expect(player.channels[player.startIndex].name, names[1]);

        Navigator.of(tester.element(players)).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(players, findsNothing);
        Focus.of(tester.element(row)).requestFocus();
        await tester.pump();
        pressOk();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(players, findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 10));
      }
    },
  );
  testWidgets(
    'la recherche de la chaîne conserve chaque variante sur ZUNO TV',
    (tester) async {
      await show(tester, const TvSearchScreen(initialQuery: 'Mire Sport'));
      try {
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        for (final name in names.skip(1)) {
          expect(find.text(name), findsOneWidget);
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 10));
      }
    },
  );
}
