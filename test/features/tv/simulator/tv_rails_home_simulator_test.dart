// =========================================================
//  tv_rails_home_simulator_test.dart — SIMULATEUR : Modèle C (Rails)
// =========================================================
//  Monte le VRAI accueil « rails » (TvRailsHomeScreen : héro + accès rapides
//  + rangée d'icônes + rail de FAVORIS EN DIRECT). Vérifie :
//    1. montage : structure + focus héro, rail replié sans favoris ;
//    2. 15 appuis D-pad : pas de crash, focus jamais perdu ;
//    3. rail de favoris : cartes affichées (avec titre EPG quand semé),
//       OK → faux lecteur sur LA bonne chaîne (liste = les favoris),
//       BACK revient et le focus reste vivant ;
//    4. CHANGEMENT DE FAVORIS PENDANT L'AFFICHAGE (streams live) : retrait
//       → la carte disparaît ; réajout → elle revient ; jamais de crash ;
//    5. timers (horloge 20 s, tic EPG 60 s) : avancer le temps ne casse rien.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/tv/core/tv_home_template.dart';

import 'tv_simulator_harness.dart';

void main() {
  setUp(resetTvSimulatorState);

  testWidgets('Rails : montage — structure, focus héro, rail replié sans favoris',
      (WidgetTester tester) async {
    await seedTvChannels();
    await pumpTvTemplate(tester, TvHomeTemplate.rails);

    expect(find.text('Accès rapide'), findsOneWidget);
    // Rangée d'icônes (libellés uppercase du template).
    expect(find.text('DIRECT'), findsOneWidget);
    expect(find.text('FILMS'), findsOneWidget);
    expect(find.text('RECHERCHE'), findsOneWidget);
    // Aucun favori → le rail (titre compris) est ENTIÈREMENT replié.
    expect(find.text('Favoris en direct'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expectTvFocusAlive(); // autofocus héro

    await unmountTv(tester);
  });

  testWidgets('Rails : 15 appuis D-pad sans crash ni focus perdu',
      (WidgetTester tester) async {
    await seedTvChannels();
    await seedTvFavorites(const <String>['sim-001', 'sim-006']);
    await pumpTvTemplate(tester, TvHomeTemplate.rails);
    expectTvFocusAlive();

    await runDpadTour(tester);

    expect(tester.takeException(), isNull);
    await unmountTv(tester);
  });

  testWidgets('Rails : rail de favoris — EPG affiché, OK → bonne chaîne, BACK revient',
      (WidgetTester tester) async {
    await seedTvChannels();
    await seedTvFavorites(const <String>['sim-001', 'sim-006']);
    // EPG pour le 1er favori : sa carte doit montrer le programme en cours.
    await seedTvEpg(const <String>['sim-001']);
    await pumpTvTemplate(tester, TvHomeTemplate.rails);

    expect(find.text('Favoris en direct'), findsOneWidget);
    expect(find.text('Sport 1'), findsOneWidget); // carte du favori (nom brut)
    expect(find.text('Sport 2'), findsOneWidget);
    expect(find.text('Maintenant 1'), findsOneWidget,
        reason: 'le programme en cours du favori doit être affiché');
    // Le favori SANS EPG garde son repli « En direct ».
    expect(find.text('En direct'), findsWidgets);

    // OK (tap = même chemin TvFocusable) sur la carte « Sport 1 ».
    await tester.tap(find.text('Sport 1'), warnIfMissed: false);
    await tvSettle(tester);

    expect(find.textContaining(kFakePlayerMarker), findsOneWidget);
    expect(tvSimulatorPlayer.plays, hasLength(1));
    expect(tvSimulatorPlayer.last.channelId, 'sim-001');
    expect(tvSimulatorPlayer.last.channelCount, 2,
        reason: 'zap du lecteur = la liste des favoris du rail');

    await pressBack(tester);
    await tvSettle(tester);
    expect(find.textContaining(kFakePlayerMarker), findsNothing);
    expect(find.text('Favoris en direct'), findsOneWidget);
    expectTvFocusAlive();

    await unmountTv(tester);
  });

  testWidgets('Rails : changement de favoris PENDANT l\'affichage (streams live)',
      (WidgetTester tester) async {
    await seedTvChannels();
    await seedTvFavorites(const <String>['sim-001', 'sim-006']);
    await pumpTvTemplate(tester, TvHomeTemplate.rails);
    expect(find.text('Sport 2'), findsOneWidget);

    // RETRAIT en direct (comme un toggle ★ fait depuis le lecteur).
    await FavoritesRepository.instance.toggle('sim-006');
    await tvSettle(tester);
    expect(find.text('Sport 2'), findsNothing);
    expect(find.text('Sport 1'), findsOneWidget);

    // RÉAJOUT en direct → la carte revient.
    await FavoritesRepository.instance.toggle('sim-006');
    await tvSettle(tester);
    expect(find.text('Sport 2'), findsOneWidget);

    // DERNIER favori retiré → le rail entier se replie proprement.
    await FavoritesRepository.instance.toggle('sim-001');
    await FavoritesRepository.instance.toggle('sim-006');
    await tvSettle(tester);
    expect(find.text('Favoris en direct'), findsNothing);
    expect(tester.takeException(), isNull);

    await unmountTv(tester);
  });

  testWidgets('Rails : les timers (horloge 20 s, tic EPG 60 s) ne cassent rien',
      (WidgetTester tester) async {
    await seedTvChannels();
    await seedTvFavorites(const <String>['sim-001']);
    await seedTvEpg(const <String>['sim-001']);
    await pumpTvTemplate(tester, TvHomeTemplate.rails);

    // 65 s par pas bornés (JAMAIS pumpAndSettle : tickers périodiques).
    for (int i = 0; i < 13; i++) {
      await tester.pump(const Duration(seconds: 5));
    }
    await tvSettle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Favoris en direct'), findsOneWidget);
    expectTvFocusAlive();

    await unmountTv(tester);
  });
}
