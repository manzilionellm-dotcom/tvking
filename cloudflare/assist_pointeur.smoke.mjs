// =========================================================
//  assist_pointeur.smoke.mjs — le doigt du support, borné au hub
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (19/09/2026) :
//
//    « Il va y avoir un simulateur de TV ou de téléphone : où je
//      touche, il voit où je touche. »
//
//  Le panel envoie une POSITION EN FRACTION D'ÉCRAN (0 → 1), le hub la
//  transporte, l'app pose un halo au même endroit chez le client.
//
//  CE FICHIER PROTÈGE LE BORNAGE, et c'est le seul endroit du trajet
//  où une valeur bizarre peut être arrêtée avant de coûter quelque
//  chose au client.
//
//  LA RÈGLE EST : BORNER, JAMAIS CORRIGER.
//
//  Ramener 1,4 à 1 semble gentil. C'est un piège : le halo se
//  poserait dans un coin que PERSONNE n'a désigné, et le client irait
//  regarder là pendant que le support lui dit « tu vois, en haut à
//  droite ». Une valeur hors écran devient donc `null`, l'app refuse
//  franchement (`position_invalide`), et le support le lit dans son
//  journal.
//
//  LES DEUX PIÈGES DE JAVASCRIPT, testés nommément :
//    • `Number(null)` et `Number('')` valent 0 — sans garde, un
//      payload SANS position poserait un halo en haut à gauche de la
//      télé du client ;
//    • `NaN` échappe à toute comparaison écrite à l'envers : la garde
//      doit être `n >= 0 && n <= 1`, jamais `!(n > 1)`.
//
//  Exécution :
//    node cloudflare/assist_pointeur.smoke.mjs
// =========================================================

import { fraction } from './realtime.js';

let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass++; console.log('PASS', m); }
  else { fail++; console.log('FAIL', m); }
};

// --- Ce qui doit passer ---------------------------------------------
ok(fraction(0) === 0, '0 est un endroit légitime (coin haut-gauche)');
ok(fraction(1) === 1, '1 est un endroit légitime (coin bas-droit)');
ok(fraction(0.5) === 0.5, 'le milieu passe');
ok(fraction(0.337) === 0.337, 'une valeur quelconque passe telle quelle');
// Le JSON peut livrer du texte selon les versions du panel ; refuser
// pour ça serait refuser un geste parfaitement correct.
ok(fraction('0.25') === 0.25, 'une position écrite en texte est lue');
ok(fraction('1') === 1, 'texte « 1 » → 1');

// --- Ce qui doit être REFUSÉ, pas raboté -----------------------------
ok(fraction(1.4) === null, 'hors écran (1,4) → null, JAMAIS ramené à 1');
ok(fraction(-0.1) === null, 'hors écran (-0,1) → null, JAMAIS ramené à 0');
ok(fraction(42) === null, 'des pixels envoyés par erreur → null');

// --- Les deux pièges de JavaScript -----------------------------------
ok(fraction(null) === null, 'null → null (et surtout pas 0)');
ok(fraction(undefined) === null, 'absent → null (et surtout pas 0)');
ok(fraction('') === null, 'chaîne vide → null (Number de la chaîne vide vaut 0 !)');
ok(fraction(NaN) === null, 'NaN → null');
ok(fraction('gauche') === null, 'du texte non numérique → null');
ok(fraction(Infinity) === null, 'Infinity → null');
ok(fraction(-Infinity) === null, '-Infinity → null');

// Un objet ou un tableau ne sont pas des positions. `Number([])` vaut
// 0 et `Number([0.5])` vaut 0.5 : sans cette vérification, un payload
// mal formé poserait quand même un doigt sur l'écran de quelqu'un.
ok(fraction({}) === null, 'un objet → null');
ok(fraction([]) === null, 'un tableau vide → null (Number([]) vaut 0 !)');

console.log(`\n${pass} PASS, ${fail} FAIL`);
process.exit(fail === 0 ? 0 : 1);
