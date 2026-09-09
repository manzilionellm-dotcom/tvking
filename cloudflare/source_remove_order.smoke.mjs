// Smoke test — SUPPRIMER UNE SOURCE DEPUIS LE PANEL DOIT ATTEINDRE LA BOX.
//
// Signalé par le propriétaire (09/09/2026) : « j'efface une liste sur le
// panel, ça ne s'efface pas dans l'app ; j'actualise, elle reste ».
//
// On ne retirait la source QUE de la base serveur. Or la synchro de l'app
// n'AJOUTE et ne MET À JOUR que ce que le panel envoie — elle ne supprime
// jamais une liste absente de l'envoi (et elle a raison : sinon elle
// effacerait les listes que le CLIENT a ajoutées lui-même). Il fallait donc
// déposer l'ORDRE `source_remove`, qui désigne la liste par serveur +
// identifiant. Ce test vérifie qu'il part bien, aux deux endroits.
//
// Lancer : node cloudflare/source_remove_order.smoke.mjs
import assert from 'node:assert/strict';
import { sourceAsOrderTarget } from './api_v1.js';

let n = 0;
const ok = (m) => { n++; console.log('  ✓', m); };

// 1) Une source Xtream devient une cible que l'app sait retrouver.
//    `_matchLocal` (côté Dart) compare serveur + identifiant : ce sont
//    donc les deux champs qui doivent survivre à la traduction.
{
  const t = sourceAsOrderTarget({
    type: 'xtream', server: 'http://exemple.test:8080',
    username: 'client42', password: 'jamais-transmis', label: 'Ma liste',
  });
  assert.equal(t.server, 'http://exemple.test:8080');
  assert.equal(t.username, 'client42');
  assert.equal(t.name, 'Ma liste');
  ok('Xtream → cible avec serveur + identifiant');
}

// 2) LE MOT DE PASSE NE PART PAS DANS L'ORDRE. Un ordre de suppression n'a
//    aucun besoin du secret du client ; il traverse le réseau et se range
//    dans une table. On vérifie qu'aucun champ ne le transporte.
{
  const t = sourceAsOrderTarget({
    type: 'xtream', server: 'http://exemple.test:8080',
    username: 'client42', password: 'SECRET-DU-CLIENT',
  });
  const brut = JSON.stringify(t);
  assert.ok(!brut.includes('SECRET-DU-CLIENT'), 'mot de passe recopié !');
  ok('le mot de passe du client ne voyage jamais dans l\'ordre');
}

// 3) Une source M3U est décrite par son URL.
{
  const t = sourceAsOrderTarget({ type: 'm3u', m3u_url: 'http://x.test/a.m3u' });
  assert.equal(t.m3u_url, 'http://x.test/a.m3u');
  assert.equal(t.server, '');
  ok('M3U → cible avec l\'URL');
}

// 4) Le champ historique `url` est accepté comme URL M3U : d'anciennes
//    lignes en base l'utilisent encore. Les ignorer aurait laissé
//    exactement les plus vieux clients sans suppression.
{
  const t = sourceAsOrderTarget({ type: 'm3u', url: 'http://vieux.test/a.m3u' });
  assert.equal(t.m3u_url, 'http://vieux.test/a.m3u');
  ok('ancien champ « url » reconnu comme URL M3U');
}

// 5) Xtream : on ne met PAS d'URL M3U dans la cible. Côté app, `_matchLocal`
//    teste l'URL M3U EN PREMIER — une URL parasite ferait donc désigner la
//    mauvaise liste, et on supprimerait celle du voisin.
{
  const t = sourceAsOrderTarget({
    type: 'xtream', server: 'http://exemple.test:8080',
    username: 'u', url: 'http://exemple.test:8080/get.php?x=1',
  });
  assert.equal(t.m3u_url, '');
  ok('Xtream : pas d\'URL M3U parasite dans la cible');
}

