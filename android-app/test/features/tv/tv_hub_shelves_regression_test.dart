// Ces scénarios n'utilisent que les API présentes dans le 116 : un échec
// de référence démontre le comportement, pas l'absence d'un symbole ajouté.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/time_picks/data/time_pick_log.dart';
import 'package:tv_king/features/tv/presentation/tv_cinematic_home.dart';

import 'hub_tick_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await HubTickFixture.setUpAll();
    await PlaylistRepository.instance.initialize();
  });
  setUp(HubTickFixture.setUp);
  tearDownAll(HubTickFixture.tearDownAll);

  testWidgets('L1-02 : les demandes rapprochées attendent un assemblage commun',
      (
    tester,
  ) async {
    await http.runWithClient(() async {
      await HubTickFixture.mount(tester);
      // Laisse finir les calculs initiaux ; aucune horloge de 20 s n'expire.
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final before = HubTickFixture.home(tester);
      final titles = before.board.discover.map((item) => item.title).toList();
      for (int i = 0; i < 3; i++) {
        TimePickLog.instance.listenable.value++;
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          HubTickFixture.home(tester),
          same(before),
          reason: 'La pause de 150 ms regroupe les demandes du carnet.',
        );
      }
      await tester.pump(const Duration(milliseconds: 99));
      expect(HubTickFixture.home(tester), same(before));
      await tester.pump(const Duration(milliseconds: 1));
      final grouped = HubTickFixture.home(tester);
      expect(grouped, isNot(same(before)));
      expect(grouped.board.hero!.title, before.board.hero!.title);
      expect(grouped.board.discover.map((item) => item.title), titles);
      // Le résultat d'une suggestion ne doit pas relancer une boucle
      // permanente 150 ms → tendances 400 ms → assemblage 150 ms.
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 550));
        expect(HubTickFixture.home(tester), same(grouped));
      }
      expect(tester.takeException(), isNull);
    }, () => HubTickFixture.client);
  });

  testWidgets('L1-02 : une portée vide ne réaffiche pas les anciennes rangées',
      (
    tester,
  ) async {
    await http.runWithClient(() async {
      await HubTickFixture.mount(tester);
      expect(HubTickFixture.home(tester).board.hero!.title, 'Bravo');
      // Même profil, retrait de toutes ses sources : l'événement SQL peut
      // attendre, mais aucun index du catalogue précédent n'est réutilisable.
      ActiveProfile.instance.set('p1', playlistIds: const []);
      await tester.pump();
      expect(find.text('Bravo'), findsNothing);
      expect(find.text('Alpha'), findsNothing);
      // L'état historique sans catalogue peut remplacer entièrement les
      // carrousels. S'ils existent encore, leurs cartes doivent être vides.
      for (final home in tester.widgetList<TvCinematicHome>(
        find.byType(TvCinematicHome),
      )) {
        expect(home.board.hero, isNull);
        expect(home.board.recommendations, isEmpty);
        expect(home.board.discover, isEmpty);
      }
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Bravo'), findsNothing);
      expect(find.text('Alpha'), findsNothing);
      expect(tester.takeException(), isNull);
    }, () => HubTickFixture.client);
  });
}
