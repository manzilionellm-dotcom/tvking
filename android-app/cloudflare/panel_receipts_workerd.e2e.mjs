// Banc local : vrais HTTP, WebSocket, Durable Objects et SQLite/D1 de workerd.
// Aucun serveur distant ni compte client réel. Les mesures portent uniquement
// sur ACK HTTP → notification panel ; elles ne promettent pas une latence WAN.
// Exécution : npm run build && node --test panel_receipts_workerd.e2e.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHmac, randomUUID } from 'node:crypto';
import { Miniflare } from 'miniflare';
import { createSession } from './account_security.js';
import { createOrder, markOrderSent } from './box_orders.js';

const MAC = 'MK:AA:BB:CC:DD:71';
const OTHER_MAC = 'MK:AA:BB:CC:DD:72';

function watchSocket(ws) {
  const frames = [];
  const listeners = new Set();
  let close;
  ws.addEventListener('message', event => {
    const value = JSON.parse(event.data);
    frames.push(value);
    for (const listener of [...listeners]) listener(value);
  });
  ws.addEventListener('close', event => { close = event; });
  ws.accept();
  function next(predicate, timeoutMs = 2000) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        listeners.delete(listener);
        reject(new Error('notification panel absente'));
      }, timeoutMs);
      const listener = value => {
        if (!predicate(value)) return;
        clearTimeout(timer);
        listeners.delete(listener);
        resolve(value);
      };
      listeners.add(listener);
    });
  }
  return {
    ws, frames, next,
    get closed() { return close; },
    async barrier() {
      const hello = next(value => value.type === 'hello');
      ws.send(JSON.stringify({ v: 1, type: 'hello' }));
      await hello;
    },
    business() { return frames.filter(value => value.type !== 'hello'); },
  };
}

