// =========================================================
//  assistance_session_test.dart — « s'il me permet »
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (18/09/2026) :
//
//    « Je veux entrer dans le téléphone d'un client, S'IL ME PERMET.
//      J'appuie sur mon ordinateur et ça s'appuie chez lui. »
//    « Un client me dit : je ne trouve pas les favoris. Je lui dis :
//      regarde ta télé. Et j'appuie — chaîne, favoris, tout. »
//
//  CE QUE CES TESTS PROTÈGENT, ET POURQUOI C'EST LE FICHIER LE PLUS
//  SÉRIEUX DE LA JOURNÉE : ils ne protègent pas une fonctionnalité,
//  ils protègent un CLIENT. Prendre la main sur l'appareil de
//  quelqu'un est acceptable à une condition — qu'il ait dit oui, qu'il
//  voie tout, et qu'il puisse couper. Si l'une des trois lâche, ce
//  n'est plus de l'assistance.
//
//   1. AUCUNE SESSION SANS UN OUI EXPLICITE. Jamais « qui ne dit rien
//      consent » : une demande sans réponse expire.
//   2. LE CLIENT PEUT TOUJOURS ARRÊTER. Il n'existe aucun état d'où il
//      ne peut pas sortir. Ce test doit rester vrai pour toujours.
//   3. ÇA S'ARRÊTE TOUT SEUL. Une assistance oubliée ouverte est une
//      assistance qui regarde.
//   4. UN ORDRE HORS SESSION NE FAIT RIEN. C'est la garde qui empêche
//      qu'un bug de panel touche l'écran d'un client qui n'a rien
//      demandé.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/assistance/assistance_session.dart';

/// Une horloge qu'on avance à la main : les règles de ce fichier sont
/// des règles de TEMPS, et attendre 30 vraies minutes dans un test
/// voudrait dire ne jamais l'écrire.
class _Horloge {
  DateTime t = DateTime(2026, 9, 18, 12);
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

  group('1. AUCUNE SESSION SANS UN OUI EXPLICITE', () {
    test('au repos, le guidage est interdit', () {
      expect(s.etat, EtatAssistance.inactive);
      expect(s.guidagePermis, isFalse);
    });

    test('demander ne suffit PAS à prendre la main', () {
      expect(s.demander('Lionel'), isTrue);
      expect(s.etat, EtatAssistance.demandee);
      expect(s.guidagePermis, isFalse,
          reason: 'entre la demande et le oui, on ne touche à RIEN');
    });

    test('c\'est le OUI du client qui ouvre la session', () {
      s.demander('Lionel');
      expect(s.accepter(), isTrue);
      expect(s.guidagePermis, isTrue);
    });

    test('QUI NE DIT RIEN NE CONSENT PAS : la demande expire', () {
      s.demander('Lionel');
      h.avancer(attenteMax);
      s.rafraichir();
      expect(s.etat, EtatAssistance.inactive);
      expect(s.guidagePermis, isFalse);
      expect(s.derniereFin, FinAssistance.demandeExpiree);
    });

    test('un OUI après expiration ne rattrape rien', () {
      // Le piège : le client revient dix minutes plus tard, voit la
      // question encore affichée sur un écran pas rafraîchi, et
      // accepte. Ce serait un oui à une question qu'il ne se rappelle
      // plus — donc non.
      s.demander('Lionel');
      h.avancer(attenteMax + const Duration(seconds: 1));
      expect(s.accepter(), isFalse);
      expect(s.guidagePermis, isFalse);
    });

    test('une demande sans nom est refusée', () {
      // « Quelqu'un veut prendre la main » n'est pas une question à
      // laquelle un client peut répondre.
      expect(s.demander(''), isFalse);
      expect(s.demander('   '), isFalse);
      expect(s.etat, EtatAssistance.inactive);
    });

    test('accepter sans demande ne démarre rien', () {
      expect(s.accepter(), isFalse);
      expect(s.guidagePermis, isFalse);
    });
  });

