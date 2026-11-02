// Recette hors réseau du bundle réellement exporté, sans les migrations Gold.
// Elle vérifie le contrat HTTP encore utilisé par les nouveaux APK.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash, createHmac } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { Miniflare, createFetchMock } from 'miniflare';
import { build } from 'esbuild';

test('export du 26 octobre : nouveaux headers, activation, sources, canal et accusé restent compatibles', { timeout: 30_000 }, async () => {
  const original = new URL('../production/worker.js', import.meta.url);
  assert.equal(createHash('sha256').update(await readFile(original)).digest('hex'),
    'ad08c5e6516c5741b686661e8ed35d16c1f9d1b20aadc164e14dc9a49628f71c');
  const bundled = await build({ entryPoints: [fileURLToPath(new URL('../production/gold.original.js', import.meta.url))],
    bundle: true, write: false, format: 'esm', platform: 'browser', target: 'es2022' });
  const fetchMock = createFetchMock();
  fetchMock.disableNetConnect();
  const adminSecret = 'legacy-fixture-admin-secret-local-only-64-characters';
  const mf = new Miniflare({ modules: true, script: bundled.outputFiles[0].text,
    compatibilityDate: '2025-05-01', durableObjects: { RT_HUB: 'RealtimeHub' },
    d1Databases: ['DB'], fetchMock, bindings: { ADMIN_SECRET: adminSecret } });
  let socket;
  try {
    await mf.ready;
    const db = await mf.getD1Database('DB');
    const schema = (await readFile(new URL('../production/schema.sql', import.meta.url), 'utf8')).replace(/--[^\n]*/g, '');
    for (const sql of schema.split(';').map(x => x.trim()).filter(Boolean)) await db.prepare(sql).run();
    const mac = 'MK:11:22:33:44:55';
    await db.batch([
      db.prepare("INSERT INTO customers(id,created_at,updated_at) VALUES ('customer',1,1)"),
      db.prepare("INSERT INTO apps(id,name,package_name,created_at,updated_at) VALUES ('app_7motion','Fixture','fixture.test',1,1)"),
      db.prepare("INSERT INTO admin_users(id,email,password_hash,role,is_active,created_at) VALUES ('admin','fixture@example.invalid','unused','super_admin',1,1)"),
      db.prepare("INSERT INTO devices(id,customer_id,mac,first_seen_at,last_seen_at,android_id) VALUES ('device','customer',?,1,1,'fixture-android')").bind(mac),
      db.prepare("INSERT INTO trial_anchors(mac,android_id,started_at) VALUES (?,'fixture-android',1)").bind(mac),
    ]);
    const enc = x => Buffer.from(JSON.stringify(x)).toString('base64url');
    const h = enc({ alg: 'HS256', typ: 'JWT' });
    const p = enc({ sub: 'admin', role: 'super_admin', iat: Math.floor(Date.now()/1000), exp: Math.floor(Date.now()/1000)+3600 });
    const token = `${h}.${p}.${createHmac('sha256', adminSecret).update(`${h}.${p}`).digest('base64url')}`;
    const secret = 'fixture-device-secret-new-client-not-enrolled';
    const call = (path, method='GET', body, auth=false) => mf.dispatchFetch(`https://legacy.example${path}`, {
      method, headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '192.0.2.10',
        'X-Device-Secret': secret, ...(auth ? { Authorization: `Bearer ${token}` } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    const proof = await call('/api/device-proof', 'POST', { mac, androidId: 'fixture-android', secret });
    assert.equal(proof.status, 404, 'la nouvelle route est absente ; enroll() doit rester best-effort');
    const ticket = await call('/api/v1/rt/ticket', 'POST', {}, true);
    assert.equal(ticket.status, 404, 'le panel doit conserver son sondage 2 s avec cet export');
    const upgraded = await mf.dispatchFetch(`https://legacy.example/api/box/ws?mac=${mac}`, {
      headers: { Upgrade: 'websocket', 'X-Device-Secret': secret, 'CF-Connecting-IP': '192.0.2.10' },
    });
    assert.equal(upgraded.status, 101);
    socket = upgraded.webSocket;
    assert.ok(socket);
    const events = [];
    socket.accept();
    socket.addEventListener('message', event => events.push(JSON.parse(event.data)));
    socket.send('{"v":1,"type":"hello"}');
    const until = async condition => {
      const end = Date.now() + 3000;
      while (!condition() && Date.now() < end) await new Promise(resolve => setTimeout(resolve, 10));
      assert.ok(condition(), 'signal attendu sur le Durable Object exporté');
    };
    await until(() => events.some(x => x.type === 'hello'));
    const activation = await call('/api/v1/activate', 'POST', { mac, plan: 'yearly' }, true);
    assert.equal(activation.status, 201, 'création initiale de licence');
    const activated = await activation.json();
    assert.equal(activated.ok, true);
    await until(() => events.some(x => x.type === 'activate'));
    const status = await call(`/api/status/${mac}`);
    assert.equal(status.status, 200);
    const statusBody = await status.json();
    assert.ok(statusBody.active || statusBody.status === 'active', JSON.stringify(statusBody));
    const added = await call(`/api/v1/sources/${mac}`, 'PUT', {
      type: 'm3u', label: 'Liste de recette', m3u_url: 'https://provider.example.invalid/client.m3u',
    }, true);
    assert.equal(added.status, 200);
    await until(() => events.some(x => x.type === 'source'));
    const source = await call(`/api/device-source/${mac}`);
    assert.equal(source.status, 200);
    const body = await source.json();
    assert.ok(body.sources.some(x => x.m3u_url === 'https://provider.example.invalid/client.m3u'));
    const order = events.find(x => x.type === 'source');
    const ack = await call(`/api/box/ack/${mac}`, 'POST', { orders: [{
      order_id: order.order_id, state: 'applied', result: 'refreshed', applied_at: Date.now(), config_rev: body.rev,
    }] });
    assert.equal(ack.status, 200);
    assert.equal((await ack.json()).results[0].state, 'applied');
    const removed = await call(`/api/v1/sources/${mac}`, 'DELETE', undefined, true);
    assert.equal(removed.status, 200);
    await until(() => events.some(x => x.type === 'source_clear'));
    const empty = await call(`/api/device-source/${mac}`);
    assert.equal(empty.status, 200);
    assert.equal((await empty.json()).sources.length, 0);
    const polling = await call(`/api/box/wait/${mac}?after=0&timeout=200`);
    assert.equal(polling.status, 200, 'le repli historique reste disponible avec le nouveau header');
  } finally {
    socket?.close();
    await mf.dispose();
  }
});
