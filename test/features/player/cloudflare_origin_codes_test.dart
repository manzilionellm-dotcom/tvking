// =========================================================
//  cloudflare_origin_codes_test.dart — panne ≠ refus
// =========================================================
//  BOÎTE NOIRE D'UNE BOX EN CLIENTÈLE, 18/09/2026, « FR TNT FR » :
//
//    ✅ 1. Internet de la box       HTTP 204
//    ✅ 2. DNS                      thekung.801802.com → 188.114.96.1…
//    ✅ 3. Serveur du fournisseur   accepte la connexion
//    ❌ 4. Réponse du flux          HTTP 520
//    ❌ 5. Signatures de lecteur    « le fournisseur refuse ce flux »
//
//  LA LIGNE 5 ACCUSAIT À TORT — et c'est la seule que le support lit.
//
//  520 n'est pas un code HTTP normalisé : c'est un code CLOUDFLARE. Les
//  adresses résolues à la ligne 2 (`188.114.96.1`, `188.114.97.1`) SONT
//  des adresses Cloudflare. La réponse ne vient donc pas du fournisseur
//  mais de Cloudflare, qui dit « je n'arrive pas à tirer une réponse
//  valable de la machine de ce client ». Le fournisseur ne refuse rien :
//  son serveur est en panne.
//
//  L'écart n'est pas cosmétique. « Refuse » envoie fouiller les
//  identifiants, la signature, l'abonnement — une soirée pour rien.
//  « En panne » dit d'attendre ou d'appeler le fournisseur.
//
//  Troisième verdict trompeur corrigé en deux jours, après `uaTried: 0`
//  et « une socket encore ouverte 5211 ms ». Toujours le même motif : un
//  message qui affirme une CAUSE alors qu'il n'a vu qu'un SYMPTÔME.
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/domain/cloudflare_origin_codes.dart';

void main() {
  test('520 — LE code du terrain — est expliqué comme une PANNE', () {
    final String? texte = expliquerCodeCloudflare(520);
    expect(texte, isNotNull);
    // Le mot qui compte pour le client : la panne est CHEZ LE FOURNISSEUR.
    expect(texte!.toLowerCase(), contains('fournisseur'));
    expect(estPanneOrigine(520), isTrue);
  });

  test('toute la famille 520-527 est couverte', () {
    // Un seul code oublié, et le verdict retombe sur « le fournisseur
    // refuse » — exactement le message qu'on vient de corriger.
    for (int code = 520; code <= 527; code++) {
      expect(expliquerCodeCloudflare(code), isNotNull,
          reason: 'HTTP $code non expliqué');
      expect(estPanneOrigine(code), isTrue, reason: 'HTTP $code');
    }
  });

  test('un VRAI refus reste un refus — on n\'excuse pas tout', () {
    // Le risque symétrique du correctif : tout transformer en « panne
    // chez le fournisseur » et ne plus jamais dire au client que ses
    // identifiants sont refusés ou que sa ligne est pleine.
    for (final int code in <int>[
      401, // pas autorisé
      403, // interdit
      404, // flux inexistant
      456, // fournisseur bloque cette IP (cas déjà traité ailleurs)
      500, // erreur serveur ORDINAIRE, pas Cloudflare
      502, // passerelle — pas un code d'origine Cloudflare
      503, // service indisponible
      200, // et le succès, évidemment
    ]) {
      expect(expliquerCodeCloudflare(code), isNull, reason: 'HTTP $code');
      expect(estPanneOrigine(code), isFalse, reason: 'HTTP $code');
    }
  });

  test('un code absent (null) n\'est pas une panne d\'origine', () {
    // `errorCode` vaut null quand l'échec est réseau (DNS, timeout) : ce
    // n'est pas une panne d'origine, et le diagnostic a déjà une branche
    // dédiée pour ça (« toutes bloquées au niveau RÉSEAU »).
    expect(estPanneOrigine(null), isFalse);
  });

  test('le diagnostic LIT cette table — pas une copie', () {
    // Deux lignes du MÊME écran parlent du même code (« Réponse du
    // flux » et « Signatures de lecteur »). Le jour où une copie dérive,
    // le diagnostic donne deux explications du même chiffre et plus
    // personne ne sait laquelle croire. Même règle que
    // `device_profiles.js` ou `ci/build_label.sh`.
    final File svc =
        File('lib/features/tv/data/tv_diagnostics_service.dart');
    expect(svc.existsSync(), isTrue, reason: svc.path);

    final String code = svc.readAsStringSync();
    expect(code.contains('cloudflare_origin_codes.dart'), isTrue,
        reason: 'le diagnostic doit importer la table, pas la recopier');
    expect('expliquerCodeCloudflare'.allMatches(code).length,
        greaterThanOrEqualTo(2),
        reason: 'les DEUX lignes concernées doivent la consulter');
    expect(code.contains('estPanneOrigine'), isTrue,
        reason: 'le verdict « refuse » doit être écarté sur une panne');
  });
}
