// Smoke test — CONFIDENTIALITÉ FAMILLE : référence opaque des membres.
// La vraie MAC d'un membre ne doit jamais sortir hors du panel ; l'app
// n'utilise qu'une référence opaque `m_…` pour renommer / retirer.
// Lancer : node cloudflare/family_ref.smoke.mjs
import assert from 'node:assert/strict';
import { familyMemberRef } from './worker.js';

let n = 0;
const ok = (m) => { n++; console.log('  ✓', m); };

const MAC_A = 'MK:AA:BB:CC:DD:EE';
const MAC_B = 'MK:11:22:33:44:55';

// 1) Déterministe : même MAC → même référence (pour retrouver le membre).
const refA1 = await familyMemberRef(MAC_A);
const refA2 = await familyMemberRef(MAC_A);
assert.equal(refA1, refA2);
ok('déterministe : même MAC → même référence');

// 2) Format opaque `m_…`, court.
assert.match(refA1, /^m_[0-9a-f]{16}$/);
ok('format opaque m_<16 hex>');

// 3) Non réversible / ne contient pas la MAC en clair.
assert.ok(!refA1.includes('AA'));
assert.ok(!refA1.toUpperCase().includes(MAC_A.replace(/:/g, '')));
ok('la référence ne révèle pas la MAC');

// 4) Deux membres différents → références différentes.
const refB = await familyMemberRef(MAC_B);
assert.notEqual(refA1, refB);
ok('deux MAC différentes → références différentes');

// 5) Insensible à la casse de la MAC (l'app peut envoyer minuscules).
const refLower = await familyMemberRef(MAC_A.toLowerCase());
assert.equal(refLower, refA1);
ok('insensible à la casse de la MAC');

console.log(`\n${n} assertions OK — référence opaque famille validée.`);
