import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/features/epg/data/epg_repository.dart';
import 'package:tv_king/features/followed/data/followed_log.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/simple_home/data/announcement_repository.dart';
import 'package:tv_king/features/tv/presentation/tv_hub_screen.dart';

import 'hub_tick_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await HubTickFixture.setUpAll();
    const output = String.fromEnvironment('ZUNO_L1_CAPTURE_DIR');
    if (output.isNotEmpty) {
      final sdk = Platform.environment['FLUTTER_ROOT'];
      if (sdk == null || sdk.isEmpty) {
        throw StateError('FLUTTER_ROOT requis pour capturer les vraies icônes');
      }
      final bytes = await File(
        '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes();
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
  setUp(() {
    HubTickFixture.setUp();
    RepairFlags.hubGlobalTickLegacy = false;
  });
  tearDown(() => RepairFlags.hubGlobalTickLegacy = false);
  tearDownAll(HubTickFixture.tearDownAll);

  testWidgets(
    'L1-06 : heure et date changent sans reconstruire les carrousels',
    (tester) async {
      await http.runWithClient(() async {
        DateTime now = DateTime(2026, 11, 11, 23, 59, 50);
        await HubTickFixture.mount(
          tester,
          child: TvHubScreen(nowForTesting: () => now),
        );
        final before = HubTickFixture.home(tester);
        expect(find.text('23:59'), findsOneWidget);
        expect(find.text('mer. 11 nov.'), findsOneWidget);
        now = now.add(const Duration(seconds: 20));
        await tester.pump(const Duration(seconds: 20));
        await tester.pump();
        expect(find.text('00:00'), findsOneWidget);
        expect(find.text('jeu. 12 nov.'), findsOneWidget);
        expect(HubTickFixture.home(tester), same(before));
      }, () => HubTickFixture.client);
    },
  );

  testWidgets('L1-06 : fermeture retire les abonnements et annule le tick', (
    tester,
  ) async {
    await http.runWithClient(() async {
      int clockReads = 0;
      await HubTickFixture.mount(
        tester,
        child: TvHubScreen(
          nowForTesting: () {
            clockReads++;
            return DateTime(2026, 11, 11, 21, 56);
          },
        ),
      );
      final clocks = tester
          .widgetList<ValueListenableBuilder<DateTime>>(
            find.byType(ValueListenableBuilder<DateTime>),
          )
          .map((widget) => widget.valueListenable)
          .whereType<ValueNotifier<DateTime>>()
          .toSet();
      expect(clocks, hasLength(1));
      // Une réponse de préférence d'annonce peut encore être en vol ici.
      AnnouncementRepository.latest.value = HubTickFixture.notice(
        603,
        'Réponse tardive',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      final readsAtClose = clockReads;
      await tester.pump(const Duration(seconds: 60));
      AnnouncementRepository.latest.value = HubTickFixture.notice(
        604,
        'Après fermeture',
      );
      await tester.pump();
      expect(clockReads, readsAtClose);
      // L'API publique refuse un abonnement sur le notifier libéré ; son
      // dispose a donc aussi détaché les ValueListenableBuilder de l'écran.
      expect(() => clocks.single.addListener(() {}), throwsFlutterError);
      expect(tester.takeException(), isNull);
    }, () => HubTickFixture.client);
  });

  testWidgets('L1-06 : le repli restaure la reconstruction globale', (
    tester,
  ) async {
    await http.runWithClient(() async {
      RepairFlags.hubGlobalTickLegacy = true;
      await HubTickFixture.mount(
        tester,
        child: TvHubScreen(nowForTesting: () => DateTime(2026, 11, 11, 21, 56)),
      );
      final before = HubTickFixture.home(tester);
      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      expect(HubTickFixture.home(tester), isNot(same(before)));
      expect(tester.takeException(), isNull);
    }, () => HubTickFixture.client);
  });

  testWidgets('L1-06 : pixels identiques entre chemin isolé et repli', (
    tester,
  ) async {
    await http.runWithClient(() async {
      final boundaryKey = GlobalKey();
      final now = DateTime(2026, 11, 11, 21, 56);
      Widget screen(String id) => RepaintBoundary(
            key: boundaryKey,
            child: TvHubScreen(key: ValueKey(id), nowForTesting: () => now),
          );
      await HubTickFixture.mount(tester, child: screen('isole'));
      await tester.pump(const Duration(milliseconds: 500));
      final isolated = await _capture(tester, boundaryKey, 'hub-isole');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      RepairFlags.hubGlobalTickLegacy = true;
      await HubTickFixture.mount(tester, child: screen('repli'));
      await tester.pump(const Duration(milliseconds: 500));
      final legacy = await _capture(tester, boundaryKey, 'hub-repli');
      expect(
        isolated,
        orderedEquals(legacy),
        reason: 'Même heure, langue, catalogue, profil, résolution et thème.',
      );
    }, () => HubTickFixture.client);
  });

  testWidgets('L1-06 : une borne du guide actualise toujours le héros', (
    tester,
  ) async {
    await http.runWithClient(() async {
      DateTime now = DateTime.now();
      final start = now.millisecondsSinceEpoch;
      final channel = PlaylistRepository.instance.currentChannels.first;
      await tester.runAsync(() async {
        await EpgRepository.instance.initialize();
        final db = await PlaylistDatabase.instance.database;
        for (final program in <Map<String, Object>>[
          {
            'channel_id': channel.id,
            'start_time': start - 300000,
            'stop_time': start + 10000,
            'title': 'Programme initial',
          },
          {
            'channel_id': channel.id,
            'start_time': start + 10000,
            'stop_time': start + 1800000,
            'title': 'Programme suivant',
          },
        ]) {
          await db.insert('epg_programs', program);
          await FollowedLog.instance.togglePin(
            title: program['title']! as String,
            channelId: channel.id,
            nowMs: start,
          );
        }
      });
      await HubTickFixture.mount(
        tester,
        child: TvHubScreen(nowForTesting: () => now),
      );
      expect(
        HubTickFixture.home(tester).board.hero!.title,
        'Programme initial',
      );
      now = now.add(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      expect(
        HubTickFixture.home(tester).board.hero!.title,
        'Programme suivant',
      );
      expect(tester.takeException(), isNull);
    }, () => HubTickFixture.client);
  });
}

Future<Uint8List> _capture(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final result = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      // Les PNG sont des artefacts facultatifs de la commande de validation,
      // jamais une référence visuelle remplacée automatiquement par le test.
      const output = String.fromEnvironment('ZUNO_L1_CAPTURE_DIR');
      if (output.isNotEmpty) {
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final file = File('$output/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(png.buffer.asUint8List());
      }
      return Uint8List.fromList(raw.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
  if (result == null) throw StateError('Capture de comparaison indisponible');
  return result;
}
