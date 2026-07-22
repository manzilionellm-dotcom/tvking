// Smoke test — COMPTES MAÎTRES : démo illimitée (bypass quota + paiement).
// Vérifie la décision pure du redeem quand l'émetteur est un MAÎTRE.
// Lancer : node cloudflare/invite_master.smoke.mjs
import assert from 'node:assert/strict';
import { inviteRedeemDecision } from './worker.js';

let n = 0;
const ok = (m) => { n++; console.log('  ✓', m); };

const NOW = 1_000_000_000_000;
const paid = { paid: true, expired: false, frozen: false, banned: false };
const notPaid = { paid: false, expired: true };
const codeRow = {
  issuer_mac: 'MK:AA:AA:AA:AA:AA',
  expires_at: NOW + 60_000,
  redeemed_at: null,
};
const base = {
  mac: 'MK:BB:BB:BB:BB:BB',
  code: '123456',
  codeRow,
  now: NOW,
  ownStatus: null,
  alreadyRedeemed: false,
};

// 1) Émetteur NON payé, NON maître → refus classique.
assert.equal(
  inviteRedeemDecision({ ...base, issuerStatus: notPaid, issuerIsMaster: false }).error,
  'issuer_not_paid',
);
ok('non-maître non payé → issuer_not_paid');

// 2) Émetteur MAÎTRE non payé → ACCEPTÉ (pas besoin d'abonnement).
assert.equal(
  inviteRedeemDecision({ ...base, issuerStatus: notPaid, issuerIsMaster: true }).ok,
  true,
);
ok('maître non payé → accepté');

// 3) Émetteur MAÎTRE au-delà du quota → ACCEPTÉ (pas de quota).
assert.equal(
  inviteRedeemDecision({
    ...base, issuerStatus: paid, issuerIsMaster: true,
    issuerWeeklyUsed: 9999, weeklyQuota: 5,
  }).ok,
  true,
);
ok('maître au-delà du quota → accepté (illimité)');

// 4) Émetteur NON maître au-delà du quota → refus.
assert.equal(
  inviteRedeemDecision({
    ...base, issuerStatus: paid, issuerIsMaster: false,
    issuerWeeklyUsed: 5, weeklyQuota: 5,
  }).error,
  'issuer_quota',
);
ok('non-maître au quota → issuer_quota');

// 5) Maître + personne AYANT DÉJÀ testé → ACCEPTÉ (re-test 1 h, 1 h…).
assert.equal(
  inviteRedeemDecision({
    ...base, issuerStatus: paid, issuerIsMaster: true, alreadyRedeemed: true,
  }).ok,
  true,
);
ok('maître → re-test autorisé (pas de « un seul pass à vie »)');

// 6) Non-maître + déjà testé → already_used_once.
assert.equal(
  inviteRedeemDecision({
    ...base, issuerStatus: paid, issuerIsMaster: false, alreadyRedeemed: true,
  }).error,
  'already_used_once',
);
ok('non-maître déjà testé → already_used_once');

// 7) Même un maître respecte la validité du code (code déjà utilisé).
assert.equal(
  inviteRedeemDecision({
    ...base, codeRow: { ...codeRow, redeemed_at: NOW - 1 },
    issuerStatus: paid, issuerIsMaster: true,
  }).error,
  'code_used',
);
ok('maître → code déjà utilisé reste refusé (intégrité)');

console.log(`\n${n} assertions OK — démo illimitée (comptes maîtres) validée.`);
