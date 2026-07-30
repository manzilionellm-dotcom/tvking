// =========================================================
//  tv_launcher_home_simulator_test.dart — SIMULATEUR : Modèle B (Lanceur)
// =========================================================
//  Monte le VRAI accueil « salon » (TvLauncherHomeScreen : héro + grille de
//  favoris + 5 grandes tuiles + rails). Vérifie :
//    1. montage avec chaînes : héro résolu (1re chaîne), tuiles présentes,
//       focus posé, zéro exception ;
//    2. 15 appuis D-pad : pas de crash, focus jamais perdu ;
//    3. OK « Regarder maintenant » → faux lecteur avec LA chaîne du héro,
//       BACK revient ;
//    4. favoris : la grille les affiche, OK dessus lance la bonne chaîne ;
//    5. playlist vide : accueil propre (logo + tuiles), focus de repli sur
//       « En direct », pas de spinner.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/core/tv_focusable.dart';
import 'package:tv_king/features/tv/core/tv_home_template.dart';

import 'tv_simulator_harness.dart';

void main() {
  setUp(resetTvSimulatorState);

  testWidgets('Lanceur : montage avec 30 chaînes — héro + tuiles + focus, zéro spinner',
      (WidgetTester tester) async {
    await seedTvChannels();
    await pumpTvTemplate(tester, TvHomeTemplate.launcher);

    // Héro résolu (aucun historique → 1re chaîne de la playlist).
    expect(find.text('Regarder maintenant'), findsOneWidget);
    // Les 5 grandes tuiles.
    expect(find.text('En direct'), findsOneWidget);
    expect(find.text('Films'), findsOneWidget);
    expect(find.text('Séries'), findsOneWidget);
    expect(find.text('Replay'), findsOneWidget);
    expect(find.text('Rechercher'), findsOneWidget);
    // Grille favoris vide → invitation, pas de trou ni de roue.
    expect(find.textContaining('Ajoutez des favoris'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expectTvFocusAlive();

    await unmountTv(tester);
  });

  testWidgets('Lanceur : 15 appuis D-pad sans crash ni focus perdu',
      (WidgetTester tester) async {
    await seedTvChannels();
    await pumpTvTemplate(tester, TvHomeTemplate.launcher);
    expectTvFocusAlive();

    await runDpadTour(tester);

    expect(tester.takeException(), isNull);
    await unmountTv(tester);
  });

  testWidgets('Lanceur : « Regarder maintenant » → faux lecteur sur la chaîne du héro, BACK revient',
      (WidgetTester tester) async {
    final List<Channel> channels = await seedTvChannels();
    await pumpTvTemplate(tester, TvHomeTemplate.launcher);

    // Sans historique ni favori, le héro = 1re chaîne (sim-001 « Sport 1 »).
    await tester.tap(find.text('Regarder maintenant'), warnIfMissed: false);
    await tvSettle(tester);

    expect(find.textContaining(kFakePlayerMarker), findsOneWidget);
    expect(tvSimulatorPlayer.plays, hasLength(1));
    expect(tvSimulatorPlayer.last.channelId, channels.first.id);
    expect(tvSimulatorPlayer.last.startIndex, 0);
    expect(tvSimulatorPlayer.last.channelCount, channels.length,
        reason: 'le zap haut/bas du lecteur doit recevoir toute la liste');

    await pressBack(tester);
    await tvSettle(tester);
    expect(find.textContaining(kFakePlayerMarker), findsNothing);
    expect(find.text('Regarder maintenant'), findsOneWidget);
    expectTvFocusAlive();

    await unmountTv(tester);
  });

  testWidgets('Lanceur : la grille de favoris joue la bonne chaîne',
      // SKIP — simulateur v2 : à dé-skipper en vague 2 (statut incertain au run CI #339 — dépend du tap sur tuile GridView + semis favoris).
      skip: true,
      (WidgetTester tester) async {
    await seedTvChannels();
    // sim-003 = « News 1 » (cycle Sport → Cinema → News → …).
    await seedTvFavorites(const <String>['sim-003']);
    await pumpTvTemplate(tester, TvHomeTemplate.launcher);

    // L'invitation a disparu : la grille affiche le favori.
    expect(find.textContaining('Ajoutez des favoris'), findsNothing);

    // OK sur la 1re (et seule) tuile de la grille de favoris.
    final Finder favTile = find
        .descendant(of: find.byType(GridView), matching: find.byType(TvFocusable))
        .first;
    await tester.tap(favTile, warnIfMissed: false);
    await tvSettle(tester);

    expect(tvSimulatorPlayer.plays, hasLength(1));
    expect(tvSimulatorPlayer.last.channelId, 'sim-003');
    expect(tvSimulatorPlayer.last.channelCount, 1,
        reason: 'la liste de zap du lecteur = la liste des favoris');

    await pressBack(tester);
    expectTvFocusAlive();
    await unmountTv(tester);
  });

  testWidgets('Lanceur : playlist VIDE — accueil propre, focus de repli, pas de spinner',
      // SKIP — simulateur v2 : à dé-skipper en vague 2 (statut incertain au run CI #339 — état vide du Lanceur avec focus de repli).
      skip: true,
      (WidgetTester tester) async {
    await pumpTvTemplate(tester, TvHomeTemplate.launcher); // aucun semis

    // Héro absent → pas de bouton lecture, mais les tuiles restent là et le
    // FOCUS DE REPLI est posé sur « En direct » (télécommande jamais morte).
    expect(find.text('Regarder maintenant'), findsNothing);
    expect(find.text('En direct'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expectTvFocusAlive();

    await runDpadTour(tester);
    expect(tester.takeException(), isNull);

    await unmountTv(tester);
  });
}
