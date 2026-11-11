// Régressions exécutables à l'identique sur le 116 et sur le correctif.
// Elles observent le vrai écran, sans inspection textuelle de son code.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tv_king/features/simple_home/data/announcement_repository.dart';

import 'hub_tick_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(HubTickFixture.setUpAll);
  setUp(HubTickFixture.setUp);
  tearDownAll(HubTickFixture.tearDownAll);

  testWidgets('L1-06 : un tick de 20 s garde le widget des carrousels', (
    tester,
  ) async {
    await http.runWithClient(() async {
      await HubTickFixture.mount(tester);
      final before = HubTickFixture.home(tester);
      final title = before.board.hero!.title;
      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      final after = HubTickFixture.home(tester);
      expect(after.board.hero!.title, title);
      expect(
        after,
        same(before),
        reason: 'Une heure modifiée ne doit pas reconstruire les carrousels.',
      );
      expect(tester.takeException(), isNull);
    }, () => HubTickFixture.client);
  });

  testWidgets('L1-06 : le panel change sans reconstruire les carrousels', (
    tester,
  ) async {
    await http.runWithClient(() async {
      await HubTickFixture.mount(tester);
      final before = HubTickFixture.home(tester);
      AnnouncementRepository.latest.value = HubTickFixture.notice(
        601,
        'Première annonce',
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Première annonce'), findsOneWidget);
      expect(HubTickFixture.home(tester), same(before));
      AnnouncementRepository.latest.value = HubTickFixture.notice(
        602,
        'Nouvelle annonce',
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Première annonce'), findsNothing);
      expect(find.text('Nouvelle annonce'), findsOneWidget);
      expect(HubTickFixture.home(tester), same(before));
      expect(tester.takeException(), isNull);
    }, () => HubTickFixture.client);
  });
}
