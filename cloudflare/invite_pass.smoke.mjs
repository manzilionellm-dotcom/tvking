// Smoke test — PASS PARTAGE (« regarder ensemble ») : règles anti-abus argent.
// Lancer : node cloudflare/invite_pass.smoke.mjs
import assert from 'node:assert/strict';
import { inviteRedeemDecision } from './worker.js';

let n = 0;
const ok = (m) => { n++; console.log('  ✓', m); };

const NOW = 1_000_000_000_000;
const paid = { paid: true, expired: false, frozen: false, banned: false };
const freshCode = {
  issuer_mac: 'MK:AA:AA:AA:AA:AA',
  expires_at: NOW + 60_000,
  redeemed_at: null,
};
const base = {
  mac: 'MK:BB:BB:BB:BB:BB',
  code: '123456',
  codeRow: freshCode,
  now: NOW,
  issuerStatus: paid,
  ownStatus: null,
  alreadyRedeemed: false,
};

// 1) Cas nominal : nouvel appareil + code frais + émetteur payé → OK.
assert.deepEqual(inviteRedeemDecision(base), { ok: true });
ok('nouvel appareil + code valide + émetteur payé → accès accordé');

// 2) Code au mauvais format → refus.
assert.equal(inviteRedeemDecision({ ...base, code: '12ab' }).error, 'code_invalid');
assert.equal(inviteRedeemDecision({ ...base, code: '999' }).error, 'code_invalid');
ok('code non-6-chiffres → code_invalid');

// 3) Code inconnu → refus.
assert.equal(inviteRedeemDecision({ ...base, codeRow: null }).error, 'code_invalid');
ok('code inexistant → code_invalid');

// 4) Code déjà utilisé → refus (non rejouable).
assert.equal(
  inviteRedeemDecision({ ...base, codeRow: { ...freshCode, redeemed_at: NOW - 10 } }).error,
  'code_used',
);
ok('code déjà consommé → code_used');

// 5) Code expiré → refus.
assert.equal(
  inviteRedeemDecision({ ...base, codeRow: { ...freshCode, expires_at: NOW - 1 } }).error,
  'code_expired',
);
ok('code expiré → code_expired');

// 6) Son propre code → refus.
assert.equal(
  inviteRedeemDecision({ ...base, mac: 'MK:AA:AA:AA:AA:AA' }).error,
  'own_code',
);
ok('utiliser son propre code → own_code');

// 7) Émetteur plus payé (expiré / gelé / banni / absent) → refus.
for (const bad of [null,
  { paid: false },
  { paid: true, expired: true },
  { paid: true, frozen: true },
  { paid: true, banned: true }]) {
  assert.equal(
    inviteRedeemDecision({ ...base, issuerStatus: bad }).error,
    'issuer_not_paid',
  );
}
ok('émetteur non payé/gelé/banni/expiré → issuer_not_paid');

// 8) Appareil DÉJÀ payé → pas besoin de pass.
assert.equal(
  inviteRedeemDecision({ ...base, ownStatus: { paid: true, expired: false } }).error,
  'already_active',
);
ok('appareil déjà payé → already_active');

// 9) GARDE-FOU CLÉ : un appareil ne peut utiliser qu'UN pass à vie.
assert.equal(
  inviteRedeemDecision({ ...base, alreadyRedeemed: true }).error,
  'already_used_once',
);
ok('appareil ayant déjà testé → already_used_once (un seul pass à vie)');

// 10) Un appareil dont le pass a EXPIRÉ (ownStatus payé=false, expired=true)
//     ne peut PAS re-tester (already_used_once prime sur le reste).
assert.equal(
  inviteRedeemDecision({
    ...base,
    ownStatus: { paid: false, expired: true },
    alreadyRedeemed: true,
  }).error,
  'already_used_once',
);
ok('pass expiré + déjà testé → doit payer (already_used_once)');

console.log(`\n${n} assertions OK — anti-abus du Pass Partage validé.`);
