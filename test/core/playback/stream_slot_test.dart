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
