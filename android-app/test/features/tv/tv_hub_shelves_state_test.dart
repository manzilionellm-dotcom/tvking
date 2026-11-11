import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/time_picks/data/time_pick_log.dart';

import 'hub_tick_fixture.dart';

Future<void> finishInitialShelves(WidgetTester tester) async {
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(HubTickFixture.setUpAll);
  setUp(() {
    HubTickFixture.setUp();
    RepairFlags.hubIndexLegacy = false;
  });
  tearDown(() => RepairFlags.hubIndexLegacy = false);
  tearDownAll(HubTickFixture.tearDownAll);

  testWidgets('L1-02 : le repli rétablit les assemblages immédiats', (
    tester,
  ) async {
    await http.runWithClient(() async {
      RepairFlags.hubIndexLegacy = true;
      await HubTickFixture.mount(tester);
      await finishInitialShelves(tester);
      final before = HubTickFixture.home(tester);
      TimePickLog.instance.listenable.value++;
      await tester.pump();
      final after = HubTickFixture.home(tester);
      expect(after, isNot(same(before)));
      expect(after.board.hero!.title, before.board.hero!.title);
      expect(
        after.board.discover.map((piece) => piece.title),
        before.board.discover.map((piece) => piece.title),
      );
    }, () => HubTickFixture.client);
  });

  testWidgets('L1-02 : un résultat de tendances ne crée pas de boucle', (
    tester,
  ) async {
    await http.runWithClient(() async {
      await HubTickFixture.mount(tester);
      await finishInitialShelves(tester);
      final before = HubTickFixture.home(tester);
      final id = PlaylistRepository.instance.currentChannels.last.id;
      await tester.runAsync(() => FavoritesRepository.instance.toggle(id));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(HubTickFixture.home(tester), isNot(same(before)));
      // Le favori déclenche le calcul normal 400 ms après son assemblage,
      // puis le résultat est regroupé pendant 150 ms, une seule fois.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 150));
      final settled = HubTickFixture.home(tester);
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 550));
        expect(HubTickFixture.home(tester), same(settled));
      }
      expect(tester.takeException(), isNull);
    }, () => HubTickFixture.client);
  });

  testWidgets('L1-02 : un catalogue remplacé actualise les objets du héros', (
    tester,
  ) async {
    await http.runWithClient(() async {
      await HubTickFixture.mount(tester);
      await finishInitialShelves(tester);
      final before = HubTickFixture.home(tester).board;
      final old = before.hero!.channel!;
      final discovery = before.discover.map((piece) => piece.title).toList();
      expect(old.name, 'Bravo');
      // Seule la base SQLite éphémère de la fixture est modifiée. On garde
      // le même id pour détecter un cache qui aurait conservé l'ancien objet.
      await tester.runAsync(() async {
        final db = await PlaylistDatabase.instance.database;
        await db.update(
          'channels',
          {'name': 'Bravo actualisé'},
          where: 'name = ?',
          whereArgs: ['Bravo'],
        );
        await PlaylistRepository.instance.initialize();
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final current = HubTickFixture.home(tester).board.hero!.channel!;
      expect(current.id, old.id);
      expect(current.name, 'Bravo actualisé');
      expect(current, isNot(same(old)));
      expect(
        HubTickFixture.home(tester).board.discover.map((piece) => piece.title),
        discovery,
      );
      expect(tester.takeException(), isNull);
    }, () => HubTickFixture.client);
  });
}
