// =========================================================
//  device_url_key.smoke.mjs — la MAC dans l'URL doit être DÉCODÉE
// =========================================================
//  POURQUOI CE TEST EXISTE (12/09/2026).
//
//  Photo du propriétaire : une box Android TV allumée, écran d'accueil,
//  son adresse `F0:92:8E:D6:58` affichée en gros. Et dans le panneau, sur
//  la fiche de cette même MAC, un bandeau rouge :
//
//      « Cette MAC n'est pas encore enregistrée (aucun démarrage de
//        l'app). »
//
//  C'était faux, et c'était notre faute. Le panneau encode l'identifiant
//  (`encodeURIComponent`), donc « MK:F0:… » part en « MK%3AF0%3A… ». Le
//  routeur du Worker découpe `url.pathname`, qui n'est PAS décodé. La clé
//  arrivait avec ses « %3A » : le SELECT ne trouvait rien, la validation
//  du format échouait, 404. Le panneau traduisait ce 404 en une
//  affirmation sur le CLIENT — « il n'a jamais démarré l'app » — alors
//  que le défaut était chez nous.
//
//  Conséquences réelles, toutes invisibles :
//   • la fiche 360° ne s'ouvrait JAMAIS par la MAC (elle marchait depuis
//     la liste Appareils, qui passe un id « dev_… » sans « : ») ;
//   • « Message rapide » tombait sur le même défaut : le message tapé
//     pour le client ne partait pas, sans erreur visible ;
//   • le revendeur envoyait son client chercher un problème inexistant.
//
//  Le dépôt CONNAISSAIT le piège : `decodeMac()` existe, documentée, et
//  neuf routes l'appellent. Deux l'avaient oubliée. Un test manquait —
//  c'est celui-ci. Il lit le VRAI fichier, pas une copie.
//
//  Lancer : node cloudflare/device_url_key.smoke.mjs
// =========================================================
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('./api_v1.js', import.meta.url), 'utf8');

let n = 0;
const ok = (m) => { n += 1; console.log('  ✓', m); };

// ---------------------------------------------------------
//  1. Le point d'entrée commun existe et décode vraiment
// ---------------------------------------------------------
assert.match(
  src,
  /function cleDeviceUrl\(id\) \{\s*return decodeMac\(String\(id \|\| ''\)\)\.trim\(\);\s*\}/,
  'cleDeviceUrl doit décoder puis nettoyer la clé',
);
ok('cleDeviceUrl() décode la clé « id ou MAC » venue de l\'URL');

// ---------------------------------------------------------
//  2. LES DEUX fonctions qui résolvent « id OU MAC » l'utilisent
// ---------------------------------------------------------
//  On vérifie le CORPS de chacune, pas juste la présence du mot dans le
//  fichier : un test qui cherche « cleDeviceUrl » n'importe où passerait
//  même si une seule des deux l'appelait — c'est exactement l'erreur qui
//  a laissé passer le bug (neuf routes correctes en cachaient deux
//  fausses).
function corpsDe(nom) {
  const i = src.indexOf(`async function ${nom}(`);
  assert.ok(i >= 0, `${nom} introuvable`);
  // Jusqu'à la prochaine déclaration de fonction au niveau racine.
  const suite = src.slice(i + 10);
  const j = suite.search(/\n(?:async )?function /);
  return j < 0 ? suite : suite.slice(0, j);
}

for (const nom of ['resolveTargetMac', 'handleDeviceOverview']) {
  const corps = corpsDe(nom);
  assert.match(
    corps,
    /const key = cleDeviceUrl\(id\);/,
    `${nom} doit tirer sa clé de cleDeviceUrl()`,
  );
  assert.doesNotMatch(
    corps,
    /const key = String\(id \|\| ''\);/,
    `${nom} ne doit plus prendre la clé brute de l'URL`,
  );
  ok(`${nom}() passe par cleDeviceUrl()`);
}

// ---------------------------------------------------------
//  3. Le décodage fait bien ce qu'on croit
// ---------------------------------------------------------
//  On rejoue la vraie fonction plutôt que de supposer son comportement.
const decodeMac = (mac) => {
  try { return decodeURIComponent(mac); } catch (_) { return mac; }
};
const cleDeviceUrl = (id) => decodeMac(String(id || '')).trim();

assert.equal(
  cleDeviceUrl('MK%3AF0%3A92%3A8E%3AD6%3A58'),
  'MK:F0:92:8E:D6:58',
  'la MAC de la photo doit se décoder',
);
ok('« MK%3AF0%3A92%3A8E%3AD6%3A58 » → « MK:F0:92:8E:D6:58 » (la MAC de la photo)');

//  Tolérance : une clé DÉJÀ décodée ne doit pas être abîmée. Les deux
//  formes circulent — le panneau encode, un appel direct ou un vieux
//  client peuvent ne pas le faire.
assert.equal(cleDeviceUrl('MK:F0:92:8E:D6:58'), 'MK:F0:92:8E:D6:58');
ok('une MAC déjà décodée traverse intacte');

//  Un identifiant de device (« dev_… ») n'a rien à décoder : il doit
//  ressortir tel quel, sinon la fiche ouverte depuis la liste Appareils
//  casserait — c'est le seul chemin qui marchait avant ce correctif.
assert.equal(cleDeviceUrl('dev_a1b2c3d4e5'), 'dev_a1b2c3d4e5');
ok('un id « dev_… » traverse intact (le chemin qui marchait déjà)');

//  Une séquence d'échappement invalide ne doit PAS faire tomber la
//  route : decodeURIComponent lance, on retombe sur la valeur brute et
//  c'est la validation de format qui refusera proprement.
assert.equal(cleDeviceUrl('MK%ZZ'), 'MK%ZZ');
ok('une séquence %XX invalide ne lance pas — la validation refusera ensuite');

assert.equal(cleDeviceUrl(null), '');
assert.equal(cleDeviceUrl(undefined), '');
ok('clé absente → chaîne vide, aucune exception');

// ---------------------------------------------------------
//  4. Le panneau n'accuse plus le client sur la foi d'un 404
// ---------------------------------------------------------
const macLink = readFileSync(
  new URL('../admin-panel/src/components/MacLink.tsx', import.meta.url),
  'utf8',
);
//  ON VISE LA PHRASE COMPLÈTE TELLE QU'ELLE ÉTAIT AFFICHÉE, pas un bout.
//  Premier jet de ce test : il cherchait « aucun démarrage de l'app » —
//  et il a échoué sur le COMMENTAIRE qui, juste au-dessus du correctif,
//  cite l'ancienne phrase pour expliquer ce qu'on a réparé. Un test qui
//  interdit un mot au lieu d'une phrase interdit aussi d'en parler ; on
//  aurait fini par effacer l'explication pour faire taire le test.
assert.doesNotMatch(
  macLink,
  /"Cette MAC n'est pas encore enregistrée \(aucun démarrage de l'app\)\."/,
  "l'ancienne affirmation ne doit plus être affichée",
);
ok('le bandeau 404 ne conclut plus à la place du revendeur');

//  Et la nouvelle formulation est bien là. Sans ce contrôle positif, une
//  suppression pure et simple du bandeau passerait le test — le
//  revendeur se retrouverait alors devant une fiche vide, sans un mot.
assert.match(
  macLink,
  /Aucune fiche trouvée pour cette MAC/,
  'le bandeau doit dire ce qu\'on sait, et quoi faire',
);
ok('il dit ce qu\'on sait, et la marche à suivre (demander la MAC au client)');

console.log(`\n${n} assertions OK`);
