// Le Worker de fixture est assemblé en mémoire. La production n'expose jamais
// cette route de déclenchement ; toutes les sorties réseau sont interceptées.
import assert from 'node:assert/strict';
import { generateKeyPairSync, randomBytes } from 'node:crypto';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { Miniflare, Log, LogLevel } from 'miniflare';
import { panelAlertSchemaStatements } from '../panel-alerts.js';

const here = dirname(fileURLToPath(import.meta.url));
const pair = generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).privateKey.export({ format: 'jwk' });
const browser = generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).publicKey.export({ format: 'jwk' });
const rawKey = (key) => Buffer.concat([Buffer.from([4]), Buffer.from(key.x, 'base64url'), Buffer.from(key.y, 'base64url')]).toString('base64url');
const fixture = await build({ stdin: { contents: `
  import {dispatchAlerts} from './index.js';
  export default {async fetch(request,env) {
    const now=Number(new URL(request.url).searchParams.get('now'))||Date.now();
    return Response.json(await dispatchAlerts(env,fetch,now));
  }};
`, resolveDir: here }, bundle: true, write: false, format: 'esm', platform: 'browser', target: 'es2022' });
const attempts = [];
let nextStatus = 201, external = 0, passed = 0;
const mf = new Miniflare({ host: '127.0.0.1', port: 0, cf: false, modules: true,
  script: fixture.outputFiles[0].text, compatibilityDate: '2025-05-01', compatibilityFlags: [],
  d1Databases: { DB: 'panel-dispatch-fixture' },
  bindings: { PANEL_PUSH_ENABLED: 'true', PANEL_PUSH_PUBLIC_KEY: rawKey(pair),
    PANEL_PUSH_PRIVATE_KEY: pair.d, PANEL_PUSH_SUBJECT: 'https://atlas-console-k7q2.vercel.app/' },
  outboundService: async (request) => {
    const url = new URL(request.url);
    if (url.hostname !== 'fcm.googleapis.com' || !url.pathname.endsWith('/fixture-never-sent')) {
      external++; return new Response(null, { status: 503 });
    }
    attempts.push({ status: nextStatus, encoding: request.headers.get('content-encoding'),
      bytes: (await request.arrayBuffer()).byteLength, auth: request.headers.get('authorization')?.startsWith('vapid ') });
    const status = nextStatus; nextStatus = 201;
    return new Response(null, { status });
  }, log: new Log(LogLevel.WARN),
});
async function step(name, fn) { await fn(); passed++; console.log('PASS ' + name); }
const run = async (now = Date.now()) => {
  const response = await mf.dispatchFetch('https://fixture.test/run?now=' + now);
  assert.equal(response.status, 200, await response.clone().text());
  return response.json();
};

