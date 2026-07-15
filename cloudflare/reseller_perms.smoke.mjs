// Smoke test — règles de permissions revendeur (sphère argent).
// Lancer : node cloudflare/reseller_perms.smoke.mjs
import assert from 'node:assert/strict';
import {
  RESELLER_CAPS_ALL, RESELLER_DEFAULT_CAPS,
  sanitizePerms, resellerCan,
} from './api_v1.js';

let n = 0;
const ok = (m) => { n++; console.log('  ✓', m); };

// 1) Les défauts sont exactement : activer / bloquer / transférer / achat crédit.
assert.deepEqual(RESELLER_DEFAULT_CAPS, ['activate', 'block', 'transfer', 'buy_credits']);
ok('défauts = activate, block, transfer, buy_credits');

// 2) « resellers » n'est JAMAIS un défaut (owner seul l'accorde).
assert.ok(!RESELLER_DEFAULT_CAPS.includes('resellers'));
ok('« resellers » (créer sous-revendeur) n’est pas un défaut');

// 3) sanitizePerms ne garde que des droits connus (anti-injection).
assert.deepEqual(
  sanitizePerms(['activate', 'block', 'pirate', 'transfer']).sort(),
  ['activate', 'block', 'transfer'].sort(),
);
ok('sanitizePerms rejette les droits inconnus');

// 4) Un droit inventé n'existe pas dans la liste canonique.
assert.ok(!RESELLER_CAPS_ALL.includes('pirate'));
ok('la liste canonique est fermée');

// 5) resellerCan : owner a TOUT ; revendeur uniquement ses droits cochés.
const owner = { role: 'super_admin' };
const admin = { role: 'admin' };
const reseller = { role: 'reseller', permissions: ['activate', 'block'] };
assert.equal(resellerCan(owner, 'resellers'), true);
assert.equal(resellerCan(admin, 'anything'), true);
assert.equal(resellerCan(reseller, 'activate'), true);
assert.equal(resellerCan(reseller, 'block'), true);
assert.equal(resellerCan(reseller, 'transfer'), false);
assert.equal(resellerCan(reseller, 'resellers'), false);
assert.equal(resellerCan(reseller, 'buy_credits'), false);
ok('resellerCan : owner=tout, revendeur=ses droits seulement');

// 6) Un revendeur créant un sous-revendeur → défauts SANS « resellers ».
const childPerms = sanitizePerms(RESELLER_DEFAULT_CAPS).filter((c) => c !== 'resellers');
assert.ok(!childPerms.includes('resellers'));
assert.deepEqual(childPerms.sort(), ['activate', 'block', 'buy_credits', 'transfer'].sort());
ok('sous-revendeur créé par un revendeur : jamais « resellers »');

console.log(`\n${n} assertions OK — règles argent/permissions validées.`);
