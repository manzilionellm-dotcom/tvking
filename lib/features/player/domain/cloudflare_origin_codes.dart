// =========================================================
//  cloudflare_origin_codes.dart — 520-527 : ce n'est PAS un refus
// =========================================================
//  BOÎTE NOIRE D'UNE BOX EN CLIENTÈLE, 18/09/2026, chaîne « FR TNT FR ».
//  Le diagnostic point par point disait :
//
//    ✅ 1. Internet de la box            HTTP 204
//    ✅ 2. DNS                           thekung.801802.com → 188.114.96.1…
//    ✅ 3. Serveur du fournisseur        accepte la connexion
//    ❌ 4. Réponse du flux               HTTP 520
//    ❌ 5. Signatures de lecteur         « le fournisseur refuse ce flux »
//
//  LA LIGNE 5 ACCUSAIT À TORT, et c'est la seule que le support lit.
//
//  ---------------------------------------------------------
//  POURQUOI 520 N'EST PAS UN REFUS
//  ---------------------------------------------------------
//  520 n'existe pas dans la norme HTTP : c'est un code inventé par
//  CLOUDFLARE. Regardez les adresses résolues plus haut —
//  `188.114.96.1`, `188.114.97.1` — ce sont des adresses Cloudflare. Le
//  serveur du fournisseur est donc DERRIÈRE Cloudflare, et la réponse
//  qu'on reçoit ne vient pas du fournisseur : elle vient de Cloudflare,
//  qui nous dit « je n'arrive pas à tirer une réponse valable de la
//  machine de ce client ».
//
//  Autrement dit : le fournisseur ne refuse rien. Son serveur est en
//  panne, surchargé, ou répond n'importe quoi.
//
//  ---------------------------------------------------------
//  CE QUE ÇA CHANGE POUR LE CLIENT — TOUT
//  ---------------------------------------------------------
//  « Le fournisseur refuse ce flux » envoie chercher du côté des
//  identifiants, de la signature du lecteur, de l'abonnement. On peut y
//  passer une soirée. « Le serveur du fournisseur est en panne » dit
//  d'attendre, ou d'appeler le fournisseur. Ce n'est pas la même
//  soirée, et ce n'est pas le même client le lendemain.
//
//  C'est le TROISIÈME verdict trompeur corrigé en deux jours, après
//  `uaTried: 0` et « une socket encore ouverte 5211 ms ». Le motif est
//  toujours le même : un message qui affirme une CAUSE alors qu'il n'a
//  observé qu'un SYMPTÔME.
//
//  ---------------------------------------------------------
//  UNE SEULE IMPLÉMENTATION, AUTANT D'APPELANTS QU'ON VEUT
//  ---------------------------------------------------------
//  Deux écrans disent la même chose du même code (la ligne « Réponse du
//  flux » et la ligne « Signatures de lecteur »). La table vit ICI, une
//  fois. Le jour où une copie dérive, deux lignes du MÊME diagnostic
//  donnent deux explications du même chiffre, et plus personne ne sait
//  laquelle croire.
// =========================================================

/// Explique un code d'erreur d'ORIGINE Cloudflare (520-527), ou `null` si
/// [code] n'en est pas un.
///
/// Le texte est court et sans jargon : il s'affiche tel quel sur une TV,
/// à trois mètres, et c'est souvent le propriétaire qui le lit au
/// téléphone à son client.
String? expliquerCodeCloudflare(int code) {
  switch (code) {
    case 520:
      return 'le serveur du fournisseur répond n\'importe quoi '
          '(panne chez LUI, pas chez toi)';
    case 521:
      return 'le serveur du fournisseur est ÉTEINT ou refuse Cloudflare';
    case 522:
      return 'le serveur du fournisseur ne répond plus (délai dépassé)';
    case 523:
      return 'Cloudflare n\'atteint plus le serveur du fournisseur';
    case 524:
      return 'le serveur du fournisseur a mis trop de temps à répondre';
    case 525:
    case 526:
      return 'problème de certificat entre Cloudflare et le fournisseur';
    case 527:
      return 'coupure interne chez Cloudflare';
    default:
      return null;
  }
}

/// Ce code désigne-t-il une panne du serveur d'origine plutôt qu'un REFUS ?
///
/// Sert à choisir le VERDICT : sur une panne d'origine, insister avec
/// d'autres signatures de lecteur ne sert à rien, et accuser le
/// fournisseur de « refuser » est faux.
bool estPanneOrigine(int? code) =>
    code != null && expliquerCodeCloudflare(code) != null;