try {
  await mf.ready;
  const db = await mf.getD1Database('DB');
  await step('schéma réel D1 et tables d’authentification de fixture', async () => {
    await db.batch([
      db.prepare('CREATE TABLE admin_users(id TEXT PRIMARY KEY,role TEXT,is_active INTEGER,password_changed_at INTEGER)'),
      db.prepare('CREATE TABLE auth_sessions(id TEXT PRIMARY KEY,actor TEXT,expires_at INTEGER,created_at INTEGER)'),
      db.prepare('CREATE TABLE devices(id TEXT PRIMARY KEY,mac TEXT)'),
      db.prepare('CREATE TABLE licenses(id TEXT PRIMARY KEY,device_id TEXT,app_id TEXT,status TEXT,expires_at INTEGER,updated_at INTEGER)'),
      db.prepare('CREATE TABLE box_orders(order_id TEXT PRIMARY KEY,mac TEXT,state TEXT,failed_srv INTEGER)'),
      ...panelAlertSchemaStatements().map((sql) => db.prepare(sql)),
    ]);
    const now = Date.now();
    await db.batch([
      db.prepare('INSERT INTO admin_users VALUES(?,?,?,?)').bind('owner', 'super_admin', 1, 0),
      db.prepare('INSERT INTO auth_sessions VALUES(?,?,?,?)').bind('session-1', 'admin:owner', now + 86400000, now - 100000),
      db.prepare('INSERT INTO panel_alert_preferences(actor_id,enabled,new_device,activation,problem,enabled_at,updated_at) VALUES(?,?,?,?,?,?,?)')
        .bind('owner', 1, 1, 1, 1, now - 10000, now),
      db.prepare('INSERT INTO panel_push_subscriptions(id,actor_id,session_id,endpoint_hash,endpoint,p256dh,auth,label,enabled,created_at,consented_at,updated_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)')
        .bind('sub-1', 'owner', 'session-1', 'fixture-hash', 'https://fcm.googleapis.com/fcm/send/fixture-never-sent',
          rawKey(browser), randomBytes(16).toString('base64url'), 'Fixture only', 1, now, now - 10000, now, now + 86400000),
    ]);
    const initial = await run();
    assert.equal(initial.processed, 0);
  });
  await step('premier appareil et licence commités produisent deux pushes chiffrés interceptés', async () => {
    const now = Date.now();
    await db.batch([
      db.prepare('INSERT INTO devices VALUES(?,?)').bind('device-1', 'MK:11:22:33:44:55'),
      db.prepare('INSERT INTO licenses VALUES(?,?,?,?,?,?)').bind('lic-1', 'device-1', 'app-fixture', 'active', now + 86400000, now),
    ]);
    const result = await run();
    assert.equal(result.sent, 2, JSON.stringify({ result,
      events: (await db.prepare('SELECT event_id,type,created_at FROM panel_alert_events').all()).results,
      deliveries: (await db.prepare('SELECT state,last_error,last_status FROM panel_push_deliveries').all()).results }));
    assert.equal(attempts.length, 2);
    for (const attempt of attempts) assert.deepEqual(attempt, { status: 201, encoding: 'aes128gcm', bytes: 4096, auth: true });
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM panel_push_deliveries WHERE sent_at IS NOT NULL').first()).n, 2);
  });
  await step('relecture du cron sans doublon ni notification de présence', async () => {
    const result = await run();
    assert.equal(result.processed, 0);
    assert.equal(attempts.length, 2);
  });
  await step('échec ACK persisté collecté une fois, anciens échecs ignorés', async () => {
    const now = Date.now();
    await db.batch([
      db.prepare('INSERT INTO box_orders VALUES(?,?,?,?)').bind('order-new', 'MK:11:22:33:44:55', 'failed', now),
      db.prepare('INSERT INTO box_orders VALUES(?,?,?,?)').bind('order-old', 'MK:11:22:33:44:55', 'failed', now - 86400000),
      db.prepare('INSERT INTO box_orders VALUES(?,?,?,?)').bind('order-ok', 'MK:11:22:33:44:55', 'applied', now),
    ]);
    assert.equal((await run()).sent, 1);
    assert.equal((await run()).processed, 0);
    assert.equal((await db.prepare("SELECT COUNT(*) n FROM panel_alert_events WHERE type='problem'").first()).n, 1);
  });
  await step('crons concurrents réservent une seule fois une prolongation réelle', async () => {
    const before = attempts.length, now = Date.now();
    await db.prepare('UPDATE licenses SET expires_at=?,updated_at=? WHERE id=?').bind(now + 172800000, now, 'lic-1').run();
    const results = await Promise.all([run(), run()]);
    assert.equal(results.reduce((sum, item) => sum + item.sent, 0), 1);
    assert.equal(attempts.length - before, 1);
  });
  await step('503 reprend avec le même événement, puis accepté au prochain essai éligible', async () => {
    const before = attempts.length;
    await db.prepare('INSERT INTO devices VALUES(?,?)').bind('device-2', 'MK:22:33:44:55:66').run();
    nextStatus = 503;
    const now = Date.now();
    assert.equal((await run(now)).retry, 1);
    assert.equal((await run(now + 30000)).processed, 0);
    assert.equal((await run(now + 61000)).sent, 1);
    assert.equal(attempts.length - before, 2);
  });
  await step('session supprimée interdit tout envoi suivant', async () => {
    const before = attempts.length;
    await db.prepare('DELETE FROM auth_sessions WHERE id=?').bind('session-1').run();
    await db.prepare('INSERT INTO devices VALUES(?,?)').bind('device-3', 'MK:33:44:55:66:77').run();
    assert.equal((await run()).processed, 0);
    assert.equal(attempts.length, before);
  });
  await step('aucune sortie réelle ni données fournisseur dans les événements', async () => {
    assert.equal(external, 0);
    const events = await db.prepare('SELECT title,message,url FROM panel_alert_events').all();
    const serialized = JSON.stringify(events.results);
    assert.ok(!serialized.includes('fixture-never-sent'));
    assert.ok(!serialized.includes(rawKey(browser)));
    assert.ok(!serialized.includes(pair.d));
  });
  console.log(JSON.stringify({ status: 'PASS', checks: passed, runtime: 'workerd', external_network_requests: external,
    encrypted_pushes_intercepted: attempts.length, compatibility_date: '2025-05-01', compatibility_flags: [] }));
} finally { await mf.dispose(); }