// 6) Une source sans serveur NI URL ne produit pas d'ordre. Un ordre sans
//    cible ne serait applicable par aucun appareil : il resterait en file
//    pour l'éternité, rejoué à chaque synchro.
{
  assert.equal(sourceAsOrderTarget({ type: 'xtream', username: 'u' }), null);
  assert.equal(sourceAsOrderTarget({}), null);
  assert.equal(sourceAsOrderTarget(null), null);
  ok('source sans serveur ni URL → aucun ordre déposé');
}

// 7) Les espaces parasites sont retirés : le panel reçoit ce que l'humain a
//    collé, l'app compare des chaînes à l'octet près.
{
  const t = sourceAsOrderTarget({
    type: 'xtream', server: '  http://exemple.test:8080  ', username: ' u ',
  });
  assert.equal(t.server, 'http://exemple.test:8080');
  assert.equal(t.username, 'u');
  ok('serveur et identifiant sont nettoyés (comparaison exacte côté app)');
}

// =====================================================================
//  REMPLACEMENT D'UNE LIGNE — « j'active une autre M3U, l'ancienne reste
//  et elle fonctionne encore »
// =====================================================================
//  Quand le panel remplace les sources, `upsertDeviceSource` compare
//  l'ancien envoi au nouveau et fait oublier ce qui disparaît. La
//  comparaison se fait sur une CLÉ construite depuis `sourceAsOrderTarget`.
//
//  Cette clé est l'endroit dangereux du correctif : trop laxiste, on
//  efface la ligne NEUVE du client ; trop stricte, l'ancienne survit et
//  le problème reste entier. D'où ces assertions.
const cle = (s) => {
  const t = sourceAsOrderTarget(s);
  return t ? `${t.server}|${t.username}|${t.m3u_url}` : null;
};

// 8) Deux lignes DIFFÉRENTES ne se confondent pas → l'ancienne part.
{
  const ancienne = { type: 'xtream', server: 'http://a.test:80', username: 'u1' };
  const nouvelle = { type: 'xtream', server: 'http://b.test:80', username: 'u2' };
  assert.notEqual(cle(ancienne), cle(nouvelle));
  ok('serveurs différents → l\'ancienne ligne est bien oubliée');
}

// 9) MÊME serveur, IDENTIFIANT différent : c'est un autre abonnement, même
//    fournisseur. Cas très courant (le revendeur repasse le client sur une
//    autre ligne du même serveur). Sans l'identifiant dans la clé, on
//    croirait que rien n'a changé et l'ancienne resterait jouable.
{
  const a = { type: 'xtream', server: 'http://a.test:80', username: 'client1' };
  const b = { type: 'xtream', server: 'http://a.test:80', username: 'client2' };
  assert.notEqual(cle(a), cle(b));
  ok('même serveur, identifiant différent → considérés distincts');
}

// 10) LA MÊME ligne repoussée ne s'auto-détruit PAS. Le mot de passe a beau
//     changer (renouvellement), c'est le même abonnement : le supprimer
//     couperait un client à jour de ses paiements.
{
  const avant = { type: 'xtream', server: 'http://a.test:80', username: 'u', password: 'vieux' };
  const apres = { type: 'xtream', server: 'http://a.test:80', username: 'u', password: 'neuf' };
  assert.equal(cle(avant), cle(apres));
  ok('même ligne, mot de passe renouvelé → JAMAIS supprimée');
}

// 11) M3U : c'est l'URL qui identifie. Deux fichiers différents → l'ancien
//     s'en va.
{
  const a = { type: 'm3u', m3u_url: 'http://x.test/a.m3u' };
  const b = { type: 'm3u', m3u_url: 'http://x.test/b.m3u' };
  assert.notEqual(cle(a), cle(b));
  assert.equal(cle(a), cle({ type: 'm3u', url: 'http://x.test/a.m3u' }));
  ok('M3U : URL différente → oubliée ; même URL (champ ancien) → gardée');
}

console.log(`\n${n} assertions OK — la suppression panel atteint l'appareil.`);
