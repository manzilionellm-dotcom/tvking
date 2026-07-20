// Smoke test — PRÊT D'ABONNEMENT (mode='lend') : règlement paresseux.
// Vérifie la DÉCISION PURE de retour auto (loanSettleDecision), sans base.
// Lancer : node cloudflare/invite_loan.smoke.mjs
import assert from 'node:assert/strict';
import { loanSettleDecision } from './worker.js';

let n = 0;
const ok = (m) => { n++; console.log('  ✓', m); };

const NOW = 1_000_000_000_000;

// 1) Un abonné NORMAL (licence active) ne déclenche JAMAIS la logique de prêt
//    → 'none' (aucune requête app_loans sur le chemin chaud).
assert.equal(
  loanSettleDecision({ lstatus: 'active', loanRow: null, now: NOW }),
  'none',
);
ok("licence active → 'none' (hors chemin de prêt)");

// 2) Essai / expiré : idem, jamais concerné.
assert.equal(
  loanSettleDecision({ lstatus: 'expired', loanRow: null, now: NOW }),
  'none',
);
ok("licence expirée → 'none'");

// 3) En pause 'loaned', prêt ENCORE en cours (return_at futur) → 'hold' :
//    le propriétaire reste en pause, on affiche « prêté, retour dans X ».
assert.equal(
  loanSettleDecision({
    lstatus: 'loaned',
    loanRow: { return_at: NOW + 3_600_000, returned_at: null },
    now: NOW,
  }),
  'hold',
);
ok("prêt en cours → 'hold' (propriétaire en pause)");

// 4) En pause 'loaned', échéance ATTEINTE (return_at passé) → 'restore' :
//    retour automatique de l'abonnement au propriétaire.
assert.equal(
  loanSettleDecision({
    lstatus: 'loaned',
    loanRow: { return_at: NOW - 1, returned_at: null },
    now: NOW,
  }),
  'restore',
);
ok("échéance atteinte → 'restore' (retour auto)");

// 5) Échéance pile à l'instant présent → 'restore' (borne incluse).
assert.equal(
  loanSettleDecision({
    lstatus: 'loaned',
    loanRow: { return_at: NOW, returned_at: null },
    now: NOW,
  }),
  'restore',
);
ok('échéance == maintenant → restore (borne incluse)');

// 6) Prêt DÉJÀ réglé (returned_at posé) → 'none' : idempotent, ne se rejoue pas.
assert.equal(
  loanSettleDecision({
    lstatus: 'loaned',
    loanRow: { return_at: NOW - 10_000, returned_at: NOW - 5_000 },
    now: NOW,
  }),
  'none',
);
ok('prêt déjà réglé → none (idempotent)');

// 7) Statut 'loaned' résiduel SANS ligne de prêt → 'none' : repli sûr
//    (le caller laisse le calcul normal → propriétaire non payé, jamais
//    d'accès accordé par erreur).
assert.equal(
  loanSettleDecision({ lstatus: 'loaned', loanRow: null, now: NOW }),
  'none',
);
ok("'loaned' sans prêt → none (repli sûr)");

console.log(`\n${n} assertions OK — retour auto du PRÊT validé.`);
