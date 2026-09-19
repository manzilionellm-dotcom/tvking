// =========================================================
//  assistance_controller_test.dart — la porte unique
// =========================================================
//  La machine à états est testée à part
//  (assistance_session_test.dart). Ici on protège LE POINT UNIQUE DE
//  PASSAGE : `executer()`.
//
//  C'est la seule porte par laquelle un ordre venu du panel peut
//  atteindre l'écran d'un client. Ce qu'elle garde a changé le
//  19/09/2026 — le propriétaire a demandé que la prise soit
//  automatique, donc la porte ne demande plus « le client a-t-il dit
//  oui ? ». Elle demande maintenant :
//
//    1. AU NOM DE QUI ? Sans nom, rien ne passe. Le bandeau affiché
//       chez le client porte toujours le nom de quelqu'un.
//    2. LE CLIENT A-T-IL COUPÉ ? Son « Arrêter » tient deux minutes,
//       même face à un support qui reclique.
//    3. QUELQU'UN D'AUTRE A-T-IL LA MAIN ? On ne la lui vole pas.
//
//  Et, dans tous les cas : ON DIT POURQUOI. Un « refusé » sans cause
//  a fait perdre une matinée au propriétaire le 19/09.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/assistance/assistance_controller.dart';
import 'package:tv_king/core/assistance/assistance_session.dart';

const String _moi = 'Lionel (7 MOTION)';

/// Un exécuteur qui NOTE tout ce qu'on lui demande. C'est lui le
/// témoin : s'il a bougé alors que personne n'avait la main, le test
/// doit tomber.
class _ExecuteurTemoin implements AssistanceExecuteur {
  final List<String> gestes = <String>[];

  /// La raison que l'exécuteur renverra. `null` = le geste a eu lieu.
  String? raison;

  @override
  Future<String?> ouvrirEcran(String nom) async {
    gestes.add('ouvrir:$nom');
    return raison;
  }

  @override
  Future<String?> ouvrirCategorie(String nom) async {
    gestes.add('categorie:$nom');
    return raison;
  }

  @override
  Future<String?> ouvrirChaine(String id) async {
    gestes.add('chaine:$id');
    return raison;
  }

  @override
  Future<String?> basculerFavori(String id) async {
    gestes.add('favori:$id');
    return raison;
  }

  @override
  Future<String?> retour() async {
    gestes.add('retour');
    return raison;
  }

  @override
  Future<String?> redemarrer() async {
    gestes.add('redemarrer');
    return raison;
  }

  @override
  Future<String?> resynchroniser() async {
    gestes.add('resync');
    return raison;
  }

  @override
  String ecranCourant() => 'Accueil';
}

/// Un exécuteur qui EXPLOSE. Le pire moment pour planter, c'est
/// pendant qu'on aide quelqu'un.
class _ExecuteurQuiJette implements AssistanceExecuteur {
  @override
  Future<String?> ouvrirEcran(String nom) async => throw StateError('boum');
  @override
  Future<String?> ouvrirCategorie(String nom) async => throw StateError('boum');
  @override
  Future<String?> ouvrirChaine(String id) async => throw StateError('boum');
  @override
  Future<String?> basculerFavori(String id) async => throw StateError('boum');
  @override
  Future<String?> retour() async => throw StateError('boum');
  @override
  Future<String?> redemarrer() async => throw StateError('boum');
  @override
  Future<String?> resynchroniser() async => throw StateError('boum');
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

