// Les PNG complets restent exclusivement sur le runner. Le seul export est
// le nombre de pixels différents et les empreintes, jamais un log de contenu.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/core/i18n/locale_repository.dart';
import 'package:tv_king/features/epg/data/epg_repository.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/tv/presentation/tv_app.dart';
import 'package:tv_king/features/tv/presentation/tv_hub_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_live_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_player_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_settings_screen.dart';
import 'package:tv_king/features/voice/presentation/voice_navigation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dbDir;
  setUpAll(() async {
    AppPlatform.configureZuno(isAndroidHandset: false);
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocaleRepository.instance.setLocale(const Locale('fr'));
    // Charger les variantes de production avant le premier layout, avec
    // les octets des polices embarquées et les clés réelles de leur manifeste.
    final base = Directory('assets/fonts');
    final assets = <String, List<Map<String, String>>>{};
    for (final file in base.listSync().whereType<File>()) {
      if (file.path.endsWith('.ttf'))
        assets[file.path] = [
          {'asset': file.path},
        ];
    }
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (
      ByteData? message,
    ) async {
      final key = utf8.decode(
        message!.buffer.asUint8List(
          message.offsetInBytes,
          message.lengthInBytes,
        ),
      );
      if (key == 'AssetManifest.bin')
        return const StandardMessageCodec().encodeMessage(assets);
      if (key == 'AssetManifest.json')
        return ByteData.sublistView(
          Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                for (final k in assets.keys) k: [k],
              }),
            ),
          ),
        );
      if (assets.containsKey(key))
        return ByteData.sublistView(File(key).readAsBytesSync());
      return messenger.delegate.send('flutter/assets', message);
    });
    const weights = {
      'Regular': FontWeight.w400,
      'Medium': FontWeight.w500,
      'SemiBold': FontWeight.w600,
      'Bold': FontWeight.w700,
      'ExtraBold': FontWeight.w800,
    };
    for (final path in assets.keys) {
      final parts = path.split('/').last.replaceAll('.ttf', '').split('-');
      GoogleFonts.getFont(
        {
              'JetBrainsMono': 'JetBrains Mono',
              'BricolageGrotesque': 'Bricolage Grotesque',
            }[parts[0]] ??
            parts[0],
        fontWeight: weights[parts[1]],
      );
    }
    await GoogleFonts.pendingFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    dbDir = await Directory.systemTemp.createTemp('style-db-');
    PlaylistDatabase.debugFilePath = '${dbDir.path}/fixture.db';
    await FavoritesRepository.instance.initialize();
    await EpgRepository.instance.initialize();
    final server = MockClient((req) async {
      final response = switch (req.url.queryParameters['action']) {
        'get_live_categories' => [
          {'category_id': '1', 'category_name': 'Mires'},
        ],
        'get_live_streams' => [
          for (final (i, name) in ['Mire A', 'Mire B'].indexed)
            {'stream_id': i + 1, 'name': name, 'category_id': '1'},
        ],
        _ => {
          'user_info': {'auth': 1, 'status': 'Active'},
        },
      };
      return http.Response(jsonEncode(response), 200);
    });
    await PlaylistRepository.instance.addXtreamPlaylist(
      name: 'Mires',
      serverUrl: 'http://127.0.0.1:18471',
      username: 'fixture',
      password: 'fixture',
      httpClient: server,
    );
    server.close();
  });
  tearDownAll(() async {
    await PlaylistDatabase.instance.closeForTesting();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });
  for (final name in ['accueil', 'direct', 'lecteur', 'reglages']) {
    testWidgets('rendu réel $name', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: const TvApp()),
      );
      await tester.pump();
      try {
        final screen = switch (name) {
          'accueil' => const TvHubScreen(),
          'direct' => const TvLiveScreen(),
          'lecteur' => TvPlayerScreen(
            channels: PlaylistRepository.instance.currentChannels,
            startIndex: 0,
          ),
          _ => const TvSettingsScreen(),
        };
        VoiceNavigation.navigatorKey.currentState!.push<void>(
          PageRouteBuilder<void>(
            pageBuilder: (_, __, ___) => screen,
            transitionDuration: Duration.zero,
          ),
        );
        await tester.pump();
        for (int i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byWidget(screen), findsOneWidget);
        final box =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final out = Platform.environment['STYLE_PRIVATE']!;
        await tester.runAsync(() async {
          final image = await box.toImage(pixelRatio: 1);
          expect(image.width, 1280);
          expect(image.height, 720);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          await File('$out/$name.png').writeAsBytes(data!.buffer.asUint8List());
        });
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 10));
      }
    });
  }
}
