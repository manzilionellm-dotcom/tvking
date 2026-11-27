import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/novatube_tv_edition.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/core/tv_provider_channel_name.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/tv/presentation/tv_live_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_player_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_search_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

import 'ahem_fonts.dart';

const names = ['FOX Sports 1', 'FOX Sports 1 RAW', 'FOX Sports 1 UHD'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUpAll(() async {
    installAhemFonts();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    dir = await Directory.systemTemp.createTemp('direct-variantes-');
    PlaylistDatabase.debugFilePath = '${dir.path}/catalogue.db';
    // Préparer SQLite en temps réel, avant l’horloge simulée du widget.
    await FavoritesRepository.instance.initialize();
    final server = MockClient((req) async {
      final action = req.url.queryParameters['action'];
      final Object payload = switch (action) {
        'get_live_categories' => [
            {'category_id': '1', 'category_name': 'Sports'}
          ],
        'get_live_streams' => [
            for (final (i, name) in names.indexed)
              {'stream_id': i + 1, 'name': name, 'category_id': '1'}
          ],
        _ => {
            'user_info': {'auth': 1, 'status': 'Active'}
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
          httpClient: server);
    } finally {
      server.close();
    }
    expect(
        PlaylistRepository.instance.currentChannels
            .map((c) => c.streamUrl)
            .toSet(),
        hasLength(3));
  });
  tearDownAll(() async {
    removeAhemFonts();
    await PlaylistDatabase.instance.closeForTesting();
    await dir.delete(recursive: true);
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: screen)));
    await tester.pump();
  }

  test(
      'un libellé de fournisseur vide ou porteur de secrets utilise le texte de repli',
      () {
    Channel channel(String name) => Channel(
        id: 'id',
        name: name,
        category: 'Sports',
        streamUrl: 'https://example.invalid/fixture',
        isLive: true);
    for (final value in [
      '',
      '  ',
      'https://example.invalid/?username=secret',
      'Sports password=secret'
    ]) {
      expect(tvProviderChannelName(channel(value), 'Chaîne'), 'Chaîne');
    }
    expect(tvProviderChannelName(channel('قناة HD'), 'Chaîne'), 'قناة HD');
  });

  testWidgets(
      'le Direct distingue les variantes sélectionnables à la télécommande',
      (tester) async {
    await show(tester, const TvLiveScreen());
    try {
      final list = find.byType(ListView).last;
      final rows = find.descendant(of: list, matching: find.byType(Text));
      final titles = tester.widgetList<Text>(rows).map((w) => w.data).toList();
      if (kNovatubeTv) {
        expect(titles, containsAllInOrder(names));
        Focus.of(tester.element(find.text(names[1]).first)).requestFocus();
        await tester.pump();
        expect(Focus.of(tester.element(find.text(names[1]).first)).hasFocus,
            isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(Focus.of(tester.element(find.text(names[2]).first)).hasFocus,
            isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final player =
            tester.widget<TvPlayerScreen>(find.byType(TvPlayerScreen));
        final selected = player.channels[player.startIndex];
        expect(selected.name, names[2]);
        expect(selected.streamUrl,
            PlaylistRepository.instance.currentChannels[2].streamUrl);
      } else {
        expect(titles.where((title) => title == names.first), hasLength(3));
      }
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    }
  });
  for (final changeFocus in [false, true]) {
    final scenario =
        changeFocus ? 'après un changement de chaîne' : 'sur la même chaîne';
    testWidgets(
        'deux appuis OK $scenario attendent la libération et ouvrent un seul lecteur',
        (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final release = Completer<void>();
      final natives = <MethodChannel>[];
      var releases = 0;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views,
          (call) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map)['id'] as int;
          final channel = MethodChannel('native_video_player/$id');
          natives.add(channel);
          messenger.setMockMethodCallHandler(channel, (method) async {
            if (method.method == 'dispose' && channel == natives.first) {
              releases++;
              await release.future;
            }
            return null;
          });
        }
        return null;
      });
      try {
        await show(tester, const TvLiveScreen());
        Focus.of(tester.element(find.text(names[0]).first)).requestFocus();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1600));
        await tester.pump();
        expect(natives, hasLength(1));
        if (changeFocus) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump(const Duration(milliseconds: 150));
          expect(releases, 1);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump(const Duration(milliseconds: 50));
        expect(releases, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(TvPlayerScreen, skipOffstage: false), findsNothing);
        release.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final screens = find.byType(TvPlayerScreen, skipOffstage: false);
        expect(screens, findsOneWidget);
        final opened = tester.widget<TvPlayerScreen>(screens);
        expect(opened.channels[opened.startIndex].name,
            names[changeFocus ? 1 : 0]);
      } finally {
        if (!release.isCompleted) release.complete();
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 10));
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        for (final channel in natives) {
          messenger.setMockMethodCallHandler(channel, null);
        }
      }
    },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
        skip: !kNovatubeTv);
  }

  testWidgets(
      'la recherche de la chaîne conserve chaque variante dans NovaTube',
      (tester) async {
    await show(tester, const TvSearchScreen(initialQuery: 'FOX Sports 1'));
    try {
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      for (final name in names.skip(1)) {
        expect(find.text(name), kNovatubeTv ? findsOneWidget : findsNothing);
      }
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    }
  });
}
