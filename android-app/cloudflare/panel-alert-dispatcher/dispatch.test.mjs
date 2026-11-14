import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { generateKeyPairSync, randomBytes } from 'node:crypto';
import { dispatchAlerts } from './index.js';

const vapid = generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).privateKey.export({ format: 'jwk' });
const client = generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).publicKey.export({ format: 'jwk' });
const rawKey = (key) => Buffer.concat([Buffer.from([4]), Buffer.from(key.x, 'base64url'), Buffer.from(key.y, 'base64url')]).toString('base64url');
const NOW = Date.now();

function fixture(t) {
  const sqlite = new DatabaseSync(':memory:');
  t.after(() => sqlite.close());
  sqlite.exec(`
    CREATE TABLE admin_users(id TEXT PRIMARY KEY, role TEXT, is_active INTEGER, password_changed_at INTEGER);
    CREATE TABLE auth_sessions(id TEXT PRIMARY KEY, actor TEXT, expires_at INTEGER, created_at INTEGER);
    CREATE TABLE panel_alert_events(seq INTEGER PRIMARY KEY AUTOINCREMENT,event_id TEXT UNIQUE,type TEXT,created_at INTEGER,title TEXT,message TEXT,url TEXT);
    CREATE TABLE panel_alert_preferences(actor_id TEXT PRIMARY KEY,enabled INTEGER,new_device INTEGER,activation INTEGER,problem INTEGER,enabled_at INTEGER);
    CREATE TABLE panel_push_subscriptions(id TEXT PRIMARY KEY,actor_id TEXT,session_id TEXT,endpoint TEXT,p256dh TEXT,auth TEXT,enabled INTEGER,consented_at INTEGER,expires_at INTEGER,revoked_at INTEGER,revoked_reason TEXT,updated_at INTEGER,last_success_at INTEGER);
    CREATE TABLE panel_push_deliveries(event_id TEXT,subscription_id TEXT,state TEXT,attempts INTEGER,next_attempt_at INTEGER,lease_token TEXT,lease_until INTEGER,last_status INTEGER,last_error TEXT,sent_at INTEGER,created_at INTEGER,updated_at INTEGER,PRIMARY KEY(event_id,subscription_id));
  `);
  sqlite.prepare('INSERT INTO admin_users VALUES (?,?,?,?)').run('owner', 'super_admin', 1, 0);
  sqlite.prepare('INSERT INTO auth_sessions VALUES (?,?,?,?)').run('session-1', 'admin:owner', NOW + 86400000, NOW - 100000);
  sqlite.prepare('INSERT INTO panel_alert_preferences VALUES (?,?,?,?,?,?)').run('owner', 1, 1, 1, 1, NOW - 20000);
  sqlite.prepare('INSERT INTO panel_push_subscriptions (id,actor_id,session_id,endpoint,p256dh,auth,enabled,consented_at) VALUES (?,?,?,?,?,?,?,?)')
    .run('subscription-1', 'owner', 'session-1', 'https://fcm.googleapis.com/fcm/send/fixture-only-never-sent',
      rawKey(client), randomBytes(16).toString('base64url'), 1, NOW - 10000);
  sqlite.prepare('INSERT INTO panel_alert_events (event_id,type,created_at,title,message,url) VALUES (?,?,?,?,?,?)')
    .run('evt_fixture_0001', 'activation', NOW - 5000, 'Licence activée',
      'Une licence vient d’être activée.', '/devices?mac=MK:11:22:33:44:55');
  const DB = { prepare(sql) {
    const wrapped = (values = []) => ({
      bind(...next) { return wrapped(next); },
      run() { const value = sqlite.prepare(sql).run(...values); return Promise.resolve({ success: true, meta: { changes: Number(value.changes) } }); },
      async first() { return sqlite.prepare(sql).get(...values) || null; },
      async all() { return { results: sqlite.prepare(sql).all(...values) }; },
    });
    return wrapped();
  }, batch(statements) {
    sqlite.exec('BEGIN');
    try { const results = statements.map((statement) => statement.run()); sqlite.exec('COMMIT'); return Promise.all(results); }
    catch (error) { sqlite.exec('ROLLBACK'); throw error; }
  } };
  return { sqlite, env: { DB, PANEL_PUSH_ENABLED: 'true', PANEL_PUSH_PUBLIC_KEY: rawKey(vapid),
    PANEL_PUSH_PRIVATE_KEY: vapid.d, PANEL_PUSH_SUBJECT: 'https://atlas-console-k7q2.vercel.app/' } };
}

