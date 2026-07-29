// =========================================================
//  tv_tivimate_home_simulator_test.dart — SIMULATEUR : Modèle D (TiviMate)
// =========================================================
//  Monte le VRAI accueil « panneau de chaînes » (TvTivimateHomeScreen :
//  rail d'icônes + colonne de groupes + liste + aperçu EPG). Vérifie :
//    1. montage : groupes (« ★ Favoris », « Toutes les chaînes », vraies
//       catégories), liste remplie, aperçu, focus posé, zéro spinner ;
//    2. 15 appuis D-pad : pas de crash, focus jamais perdu ;
//    3. OK sur une chaîne → faux lecteur : bonne chaîne + liste complète,
//       BACK revient ;
//    4. changement de GROUPE : la liste se re-filtre ;
//    5. OK MAINTENU (appui long) sur une chaîne = toggle favori (étoile),
//       SANS ouvrir le lecteur ;
//    6. playlist vide : « Aucune chaîne dans ce groupe », pas de spinner
//       infini, l'écran reste pilotable.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/tv/core/tv_home_template.dart';

import 'tv_simulator_harness.dart';

void main() {
  setUp(resetTvSimulatorState);

  testWidgets('TiviMate : montage — groupes + liste + aperçu, focus posé, zéro spinner',
      (WidgetTester tester) async {
    await seedTvChannels();
    await pumpTvTemplate(tester, TvHomeTemplate.tivimate);

    expect(find.text('Groupes'), findsOneWidget);
    expect(find.text('Recherche intelligente'), findsOneWidget);
    expect(find.text('Toutes les chaînes'), findsOneWidget);
    expect(find.textContaining('Favoris'), findsWidgets); // « ★ Favoris »
    // 1re chaîne visible : dans la liste ET dans l'aperçu du haut.
    expect(find.text('Sport 1'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expectTvFocusAlive(); // autofocus 1re ligne de chaîne

    await unmountTv(tester);
  });

  testWidgets('TiviMate : 15 appuis D-pad sans crash ni focus perdu',
      (WidgetTester tester) async {
    await seedTvChannels();
    await pumpTvTemplate(tester, TvHomeTemplate.tivimate);
    expectTvFocusAlive();

    await runDpadTour(tester);

    expect(tester.takeException(), isNull);
    await unmountTv(tester);
  });

  testWidgets('TiviMate : OK sur la 1re chaîne → faux lecteur (bonne chaîne, liste complète), BACK revient',
      (WidgetTester tester) async {
    final List<Channel> channels = await seedTvChannels();
    await pumpTvTemplate(tester, TvHomeTemplate.tivimate);

    // Le focus initial est sur la 1re ligne (« Sport 1 ») → OK télécommande.
    await pressOk(tester);

    expect(find.textContaining(kFakePlayerMarker), findsOneWidget);
    expect(tvSimulatorPlayer.plays, hasLength(1));
    expect(tvSimulatorPlayer.last.channelId, 'sim-001');
    expect(tvSimulatorPlayer.last.startIndex, 0);
    expect(tvSimulatorPlayer.last.channelCount, channels.length,
        reason: 'groupe « Toutes les chaînes » → zap sur tout le bouquet');

    await pressBack(tester);
    await tvSettle(tester);
    expect(find.textContaining(kFakePlayerMarker), findsNothing);
    expect(find.text('Toutes les chaînes'), findsOneWidget);
    expectTvFocusAlive();

    await unmountTv(tester);
  });

  testWidgets('TiviMate : OK sur un groupe re-filtre la liste des chaînes',
      (WidgetTester tester) async {
    await seedTvChannels();
    await pumpTvTemplate(tester, TvHomeTemplate.tivimate);

    // Toutes les catégories sont mélangées au départ.
    expect(find.text('Generalistes 1'), findsOneWidget);

    // OK (tap = même chemin TvFocusable) sur le groupe « Sport ».
    await tester.tap(find.text('Sport'), warnIfMissed: false);
    await tvSettle(tester);

    // La liste ne montre plus QUE les chaînes Sport (6 sur 30).
    expect(find.text('Generalistes 1'), findsNothing);
    expect(find.text('Sport 1'), findsWidgets);
    expect(find.text('Sport 2'), findsWidgets);
    expect(tester.takeException(), isNull);

    await unmountTv(tester);
  });

  testWidgets('TiviMate : OK MAINTENU (appui long) = favori, sans ouvrir le lecteur',
      (WidgetTester tester) async {
    await seedTvChannels();
    await pumpTvTemplate(tester, TvHomeTemplate.tivimate);
    expect(FavoritesRepository.instance.isFavorite('sim-001'), isFalse);

    // Focus initial = 1re ligne (« Sport 1 ») → OK maintenu > 450 ms.
    await pressOkLong(tester);

    expect(FavoritesRepository.instance.isFavorite('sim-001'), isTrue,
        reason: 'l\'appui long doit mettre la chaîne en favori');
    expect(tvSimulatorPlayer.plays, isEmpty,
        reason: 'l\'appui long NE doit PAS ouvrir le lecteur');
    // L'étoile apparaît sur la ligne (repaint via le stream de favoris).
    expect(find.byIcon(Icons.star_rounded), findsWidgets);

    await unmountTv(tester);
  });

  testWidgets('TiviMate : playlist VIDE — message propre, écran pilotable, pas de spinner infini',
      (WidgetTester tester) async {
    await pumpTvTemplate(tester, TvHomeTemplate.tivimate); // aucun semis

    expect(find.text('Aucune chaîne dans ce groupe'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // L'écran reste INTERACTIF : sélectionner un groupe (action sans
    // navigation) prend le focus — la télécommande n'est pas morte.
    await tester.tap(find.text('Toutes les chaînes'), warnIfMissed: false);
    await tvSettle(tester);
    expectTvFocusAlive();
    expect(tester.takeException(), isNull);

    await unmountTv(tester);
  });
}
