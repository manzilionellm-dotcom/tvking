// Pannes du transport et confidentialité : l'accusé métier reste durable,
// même si le panel n'est plus connecté. Les E2E workerd vérifient le vrai WS.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createD1 } from './test_support/d1_sqlite.mjs';
import { createOrder, recordAck } from './box_orders.js';
import { publicPanelState, publishPanelState } from './panel_events.js';

const MAC = 'MK:AA:BB:CC:DD:71';
const ORDER = 'ord_12345678-abcd';

test('les trames panel ne transportent que le contrat public', () => {
  const receipt = publicPanelState({
    type: 'receipt', mac: MAC, at: 123, order_id: ORDER, kind: 'source',
    state: 'applied', config_rev: 7, applied_rev: 7, elapsed_ms: 32,
    password: 'fixture-private', error_message: 'fixture-private',
    server_url: 'https://private.example.test', trace_id: 'private-trace',
  });
  assert.deepEqual(receipt, {
    v: 1, type: 'receipt', mac: MAC, at: 123, order_id: ORDER, kind: 'source',
    state: 'applied', config_rev: 7, applied_rev: 7, elapsed_ms: 32,
  });
  assert.deepEqual(publicPanelState({
    type: 'presence', mac: MAC, at: 123, online: true, last_seen_at: 120,
    ip: '192.0.2.1', channel: 'private-channel', sources: ['private-source'],
  }), { v: 1, type: 'presence', mac: MAC, at: 123, online: true, last_seen_at: 120 });
  for (const invalid of [
    { ...receipt, at: -1 }, { ...receipt, at: '123' },
    { ...receipt, order_id: 'other' }, { ...receipt, state: 'queued' },
    { ...receipt, applied_rev: 1.5 }, { ...receipt, config_rev: -1 },
    { ...receipt, mac: 'another-device' }, { ...receipt, type: 'free-text' },
  ]) assert.equal(publicPanelState(invalid), null);
});

for (const mode of ['disabled', 'unavailable', 'throws', 'http-failure']) {
  test(`transport ${mode} : APPLIED reste écrit sans faire échouer l'accusé`, async () => {
    const fixture = createD1();
    let calls = 0;
    let order;
    let persistedBeforePush = false;
    const env = { DB: fixture.DB, RT_HUB: {
      idFromName: name => { assert.equal(name, 'panel-v1'); return name; },
      get: () => ({ fetch: async () => {
        calls += 1;
        persistedBeforePush = fixture.db.prepare('SELECT state FROM box_orders WHERE order_id = ?').get(order).state === 'applied';
        if (mode === 'throws') throw new Error('transport unavailable');
        return new Response('', { status: 503 });
      } }),
    } };
    if (mode === 'disabled') env.REALTIME_PUSH_OFF = '1';
    if (mode === 'unavailable') delete env.RT_HUB;
    try {
      order = await createOrder(env, { mac: MAC, kind: 'activate' });
      const result = await recordAck(env, MAC, { order_id: order, state: 'applied' });
      assert.equal(result.status, 200);
      assert.equal(result.body.changed, true);
      assert.equal(fixture.db.prepare('SELECT state FROM box_orders WHERE order_id = ?').get(order).state, 'applied');
      assert.equal(calls, ['disabled', 'unavailable'].includes(mode) ? 0 : 1);
      if (calls) assert.equal(persistedBeforePush, true);
    } finally { fixture.db.close(); }
  });
}

test('une entrée invalide ne contacte pas le hub', async () => {
  const env = { RT_HUB: { idFromName() { throw new Error('must not connect'); } } };
  assert.equal(await publishPanelState(env, { type: 'receipt', mac: MAC }), false);
});
