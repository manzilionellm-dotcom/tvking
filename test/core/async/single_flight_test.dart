// =========================================================
//  single_flight_test.dart — Anti-doublon des appels simultanés
// =========================================================
//  Ce garde-fou vient d'un vrai symptôme client (22/08, photo « le
//  Cinéma côté mobile tarde à venir ») : l'accueil préchauffe le
//  catalogue de films en tâche de fond, et le client ouvre le Cinéma
//  pendant ce temps. Sans lui, les deux appels téléchargeaient chacun le
//  catalogue ENTIER — on doublait exactement l'attente qu'on voulait
//  supprimer, sur le réseau ET en mémoire.
//
//  Le bug qu'il empêche est INVISIBLE en lecture de code : tout marche,
//  c'est juste deux fois plus lent. D'où ces tests.
// =========================================================
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/async/single_flight.dart';

void main() {
  test('deux appels SIMULTANÉS → un seul travail, le même résultat', () async {
    final SingleFlight<int> flight = SingleFlight<int>();
    int lancements = 0;
    final Completer<int> porte = Completer<int>();

    Future<int> travail() {
      lancements++;
      return porte.future;
    }

    // Le préchauffage part…
    final Future<int> a = flight.run(travail);
    // …et le client ouvre l'écran pendant ce temps-là.
    final Future<int> b = flight.run(travail);

    expect(lancements, 1, reason: 'UN SEUL téléchargement, pas deux');
    expect(flight.isRunning, isTrue);

    porte.complete(42);
    expect(await a, 42);
    expect(await b, 42, reason: 'le second appelant reçoit le même résultat');
    expect(flight.isRunning, isFalse, reason: 'la place est libérée');
  });

  test('une fois TERMINÉ, l\'appel suivant relance un travail neuf', () async {
    final SingleFlight<int> flight = SingleFlight<int>();
    int lancements = 0;
    Future<int> travail() async {
      lancements++;
      return lancements;
    }

    expect(await flight.run(travail), 1);
    // Ce n'est PAS un cache : le catalogue doit pouvoir être rechargé.
    expect(await flight.run(travail), 2);
    expect(lancements, 2);
  });

  test('une ERREUR atteint tous les appelants, puis la place se libère',
      () async {
    final SingleFlight<int> flight = SingleFlight<int>();
    final Completer<int> porte = Completer<int>();
    int lancements = 0;

    Future<int> quiEchoue() {
      lancements++;
      return porte.future;
    }

    final Future<int> a = flight.run(quiEchoue);
    final Future<int> b = flight.run(quiEchoue);
    porte.completeError(StateError('réseau coupé'));

    await expectLater(a, throwsA(isA<StateError>()));
    await expectLater(b, throwsA(isA<StateError>()));
    expect(lancements, 1);

    // LE POINT CRUCIAL : un échec ne doit jamais condamner les ouvertures
    // suivantes à ce même échec. La place doit être rendue.
    expect(flight.isRunning, isFalse);
    expect(await flight.run(() async => 7), 7);
  });

  test('une erreur SYNCHRONE suit le même chemin (pas de fuite)', () async {
    final SingleFlight<int> flight = SingleFlight<int>();
    // Un travail qui lève AVANT son premier `await` ne doit pas remonter
    // en exception brute chez l'appelant, ni laisser la place occupée.
    await expectLater(
      flight.run(() => throw StateError('boum')),
      throwsA(isA<StateError>()),
    );
    expect(flight.isRunning, isFalse);
    expect(await flight.run(() async => 1), 1);
  });

  test('trois appelants simultanés partagent le même unique travail',
      () async {
    final SingleFlight<String> flight = SingleFlight<String>();
    int lancements = 0;
    final Completer<String> porte = Completer<String>();
    Future<String> travail() {
      lancements++;
      return porte.future;
    }

    final List<Future<String>> tous = <Future<String>>[
      flight.run(travail),
      flight.run(travail),
      flight.run(travail),
    ];
    porte.complete('catalogue');
    expect(await Future.wait(tous), <String>['catalogue', 'catalogue', 'catalogue']);
    expect(lancements, 1);
  });
}
