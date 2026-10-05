// Essais gratuits de l'activation à distance : identifiants compris par le Worker.
import { test } from 'node:test';
import assert from 'node:assert/strict';

// Copie de planToDays (cloudflare/api_v1.js) pour les plans proposés par l'écran.
function planToDays(plan: string): number | null {
  const dm = /^trial_(\d+)d$/.exec(plan);
  if (dm) return Number(dm[1]);
  if (plan === 'yearly') return 365;
  if (plan === 'lifetime') return null;
  return 30;
}

test('3 jours, 7 jours, 1 mois d\'essai, 1 an, à vie', () => {
  assert.equal(planToDays('trial_3d'), 3);
  assert.equal(planToDays('trial_7d'), 7);
  assert.equal(planToDays('trial_30d'), 30);
  assert.equal(planToDays('yearly'), 365);
  assert.equal(planToDays('lifetime'), null);
});
