// =========================================================
//  stream_slot_test.dart — « un seul flux à la fois », vérifié
// =========================================================
//  Scénario terrain (17/08) : « j'ouvre le cinéma, je pars sur France 2 →
//  un autre flux est déjà en route ». Ces tests verrouillent la règle qui
//  l'empêche : réclamer le créneau DÉMONTE les autres consommateurs et
//  ATTEND qu'ils aient fini avant de rendre la main.
// =========================================================

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/playback/stream_slot.dart';

void main() {
  late StreamSlot slot;
  setUp(() {
    slot = StreamSlot.instance;
    slot.resetForTest();
  });

  test('réclamer démonte les autres détenteurs', () async {
    final List<String> demontes = <String>[];
    final Object film = Object();
    final Object chaine = Object();
    slot.register(film,
        label: 'film', teardown: () async => demontes.add('film'));
    slot.register(chaine,
        label: 'chaine', teardown: () async => demontes.add('chaine'));

    await slot.claim(chaine);
    expect(demontes, <String>['film']);
  });

  test('la réclamation ATTEND la fin du démontage', () async {
    bool fini = false;
    final Object lent = Object();
    final Object rapide = Object();
    slot.register(lent, label: 'lent', teardown: () async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      fini = true;
    });
    slot.register(rapide, label: 'rapide', teardown: () async {});

    await slot.claim(rapide);
    // C'est TOUT le correctif : sans cette attente, la nouvelle connexion
    // partait pendant que l'ancienne se fermait encore.
    expect(fini, isTrue);
  });

  test('un démontage qui échoue ne bloque pas la lecture suivante', () async {
    final Object casse = Object();
    final Object neuf = Object();
    slot.register(casse,
        label: 'casse', teardown: () async => throw StateError('boom'));
    slot.register(neuf, label: 'neuf', teardown: () async {});

    // Fail-open assumé : mieux vaut un refus serveur qu'un écran noir.
    await expectLater(slot.claim(neuf), completes);
  });

  test('un démontage qui ne rend jamais la main est plafonné', () async {
    final Object bloque = Object();
    final Object neuf = Object();
    slot.register(bloque,
        label: 'bloque', teardown: () => Completer<void>().future);
    slot.register(neuf, label: 'neuf', teardown: () async {});

    await expectLater(slot.claim(neuf), completes);
  });

  test('les tuiles multi-vue se tolèrent entre elles', () async {
    final List<String> demontes = <String>[];
    final Object a = Object();
    final Object b = Object();
    final Object apercu = Object();
    slot.register(a,
        group: StreamSlot.groupMultiview,
        label: 'tuile-a',
        teardown: () async => demontes.add('a'));
    slot.register(b,
        group: StreamSlot.groupMultiview,
        label: 'tuile-b',
        teardown: () async => demontes.add('b'));
    slot.register(apercu,
        label: 'apercu', teardown: () async => demontes.add('apercu'));

    await slot.claim(a);
    // La tuile sœur survit ; l'aperçu, lui, rend sa connexion.
    expect(demontes, <String>['apercu']);
  });

  test('les téléchargements sont démontés par n’importe quelle lecture',
      () async {
    bool coupe = false;
    final Object dl = Object();
    final Object lecteur = Object();
    slot.register(dl,
        group: StreamSlot.groupDownloads,
        label: 'telechargements',
        teardown: () async => coupe = true);
    slot.register(lecteur, label: 'lecteur', teardown: () async {});

    await slot.claim(lecteur);
    expect(coupe, isTrue);
  });

  // ---- handOff : la fermeture d'un écran quitté est ATTENDUE ----
  //  Scénario terrain (19/08) : « je quitte un film, je lance une chaîne →
  //  limite de connexions 1/1 ». dispose() est synchrone : sans détenteur de
  //  transition, le claim() suivant ne trouvait plus personne à attendre et
  //  ouvrait sa connexion pendant que celle du film se fermait encore.

  test('après handOff, la réclamation suivante attend la fermeture', () async {
    final Object filmQuitte = Object();
    final Object chaine = Object();
    slot.register(filmQuitte, label: 'film', teardown: () async {});
    slot.register(chaine, label: 'chaine', teardown: () async {});

    bool fermetureFinie = false;
    final Completer<void> fermeture = Completer<void>();
    slot.handOff(
      filmQuitte,
      fermeture.future.then((_) => fermetureFinie = true),
      label: 'fermeture film',
    );

    final Future<void> reclamation = slot.claim(chaine);
    // La fermeture n'a pas fini : la réclamation ne doit pas avoir abouti.
    bool reclamationFinie = false;
    unawaited(reclamation.then((_) => reclamationFinie = true));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(reclamationFinie, isFalse,
        reason: 'claim() doit attendre la fermeture du film quitté');

    fermeture.complete();
    await reclamation;
    expect(fermetureFinie, isTrue);
  });

  test('le détenteur de transition se retire tout seul à la fin', () async {
    final Object ecran = Object();
    slot.register(ecran, label: 'ecran', teardown: () async {});
    final Completer<void> fermeture = Completer<void>();
    slot.handOff(ecran, fermeture.future, label: 'fermeture ecran');
    expect(slot.holdersForTest, hasLength(1));

    fermeture.complete();
    // Laisse le whenComplete s'exécuter.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(slot.holdersForTest, isEmpty);
  });

  test('une fermeture qui échoue ne bloque ni la réclamation ni le créneau',
      () async {
    final Object ecran = Object();
    final Object suivant = Object();
    slot.register(ecran, label: 'ecran', teardown: () async {});
    slot.register(suivant, label: 'suivant', teardown: () async {});
    slot.handOff(
      ecran,
      Future<void>.error(StateError('stop natif KO')),
      label: 'fermeture cassee',
    );

    await expectLater(slot.claim(suivant), completes);
    await Future<void>.delayed(Duration.zero);
    // Le détenteur de transition ne doit pas rester coincé après l'erreur.
    expect(slot.holdersForTest.toList(), <String>['solo:suivant']);
  });

  test('une fermeture qui ne rend jamais la main est plafonnée', () async {
    final Object ecran = Object();
    final Object suivant = Object();
    slot.register(ecran, label: 'ecran', teardown: () async {});
    slot.register(suivant, label: 'suivant', teardown: () async {});
    slot.handOff(ecran, Completer<void>().future, label: 'fermeture bloquee');

    // Fail-open : mieux vaut un refus serveur qu'un écran noir définitif.
    await expectLater(slot.claim(suivant), completes);
  });

  // ---- claimIfNeeded : zéro coût quand il n'y a rien à faire ----
  //  Régression CI du 19/08 : un claim() systématique dans l'aperçu
  //  introduisait des sauts de microtâches même sans aucun détenteur à
  //  démonter — l'aperçu ne démarrait plus dans la même frame que son tick.

  test('claimIfNeeded → null quand rien à démonter (aucun saut asynchrone)',
      () {
    final Object seul = Object();
    slot.register(seul, label: 'seul', teardown: () async {});
    expect(slot.claimIfNeeded(seul), isNull);
  });

  test('claimIfNeeded → vraie réclamation quand un autre détenteur existe',
      () async {
    bool demonte = false;
    final Object ancien = Object();
    final Object nouveau = Object();
    slot.register(ancien,
        label: 'ancien', teardown: () async => demonte = true);
    slot.register(nouveau, label: 'nouveau', teardown: () async {});

    final Future<void>? wait = slot.claimIfNeeded(nouveau);
    expect(wait, isNotNull);
    await wait;
    expect(demonte, isTrue);
  });

  test('claimIfNeeded → non-null tant qu\'une réclamation est en vol '
      '(la sérialisation est préservée)', () async {
    final Object lent = Object();
    final Object a = Object();
    final Object b = Object();
    final Completer<void> fermeture = Completer<void>();
    slot.register(lent, label: 'lent', teardown: () => fermeture.future);
    slot.register(a, label: 'a', teardown: () async {});
    slot.register(b, label: 'b', teardown: () async {});

    final Future<void> first = slot.claim(a); // démonte `lent` (en cours)
    slot.unregister(lent); // même parti, la réclamation en vol reste en vol
    final Future<void>? second = slot.claimIfNeeded(b);
    expect(second, isNotNull,
        reason: 'une réclamation en vol impose la sérialisation');
    fermeture.complete();
    await first;
    await second;
  });

  test('deux réclamations simultanées se sérialisent', () async {
    final List<String> ordre = <String>[];
    final Object un = Object();
    final Object deux = Object();
    final Object cible = Object();
    slot.register(cible, label: 'cible', teardown: () async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      ordre.add('demontage');
    });
    slot.register(un, label: 'un', teardown: () async {});
    slot.register(deux, label: 'deux', teardown: () async {});

    await Future.wait(<Future<void>>[
      slot.claim(un).then((_) => ordre.add('un')),
      slot.claim(deux).then((_) => ordre.add('deux')),
    ]);
    // La cible n'est démontée qu'une fois, et personne ne double l'autre.
    expect(ordre.first, 'demontage');
    expect(ordre.length, greaterThanOrEqualTo(3));
  });
}
