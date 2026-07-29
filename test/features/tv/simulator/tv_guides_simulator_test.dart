// =========================================================
//  tv_guides_simulator_test.dart — SIMULATEUR : les 3 guides EPG
// =========================================================
//  Monte les VRAIS guides :
//    • TvGuideGridScreen     (« Maintenant / À suivre », lignes paginées) ;
//    • TvTimelineGuideScreen (grille horaire style câble US, blocs) ;
//    • TvTivimateGuideScreen (grille horaire style TiviMate).
//  Pour chacun : montage SANS EPG (états « discrets »/vides corrects) puis
//  AVEC programmes semés (now/next affichés), navigation D-pad, décalage
//  ±30 min (chips ⟨ ⟩), tics 30 s (pompes BORNÉES — jamais pumpAndSettle),
//  lecture d'un programme EN COURS via le faux lecteur, et playlist vide
//  (message propre, pas de spinner infini — correctifs récents).
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/presentation/tv_guide_grid_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_shell.dart';
import 'package:tv_king/features/tv/presentation/tv_timeline_guide_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_tivimate_guide_screen.dart';

import 'tv_simulator_harness.dart';

void main() {
  setUp(resetTvSimulatorState);

  // ============================================================
  //  Guide « Maintenant / À suivre »
  // ============================================================

  testWidgets('Guide (now/next) : playlist vide → message propre, pas de spinner infini',
      (WidgetTester tester) async {
    await pumpTvScreen(tester, const TvShell(child: TvGuideGridScreen()));

    expect(find.text('Aucune chaîne pour l\'instant'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);

    await unmountTv(tester);
  });

  testWidgets('Guide (now/next) : EPG VIDE → lignes discrètes (catégorie), D-pad OK',
      (WidgetTester tester) async {
    await seedTvChannels();
    await pumpTvScreen(tester, const TvShell(child: TvGuideGridScreen()));
    // Laisse passer l'anti-rebond EPG des lignes (250 ms) : aucun programme.
    await tester.pump(const Duration(milliseconds: 300));
    await tvSettle(tester);

    expect(find.text('Sport 1'), findsOneWidget);
    expect(find.textContaining('Maintenant'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await runDpadTour(tester);
    expect(tester.takeException(), isNull);

    await unmountTv(tester);
  });

  testWidgets('Guide (now/next) : EPG semé → now/next + progression, tic 30 s sans crash',
      (WidgetTester tester) async {
    await seedTvChannels();
    await seedTvEpg(const <String>['sim-001', 'sim-002']);
    await pumpTvScreen(tester, const TvShell(child: TvGuideGridScreen()));
    await tester.pump(const Duration(milliseconds: 300)); // anti-rebond EPG
    await tvSettle(tester);

    expect(find.text('Maintenant 1'), findsOneWidget);
    expect(find.text('Maintenant 2'), findsOneWidget);
    expect(find.textContaining('Ensuite 1'), findsOneWidget); // « À suivre · … »
    expect(find.byType(LinearProgressIndicator), findsWidgets);

    // Tic périodique 30 s (progression / bascule) : rien ne casse.
    await tester.pump(const Duration(seconds: 31));
    await tvSettle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Maintenant 1'), findsOneWidget);

    await unmountTv(tester);
  });

  testWidgets('Guide (now/next) : OK sur une ligne → faux lecteur, BACK revient',
      (WidgetTester tester) async {
    await seedTvChannels();
    await pumpTvScreen(tester, const TvShell(child: TvGuideGridScreen()));
    await tvSettle(tester);

    await tester.tap(find.text('Sport 1'), warnIfMissed: false);
    await tvSettle(tester);

    expect(find.textContaining(kFakePlayerMarker), findsOneWidget);
    expect(tvSimulatorPlayer.last.channelId, 'sim-001');

    await pressBack(tester);
    await tvSettle(tester);
    expect(find.textContaining(kFakePlayerMarker), findsNothing);
    expect(find.text('Sport 1'), findsOneWidget);

    await unmountTv(tester);
  });

  // ============================================================
  //  Grille horaire (style câble US)
  // ============================================================

  testWidgets('Grille horaire : playlist vide → message propre, pas de spinner infini',
      (WidgetTester tester) async {
    await pumpTvScreen(tester, const TvShell(child: TvTimelineGuideScreen()));

    expect(find.text('GRILLE TV'), findsOneWidget);
    expect(find.text('Aucune chaîne pour l\'instant'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await unmountTv(tester);
  });

  testWidgets('Grille horaire : blocs EPG affichés, focus posé, D-pad OK',
      (WidgetTester tester) async {
    await seedTvChannels();
    await seedTvEpg(const <String>['sim-001', 'sim-002', 'sim-003']);
    await pumpTvScreen(tester, const TvShell(child: TvTimelineGuideScreen()));
    await tvSettle(tester);

    expect(find.text('GRILLE TV'), findsOneWidget);
    expect(find.text('Sport 1'), findsOneWidget); // cellule chaîne
    expect(find.text('Maintenant 1'), findsOneWidget); // bloc en cours
    expect(find.text('Ensuite 1'), findsOneWidget); // bloc suivant
    expectTvFocusAlive(); // autofocus 1re cellule chaîne

    await runDpadTour(tester);
    expect(tester.takeException(), isNull);

    await unmountTv(tester);
  });

  testWidgets('Grille horaire : décalage ±30 min sans crash, focus conservé',
      (WidgetTester tester) async {
    await seedTvChannels();
    await seedTvEpg(const <String>['sim-001', 'sim-002']);
    await pumpTvScreen(tester, const TvShell(child: TvTimelineGuideScreen()));
    await tvSettle(tester);

    // ⟩ : fenêtre +30 min — le bloc « Ensuite 1 » reste dans le champ.
    await tester.tap(find.byIcon(Icons.chevron_right_rounded),
        warnIfMissed: false);
    await tvSettle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Ensuite 1'), findsOneWidget);
    expectTvFocusAlive();

    // ⟨ : retour −30 min.
    await tester.tap(find.byIcon(Icons.chevron_left_rounded),
        warnIfMissed: false);
    await tvSettle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Maintenant 1'), findsOneWidget);

    // Tic 30 s de la ligne « maintenant » : rien ne casse.
    await tester.pump(const Duration(seconds: 31));
    await tvSettle(tester);
    expect(tester.takeException(), isNull);

    await unmountTv(tester);
  });

  testWidgets('Grille horaire : OK sur un bloc EN COURS → lecteur ; programme à VENIR → petit message',
      (WidgetTester tester) async {
    await seedTvChannels();
    await seedTvEpg(const <String>['sim-001']);
    await pumpTvScreen(tester, const TvShell(child: TvTimelineGuideScreen()));
    await tvSettle(tester);

    // Bloc EN COURS → lecture directe de la chaîne.
    await tester.tap(find.text('Maintenant 1'), warnIfMissed: false);
    await tvSettle(tester);
    expect(find.textContaining(kFakePlayerMarker), findsOneWidget);
    expect(tvSimulatorPlayer.last.channelId, 'sim-001');
    await pressBack(tester);
    await tvSettle(tester);
    expect(find.textContaining(kFakePlayerMarker), findsNothing);

    // Bloc À VENIR (pas d'archive) → toast « Programme à venir », pas de
    // lecteur.
    await tester.tap(find.text('Ensuite 1'), warnIfMissed: false);
    await tvSettle(tester);
    expect(find.text('Programme à venir'), findsOneWidget);
    expect(tvSimulatorPlayer.plays, hasLength(1)); // toujours une seule lecture
    // Laisse le toast se refermer (2 s) avant le démontage.
    await tester.pump(const Duration(seconds: 3));
    await tvSettle(tester);

    await unmountTv(tester);
  });

  // ============================================================
  //  Grille horaire « TiviMate »
  // ============================================================

  testWidgets('Grille TiviMate : playlist vide → message propre, pas de spinner infini',
      (WidgetTester tester) async {
    await pumpTvScreen(tester, const TvTivimateGuideScreen());

    expect(find.text('Aucune chaîne pour l\'instant'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await unmountTv(tester);
  });

  testWidgets('Grille TiviMate : blocs EPG + D-pad + décalage ±30 min + tic 30 s',
      (WidgetTester tester) async {
    await seedTvChannels();
    await seedTvEpg(const <String>['sim-001', 'sim-002']);
    await pumpTvScreen(tester, const TvTivimateGuideScreen());
    await tvSettle(tester);

    expect(find.text('Sport 1'), findsOneWidget);
    expect(find.text('Maintenant 1'), findsOneWidget);
    expectTvFocusAlive(); // autofocus 1re cellule chaîne

    await runDpadTour(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded),
        warnIfMissed: false);
    await tvSettle(tester);
    expect(find.text('Ensuite 1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded),
        warnIfMissed: false);
    await tvSettle(tester);

    await tester.pump(const Duration(seconds: 31));
    await tvSettle(tester);
    expect(tester.takeException(), isNull);

    await unmountTv(tester);
  });
}
