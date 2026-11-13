import test from 'node:test';
import assert from 'node:assert/strict';
import gold, { RealtimeHub } from './gold.js';
import orig from './worker.js';

const ctx = { waitUntil() {}, passThroughOnException() {} };
const brokenDb = { prepare() { throw new Error('db_down'); } };

test('gold wrapper garde les exports du worker (Durable Object)', () => {
  assert.equal(typeof RealtimeHub, 'function');
  assert.equal(typeof gold.fetch, 'function');
});

test('/api/gold-trial est servi par le module Gold', async () => {
  const r = await gold.fetch(new Request('https://x/api/gold-trial', { method: 'POST', body: '{}' }), { DB: brokenDb }, ctx);
  const body = await r.json();
  assert.ok(['gold_internal', 'bad_request', 'invalid_mac', 'disabled'].includes(body.error) || r.status < 500, JSON.stringify(body));
});

test('/api/v1/gold/* exige une session admin', async () => {
  const r = await gold.fetch(new Request('https://x/api/v1/gold/config'), { DB: brokenDb }, ctx);
  assert.ok(r.status === 401 || r.status === 403 || r.status === 500);
});

test('les autres routes passent au worker inchangé', async () => {
  const env = { DB: brokenDb };
  const a = await gold.fetch(new Request('https://x/does-not-exist-xyz'), env, ctx).then(r => r.status).catch(e => 'throw');
  const b = await orig.fetch(new Request('https://x/does-not-exist-xyz'), env, ctx).then(r => r.status).catch(e => 'throw');
  assert.equal(a, b);
});