  group('2. LE CLIENT PEUT TOUJOURS ARRÊTER', () {
    test('il refuse la demande', () {
      s.demander('Lionel');
      s.refuser();
      expect(s.etat, EtatAssistance.inactive);
      expect(s.derniereFin, FinAssistance.refusee);
    });

    test('il coupe une session en cours, à la seconde', () {
      s.demander('Lionel');
      s.accepter();
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
        () => s.demander('Lionel'),
        () {
          s.demander('Lionel');
          s.accepter();
        },
        () {
          s.demander('Lionel');
          s.accepter();
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

    test('le support peut rendre la main de son côté', () {
      s.demander('Lionel');
      s.accepter();
      s.arreterParSupport();
      expect(s.guidagePermis, isFalse);
      expect(s.derniereFin, FinAssistance.arreteeParSupport);
    });
  });

  group('3. ÇA S\'ARRÊTE TOUT SEUL', () {
    test('silence trop long → coupé', () {
      s.demander('Lionel');
      s.accepter();
      h.avancer(inactiviteMax);
      s.rafraichir();
      expect(s.guidagePermis, isFalse);
      expect(s.derniereFin, FinAssistance.silence);
    });

    test('chaque ordre repousse le silence', () {
      //  LES CHIFFRES SONT CHOISIS, PAS PRIS AU HASARD — mon premier
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
      s.demander('Lionel');
      s.accepter();
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
      s.demander('Lionel');
      s.accepter();
      for (int i = 0; i < 100; i++) {
        h.avancer(const Duration(seconds: 30));
        s.noterOrdre();
      }
      s.rafraichir();
      expect(s.guidagePermis, isFalse);
      expect(s.derniereFin, FinAssistance.tempsEcoule);
    });

    test('le temps restant est annoncé, et il décroît', () {
      s.demander('Lionel');
      s.accepter();
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
      s.demander('Lionel');
      expect(s.tempsRestant, isNull);
    });
  });

  group('4. UN ORDRE HORS SESSION NE FAIT RIEN', () {
    test('au repos, l\'ordre est refusé', () {
      expect(s.noterOrdre(), isFalse);
    });

    test('pendant la demande, l\'ordre est refusé', () {
      s.demander('Lionel');
      expect(s.noterOrdre(), isFalse,
          reason: 'le client n\'a pas encore dit oui');
    });

    test('après un refus, l\'ordre est refusé', () {
      s.demander('Lionel');
      s.refuser();
      expect(s.noterOrdre(), isFalse);
    });

    test('après expiration, l\'ordre est refusé', () {
      s.demander('Lionel');
      s.accepter();
      h.avancer(dureeMax);
      expect(s.noterOrdre(), isFalse);
    });
  });

  group('UNE SEULE SESSION À LA FOIS', () {
    test('on ne fait pas la queue derrière une demande', () {
      expect(s.demander('Lionel'), isTrue);
      expect(s.demander('Quelqu\'un d\'autre'), isFalse);
      expect(s.support, 'Lionel',
          reason: 'le client doit savoir QUI, et que ça ne change pas '
              'sous ses yeux');
    });

    test('ni derrière une session en cours', () {
      s.demander('Lionel');
      s.accepter();
      expect(s.demander('Un autre revendeur'), isFalse);
      expect(s.support, 'Lionel');
    });

    test('une fois terminée, une nouvelle demande est possible', () {
      s.demander('Lionel');
      s.accepter();
      s.arreterParClient();
      expect(s.demander('Lionel'), isTrue);
    });
  });

  group('les gestes venus du réseau', () {
    test('les gestes connus sont lus', () {
      expect(lireGeste('ouvrir'), GesteGuidage.ouvrirEcran);
      expect(lireGeste('categorie'), GesteGuidage.ouvrirCategorie);
      expect(lireGeste('chaine'), GesteGuidage.ouvrirChaine);
      expect(lireGeste('favori'), GesteGuidage.basculerFavori);
      expect(lireGeste('retour'), GesteGuidage.retour);
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
      // 1. Lionel demande. 2. Le client accepte. 3. Lionel ouvre les
      // chaînes, va dans les favoris, met un favori. 4. Il rend la
      // main. Le client a tout vu sur sa télé.
      expect(s.demander('Lionel (7 MOTION)'), isTrue);
      expect(s.accepter(), isTrue);

      for (final GesteGuidage _ in <GesteGuidage>[
        GesteGuidage.ouvrirEcran,
        GesteGuidage.ouvrirCategorie,
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
      s.demander('Lionel (7 MOTION)');
      s.accepter();
      s.noterOrdre();
      s.arreterParClient();
      expect(s.noterOrdre(), isFalse,
          reason: 'dès qu\'il coupe, plus un seul ordre ne passe');
    });
  });
}