  group('1. LA PRISE AUTOMATIQUE — mais jamais masquée', () {
    test('le PREMIER geste ouvre la session tout seul', () async {
      // C'est la demande du 19/09, testée telle quelle : le support
      // n'a rien cliqué avant, il appuie sur « Chaînes », ça part.
      expect(c.etat, EtatAssistance.inactive);
      final ResultatGeste r = await c.executer(
        GesteGuidage.ouvrirEcran,
        <String, Object?>{'nom': 'favoris'},
        support: _moi,
      );
      expect(r.ok, isTrue, reason: r.raison);
      expect(ex.gestes, <String>['ouvrir:favoris']);
      expect(c.etat, EtatAssistance.active,
          reason: 'et le bandeau est chez le client dans la même seconde');
      expect(c.support, _moi);
    });

    test('SANS NOM, AUCUN GESTE NE PASSE', () async {
      final ResultatGeste r = await c.executer(
        GesteGuidage.ouvrirEcran,
        <String, Object?>{'nom': 'favoris'},
        support: '  ',
      );
      expect(r.ok, isFalse);
      expect(r.raison, 'sans_nom_de_support');
      expect(ex.gestes, isEmpty,
          reason: 'le témoin doit être resté immobile');
      expect(c.etat, EtatAssistance.inactive);
    });

    test('TOUS les gestes passent par la même porte', () async {
      // Le test qui attrape l'oubli : quelqu'un ajoute un geste et
      // oublie de le faire passer par la session. On les parcourt TOUS,
      // sans en nommer aucun — un geste ajouté demain est couvert sans
      // qu'on y pense.
      for (final GesteGuidage g in GesteGuidage.values) {
        c.reinitialiserPourTest();
        c.installerExecuteur(ex);
        final ResultatGeste r =
            await c.executer(g, const <String, Object?>{}, support: '');
        expect(r.ok, isFalse,
            reason: 'le geste ${g.name} passe sans nom de support !');
        expect(r.raison, 'sans_nom_de_support', reason: g.name);
      }
    });

    test('le bouton « Prendre la main » pose le bandeau avant tout geste',
        () {
      expect(c.prendreLaMain(_moi), isTrue);
      expect(c.etat, EtatAssistance.active);
      expect(ex.gestes, isEmpty, reason: 'il n\'a encore rien touché');
    });
  });

  group('2. LE « ARRÊTER » DU CLIENT TIENT', () {
    test('après sa coupure, le support ne reprend PAS la main aussitôt',
        () async {
      //  LE TEST LE PLUS IMPORTANT DU FICHIER. Sans le répit, le client
      //  appuie sur « Arrêter », le support reclique une seconde plus
      //  tard, et le bandeau revient : le bouton d'arrêt ne serait
      //  qu'une décoration, et une sortie décorative est pire que pas
      //  de sortie — elle fait croire à une protection qui n'existe pas.
      await c.executer(GesteGuidage.retour, const <String, Object?>{},
          support: _moi);
      expect(ex.gestes.length, 1);

      c.arreterParClient();

      final ResultatGeste r = await c.executer(
        GesteGuidage.ouvrirEcran,
        <String, Object?>{'nom': 'favoris'},
        support: _moi,
      );
      expect(r.ok, isFalse);
      expect(r.raison, 'client_a_coupe');
      expect(ex.gestes.length, 1,
          reason: 'aucun geste supplémentaire n\'a atteint son app');
      expect(c.etat, EtatAssistance.inactive);
    });

    test('et AUCUN geste ne passe, pas même montrer du doigt', () async {
      c.arreterParClient();
      for (final GesteGuidage g in GesteGuidage.values) {
        final ResultatGeste r = await c.executer(
          g,
          <String, Object?>{'x': 0.5, 'y': 0.5, 'phrase': 'ici'},
          support: _moi,
        );
        expect(r.ok, isFalse, reason: 'geste ${g.name} après coupure');
        expect(r.raison, 'client_a_coupe', reason: g.name);
      }
      expect(c.designation, isNull,
          reason: 'écrire sur l\'écran de quelqu\'un qui vient de couper, '
              'c\'est entrer chez lui après qu\'il a fermé la porte');
    });

    test('quand le SUPPORT rend la main, il peut reprendre tout de suite',
        () async {
      // Il ne s'est rien refusé à lui-même : le répit ne concerne que
      // le non du client.
      await c.executer(GesteGuidage.retour, const <String, Object?>{},
          support: _moi);
      c.arreterParSupport();
      final ResultatGeste r = await c.executer(
        GesteGuidage.retour,
        const <String, Object?>{},
        support: _moi,
      );
      expect(r.ok, isTrue, reason: r.raison);
    });
  });

  group('3. ON NE VOLE PAS LA MAIN D\'UN AUTRE', () {
    test('un second support est refusé, et on lui dit pourquoi', () async {
      c.prendreLaMain(_moi);
      final ResultatGeste r = await c.executer(
        GesteGuidage.retour,
        const <String, Object?>{},
        support: 'Un autre revendeur',
      );
      expect(r.ok, isFalse);
      expect(r.raison, 'autre_session_en_cours');
      expect(c.support, _moi,
          reason: 'le nom affiché chez le client ne change pas sous ses yeux');
    });
  });