test('une seule livraison durable malgré deux crons simultanés et une reprise', async (t) => {
  const { env, sqlite } = fixture(t);
  let requests = 0;
  const sender = async () => { requests++; return new Response(null, { status: 201 }); };
  const outcomes = await Promise.all([dispatchAlerts(env, sender, NOW), dispatchAlerts(env, sender, NOW)]);
  assert.equal(outcomes.reduce((sum, item) => sum + item.sent, 0), 1);
  assert.equal(requests, 1);
  const row = sqlite.prepare('SELECT * FROM panel_push_deliveries').get();
  assert.equal(row.state, 'sent');
  assert.equal(row.attempts, 1);
  assert.equal(row.lease_token, null);
  assert.ok(row.sent_at >= NOW && row.sent_at <= Date.now());
  await dispatchAlerts(env, sender, NOW + 60000);
  assert.equal(requests, 1);
});

test('permission du compte, session, mot de passe et consentement contrôlés avant envoi', async (t) => {
  for (const sql of [
    "UPDATE admin_users SET role='support'",
    'UPDATE admin_users SET is_active=0',
    'DELETE FROM auth_sessions',
    'UPDATE auth_sessions SET expires_at=1',
    "UPDATE auth_sessions SET actor='admin:someone-else'",
    'UPDATE admin_users SET password_changed_at=' + NOW,
    'UPDATE admin_users SET password_changed_at=' + Math.floor(NOW / 1000),
    'UPDATE panel_alert_preferences SET enabled=0',
    'UPDATE panel_alert_preferences SET activation=0',
    'UPDATE panel_push_subscriptions SET enabled=0',
    'UPDATE panel_push_subscriptions SET revoked_at=1',
    'UPDATE panel_push_subscriptions SET expires_at=1',
    'UPDATE panel_push_subscriptions SET consented_at=' + NOW,
    'UPDATE panel_alert_preferences SET enabled_at=' + NOW,
    'UPDATE panel_alert_events SET created_at=1',
    'UPDATE panel_alert_events SET created_at=' + (NOW + 100000),
  ]) {
    const { env, sqlite } = fixture(t);
    sqlite.exec(sql);
    const result = await dispatchAlerts(env, async () => { throw new Error('must not send'); }, NOW);
    assert.equal(result.processed, 0, sql);
    assert.equal(sqlite.prepare('SELECT COUNT(*) n FROM panel_push_deliveries').get().n, 0, sql);
  }
});

test('une session révoquée après mise en file annule la livraison', async (t) => {
  const { env, sqlite } = fixture(t);
  sqlite.prepare('INSERT INTO panel_push_deliveries(event_id,subscription_id,state,attempts,next_attempt_at,created_at,updated_at) VALUES (?,?,?,?,?,?,?)')
    .run('evt_fixture_0001', 'subscription-1', 'pending', 0, NOW, NOW, NOW);
  sqlite.exec('DELETE FROM auth_sessions');
  let requests = 0;
  const result = await dispatchAlerts(env, async () => { requests++; return new Response(); }, NOW);
  assert.equal(result.cancelled, 1);
  assert.equal(requests, 0);
  assert.equal(sqlite.prepare('SELECT state FROM panel_push_deliveries').get().state, 'cancelled');
});

