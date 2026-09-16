// =========================================================
//  instant_activation_test.dart — QUELLE chaîne part toute seule
// =========================================================
//  Le maillon manquant du 16/09/2026 : le panel pousse un M3U, l'import
//  réussit… et l'app affichait la grille des catégories au lieu de
//  lancer quoi que ce soit.
//
//  Ce que ces tests verrouillent :
//   1. Sans consigne, on lance la PREMIÈRE chaîne — jamais une chaîne
//      adulte, parce que la première image d'une activation se voit
//      parfois devant toute la famille.
//   2. Le panel a le dernier mot quand il désigne une chaîne.
//   3. Le jeton se consomme UNE SEULE FOIS : un `sync all` suivi d'un
//      `sync sources` arrive en rafale, et deux lecteurs qui s'ouvrent,
//      c'est pire que zéro.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/playlists/data/instant_activation.dart';

Channel _ch(String id, String nom, {String categorie = 'France'}) => Channel(
      id: id,
      name: nom,
      category: categorie,
      streamUrl: 'http://exemple.tv/$id.ts',
      isLive: true,
    );

void main() {
  setUp(InstantActivation.reinitialiserPourTest);

  group('chaineADemarrer — sans consigne du panel', () {
    test('liste vide → rien à lancer (jamais d\'exception)', () {
      expect(chaineADemarrer(const <Channel>[]), isNull);
    });

    test('la première chaîne', () {
      final List<Channel> l = <Channel>[_ch('1', 'TF1'), _ch('2', 'France 2')];
      expect(chaineADemarrer(l)!.id, '1');
    });

    test('une chaîne adulte en tête est ENJAMBÉE', () {
      //  Elle est légitime dans la liste — le client l'a achetée. Mais
      //  elle ne doit pas être la première image d'une activation.
      final List<Channel> l = <Channel>[
        _ch('x', 'XXX Channel', categorie: 'Adult'),
        _ch('1', 'TF1'),
      ];
      final Channel? c = chaineADemarrer(l);
      expect(c, isNotNull);
      expect(c!.id, '1');
    });

    test('une liste FAITE QUE de ça joue quand même', () {
      //  Bouquet spécialisé : refuser de jouer serait pire que jouer ce
      //  que le client a effectivement acheté.
      final List<Channel> l = <Channel>[
        _ch('x1', 'XXX One', categorie: 'Adult'),
        _ch('x2', 'XXX Two', categorie: 'Adult'),
      ];
      expect(chaineADemarrer(l), isNotNull);
    });
  });

  group('chaineADemarrer — le panel désigne', () {
    final List<Channel> l = <Channel>[
      _ch('1', 'TF1'),
      _ch('2', 'France 2'),
      _ch('3', 'M6'),
    ];

    test('par identifiant : le revendeur a le dernier mot', () {
      expect(chaineADemarrer(l, demandee: '3')!.name, 'M6');
    });

    test('par NOM : le panel affiche des noms, pas des identifiants', () {
      expect(chaineADemarrer(l, demandee: 'France 2')!.id, '2');
      expect(chaineADemarrer(l, demandee: 'france 2')!.id, '2',
          reason: 'la casse ne doit pas décider');
    });

    test('désignation introuvable → on retombe sur la règle générale', () {
      //  Ne JAMAIS bloquer parce qu\'une consigne est périmée : le client
      //  aurait un écran vide au lieu de sa télé.
      expect(chaineADemarrer(l, demandee: 'Chaine supprimee')!.id, '1');
    });

    test('désignation vide ou blanche → ignorée', () {
      expect(chaineADemarrer(l, demandee: '')!.id, '1');
      expect(chaineADemarrer(l, demandee: '   ')!.id, '1');
    });
  });

  group('le jeton ne se consomme QU\'UNE FOIS', () {
    test('deuxième lecteur impossible sur une rafale sync all + sources', () {
      final List<Channel> l = <Channel>[_ch('1', 'TF1')];
      InstantActivation.demander(
        DemandeLectureInstantanee(chaine: l.first, liste: l),
      );
      expect(InstantActivation.enAttente, isTrue);

      expect(InstantActivation.consommer(), isNotNull);
      expect(InstantActivation.consommer(), isNull,
          reason: 'deux lecteurs ouverts, c\'est pire que zéro');
      expect(InstantActivation.enAttente, isFalse);
    });

    test('le tick monte à chaque demande — c\'est lui qui réveille l\'écran',
        () {
      final List<Channel> l = <Channel>[_ch('1', 'TF1')];
      final int avant = InstantActivation.tick.value;
      InstantActivation.demander(
        DemandeLectureInstantanee(chaine: l.first, liste: l),
      );
      expect(InstantActivation.tick.value, avant + 1);
    });

    test('la liste voyage avec la chaîne (zapping dès la 1re seconde)', () {
      final List<Channel> l = <Channel>[_ch('1', 'TF1'), _ch('2', 'France 2')];
      InstantActivation.demander(
        DemandeLectureInstantanee(chaine: l.first, liste: l),
      );
      final DemandeLectureInstantanee d = InstantActivation.consommer()!;
      expect(d.liste.length, 2,
          reason: 'sans elle, le client atterrit sur une chaîne dont il ne '
              'peut pas sortir autrement qu\'en revenant en arrière');
    });
  });
}
