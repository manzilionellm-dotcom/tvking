// =========================================================
//  remote_source_store_gate_test.dart — le verrou magasin, son histoire
// =========================================================
//  CE FICHIER RACONTE UNE DÉCISION QUI A CHANGÉ DEUX FOIS. Il ne teste
//  pas une règle immuable : il garde la trace de ce qui a été essayé,
//  pourquoi, et ce qu'on a choisi à la fin. Sans ça, le prochain qui
//  passera croira à un oubli et remettra la garde « pour bien faire ».
//
//  ---------------------------------------------------------
//  19/08/2026 — LE REFUS
//  ---------------------------------------------------------
//  Amazon Appstore refuse l'app : « pirated content ». Cause établie :
//  le testeur du magasin, en ouvrant l'app sur un compte de test,
//  voyait un bouquet de chaînes déjà poussé par le panel du revendeur.
//
//  Correctif de l'époque : trois gardes dans
//  RemoteSourceRepository — sync(), fetchAssignedSources(),
//  applySources(). Dans un build magasin (`PLAY_BUILD=true`), l'app ne
//  récupérait AUCUNE source poussée. Le testeur ne voyait plus que
//  « Ajoute ta source ». L'app est passée.
//
//  ---------------------------------------------------------
//  16/09/2026 — LE PROPRIÉTAIRE TRANCHE DANS L'AUTRE SENS
//  ---------------------------------------------------------
//  Un client installe depuis le Play Store. Le propriétaire l'active
//  depuis son panneau, le client n'est PAS avec lui — et rien n'arrive.
//  Personne ne pouvait le voir : ni lui, ni le client, ni le panneau.
//
//  Le refus du 19/08 lui a été rappelé EXPLICITEMENT avant l'arbitrage,
//  avec l'option intermédiaire (un bouton « récupérer mes chaînes » que
//  l'examinateur n'appuie jamais). Il a choisi le retrait complet : son
//  métier, c'est d'activer à distance, et un client bloqué coûte plus
//  cher qu'un risque de refus.
//
//  LE RISQUE ACCEPTÉ, écrit noir sur blanc : un examinateur Google ou
//  Amazon qui ouvre l'app sur une MAC déjà pourvue reverra un bouquet
//  garni — le motif exact du refus du 19/08.
//
//  ---------------------------------------------------------
//  CE QUE CE TEST VÉRIFIE, ET POURQUOI IL LIT LE FICHIER SOURCE
//  ---------------------------------------------------------
//  Prouver une ABSENCE de garde par le comportement demanderait de
//  laisser sync() partir sur le réseau — impossible en test unitaire, et
//  ça ne prouverait rien de plus. On lit donc le fichier réel et on
//  vérifie qu'aucune des trois gardes n'est revenue en douce.
//
//  Si un refus arrive un jour, c'est ICI qu'on remet les gardes, et
//  c'est ce texte qu'on met à jour — pas une correction ailleurs.
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final File source =
      File('lib/features/playlists/data/remote_source_repository.dart');

  test('le fichier source est bien là où on le croit', () {
    // Un test qui lit un fichier absent passerait tout vert sans rien
    // vérifier. On échoue franchement plutôt que de rassurer à tort.
    expect(source.existsSync(), isTrue,
        reason: 'chemin attendu : ${source.path}');
  });

  test('aucune des trois gardes « build magasin » n\'est revenue', () {
    final String code = source.readAsStringSync();
    // On cherche la GARDE (le retour anticipé), pas le mot « storeBuild » :
    // le bloc d'explication en tête de classe en parle longuement, et un
    // test qui interdirait le mot interdirait aussi d'expliquer la
    // décision. On a déjà fait cette erreur sur la page de confidentialité
    // — un test qui empêche de documenter finit par être désactivé.
    expect(code.contains('if (storeBuild)'), isFalse,
        reason: 'une garde « build magasin » a été réintroduite : '
            'les clients Play Store ne recevront plus leurs chaînes. '
            'Si c\'est voulu (nouveau refus de magasin), mets à jour '
            'l\'en-tête de ce fichier ET le bloc en tête de classe.');
  });

  test('la décision et son risque restent écrits dans le code', () {
    final String code = source.readAsStringSync();
    // Le jour où quelqu'un efface l'explication, la prochaine personne
    // croira à un oubli et « corrigera » en remettant la garde.
    expect(code.contains('19/08/2026'), isTrue,
        reason: 'le refus Amazon doit rester cité : c\'est lui qui '
            'justifie l\'existence même de cette question');
    expect(code.contains('16/09/2026'), isTrue,
        reason: 'la décision du propriétaire doit rester datée');
  });
}