  group('les commandes de dépannage', () {
    test('resynchroniser passe par la même porte et l\'exécuteur bouge',
        () async {
      final ResultatGeste r = await c.executer(
        GesteGuidage.resynchroniser,
        const <String, Object?>{},
        support: _moi,
      );
      expect(r.ok, isTrue, reason: r.raison);
      expect(ex.gestes, <String>['resync']);
    });

    test('redémarrer aussi', () async {
      final ResultatGeste r = await c.executer(
        GesteGuidage.redemarrer,
        const <String, Object?>{},
        support: _moi,
      );
      expect(r.ok, isTrue, reason: r.raison);
      expect(ex.gestes, <String>['redemarrer']);
    });

    test('elles restent soumises au « Arrêter » du client', () async {
      c.arreterParClient();
      for (final GesteGuidage g in <GesteGuidage>[
        GesteGuidage.redemarrer,
        GesteGuidage.resynchroniser,
      ]) {
        final ResultatGeste r =
            await c.executer(g, const <String, Object?>{}, support: _moi);
        expect(r.ok, isFalse, reason: g.name);
        expect(r.raison, 'client_a_coupe', reason: g.name);
      }
      expect(ex.gestes, isEmpty);
    });

    test('sans nom de support, elles ne partent pas non plus', () async {
      final ResultatGeste r = await c.executer(
        GesteGuidage.redemarrer,
        const <String, Object?>{},
        support: '',
      );
      expect(r.ok, isFalse);
      expect(r.raison, 'sans_nom_de_support');
      expect(ex.gestes, isEmpty);
    });
  });

  group('4. LE SUPPORT SAIT CE QUI S\'EST VRAIMENT PASSÉ', () {
    test('la raison de l\'app remonte telle quelle', () async {
      ex.raison = 'ecran_inconnu';
      final ResultatGeste r = await c.executer(
        GesteGuidage.ouvrirEcran,
        <String, Object?>{'nom': 'nimporte_quoi'},
        support: _moi,
      );
      expect(r.ok, isFalse);
      expect(r.raison, 'ecran_inconnu',
          reason: 'c\'est la correction du 19/09 : « refuse_ou_echoue » ne '
              'disait pas au support quoi faire ensuite');
    });

    test('un exécuteur qui EXPLOSE ne tue pas la session', () async {
      // Le client verrait son app se figer pendant qu'on l'aide.
      c.reinitialiserPourTest();
      c.installerExecuteur(_ExecuteurQuiJette());
      final ResultatGeste r = await c.executer(
        GesteGuidage.retour,
        const <String, Object?>{},
        support: _moi,
      );
      expect(r.ok, isFalse);
      expect(r.raison, 'exception');
      expect(c.etat, EtatAssistance.active,
          reason: 'la session tient : on peut réessayer autre chose');
    });

    test('sans exécuteur installé, le geste est refusé, pas ignoré',
        () async {
      // Le cas du téléphone aujourd'hui : il n'a pas d'exécuteur. Le
      // panel affiche la cause en toutes lettres, au lieu d'un bouton
      // qui ne fait rien sans qu'on sache pourquoi.
      c.reinitialiserPourTest();
      final ResultatGeste r = await c.executer(
        GesteGuidage.ouvrirEcran,
        <String, Object?>{'nom': 'favoris'},
        support: _moi,
      );
      expect(r.ok, isFalse);
      expect(r.raison, 'plateforme_sans_executeur');
    });
  });