test('une session expirée entre deux lots interdit le cinquième envoi', async (t) => {
  const { env, sqlite } = fixture(t);
  let current = NOW;
  let requests = 0;
  sqlite.prepare('UPDATE auth_sessions SET expires_at = ?').run(NOW + 1000);
  for (let index = 2; index <= 5; index++) {
    sqlite.prepare(`INSERT INTO panel_alert_events(event_id,type,created_at,title,message,url)
      SELECT ?,type,created_at,title,message,url FROM panel_alert_events WHERE event_id = ?`)
      .run('evt_fixture_' + String(index).padStart(4, '0'), 'evt_fixture_0001');
  }
  const result = await dispatchAlerts(env, async () => {
    requests++;
    if (requests === 4) current = NOW + 2000;
    return new Response(null, { status: 201 });
  }, NOW, () => current);
  assert.equal(requests, 4);
  assert.equal(result.sent, 4);
  assert.equal(result.cancelled, 1);
  const last = sqlite.prepare('SELECT state,updated_at FROM panel_push_deliveries WHERE event_id = ?')
    .get('evt_fixture_0005');
  assert.equal(last.state, 'cancelled');
  assert.equal(last.updated_at, NOW + 2000);
});

test('expiration pendant la lecture D1 revérifiée avant chiffrement', async (t) => {
  const { env, sqlite } = fixture(t);
  let current = NOW;
  let requests = 0;
  sqlite.prepare('UPDATE auth_sessions SET expires_at = ?').run(NOW + 1000);
  const prepare = env.DB.prepare;
  env.DB.prepare = (sql) => {
    const statement = prepare(sql);
    if (!sql.includes('AS session_expires_at')) return statement;
    return { bind(...values) {
      const bound = statement.bind(...values);
      return { async first() {
        const row = await bound.first();
        current = NOW + 2000;
        return row;
      } };
    } };
  };
  const result = await dispatchAlerts(env, async () => {
    requests++; return new Response(null, { status: 201 });
  }, NOW, () => current);
  assert.equal(result.cancelled, 1);
  assert.equal(requests, 0);
  assert.equal(sqlite.prepare('SELECT last_error FROM panel_push_deliveries').get().last_error,
    'consent_or_session_inactive');
});

test('expiration pendant le chiffrement bloque le transport sans révoquer l’abonnement', async (t) => {
  const { env, sqlite } = fixture(t);
  let current = NOW;
  let requests = 0;
  sqlite.prepare('UPDATE auth_sessions SET expires_at = ?').run(NOW + 1000);
  const digest = crypto.subtle.digest.bind(crypto.subtle);
  t.mock.method(crypto.subtle, 'digest', async (...args) => {
    const value = await digest(...args);
    current = NOW + 2000;
    return value;
  });
  const result = await dispatchAlerts(env, async () => {
    requests++; return new Response(null, { status: 201 });
  }, NOW, () => current);
  assert.equal(result.cancelled, 1);
  assert.equal(result.retry, 0);
  assert.equal(requests, 0);
  assert.equal(sqlite.prepare('SELECT enabled FROM panel_push_subscriptions').get().enabled, 1);
});

test('reprise et horodatage calculés après la réponse, sans raccourcir Retry-After', async (t) => {
  const { env, sqlite } = fixture(t);
  let current = NOW;
  let requests = 0;
  const sender = async () => {
    requests++;
    if (requests === 1) {
      current = NOW + 8000;
      return new Response(null, { status: 503, headers: { 'Retry-After': '120' } });
    }
    current = NOW + 130000;
    return new Response(null, { status: 201 });
  };
  assert.equal((await dispatchAlerts(env, sender, NOW, () => current)).retry, 1);
  let row = sqlite.prepare('SELECT * FROM panel_push_deliveries').get();
  assert.equal(row.updated_at, NOW + 8000);
  assert.equal(row.next_attempt_at, NOW + 128000);
  assert.equal(row.sent_at, null);
  current = NOW + 127999;
  assert.equal((await dispatchAlerts(env, sender, current, () => current)).processed, 0);
  current = NOW + 128000;
  assert.equal((await dispatchAlerts(env, sender, current, () => current)).sent, 1);
  row = sqlite.prepare('SELECT * FROM panel_push_deliveries').get();
  assert.equal(row.sent_at, NOW + 130000);
  assert.equal(row.updated_at, NOW + 130000);
  assert.equal(sqlite.prepare('SELECT last_success_at FROM panel_push_subscriptions').get().last_success_at,
    NOW + 130000);
  assert.equal(requests, 2);
});

