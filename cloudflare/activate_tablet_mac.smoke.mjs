// =========================================================
//  activate_tablet_mac.smoke.mjs — Lionel, tablette CD:18:EF:A1:A0
// =========================================================
//  Photo du 13/09 : écran mobile « Nos offres » (pas la box TV).
//  On verrouille le pont AFFICHAGE → ACTIVER → publishRt :
//    écran    CD:18:EF:A1:A0
//    interne  MK:CD:18:EF:A1:A0
//    panel    formatMacInput remet MK:
//    Worker   MAC_RX / RT_MAC_RX acceptent
//    licence  annuel frais gagne contre lifetime inactive
// =========================================================
import assert from 'node:assert/strict';
import { pickBestLicense } from './license_pick.js';
import { formatMacInput, formatMacAsYouType } from './mac_identity.js';

const SHOWN = 'CD:18:EF:A1:A0';
const INTERNAL = 'MK:CD:18:EF:A1:A0';
const MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/i;

let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass++; console.log('PASS', m); }
  else { fail++; console.log('FAIL', m); }
};

ok(formatMacInput(SHOWN) === INTERNAL, 'coller CD:18:EF:A1:A0 → MK:CD:18:EF:A1:A0');
ok(formatMacInput(INTERNAL) === INTERNAL, 'coller MK:CD:18:EF:A1:A0 inchangé');
ok(formatMacInput('cd18efa1a0') === INTERNAL, 'chiffres seuls → même MAC');
ok(formatMacAsYouType('cd18efa1a0') === SHOWN, 'as-you-type sans MK: → numéro affiché');
ok(formatMacAsYouType(INTERNAL) === INTERNAL, 'as-you-type garde MK: si déjà là');
ok(MAC_RX.test(INTERNAL), '/activate + hub RT acceptent MK:CD:18:EF:A1:A0');
ok(!MAC_RX.test(SHOWN), 'le code NU seul est refusé (le panel DOIT préfixer)');

// Après Activer : annuel actif doit déverrouiller même si une lifetime
// inactive traîne (autre app_id) — c'était le trou panel-vert / tablette-verrou.
const now = Date.now();
const yearly = { lstatus: 'active', expires_at: now + 365 * 86400000 };
const deadLife = { lstatus: 'inactive', expires_at: null };
ok(pickBestLicense([deadLife, yearly], now) === yearly,
  'Activer annuel sur CETTE MAC → heartbeat paid (pas la lifetime morte)');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
