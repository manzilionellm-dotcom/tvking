import test from 'node:test';
import assert from 'node:assert/strict';
import { ActivationSession } from './activationSession.ts';
import { deliveryLabel, resolvePanelApiBase } from './deliveryStatus.ts';

test('Vercel sans variable vise le Worker ; le proxy Vite et la surcharge restent possibles', () => {
  assert.equal(resolvePanelApiBase(undefined, true), 'https://app.7themotion.com');
  assert.equal(resolvePanelApiBase(undefined, false), '');
  assert.equal(resolvePanelApiBase(' https://staging.example.test/// ', true), 'https://staging.example.test');
});

test('une écriture serveur ne prouve ni réception ni application de la bonne révision', () => {
  const order = { order_id: 'ord_fixture1234', kind: 'source', state: 'sent', config_rev: 19 };
  assert.match(deliveryLabel(order), /attente/);
  assert.match(deliveryLabel({ ...order, state: 'received' }), /en cours/);
  assert.match(deliveryLabel({ ...order, state: 'applied', applied_rev: 18 }), /non confirmée/);
  assert.match(deliveryLabel({ ...order, state: 'applied', applied_rev: 19 }), /^Appliqué/);
  assert.match(deliveryLabel({ ...order, state: 'failed' }), /échec/);
});

test('échec des sources après débit : une reprise ne renouvelle jamais la licence', async () => {
  let charges = 0, sends = 0, saved = 0;
  const session = new ActivationSession({
    activate: async () => { charges++; return { id: 'lic-fixture' }; },
    sendSources: async () => { if (++sends === 1) throw Error('coupure'); return { count: 1 }; },
    onLicense: () => { saved++; },
  });
  await assert.rejects(session.run(), /coupure/);
  assert.equal(session.license?.id, 'lic-fixture');
  await session.run();
  await session.run();
  assert.deepEqual({ charges, sends, saved }, { charges: 1, sends: 2, saved: 1 });
});

test('deux clics concurrents partagent la même opération payante', async () => {
  let calls = 0;
  let finish!: () => void;
  const wait = new Promise<void>(resolve => { finish = resolve; });
  const session = new ActivationSession({
    activate: async () => { calls++; await wait; return { ok: true }; },
    onLicense: () => {},
  });
  const first = session.run(), second = session.run();
  assert.equal(first, second);
  finish();
  await first;
  assert.equal(calls, 1);
});

test('réponse d’activation perdue : pas de second débit automatique', async () => {
  let calls = 0;
  const session = new ActivationSession({
    activate: async () => { calls++; throw Error('réponse perdue'); },
    onLicense: () => {},
  });
  await assert.rejects(session.run(), /réponse perdue/);
  await assert.rejects(session.run(), /incertain/);
  assert.equal(calls, 1);
});
