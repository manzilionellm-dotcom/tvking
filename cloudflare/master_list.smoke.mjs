// Smoke test — LISTE DE TEST INDÉPENDANTE (« notre liste », < 5 chaînes).
// Vérifie les deux briques PURES qui rendent le test indépendant du
// fournisseur : le comptage de chaînes d'un M3U et la référence opaque stable
// (jamais la MAC maître en clair dans l'URL du testeur).
// Lancer : node cloudflare/master_list.smoke.mjs
import assert from 'node:assert/strict';
import { countM3uChannels, masterListRef } from './worker.js';
import { masterListRefPanel } from './api_v1.js';

let n = 0;
const ok = (m) => { n++; console.log('  ✓', m); };

// --- countM3uChannels : compte les #EXTINF (indicateur < 5 chaînes) ---------
assert.equal(countM3uChannels(''), 0);
ok('M3U vide → 0 chaîne');

assert.equal(countM3uChannels(null), 0);
ok('M3U null → 0 chaîne (jamais d’erreur)');

const m3u3 =
  '#EXTM3U\n' +
  '#EXTINF:-1,Chaîne 1\nhttps://gw/live/1.ts\n' +
  '#EXTINF:-1,Chaîne 2\nhttps://gw/live/2.ts\n' +
  '#EXTINF:-1,Chaîne 3\nhttps://gw/live/3.ts\n';
assert.equal(countM3uChannels(m3u3), 3);
ok('M3U de 3 chaînes → 3 (petite liste = indépendance)');

// Casse insensible (#extinf minuscule) toujours comptée.
assert.equal(countM3uChannels('#extinf:-1,x\nhttp://a\n'), 1);
ok('#extinf minuscule compté (robustesse)');

// --- masterListRef : opaque, stable, ne révèle pas la MAC -------------------
const MAC = 'MK:24:2A:D0:0E:F3';
const ref1 = await masterListRef(MAC);
const ref2 = await masterListRef(MAC);
assert.equal(ref1, ref2);
ok('référence STABLE pour une même MAC (URL de test constante)');

assert.match(ref1, /^ml_[0-9a-f]{20}$/);
ok('référence au format opaque ml_… (20 hex)');

assert.ok(!ref1.includes('24') && !ref1.toUpperCase().includes(MAC));
ok('la MAC maître n’apparaît JAMAIS dans la référence (privé)');

const refOther = await masterListRef('MK:AA:BB:CC:DD:EE');
assert.notEqual(ref1, refOther);
ok('deux maîtres → deux références distinctes');

// --- PARITÉ worker ↔ panel : masterListRefPanel (api_v1) = masterListRef ----
// Le panel (test-grant) bâtit l'URL de liste avec SA réplique de la fonction
// (cycle d'imports interdit) : les deux DOIVENT produire le même hash, sinon
// les tests donnés depuis le panel serviraient une URL morte.
assert.equal(await masterListRefPanel(MAC), ref1);
assert.equal(await masterListRefPanel('MK:AA:BB:CC:DD:EE'), refOther);
ok('masterListRefPanel (api_v1) ≡ masterListRef (worker) — parité verrouillée');

console.log(`\n${n} assertions OK — liste de test indépendante validée.`);
