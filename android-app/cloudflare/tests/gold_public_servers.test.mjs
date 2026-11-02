// Vrai gold.fetch et SQLite : catalogue admin → app → signal durable.
// Le DO est localement simulé ; aucun serveur ou appareil réel n'est contacté.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHmac } from 'node:crypto';
import { createD1 } from '../test_support/d1_sqlite.mjs';
import '../prepare_gold_runtime.mjs';
const gold = (await import('../gold.js')).default;
const macs = ['MK:11:22:33:44:55', 'MK:AA:BB:CC:DD:EE'];
const legacy = { id: 'ancien', label: 'Ancien repli', url: 'https://legacy.example.invalid/' };

function fixture() {
  const f = createD1({ schema: false });
  f.db.exec(readFileSync(new URL('../production/schema.sql', import.meta.url), 'utf8'));
  f.db.exec("INSERT INTO admin_users(id,email,password_hash,role,is_active,created_at) VALUES ('admin','fixture@example.invalid','unused','super_admin',1,1)");
  f.db.exec("INSERT INTO customers(id,created_at,updated_at) VALUES ('customer',1,1)");
  for (const [i, mac] of macs.entries()) {
    f.db.prepare('INSERT INTO devices(id,customer_id,mac,first_seen_at,last_seen_at) VALUES (?,?,?,?,?)')
      .run(`device-${i}`, 'customer', mac, 1, 1);
  }
  const secret = 'fixture-public-servers-local-only';
  const enc = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const h = enc({ alg: 'HS256', typ: 'JWT' });
  const p = enc({ sub: 'admin', role: 'super_admin', iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + 3600 });
  const token = `${h}.${p}.${createHmac('sha256', secret).update(`${h}.${p}`).digest('base64url')}`;
  const tasks = [], signals = [];
  const env = { DB: f.DB, ADMIN_SECRET: secret, DEFAULT_SERVERS: JSON.stringify([legacy]), RT_HUB: {
    idFromName: value => value,
    get: name => ({ fetch: async (url, init) => {
      const path = new URL(url).pathname;
      assert.ok(['/notify', '/fanout'].includes(path));
      assert.equal(init.method, 'POST');
      signals.push({ name, path, body: JSON.parse(init.body) });
      return Response.json({ ok: true, seq: signals.length });
    } }),
  } };
  const flush = async () => { while (tasks.length) await Promise.all(tasks.splice(0)); };
  async function call(path, method = 'GET', body, authorized = true) {
    const response = await gold.fetch(new Request(`https://fixture.example${path}`, {
      method, headers: { 'Content-Type': 'application/json',
        ...(authorized ? { Authorization: `Bearer ${token}` } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }), env, { waitUntil: promise => tasks.push(promise) });
    await flush();
    return { response, body: await response.json() };
  }
  return { ...f, env, signals, call, async close() { await flush(); f.db.close(); } };
}

test('serveurs panel : créer/modifier/masquer/supprimer met à jour le catalogue et chaque appareil', async () => {
  const f = fixture();
  try {
    let mutations = 0;
    async function write(path, method, body) {
      const result = await f.call(path, method, body);
      assert.ok(result.response.ok, `${method} ${path}: ${result.response.status}`);
      mutations++;
      const orders = f.db.prepare("SELECT mac,kind,state FROM box_orders ORDER BY created_at,order_id").all();
      assert.equal(orders.length, mutations * macs.length);
      assert.ok(orders.every(order => order.kind === 'servers' && order.state === 'sent'));
      for (const mac of macs) assert.equal(orders.filter(order => order.mac === mac).length, mutations);
      assert.equal(f.signals.filter(signal => signal.path === '/notify').length, mutations * macs.length);
      assert.ok(f.signals.every(signal => signal.body.kind === 'servers' && signal.body.order_id));
      assert.doesNotMatch(JSON.stringify(f.signals), /example\.invalid|password|username/);
      return result.body;
    }
    const one = { id: 'one', label: 'Premier', url: 'https://one.example.invalid/', position: 2 };
    const two = { id: 'two', label: 'Second', url: 'https://two.example.invalid/', position: 1 };
    await write('/api/v1/servers', 'POST', one);
    await write('/api/v1/servers', 'POST', two);
    assert.deepEqual((await f.call('/api/servers')).body.servers.map(row => row.id), ['two', 'one']);
    await write('/api/v1/servers/one', 'PATCH', { label: 'Modifié', url: 'https://changed.example.invalid/', position: 0 });
    const listed = await f.call('/api/servers');
    assert.deepEqual(listed.body.servers[0], { id: 'one', label: 'Modifié', url: 'https://changed.example.invalid/' });
    assert.equal(listed.response.headers.get('cache-control'), 'no-store');
    await write('/api/v1/servers/one', 'PATCH', { enabled: false });
    assert.deepEqual((await f.call('/api/servers')).body.servers.map(row => row.id), ['two']);
    await write('/api/v1/servers/two', 'PATCH', { enabled: false });
    assert.deepEqual((await f.call('/api/servers')).body, { servers: [] });
    await write('/api/v1/servers/one', 'DELETE');
    await write('/api/v1/servers/two', 'DELETE');
    assert.deepEqual((await f.call('/api/servers')).body, { servers: [] });
  } finally { await f.close(); }
});

test('catalogue D1 présent mais vide : aucun ancien serveur injecté par DEFAULT_SERVERS', async () => {
  const f = fixture();
  try {
    assert.deepEqual((await f.call('/api/servers')).body, { servers: [] });
    const denied = await f.call('/api/v1/servers', 'POST', { label: 'Refusé', url: legacy.url }, false);
    assert.ok([401, 403].includes(denied.response.status));
    assert.equal(f.db.prepare('SELECT COUNT(*) n FROM default_servers').get().n, 0);
    assert.equal(f.signals.length, 0);
    assert.equal((await f.call('/api/servers', 'POST')).response.status, 400);
  } finally { await f.close(); }
});

test('ancienne table absente : repli historique ; D1 absent : échec explicite', async () => {
  const f = fixture();
  try {
    f.db.exec('DROP TABLE default_servers');
    assert.deepEqual((await f.call('/api/servers')).body, { servers: [legacy] });
    delete f.env.DB;
    assert.equal((await f.call('/api/servers')).response.status, 503);
  } finally { await f.close(); }
});

test('D1 indisponible : échec explicite, jamais un succès contenant le serveur retiré', async () => {
  const f = fixture();
  try {
    f.faults.add({ match: /PRAGMA table_info\(default_servers\)/, times: 1 });
    const failed = await f.call('/api/servers');
    assert.equal(failed.response.status, 503);
    assert.deepEqual(failed.body, { error: 'servers_unavailable' });
    assert.equal(failed.response.headers.get('cache-control'), 'no-store');
    assert.deepEqual((await f.call('/api/servers')).body, { servers: [] });
    f.faults.add({ match: /SELECT id, label, url FROM default_servers/, times: 2 });
    assert.equal((await f.call('/api/servers')).response.status, 503);
    assert.deepEqual((await f.call('/api/servers')).body, { servers: [] });
  } finally { await f.close(); }
});
