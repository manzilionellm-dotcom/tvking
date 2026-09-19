// =========================================================
//  assistance_controller_test.dart — aucun geste sans le oui
// =========================================================
//  La machine à états du consentement est testée à part
//  (assistance_session_test.dart). Ici on protège LE POINT UNIQUE DE
//  PASSAGE : `executer()`.
//
//  C'est la seule porte par laquelle un ordre venu du panel peut
//  atteindre l'écran d'un client. Si elle s'ouvre une fois de trop,
//  tout le reste ne sert à rien — le consentement le plus rigoureux du
//  monde ne protège personne s'il existe un chemin qui le contourne.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/assistance/assistance_controller.dart';
import 'package:tv_king/core/assistance/assistance_session.dart';

/// Un exécuteur qui NOTE tout ce qu'on lui demande. C'est lui le
/// témoin : s'il a bougé alors que le client n'avait pas dit oui, le
/// test doit tomber.
class _ExecuteurTemoin implements AssistanceExecuteur {
  final List<String> gestes = <String>[];
  bool reussit = true;

  @override
  Future<bool> ouvrirEcran(String nom) async {
    gestes.add('ouvrir:$nom');
    return reussit;
  }

  @override
  Future<bool> ouvrirCategorie(String nom) async {
    gestes.add('categorie:$nom');
    return reussit;
  }

  @override
  Future<bool> ouvrirChaine(String id) async {
    gestes.add('chaine:$id');
    return reussit;
  }

  @override
  Future<bool> basculerFavori(String id) async {
    gestes.add('favori:$id');
    return reussit;
  }

  @override
  Future<bool> retour() async {
    gestes.add('retour');
    return reussit;
  }

  @override
  String ecranCourant() => 'Accueil';
}

/// Un exécuteur qui EXPLOSE. Le pire moment pour planter, c'est
/// pendant qu'on aide quelqu'un.
class _ExecuteurQuiJette implements AssistanceExecuteur {
  @override
  Future<bool> ouvrirEcran(String nom) async => throw StateError('boum');
  @override
  Future<bool> ouvrirCategorie(String nom) async => throw StateError('boum');
  @override
  Future<bool> ouvrirChaine(String id) async => throw StateError('boum');
  @override
  Future<bool> basculerFavori(String id) async => throw StateError('boum');
  @override
  Future<bool> retour() async => throw StateError('boum');
  @override
  String ecranCourant() => '';
}

