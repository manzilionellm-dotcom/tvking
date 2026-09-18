// =========================================================
//  heartbeat_raison_echec_test.dart — qui faut-il réveiller ?
// =========================================================
//  BOÎTE NOIRE D'UNE BOX EN CLIENTÈLE, NUIT DU 17 AU 18/09/2026.
//  Huit fois, toutes les 45 minutes, la MÊME ligne :
//
//    05:32:52 WARN sub.sync.empty {reason: remote_unknown}
//    04:47:52 WARN sub.sync.empty {reason: remote_unknown}
//    04:02:52 WARN sub.sync.empty {reason: remote_unknown}
//    03:17:53 WARN sub.sync.empty {reason: remote_unknown}
//    …
//
//  `remote_unknown` était écrit dans TROIS situations sans rapport :
//
//    • aucun hôte joignable      → la ligne du CLIENT est coupée
//    • un hôte répond en erreur  → NOTRE Worker est cassé
//    • une casse avant l'envoi   → l'APPAREIL lui-même
//
//  Trois responsables possibles, un seul mot pour les trois. On ne
//  pouvait donc pas répondre à la seule question qui compte à 3 h du
//  matin : qui faut-il réveiller ?
//
//  Et ce n'est pas anodin : un heartbeat qui échoue, c'est le panel qui
//  ne voit plus la box, le `buildLabel` qui ne remonte plus, et la
//  licence qui ne se rafraîchit plus. Huit échecs d'affilée méritaient
//  mieux qu'un haussement d'épaules.
//
//  QUATRIÈME verdict trompeur corrigé en deux jours, après `uaTried: 0`,
//  « socket encore ouverte 5211 ms » et « le fournisseur refuse ce
//  flux ». Le motif ne change pas : un message qui en dit MOINS que ce
//  que le code savait déjà.
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/subscription/data/subscription_backend.dart';

void main() {
  test('le « inconnu » historique n\'accuse personne', () {
    // Il reste utilisé comme valeur par défaut ; il ne doit pas se mettre
    // à désigner un coupable au hasard.
    expect(RemoteSubscriptionStatus.unknown.exists, isFalse);
    expect(RemoteSubscriptionStatus.unknown.raisonEchec, isNull);
  });

  test('chaque cause porte SON nom', () {
    for (final String raison in <String>[
      'reseau', // la ligne du client
      'http_500', // notre Worker
      'http_503',
      'exception', // l'appareil
      'aucun_hote',
    ]) {
      final RemoteSubscriptionStatus s =
          RemoteSubscriptionStatus.inconnuCar(raison);
      expect(s.raisonEchec, raison);
      // Et surtout : un échec ne doit JAMAIS ressembler à une réponse.
      // Si `exists` passait à true, l'app croirait le serveur joignable
      // et écraserait le cache de licence d'un client qui paie.
      expect(s.exists, isFalse, reason: raison);
      expect(s.paid, isFalse, reason: raison);
      expect(s.banned, isFalse, reason: raison);
      expect(s.frozen, isFalse, reason: raison);
      expect(s.expired, isFalse,
          reason: 'un réseau coupé ne doit pas « expirer » un abonnement');
    }
  });

  test('le code DISTINGUE réellement les trois cas', () {
    final File f =
        File('lib/features/subscription/data/subscription_backend.dart');
    expect(f.existsSync(), isTrue, reason: f.path);
    final String code = f.readAsStringSync();

    // Réseau : l'hôte n'a même pas répondu.
    expect(code.contains("dernierEchec = 'reseau'"), isTrue,
        reason: 'un hôte injoignable doit se distinguer d\'un hôte en erreur');
    // HTTP : l'hôte a répondu, mal — c'est NOTRE serveur.
    expect(code.contains("dernierEchec = 'http_\${resp.statusCode}'"), isTrue,
        reason: 'le code HTTP réel doit être conservé, pas aplati');
    // Exception : ça a cassé avant l'envoi.
    expect(code.contains("inconnuCar('exception')"), isTrue,
        reason: 'une casse locale ne doit accuser ni le réseau ni le Worker');
  });

  test('le journal RECOPIE la raison au lieu de la remplacer', () {
    // Le correctif ne vaut que si la raison arrive jusqu'à la Boîte
    // noire. Un `heartbeat` qui la porte et un journal qui écrit quand
    // même « remote_unknown » n'aurait rien changé pour le propriétaire.
    final File f =
        File('lib/features/subscription/data/subscription_state.dart');
    expect(f.existsSync(), isTrue, reason: f.path);
    final String code = f.readAsStringSync();

    expect(code.contains('snap.raisonEchec'), isTrue,
        reason: 'sub.sync.empty doit écrire la raison réelle');
    // `remote_unknown` reste comme REPLI (une vieille valeur sans
    // raison), mais plus comme valeur unique.
    expect(
      code.contains("'reason': 'remote_unknown'"),
      isFalse,
      reason: 'la constante en dur est ce qui masquait les trois causes',
    );
  });
}
