// =========================================================
//  assistance_session_test.dart — ce que le client garde, toujours
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE, EN TROIS TEMPS :
//
//   18/09 — « Je veux entrer dans le téléphone d'un client, s'il me
//            permet. J'appuie sur mon ordinateur et ça s'appuie chez
//            lui. »
//   18/09 — « Un client me dit : je ne trouve pas les favoris. Je lui
//            dis : regarde ta télé. Et j'appuie — chaîne, favoris,
//            tout. »
//   19/09 — « Je veux que ça soit automatique. »
//
//  CE QUE CES TESTS PROTÈGENT, ET POURQUOI C'EST LE FICHIER LE PLUS
//  SÉRIEUX DE LA SEMAINE : ils ne protègent pas une fonctionnalité,
//  ils protègent un CLIENT.
//
//  LA QUESTION POSÉE SUR SA TÉLÉ A DISPARU le 19/09, et c'est une
//  décision du propriétaire, prise après l'avoir essayé en vrai : le
//  client est au téléphone, il dit « oui vas-y » à l'oreille du
//  support, pas à sa télécommande. Attendre un appui qui ne vient
//  jamais n'était pas une protection, c'était une panne.
//
//  CE QUI RESTE EST DONC TOUT CE QUI PROTÈGE ENCORE, et ces tests
//  existent pour que personne ne le retire par inadvertance :
//
//   1. ON NE GUIDE JAMAIS MASQUÉ. Pas de nom → pas de session. Le
//      bandeau du client porte toujours le nom de quelqu'un.
//   2. LE CLIENT PEUT TOUJOURS ARRÊTER. Il n'existe aucun état d'où il
//      ne peut pas sortir. Ce test doit rester vrai pour toujours.
//   3. ÇA S'ARRÊTE TOUT SEUL. Une assistance oubliée ouverte est une
//      assistance qui regarde.
//   4. UNE SEULE À LA FOIS, ET ON NE VOLE PAS LA MAIN D'UN AUTRE.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/assistance/assistance_session.dart';

/// Une horloge qu'on avance à la main : les règles de ce fichier sont
/// des règles de TEMPS, et attendre 30 vraies minutes dans un test
/// voudrait dire ne jamais l'écrire.
class _Horloge {
  DateTime t = DateTime(2026, 9, 19, 12);
  DateTime lire() => t;
  void avancer(Duration d) => t = t.add(d);
}