void main() {
  late AssistanceController c;
  late _ExecuteurTemoin ex;

  setUp(() {
    c = AssistanceController.instance;
    c.reinitialiserPourTest();
    ex = _ExecuteurTemoin();
    c.installerExecuteur(ex);
  });

  tearDown(() => c.reinitialiserPourTest());

  group('AUCUN GESTE SANS LE OUI DU CLIENT', () {
    test('au repos, rien ne passe et l\'exécuteur ne bouge pas', () async {
      expect(
        await c.executer(GesteGuidage.ouvrirEcran, <String, Object?>{
          'nom': 'favoris',
        }),
        isFalse,
      );
      expect(ex.gestes, isEmpty,
          reason: 'le témoin doit être resté immobile : personne n\'a '
              'demandé la main');
    });

    test('demande envoyée mais pas encore acceptée : rien ne passe',
        () async {
      c.demandeRecue('Lionel');
      expect(await c.executer(GesteGuidage.retour, const <String, Object?>{}),
          isFalse);
      expect(ex.gestes, isEmpty);
    });

    test('après le OUI, le geste passe et l\'exécuteur bouge', () async {
      c.demandeRecue('Lionel');
      c.accepter();
      expect(
        await c.executer(GesteGuidage.ouvrirEcran, <String, Object?>{
          'nom': 'favoris',
        }),
        isTrue,
      );
      expect(ex.gestes, <String>['ouvrir:favoris']);
    });

    test('APRÈS UN REFUS, plus rien ne passe', () async {
      c.demandeRecue('Lionel');
      c.refuser();
      expect(
        await c.executer(GesteGuidage.basculerFavori, <String, Object?>{
          'id': '42',
        }),
        isFalse,
      );
      expect(ex.gestes, isEmpty);
    });

    test('DÈS QUE LE CLIENT COUPE, plus un seul geste ne passe', () async {
      c.demandeRecue('Lionel');
      c.accepter();
      await c.executer(GesteGuidage.retour, const <String, Object?>{});
      expect(ex.gestes.length, 1);

      c.arreterParClient();

      for (final GesteGuidage g in GesteGuidage.values) {
        expect(await c.executer(g, const <String, Object?>{}), isFalse,
            reason: 'geste ${g.name} après coupure');
      }
      expect(ex.gestes.length, 1,
          reason: 'aucun geste supplémentaire n\'a atteint l\'app');
    });

    test('TOUS les gestes sont soumis à la même porte', () async {
      // Le test qui attrape l'oubli : quelqu'un ajoute un geste et
      // oublie de le faire passer par la session. Ici on les parcourt
      // TOUS, sans en nommer aucun — un geste ajouté demain est couvert
      // sans qu'on y pense.
      for (final GesteGuidage g in GesteGuidage.values) {
        c.reinitialiserPourTest();
        c.installerExecuteur(ex);
        expect(await c.executer(g, const <String, Object?>{}), isFalse,
            reason: 'le geste ${g.name} passe sans consentement !');
      }
    });
  });

  group('le support sait ce qui s\'est vraiment passé', () {
    test('un geste qui échoue est rapporté FAUX', () async {
      c.demandeRecue('Lionel');
      c.accepter();
      ex.reussit = false;
      expect(
        await c.executer(GesteGuidage.ouvrirEcran, <String, Object?>{
          'nom': 'inconnu',
        }),
        isFalse,
        reason: 'un support qui croit avoir cliqué alors que rien n\'a '
            'bougé finit par cliquer dix fois',
      );
    });

    test('un exécuteur qui EXPLOSE ne tue pas la session', () async {
      // Le client verrait son app se figer pendant qu'on l'aide.
      c.reinitialiserPourTest();
      c.installerExecuteur(_ExecuteurQuiJette());
      c.demandeRecue('Lionel');
      c.accepter();

      expect(
        await c.executer(GesteGuidage.retour, const <String, Object?>{}),
        isFalse,
      );
      expect(c.etat, EtatAssistance.active,
          reason: 'la session tient : on peut réessayer autre chose');
    });

    test('sans exécuteur installé, le geste est refusé, pas ignoré',
        () async {
      c.reinitialiserPourTest();
      c.demandeRecue('Lionel');
      c.accepter();
      expect(
        await c.executer(GesteGuidage.ouvrirEcran, <String, Object?>{
          'nom': 'favoris',
        }),
        isFalse,
      );
    });
  });

  group('la désignation — éclairer sans rien toucher', () {
    test('elle n\'a pas besoin d\'exécuteur', () async {
      c.reinitialiserPourTest();
      c.demandeRecue('Lionel');
      c.accepter();
      expect(
        await c.executer(GesteGuidage.designer, <String, Object?>{
          'cible': 'bouton_favoris',
          'phrase': 'C\'est ici',
        }),
        isTrue,
      );
      expect(c.designation?.cible, 'bouton_favoris');
      expect(c.designation?.phrase, 'C\'est ici');
    });

    test('mais elle reste soumise au consentement', () async {
      expect(
        await c.executer(GesteGuidage.designer, <String, Object?>{
          'cible': 'bouton_favoris',
        }),
        isFalse,
      );
      expect(c.designation, isNull,
          reason: 'écrire sur l\'écran d\'un client est déjà entrer chez lui');
    });

    test('effacer retire la désignation', () async {
      c.demandeRecue('Lionel');
      c.accepter();
      await c.executer(GesteGuidage.designer, <String, Object?>{
        'cible': 'x',
        'phrase': 'ici',
      });
      await c.executer(GesteGuidage.effacer, const <String, Object?>{});
      expect(c.designation, isNull);
    });

    test('la coupure efface ce qui était éclairé', () async {
      c.demandeRecue('Lionel');
      c.accepter();
      await c.executer(GesteGuidage.designer, <String, Object?>{
        'cible': 'x',
        'phrase': 'ici',
      });
      c.arreterParClient();
      expect(c.designation, isNull,
          reason: 'une flèche qui reste sur l\'écran après la fin ferait '
              'croire que quelqu\'un est encore là');
    });
  });

  test('l\'écran courant est rapporté, pour ne pas piloter à l\'aveugle',
      () {
    expect(c.ecranCourant(), 'Accueil');
    c.reinitialiserPourTest();
    expect(c.ecranCourant(), '',
        reason: 'sans exécuteur, on ne devine pas où est le client');
  });
}
