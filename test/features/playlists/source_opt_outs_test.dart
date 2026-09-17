// =========================================================
//  source_opt_outs_test.dart — « j'active à distance, rien n'arrive »
// =========================================================
//  CE QUE CE TEST EMPÊCHE DE REVENIR (17/09/2026).
//
//  Le propriétaire, deux jours durant :
//    « Si j'écris bonjour, l'application reçoit bonjour. Mais si
//      j'active à distance, l'application ne peut pas s'activer. Et si
//      le client le met manuellement, ça fonctionne. »
//
//  Trois faits qui, ensemble, ne laissaient qu'un coupable possible :
//  le transport allait bien (le message arrive), les identifiants
//  allaient bien (la saisie manuelle marche), donc un FILTRE local
//  mangeait la source poussée. C'était l'empreinte de suppression.
//
//  Elle n'était levée que par un événement WebSocket. Quand celui-ci
//  n'arrivait pas — socket coupé, app en arrière-plan, réveil par le
//  sondage — le revendeur poussait dans le vide, indéfiniment.
//
//  Le juge ci-dessous départage les deux besoins qui se contredisaient.
//  Si quelqu'un le simplifie un jour en « empreinte présente → on
//  saute », ces tests tombent, et c'est exactement leur rôle.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/source_opt_outs.dart';

void main() {
  // Deux instants, bien séparés, pour que la lecture reste évidente.
  const int lundi = 1000000;
  const int mardi = 2000000;

  group('le besoin du 21/08 — une suppression doit TENIR', () {
    test('supprimée APRÈS la dernière assignation → on saute', () {
      //  Le client a supprimé sa liste. Le panel n'a rien fait depuis.
      //  Au redémarrage, elle ne doit PAS revenir : « c'est pas
      //  professionnel » — et il avait raison.
      expect(
        SourceOptOuts.doitSauter(suppressionMs: mardi, assignationMs: lundi),
        isTrue,
      );
    });

    test('même milliseconde → la suppression gagne', () {
      //  À égalité, la suppression est forcément postérieure : on ne
      //  peut supprimer que ce qui est déjà assigné.
      expect(
        SourceOptOuts.doitSauter(suppressionMs: lundi, assignationMs: lundi),
        isTrue,
      );
    });
  });

  group('LE BESOIN D\'AUJOURD\'HUI — le revendeur repousse, ça arrive', () {
    test('réassignée APRÈS la suppression → on NE saute PAS', () {
      //  C'est LE cas qui rendait l'activation à distance impossible.
      expect(
        SourceOptOuts.doitSauter(suppressionMs: lundi, assignationMs: mardi),
        isFalse,
      );
    });

    test('jamais supprimée → on ne saute jamais', () {
      expect(
        SourceOptOuts.doitSauter(suppressionMs: null, assignationMs: mardi),
        isFalse,
      );
      expect(
        SourceOptOuts.doitSauter(suppressionMs: 0, assignationMs: mardi),
        isFalse,
      );
    });
  });

  group('DANS LE DOUTE, ON NE BLOQUE PAS', () {
    //  Les deux erreurs ne coûtent pas pareil : une source qui revient
    //  une fois de trop est agaçante et visible ; un client payant
    //  devant un écran vide coûte un abonnement et un appel.

    test('serveur qui ne dit pas depuis quand (vieux Worker) → on passe', () {
      expect(
        SourceOptOuts.doitSauter(suppressionMs: mardi, assignationMs: null),
        isFalse,
        reason: 'un Worker antérieur au 17/09 n\'envoie pas assigned_at ; '
            'bloquer ici rendrait la mise à jour du serveur obligatoire '
            'pour que les clients revoient leurs chaînes',
      );
      expect(
        SourceOptOuts.doitSauter(suppressionMs: mardi, assignationMs: 0),
        isFalse,
      );
    });

    test('empreinte migrée depuis la v1 (date inconnue = 0) → on passe', () {
      //  L'AMNISTIE : une empreinte posée avant le 17/09 n'a pas de date.
      //  On ne peut pas trancher, donc on laisse passer — et c'est ça qui
      //  débloque tout seul chaque appareil coincé aujourd'hui, sans que
      //  personne ait à toucher un téléphone.
      expect(
        SourceOptOuts.doitSauter(suppressionMs: 0, assignationMs: mardi),
        isFalse,
      );
    });

    test('tout inconnu → on passe', () {
      expect(SourceOptOuts.doitSauter(), isFalse);
    });
  });
}