async function fixture() {
  const secret = randomUUID() + randomUUID();
  const mf = new Miniflare({
    modules: true,
    scriptPath: new URL('./dist/gold.js', import.meta.url).pathname,
    compatibilityDate: '2025-05-01',
    durableObjects: { RT_HUB: { className: 'RealtimeHub', useSQLite: true } },
    d1Databases: { DB: 'panel-receipts-local' },
    bindings: { ADMIN_SECRET: secret, DEFAULT_SERVERS: '[]' },
  });
  const DB = await mf.getD1Database('DB');
  const env = { DB };
  const sql = readFileSync(new URL('./schema.sql', import.meta.url), 'utf8')
    .replace(/^\s*--.*$/gm, '');
  for (const statement of sql.split(';').map(s => s.trim()).filter(Boolean)) {
    await DB.prepare(statement).run();
  }
  for (const column of ['parent_reseller_id TEXT', 'level TEXT', 'permissions TEXT']) {
    await DB.prepare('ALTER TABLE resellers ADD COLUMN ' + column).run();
  }
  const now = Date.now();
  await DB.prepare("INSERT INTO admin_users (id,email,password_hash,role,is_active,created_at) VALUES ('admin-test','admin@example.test','unused','admin',1,?)").bind(now).run();
  for (const id of ['owner-test', 'other-test']) {
    await DB.prepare("INSERT INTO resellers (id,email,password_hash,status,created_at) VALUES (?,?,'unused','active',?)")
      .bind(id, id + '@example.test', now).run();
  }
  await DB.prepare("INSERT INTO customers (id,name,created_at,updated_at) VALUES ('customer-test','Test local',?,?)").bind(now, now).run();
  await DB.prepare("INSERT INTO devices (id,customer_id,mac,reseller_id,first_seen_at,last_seen_at) VALUES ('device-test','customer-test',?,'owner-test',?,?)")
    .bind(MAC, now, now).run();
  const sockets = [];
  async function api(path, { method = 'GET', body, token, headers = {} } = {}) {
    return mf.dispatchFetch('https://worker.test' + path, {
      method,
      headers: { ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
        ...(token ? { Authorization: 'Bearer ' + token } : {}), ...headers },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
  }
  async function session(id, role) {
    const actor = { sub: id, role };
    const created = await createSession(env, actor);
    const iat = Math.floor(Date.now() / 1000);
    const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
    const payload = Buffer.from(JSON.stringify({ ...actor, sid: created.sid, iat, iat_ms: Date.now(), exp: iat + 900 })).toString('base64url');
    const input = header + '.' + payload;
    const token = input + '.' + createHmac('sha256', secret).update(input).digest('base64url');
    return { ...created, token };
  }
  async function open(login) {
    const ticketResponse = await api('/api/v1/rt/ticket', { method: 'POST', token: login.token });
    assert.equal(ticketResponse.status, 200);
    const { ticket } = await ticketResponse.json();
    const response = await api('/api/v1/rt/ws?ticket=' + ticket, { headers: { Upgrade: 'websocket' } });
    assert.equal(response.status, 101);
    const socket = watchSocket(response.webSocket);
    sockets.push(socket);
    assert.equal((await api('/api/v1/rt/ws?ticket=' + ticket, { headers: { Upgrade: 'websocket' } })).status, 401);
    await socket.barrier();
    return socket;
  }
  async function order(kind = 'source', configRev = 7) {
    const id = await createOrder(env, { mac: MAC, kind, configRev, traceId: 'local-trace-' + randomUUID(), t1: Date.now(), t2: Date.now() });
    assert.ok(id);
    await markOrderSent(env, id, 1);
    return id;
  }
  async function ack(id, state, { mac = MAC, ...extra } = {}) {
    const response = await api('/api/box/ack/' + mac, {
      method: 'POST', body: { orders: [{ order_id: id, state, ...extra }] },
    });
    assert.equal(response.status, 200);
    return (await response.json()).results[0];
  }
  return { mf, DB, api, session, open, order, ack, async dispose() {
    for (const socket of sockets) { try { socket.ws.close(); } catch {} }
    await mf.dispose();
  } };
}

test('workerd : reçus et présence après commit, filtrés par session et revendeur', { timeout: 60000 }, async t => {
  const f = await fixture();
  try {
    assert.equal((await f.api('/api/v1/rt/ticket', { method: 'POST' })).status, 401);
    assert.equal((await f.api('/api/v1/rt/ws?mac=' + MAC, { headers: { Upgrade: 'websocket' } })).status, 401);
    const adminSession = await f.session('admin-test', 'admin');
    const ownerSession = await f.session('owner-test', 'reseller');
    const otherSession = await f.session('other-test', 'reseller');
    const admin = await f.open(adminSession);
    const owner = await f.open(ownerSession);
    const other = await f.open(otherSession);

    await t.test('received/applied/failed : ordre exact, heure serveur et SQL déjà visible', async () => {
      const id = await f.order();
      for (const state of ['received', 'applied']) {
        const start = Date.now();
        const events = Promise.all([admin.next(e => e.type === 'receipt'), owner.next(e => e.type === 'receipt')]);
        const posted = f.ack(id, state, { received_at: 1, applied_at: 2, config_rev: 7, result: 'loaded', app_version: 'local-test' });
        const [a, b] = await events;
        assert.deepEqual(a, b);
        assert.equal(a.v, 1);
        assert.equal(a.mac, MAC);
        assert.equal(a.order_id, id);
        assert.equal(a.kind, 'source');
        assert.equal(a.state, state);
        assert.ok(a.at >= start && a.at <= Date.now(), 'horloge serveur, jamais horloge déclarée par la box');
        assert.equal(a.config_rev, 7);
        assert.ok(Object.keys(a).every(key => ['v','type','mac','at','order_id','kind','state','trace_id','config_rev','applied_rev','elapsed_ms'].includes(key)));
        const row = await f.DB.prepare('SELECT * FROM box_orders WHERE order_id=?').bind(id).first();
        assert.equal(row.state, state, 'commit observable dès réception WS');
        assert.equal(a.at, state === 'applied' ? row.applied_srv : row.received_srv);
        assert.equal((await posted).changed, true);
      }
      const failedId = await f.order('reset');
      const event = admin.next(e => e.type === 'receipt' && e.order_id === failedId);
      const posted = f.ack(failedId, 'failed', { error_code: 'source_failed', error_message: 'https://fixture.test/?password=do-not-publish', config_rev: 7 });
      const value = await event;
      assert.equal(value.state, 'failed');
      assert.equal(value.kind, 'reset');
      assert.equal(value.error_message, undefined);
      assert.equal((await posted).changed, true);
      await Promise.all([admin.barrier(), owner.barrier(), other.barrier()]);
      assert.deepEqual(other.business(), [], 'aucune MAC étrangère chez un autre revendeur');
      assert.equal(owner.business().filter(e => e.order_id === failedId).length, 1);
    });

    await t.test('dupliqué, mauvais appareil, ordre inconnu et écriture refusée : aucun faux reçu', async () => {
      const id = await f.order('activate', null);
      const received = admin.next(e => e.type === 'receipt' && e.order_id === id);
      await f.ack(id, 'received');
      await received;
      await Promise.all([admin.barrier(), owner.barrier()]);
      const before = admin.business().length;
      assert.equal((await f.ack(id, 'received')).changed, false);
      assert.equal((await f.ack(id, 'applied', { mac: OTHER_MAC })).status, 404);
      assert.equal((await f.ack('ord_' + randomUUID(), 'applied')).status, 404);
      assert.equal((await f.ack(id, 'invented')).status, 400);
      await f.DB.prepare("CREATE TRIGGER refuse_ack BEFORE UPDATE OF state ON box_orders BEGIN SELECT RAISE(ABORT, 'test rejected ACK'); END").run();
      assert.equal((await f.ack(id, 'applied')).status, 500);
      await f.DB.prepare('DROP TRIGGER refuse_ack').run();
      await Promise.all([admin.barrier(), owner.barrier(), other.barrier()]);
      assert.equal(admin.business().length, before);
      assert.equal((await f.DB.prepare('SELECT state FROM box_orders WHERE order_id=?').bind(id).first()).state, 'received');

      // Deux requêtes réelles en vol : seule la gagnante du CAS annonce la
      // transition. Un accusé rejoué ne crée pas de notification supplémentaire.
      const concurrentId = await f.order('activate', null);
      const committed = admin.next(e => e.type === 'receipt' && e.order_id === concurrentId);
      const replies = await Promise.all([f.ack(concurrentId, 'received'), f.ack(concurrentId, 'received')]);
      await committed;
      await admin.barrier();
      assert.equal(replies.filter(result => result.changed === true).length, 1);
      assert.equal(admin.business().filter(event => event.order_id === concurrentId).length, 1);
    });

    await t.test('présence : inventaire visible, aucune donnée privée dans la trame', async () => {
      const pending = Promise.all([admin.next(e => e.type === 'presence'), owner.next(e => e.type === 'presence')]);
      const posted = f.api('/api/heartbeat', { method: 'POST', body: {
        mac: MAC, model: 'Local phone', appBuild: 991, appVersion: 'local-test', platform: 'mobile',
        channel: 'Private fixture channel', androidId: 'test-installation-id',
      }, headers: { 'CF-Connecting-IP': '192.0.2.1', 'CF-IPCountry': 'FR' } });
      const [a, b] = await pending;
      assert.deepEqual(a, b);
      assert.deepEqual(Object.keys(a).sort(), ['at','last_seen_at','mac','online','type','v']);
      assert.equal(a.mac, MAC);
      assert.equal(a.online, true);
      const presence = await f.DB.prepare('SELECT last_seen FROM presence WHERE mac=?').bind(MAC).first();
      const device = await f.DB.prepare('SELECT last_seen_at,app_build FROM devices WHERE mac=?').bind(MAC).first();
      assert.equal(a.last_seen_at, presence.last_seen);
      assert.equal(a.last_seen_at, device.last_seen_at);
      assert.equal(device.app_build, 991, 'inventaire persisté avant notification');
      assert.equal((await posted).status, 200);
      await Promise.all([admin.barrier(), owner.barrier(), other.barrier()]);
      assert.deepEqual(other.business(), []);
      const before = admin.business().length;
      await f.DB.prepare("CREATE TRIGGER refuse_presence BEFORE INSERT ON presence BEGIN SELECT RAISE(ABORT, 'test rejected presence'); END").run();
      const failed = await f.api('/api/heartbeat', { method: 'POST', body: { mac: MAC } });
      assert.equal(failed.status, 200, 'le heartbeat reste disponible en cas de panne présence');
      await f.DB.prepare('DROP TRIGGER refuse_presence').run();
      await Promise.all([admin.barrier(), owner.barrier()]);
      assert.equal(admin.business().length, before, 'aucune présence annoncée avant écriture réussie');
    });

    await t.test('session révoquée ou expirée : aucun reçu et fermeture du socket', async () => {
      const revokedLogin = await f.session('owner-test', 'reseller');
      const expiredLogin = await f.session('owner-test', 'reseller');
      const revoked = await f.open(revokedLogin);
      const expired = await f.open(expiredLogin);
      await f.DB.prepare('DELETE FROM auth_sessions WHERE id=?').bind(revokedLogin.sid).run();
      await f.DB.prepare('UPDATE auth_sessions SET expires_at=1 WHERE id=?').bind(expiredLogin.sid).run();
      assert.equal((await f.api('/api/v1/rt/ticket', { method: 'POST', token: revokedLogin.token })).status, 401);
      const id = await f.order('activate', null);
      const event = admin.next(e => e.type === 'receipt' && e.order_id === id);
      await f.ack(id, 'received');
      await event;
      await admin.barrier();
      assert.deepEqual(revoked.business(), []);
      assert.deepEqual(expired.business(), []);
      assert.equal(revoked.closed?.code, 4001);
      assert.equal(expired.closed?.code, 4001);
    });

    await t.test('20 reçus réels : notification sans attendre un cycle de sondage', async () => {
      const elapsed = [];
      for (let i = 0; i < 20; i++) {
        const id = await f.order('activate', null);
        const pending = admin.next(e => e.type === 'receipt' && e.order_id === id);
        const start = performance.now();
        const posted = f.ack(id, 'applied');
        await pending;
        elapsed.push(performance.now() - start);
        assert.equal((await posted).changed, true);
      }
      elapsed.sort((a, b) => a - b);
      const percentile = p => elapsed[Math.ceil(elapsed.length * p) - 1];
      t.diagnostic('ACK HTTP → WS panel, workerd/D1 local, ms : ' + JSON.stringify({
        samples: elapsed.length, p50: +percentile(.5).toFixed(1), p95: +percentile(.95).toFixed(1), max: +elapsed.at(-1).toFixed(1),
      }));
      assert.ok(elapsed.at(-1) < 1000, 'budget local sub-seconde ; aucune garantie réseau distant');
    });
  } finally {
    await f.dispose();
  }
});