  group('5. LE DOIGT DU SUPPORT — « où je touche, il voit où je touche »', () {
    test('un point valide se pose, en fractions d\'écran', () async {
      final ResultatGeste r = await c.executer(
        GesteGuidage.pointer,
        <String, Object?>{'x': 0.25, 'y': 0.8, 'phrase': 'C\'est ici'},
        support: _moi,
      );
      expect(r.ok, isTrue, reason: r.raison);
      expect(c.designation?.aUnHalo, isTrue);
      expect(c.designation?.x, 0.25);
      expect(c.designation?.y, 0.8);
      expect(c.designation?.phrase, 'C\'est ici');
    });

    test('IL MARCHE SANS EXÉCUTEUR — montrer ne touche à rien', () async {
      // C'est ce qui rend le doigt utilisable sur téléphone dès
      // aujourd'hui, alors que les écrans, eux, ne s'ouvrent pas encore.
      c.reinitialiserPourTest();
      final ResultatGeste r = await c.executer(
        GesteGuidage.pointer,
        <String, Object?>{'x': 0.5, 'y': 0.5},
        support: _moi,
      );
      expect(r.ok, isTrue, reason: r.raison);
      expect(c.designation?.aUnHalo, isTrue);
    });

    test('UNE POSITION HORS ÉCRAN EST REFUSÉE, jamais rabotée', () async {
      //  Ramener 1,4 à 1 poserait le halo dans un coin que personne n'a
      //  désigné — et le client irait regarder là. On refuse.
      for (final Object? mauvais in <Object?>[
        1.4, -0.1, 'gauche', null, '', double.nan, double.infinity,
      ]) {
        c.reinitialiserPourTest();
        final ResultatGeste r = await c.executer(
          GesteGuidage.pointer,
          <String, Object?>{'x': mauvais, 'y': 0.5},
          support: _moi,
        );
        expect(r.ok, isFalse, reason: 'x = $mauvais');
        expect(r.raison, 'position_invalide', reason: 'x = $mauvais');
        expect(c.designation, isNull, reason: 'x = $mauvais');
      }
    });

    test('les bords exacts, eux, sont acceptés', () async {
      // 0 et 1 sont des endroits parfaitement légitimes : le coin
      // supérieur gauche et le coin inférieur droit d'un écran.
      for (final List<double> p in <List<double>>[
        <double>[0, 0],
        <double>[1, 1],
      ]) {
        c.reinitialiserPourTest();
        final ResultatGeste r = await c.executer(
          GesteGuidage.pointer,
          <String, Object?>{'x': p[0], 'y': p[1]},
          support: _moi,
        );
        expect(r.ok, isTrue, reason: '${p[0]} / ${p[1]} → ${r.raison}');
      }
    });

    test('une position lue depuis du texte marche aussi', () async {
      // Le JSON du hub peut livrer « 0.5 » plutôt que 0.5 selon les
      // versions ; refuser pour ça serait refuser un geste correct.
      final ResultatGeste r = await c.executer(
        GesteGuidage.pointer,
        <String, Object?>{'x': '0.5', 'y': '0.25'},
        support: _moi,
      );
      expect(r.ok, isTrue, reason: r.raison);
      expect(c.designation?.x, 0.5);
    });

    test('déplacer le doigt garde la phrase affichée', () async {
      await c.executer(
        GesteGuidage.pointer,
        <String, Object?>{'x': 0.1, 'y': 0.1, 'phrase': 'Regarde ici'},
        support: _moi,
      );
      await c.executer(
        GesteGuidage.pointer,
        <String, Object?>{'x': 0.9, 'y': 0.9},
        support: _moi,
      );
      expect(c.designation?.x, 0.9);
      expect(c.designation?.phrase, 'Regarde ici',
          reason: 'le support déplace son doigt en parlant ; sa phrase ne '
              'doit pas s\'effacer à chaque mouvement');
    });

    test('afficher une phrase n\'efface pas le doigt posé', () async {
      await c.executer(
        GesteGuidage.pointer,
        <String, Object?>{'x': 0.4, 'y': 0.6},
        support: _moi,
      );
      await c.executer(
        GesteGuidage.designer,
        <String, Object?>{'phrase': 'Appuie sur OK'},
        support: _moi,
      );
      expect(c.designation?.aUnHalo, isTrue);
      expect(c.designation?.phrase, 'Appuie sur OK');
    });

    test('effacer retire le doigt ET la phrase', () async {
      await c.executer(
        GesteGuidage.pointer,
        <String, Object?>{'x': 0.4, 'y': 0.6, 'phrase': 'ici'},
        support: _moi,
      );
      await c.executer(GesteGuidage.effacer, const <String, Object?>{},
          support: _moi);
      expect(c.designation, isNull);
    });

    test('la coupure efface ce qui était montré', () async {
      await c.executer(
        GesteGuidage.pointer,
        <String, Object?>{'x': 0.4, 'y': 0.6, 'phrase': 'ici'},
        support: _moi,
      );
      c.arreterParClient();
      expect(c.designation, isNull,
          reason: 'un doigt qui reste sur l\'écran après la fin ferait '
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