void main() {
  late _Horloge h;
  late AssistanceSession s;

  setUp(() {
    h = _Horloge();
    s = AssistanceSession(horloge: h.lire);
  });

  group('1. ON NE GUIDE JAMAIS MASQUÉ', () {
    test('au repos, le guidage est interdit', () {
      expect(s.etat, EtatAssistance.inactive);
      expect(s.guidagePermis, isFalse);
    });

    test('prendre la main ouvre la session TOUT DE SUITE', () {
      // C'est le changement du 19/09 : plus d'état intermédiaire, plus
      // d'attente. Le support appuie, la session est ouverte, le
      // bandeau s'affiche chez le client.
      expect(s.prendre('Lionel'), isTrue);
      expect(s.etat, EtatAssistance.active);
      expect(s.guidagePermis, isTrue);
    });

    test('SANS NOM, RIEN NE S\'OUVRE', () {
      // Un bandeau qui dirait « quelqu'un vous aide » est plus
      // inquiétant qu'utile : le client ne peut ni reconnaître la
      // personne qu'il a au téléphone, ni se plaindre de celle qu'il
      // n'a pas appelée.
      expect(s.prendre(''), isFalse);
      expect(s.prendre('   '), isFalse);
      expect(s.etat, EtatAssistance.inactive);
      expect(s.guidagePermis, isFalse);
    });

    test('le nom est nettoyé, et il est lisible', () {
      s.prendre('  Lionel (7 MOTION)  ');
      expect(s.support, 'Lionel (7 MOTION)');
    });

    test('hors session, il n\'y a personne à nommer', () {
      expect(s.support, isEmpty);
      s.prendre('Lionel');
      s.arreterParClient();
      expect(s.support, isEmpty,
          reason: 'un bandeau fermé ne doit garder aucun nom affichable');
    });
  });

  group('2. LE CLIENT PEUT TOUJOURS ARRÊTER', () {
    test('il coupe une session en cours, à la seconde', () {
      s.prendre('Lionel');
      h.avancer(const Duration(seconds: 5));
      s.arreterParClient();
      expect(s.guidagePermis, isFalse);
      expect(s.derniereFin, FinAssistance.arreteeParClient);
    });

    test('IL N\'EXISTE AUCUN ÉTAT D\'OÙ IL NE PEUT PAS SORTIR', () {
      // Ce test doit rester vrai pour toujours. Le jour où il tombe,
      // c'est qu'on a fabriqué un mode dont le client est prisonnier.
      for (final void Function() amener in <void Function()>[
        () {},
        () => s.prendre('Lionel'),
        () {
          s.prendre('Lionel');
          s.noterOrdre();
        },
        () {
          s.prendre('Lionel');
          h.avancer(const Duration(minutes: 20));
          s.noterOrdre();
        },
      ]) {
        h = _Horloge();
        s = AssistanceSession(horloge: h.lire);
        amener();
        s.arreterParClient();
        expect(s.guidagePermis, isFalse);
        expect(s.etat, EtatAssistance.inactive);
      }
    });

    test('dès qu\'il coupe, plus un seul ordre ne passe', () {
      s.prendre('Lionel');
      s.noterOrdre();
      s.arreterParClient();
      expect(s.noterOrdre(), isFalse);
    });

    test('le support peut rendre la main de son côté', () {
      s.prendre('Lionel');
      s.arreterParSupport();
      expect(s.guidagePermis, isFalse);
      expect(s.derniereFin, FinAssistance.arreteeParSupport);
    });

    test('SON « ARRÊTER » TIENT — le support ne reprend pas aussitôt', () {
      //  LE TEST QUI DONNE SON POIDS AU BOUTON. Tant que la session
      //  commençait par une question, « Arrêter » suffisait : pour
      //  revenir il fallait reposer la question. Depuis que la prise
      //  est automatique, sans ce répit le support reclique une
      //  seconde plus tard et le bandeau revient — un bouton d'arrêt
      //  décoratif est pire que pas de bouton du tout.
      s.prendre('Lionel');
      s.arreterParClient();
      expect(s.clientARefuse, isTrue);
      expect(s.prendre('Lionel'), isFalse);

      h.avancer(repitApresArret - const Duration(seconds: 1));
      expect(s.prendre('Lionel'), isFalse,
          reason: 'presque écoulé n\'est pas écoulé');

      h.avancer(const Duration(seconds: 2));
      expect(s.clientARefuse, isFalse);
      expect(s.prendre('Lionel'), isTrue,
          reason: 'passé le répit, le support peut le rappeler et reprendre');
    });

    test('il peut couper même s\'il n\'y avait plus de session', () {
      // Il appuie sur « Arrêter » pile au moment où le bandeau part
      // tout seul. Son geste doit compter autant.
      s.arreterParClient();
      expect(s.prendre('Lionel'), isFalse);
      expect(s.clientARefuse, isTrue);
    });
  });

  group('3. ÇA S\'ARRÊTE TOUT SEUL', () {
    test('silence trop long → coupé', () {
      s.prendre('Lionel');
      h.avancer(inactiviteMax);
      s.rafraichir();
      expect(s.guidagePermis, isFalse);
      expect(s.derniereFin, FinAssistance.silence);
    });

    test('chaque ordre repousse le silence', () {
      //  LES CHIFFRES SONT CHOISIS, PAS PRIS AU HASARD — un premier
      //  essai avançait cinq fois de 9 min, soit 45 min : la session
      //  était bien coupée, mais par la DURÉE TOTALE, pas par le
      //  silence. Le test passait pour la mauvaise raison et n'aurait
      //  rien attrapé si le report du silence avait disparu.
      //
      //  Ici : trois pas de 9 min = 27 min, donc sous les 30 min de
      //  durée totale. Et chaque pas (9 min) reste sous les 10 min de
      //  silence. Sans report, le deuxième pas ferait déjà 18 min
      //  depuis le dernier ordre connu et couperait — c'est exactement
      //  ce que ce test prouve.
      s.prendre('Lionel');
      for (int i = 0; i < 3; i++) {
        h.avancer(inactiviteMax - const Duration(minutes: 1));
        expect(s.noterOrdre(), isTrue, reason: 'tour $i');
      }
      expect(s.guidagePermis, isTrue);
    });

    test('mais RIEN ne prolonge la durée totale', () {
      // Un support très actif finit quand même par être coupé : sans
      // cette borne, une session ouverte le matin peut courir tout
      // l'après-midi.
      s.prendre('Lionel');
      for (int i = 0; i < 100; i++) {
        h.avancer(const Duration(seconds: 30));
        s.noterOrdre();
      }
      s.rafraichir();
      expect(s.guidagePermis, isFalse);
      expect(s.derniereFin, FinAssistance.tempsEcoule);
    });

    test('RECLIQUER « PRENDRE LA MAIN » NE REMET PAS LE COMPTEUR À ZÉRO', () {
      //  LE PIÈGE EXACT : le support reclique en cours de route ; si
      //  chaque clic rouvrait une session neuve, la limite de
      //  30 minutes ne limiterait plus rien du tout.
      //
      //  LA SESSION DOIT RESTER VIVANTE PENDANT LE TEST, d'où les
      //  ordres tous les 9 min. Mon premier essai avançait de 25 min
      //  d'un coup : la session était déjà morte de SILENCE (10 min),
      //  et reprendre la main marchait — normal, et sans rapport avec
      //  ce qu'on veut prouver. Le test passait pour la mauvaise
      //  raison, à l'envers.
      s.prendre('Lionel');
      for (int i = 0; i < 3; i++) {
        h.avancer(const Duration(minutes: 9));
        expect(s.noterOrdre(), isTrue);
      }
      // 27 min écoulées, session bien vivante.
      expect(s.prendre('Lionel'), isFalse,
          reason: 'la session est déjà ouverte : on ne la rouvre pas');
      expect(s.guidagePermis, isTrue, reason: 'mais elle continue');
      h.avancer(const Duration(minutes: 4));
      s.rafraichir();
      expect(s.guidagePermis, isFalse,
          reason: '31 min depuis l\'ouverture : la limite a tenu');
      expect(s.derniereFin, FinAssistance.tempsEcoule);
    });

    test('après expiration, l\'ordre est refusé', () {
      s.prendre('Lionel');
      h.avancer(dureeMax);
      expect(s.noterOrdre(), isFalse);
    });

    test('le temps restant est annoncé, et il décroît', () {
      s.prendre('Lionel');
      final Duration? d1 = s.tempsRestant;
      h.avancer(const Duration(minutes: 2));
      final Duration? d2 = s.tempsRestant;
      expect(d1, isNotNull);
      expect(d2, isNotNull);
      expect(d2!, lessThan(d1!),
          reason: 'le bandeau doit pouvoir dire « ça s\'arrête dans… » — '
              'c\'est rassurant ET c\'est vrai');
    });

    test('hors session, aucun temps restant à annoncer', () {
      expect(s.tempsRestant, isNull);
      s.prendre('Lionel');
      s.arreterParClient();
      expect(s.tempsRestant, isNull);
    });
  });

  group('4. UNE SEULE À LA FOIS', () {
    test('au repos, l\'ordre est refusé', () {
      expect(s.noterOrdre(), isFalse);
    });

    test('ON NE VOLE PAS LA MAIN DE QUELQU\'UN D\'AUTRE', () {
      expect(s.prendre('Lionel'), isTrue);
      expect(s.prendre('Un autre revendeur'), isFalse);
      expect(s.support, 'Lionel',
          reason: 'le client doit savoir QUI, et que ça ne change pas '
              'sous ses yeux');
    });

    test('après un arrêt du SUPPORT, il reprend tout de suite', () {
      s.prendre('Lionel');
      s.arreterParSupport();
      expect(s.prendre('Lionel'), isTrue,
          reason: 'il ne s\'est rien refusé à lui-même');
    });
  });

  group('les gestes venus du réseau', () {
    test('les gestes connus sont lus', () {
      expect(lireGeste('ouvrir'), GesteGuidage.ouvrirEcran);
      expect(lireGeste('categorie'), GesteGuidage.ouvrirCategorie);
      expect(lireGeste('chaine'), GesteGuidage.ouvrirChaine);
      expect(lireGeste('favori'), GesteGuidage.basculerFavori);
      expect(lireGeste('retour'), GesteGuidage.retour);
      expect(lireGeste('pointeur'), GesteGuidage.pointer);
      expect(lireGeste('designer'), GesteGuidage.designer);
      expect(lireGeste('effacer'), GesteGuidage.effacer);
    });

    test('UN GESTE INCONNU NE FAIT RIEN — on ne devine pas', () {
      // Un panel plus récent que l'app enverra des mots qu'elle ne
      // connaît pas. Choisir « le geste le plus proche » reviendrait à
      // appuyer au hasard sur l'écran d'un client.
      for (final String? inconnu in <String?>[
        null, '', 'supprimer_tout', 'payer', 'OUVRIR', ' ouvrir ',
      ]) {
        expect(lireGeste(inconnu), isNull, reason: '« $inconnu »');
      }
    });

    test('ni paiement ni mot de passe dans la liste des gestes', () {
      // Les deux seules exclusions, vérifiées sur la liste elle-même :
      // le support conduit l'app, il n'engage pas d'argent et ne touche
      // pas à ce avec quoi le client se protège.
      final String noms = GesteGuidage.values.join(' ').toLowerCase();
      for (final String interdit in <String>[
        'paie', 'pay', 'achat', 'abonn', 'motdepasse', 'password', 'pin',
        'parental',
      ]) {
        expect(noms.contains(interdit), isFalse, reason: interdit);
      }
    });
  });

  group('le cas du propriétaire, joué en entier', () {
    test('« je ne trouve pas les favoris » → je lui montre', () {
      // 1. Lionel prend la main (ou pas : le premier geste l'ouvre).
      // 2. Il ouvre les chaînes, pointe du doigt, met un favori.
      // 3. Il rend la main. Le client a tout vu sur sa télé, avec un
      //    bandeau rouge au-dessus pendant tout ce temps.
      expect(s.prendre('Lionel (7 MOTION)'), isTrue);

      for (final GesteGuidage _ in <GesteGuidage>[
        GesteGuidage.ouvrirEcran,
        GesteGuidage.pointer,
        GesteGuidage.basculerFavori,
        GesteGuidage.designer,
      ]) {
        h.avancer(const Duration(seconds: 20));
        expect(s.noterOrdre(), isTrue);
      }

      expect(s.guidagePermis, isTrue);
      s.arreterParSupport();
      expect(s.guidagePermis, isFalse);
      expect(s.derniereFin, FinAssistance.arreteeParSupport);
    });

    test('et le client peut couper au milieu, sans explication', () {
      s.prendre('Lionel (7 MOTION)');
      s.noterOrdre();
      s.arreterParClient();
      expect(s.noterOrdre(), isFalse,
          reason: 'dès qu\'il coupe, plus un seul ordre ne passe');
    });
  });
}