test('reprise temporaire espacée, résultat accepté distinct de lecture', async (t) => {
  const { env, sqlite } = fixture(t);
  let requests = 0;
  const sender = async () => { requests++; return new Response(null, { status: requests === 1 ? 503 : 201 }); };
  assert.equal((await dispatchAlerts(env, sender, NOW)).retry, 1);
  assert.equal(sqlite.prepare('SELECT sent_at FROM panel_push_deliveries').get().sent_at, null);
  assert.equal((await dispatchAlerts(env, sender, NOW + 30000)).processed, 0);
  assert.equal((await dispatchAlerts(env, sender, NOW + 61000)).sent, 1);
  assert.equal(requests, 2);
  assert.equal(sqlite.prepare('SELECT attempts FROM panel_push_deliveries').get().attempts, 2);
});

test('abonnement 410 révoqué et aucun nouvel envoi', async (t) => {
  const { env, sqlite } = fixture(t);
  const result = await dispatchAlerts(env, async () => new Response(null, { status: 410 }), NOW);
  assert.equal(result.failed, 1);
  assert.equal(sqlite.prepare('SELECT enabled FROM panel_push_subscriptions').get().enabled, 0);
  assert.equal(sqlite.prepare('SELECT revoked_reason FROM panel_push_subscriptions').get().revoked_reason, 'push_service_expired');
  assert.equal((await dispatchAlerts(env, async () => { throw new Error('must not send'); }, NOW + 60000)).processed, 0);
});

test('réservation expirée récupérée et dernier essai interrompu clos', async (t) => {
  const { env, sqlite } = fixture(t);
  sqlite.prepare('INSERT INTO panel_push_deliveries(event_id,subscription_id,state,attempts,next_attempt_at,lease_token,lease_until,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)')
    .run('evt_fixture_0001', 'subscription-1', 'leased', 1, NOW, 'interrupted', NOW - 1, NOW - 130000, NOW - 130000);
  assert.equal((await dispatchAlerts(env, async () => new Response(null, { status: 201 }), NOW)).sent, 1);
  assert.equal(sqlite.prepare('SELECT attempts FROM panel_push_deliveries').get().attempts, 2);
  sqlite.exec("UPDATE panel_push_deliveries SET state='leased',attempts=6,lease_until=1,lease_token='interrupted-again'");
  assert.equal((await dispatchAlerts(env, async () => { throw new Error('must not send'); }, NOW)).processed, 0);
  assert.equal(sqlite.prepare('SELECT state FROM panel_push_deliveries').get().state, 'failed');
});

test('arrêt explicite sans lecture ni envoi', async () => {
  const result = await dispatchAlerts({ PANEL_PUSH_ENABLED: 'false' },
    async () => { throw new Error('must not send'); }, NOW);
  assert.deepEqual(result, { enabled: false, queued: 0, processed: 0 });
});

test('mauvaise paire VAPID refusée avant toute mise en file ou révocation client', async (t) => {
  const { env, sqlite } = fixture(t);
  const wrong = generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).privateKey.export({ format: 'jwk' });
  env.PANEL_PUSH_PRIVATE_KEY = wrong.d;
  await assert.rejects(dispatchAlerts(env, async () => { throw new Error('must not send'); }, NOW), /configuration_invalid/);
  assert.equal(sqlite.prepare('SELECT COUNT(*) n FROM panel_push_deliveries').get().n, 0);
  assert.equal(sqlite.prepare('SELECT enabled FROM panel_push_subscriptions').get().enabled, 1);
});
