// =========================================================
//  source_presence.smoke.mjs — « le client l'a-t-il encore ? »
// =========================================================
//  POURQUOI CE TEST EXISTE (16/09/2026).
//
//  Le propriétaire : « si j'efface la liste au téléphone, même au panel
//  la liste ne part pas ». Exact. Quand le client supprime une liste,
//  l'app pose une empreinte LOCALE et efface sa base — elle ne prévient
//  personne (la route publique n'accepte que la lecture). La ligne
//  poussée reste, et le panel l'affiche.
//
//  Le panel avait pourtant la réponse : le heartbeat remonte
//  l'inventaire RÉEL de l'appareil. Personne ne confrontait les deux
//  listes. C'est fait, et ce fichier verrouille la confrontation.
//
//  LES DEUX FAÇONS DE SE TROMPER NE COÛTENT PAS PAREIL :
//   • rater une suppression → le panel affiche une ligne de trop. Gênant,
//     visible, sans conséquence ;
//   • déclarer « supprimée » une liste que le client A ENCORE → le
//     revendeur repousse une source par-dessus une source qui marchait,
//     ou accuse son client à tort. C'est l'erreur chère.
//  Dans le doute, donc, on NE DIT RIEN.
//
//  Lancer : node cloudflare/source_presence.smoke.mjs
// =========================================================
import assert from 'node:assert/strict';
import {
  origineUrl, memeSource, marquerPresenceSurAppareil,
} from './api_v1.js';

let n = 0;
const ok = (m) => { n += 1; console.log('  ✓', m); };

// ---------------------------------------------------------
//  1. L'origine d'une URL — le cœur du piège M3U
// ---------------------------------------------------------
//  L'inventaire de l'app ne remonte QUE l'origine d'une URL M3U : une
//  URL M3U porte presque toujours `username=…&password=…`, qu'on refuse
//  de faire voyager. Comparer les URLs entières ferait paraître TOUTE
//  liste M3U comme supprimée par son client.
assert.equal(
  origineUrl('http://pro.exemple.tv:8080/get.php?username=u&password=p&type=m3u'),
  'http://pro.exemple.tv:8080',
);
ok('une URL M3U avec identifiants se réduit à son origine');

assert.equal(origineUrl('http://pro.exemple.tv:8080'), 'http://pro.exemple.tv:8080');
assert.equal(origineUrl('https://pro.exemple.tv'), 'https://pro.exemple.tv');
ok('une origine déjà nue traverse intacte');

for (const mauvais of ['', '   ', 'pas une url', null, undefined]) {
  assert.equal(origineUrl(mauvais), '', `entrée : ${JSON.stringify(mauvais)}`);
}
ok('une entrée vide ou illisible donne une origine vide (jamais d\'exception)');

// ---------------------------------------------------------
//  2. Xtream : l'utilisateur départage
// ---------------------------------------------------------
const xtreamPousse = {
  type: 'xtream', server_url: 'http://panel.exemple.tv:8080', username: 'lionel',
};
assert.equal(
  memeSource(xtreamPousse, {
    type: 'xtream', server: 'http://panel.exemple.tv:8080', username: 'lionel',
  }),
  true,
);
ok('même panel + même utilisateur → même source');

//  LE CAS QUI COMPTE : deux lignes du MÊME panel. Sans l'utilisateur, la
//  ligne du frère passerait pour la sienne, et on dirait « toujours là »
//  alors que la sienne a disparu.
assert.equal(
  memeSource(xtreamPousse, {
    type: 'xtream', server: 'http://panel.exemple.tv:8080', username: 'sofia',
  }),
  false,
);
ok('même panel, AUTRE utilisateur → sources différentes');

//  Un identifiant vide ne prouve rien : on refuse de conclure.
assert.equal(
  memeSource(xtreamPousse, {
    type: 'xtream', server: 'http://panel.exemple.tv:8080', username: '',
  }),
  false,
);
ok('utilisateur absent d\'un côté → on ne conclut pas à l\'égalité');

assert.equal(
  memeSource(xtreamPousse, {
    type: 'xtream', server: 'http://autre.exemple.tv:8080', username: 'lionel',
  }),
  false,
);
ok('autre serveur → sources différentes');

// ---------------------------------------------------------
//  3. M3U : on compare les ORIGINES, jamais les URLs entières
// ---------------------------------------------------------
const m3uPousse = {
  type: 'm3u',
  m3u_url: 'http://pro.exemple.tv:8080/get.php?username=u&password=p&type=m3u',
};
assert.equal(
  memeSource(m3uPousse, { type: 'm3u', server: 'http://pro.exemple.tv:8080' }),
  true,
);
ok('M3U : l\'origine suffit — sinon toute liste M3U paraîtrait supprimée');

assert.equal(
  memeSource(m3uPousse, { type: 'm3u', server: 'http://autre.exemple.tv:8080' }),
  false,
);
ok('M3U : origine différente → source différente');

assert.equal(
  memeSource(m3uPousse, {
    type: 'xtream', server: 'http://pro.exemple.tv:8080', username: 'u',
  }),
  false,
);
ok('types connus et différents → jamais la même source');

// ---------------------------------------------------------
//  4. LE VERDICT — et son silence
// ---------------------------------------------------------
const pousses = [xtreamPousse, m3uPousse];

//  Le client a gardé l'Xtream et supprimé la M3U.
const r1 = marquerPresenceSurAppareil(pousses, [
  { type: 'xtream', server: 'http://panel.exemple.tv:8080', username: 'lionel' },
]);
assert.equal(r1[0].present, true);
assert.equal(r1[1].present, false);
ok('gardée → present:true ; supprimée par le client → present:false');

//  INVENTAIRE VIDE = « je ne sais pas ». App ancienne, ou heartbeat pas
//  encore passé. Dire « supprimée » ici enverrait le revendeur repousser
//  une source par-dessus une source qui marche. C'est exactement
//  l'erreur du bandeau « aucun démarrage de l'app ».
const r2 = marquerPresenceSurAppareil(pousses, []);
assert.equal('present' in r2[0], false);
assert.equal('present' in r2[1], false);
ok('inventaire vide → AUCUN verdict (le champ est absent, pas false)');

assert.deepEqual(marquerPresenceSurAppareil([], [{ type: 'm3u', server: 'http://x' }]), []);
assert.deepEqual(marquerPresenceSurAppareil(null, null), []);
ok('listes vides ou absentes → tableau vide, aucune exception');

//  On n'abîme pas la source : le panel lit encore label, serveur, etc.
assert.equal(r1[0].server_url, 'http://panel.exemple.tv:8080');
assert.equal(r1[0].username, 'lionel');
ok('les champs d\'origine de la source sont préservés');

console.log(`\n${n} assertions OK`);
