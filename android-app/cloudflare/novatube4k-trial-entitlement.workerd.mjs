// Recette de l'essai commercial dans workerd/D1 locaux, y compris redémarrage
// du runtime. Aucun réseau fournisseur/Stripe ; aucune base de production.
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { randomBytes, createHash } from 'node:crypto';
import { Miniflare, Log, LogLevel } from 'miniflare';

const here = dirname(fileURLToPath(import.meta.url));
const candidate = resolve(process.argv[2] || join(here, 'novatube4k-entry.js'));
const persist = mkdtempSync(join(tmpdir(), 'novatube-trial-workerd-'));
const RAW = 'AABBCCDDEEA1', RAW2 = 'AABBCCDDEEA2';
const KEY = randomBytes(32).toString('hex'), NEXT = randomBytes(32).toString('hex');
const adminSecret = randomBytes(32).toString('hex'), APP = 'app_novatube4k';
const DURATION = 10 * 86400000, outbound = [];
let passed = 0, current = 'startup', mf;
const options = {
  host: '127.0.0.1', port: 0, modules: true,
  modulesRules: [{ type: 'ESModule', include: ['**/*.js'] }],
  scriptPath: candidate, modulesRoot: dirname(candidate), cf: false,
  compatibilityDate: '2025-05-01', compatibilityFlags: [],
  d1Databases: { DB: 'novatube-trial-workerd-fixture' }, d1Persist: join(persist, 'd1'),
  durableObjects: { RT_HUB: { className: 'RealtimeHub', useSQLite: true } },
  durableObjectsPersist: join(persist, 'do'),
  bindings: {
    ADMIN_SECRET: adminSecret, SECRETS_KEY: randomBytes(32).toString('hex'),
    ACCOUNT_ENCRYPTION_KEY: randomBytes(32).toString('hex'), DEVICE_TOKEN_SECRET: randomBytes(32).toString('hex'),
    GOLD_PANEL_API_KEY: 'fixtureNoOutboundNetwork12345', DEFAULT_SERVERS: '[]',
    PANEL_ORIGINS: 'https://panel.fixture.test',
  },
  outboundService: async (request) => {
    outbound.push(new URL(request.url).host);
    return Response.json({ error: 'fixture_network_denied' }, { status: 503 });
  },
  log: new Log(LogLevel.WARN),
};
async function step(name, run) { current = name; const value = await run(); passed++; console.log('PASS ' + name); return value; }
async function api(method, path, { token, body, key } = {}) {
  const headers = { 'content-type': 'application/json', 'cf-connecting-ip': '192.0.2.91' };
  if (token) headers.authorization = 'Bearer ' + token;
  if (key) headers['x-device-key'] = key;
  const response = await mf.dispatchFetch('https://fixture.test' + path, {
    method, headers, body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text(); let data;
  try { data = JSON.parse(text); } catch { data = null; }
  return { status: response.status, data };
}
function device(action, { key = KEY, raw = RAW, body = {} } = {}) {
  return api('POST', '/api/novatube4k/' + action, { key, body: { raw_mac: raw, ...body } });
}
function ok(result, expected = 200) { assert.equal(result.status, expected, 'HTTP; error=' + (result.data?.error || 'none')); return result.data; }

try {
  console.log(JSON.stringify({ runtime: 'workerd', candidate,
    candidate_sha256: createHash('sha256').update(readFileSync(candidate)).digest('hex'),
    external_network: 'intercepted and denied', fixture_only: true }));
  mf = new Miniflare(options); await mf.ready;
  let db = await mf.getD1Database('DB');
  await step('D1 réel local et schéma indépendant', async () => {
    for (const sql of readFileSync(join(here, 'schema.sql'), 'utf8').split(/;\s*(?:\n|$)/)
      .map((s) => s.replace(/^\s*--.*$/gm, '').trim()).filter(Boolean)) await db.prepare(sql).run();
    try { await db.prepare('ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT').run(); } catch {}
  });
  await step('state/checkout inconnus refusés avant tout essai', async () => {
    ok(await device('state'), 401); ok(await device('checkout'), 401);
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM novatube4k_trial_entitlements').first()).n, 0);
  });
  const first = await step('inscriptions concurrentes : un essai de dix jours, aucun achat', async () => {
    const responses = await Promise.all([device('register'), device('register')]);
    for (const response of responses) ok(response);
    assert.equal(responses.filter((r) => r.data.created).length, 1);
    const result = responses[0].data;
    assert.equal(result.active, true); assert.equal(result.playback_allowed, true);
    assert.equal(result.plan, 'trial10'); assert.equal(result.access_kind, 'trial');
    assert.equal(result.expires_at - result.trial.started_at, DURATION);
    assert.deepEqual(result.commerce, { price_minor: 999, currency: 'EUR', auto_renew: false,
      license_duration: null, checkout_available: false, checkout_url: null });
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM novatube4k_trial_entitlements').first()).n, 1);
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM credit_ledger').first()).n, 0);
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM payments').first()).n, 0);
    return result;
  });
  const anchor = await db.prepare('SELECT * FROM novatube4k_trial_entitlements WHERE raw_mac=?').bind(RAW).first();
  await step('mauvaise clé, dates et durée fournies par le client sans effet', async () => {
    ok(await device('register', { key: NEXT }), 409);
    ok(await device('checkout', { key: NEXT }), 401);
    const replay = ok(await device('register', { body: { now: 1, trial_days: 365, expires_at: Date.now() + 9999999999 } }));
    assert.equal(replay.expires_at, first.expires_at);
    assert.deepEqual(await db.prepare('SELECT * FROM novatube4k_trial_entitlements WHERE raw_mac=?').bind(RAW).first(), anchor);
  });
  await step('redémarrage complet du runtime : ancre D1 et échéance inchangées', async () => {
    await mf.dispose(); mf = new Miniflare(options); await mf.ready; db = await mf.getD1Database('DB');
    const restarted = ok(await device('register'));
    assert.equal(restarted.created, false); assert.equal(restarted.expires_at, first.expires_at);
    assert.deepEqual(restarted.trial, first.trial);
    assert.deepEqual(await db.prepare('SELECT * FROM novatube4k_trial_entitlements WHERE raw_mac=?').bind(RAW).first(), anchor);
  });
  const token = await step('auth admin de fixture et source attribuée sans contacter le fournisseur', async () => {
    const login = ok(await api('POST', '/api/v1/auth/login', { body: { email: 'admin', password: adminSecret } }));
    ok(await api('PUT', '/api/v1/sources/' + encodeURIComponent(first.mac), { token: login.token,
      body: { sources: [{ type: 'm3u', label: 'Fixture', m3u_url: 'https://media.invalid/fixture.m3u' }] } }));
    assert.equal(ok(await device('state')).sources.length, 1);
    return login.token;
  });
  const stored = await db.prepare('SELECT * FROM device_sources WHERE mac=?').bind(first.mac).first();
  await step('ban, gel et app désactivée prioritaires sur l’essai', async () => {
    for (const block of ['banned', 'frozen']) {
      await db.prepare('UPDATE devices SET block_status=? WHERE mac=?').bind(block, first.mac).run();
      const result = ok(await device('register'));
      assert.equal(result.status, block); assert.equal(result.active, false); assert.equal(result.trial.status, 'unavailable');
      assert.deepEqual(result.sources, []);
    }
    await db.prepare('UPDATE devices SET block_status=NULL WHERE mac=?').bind(first.mac).run();
    await db.prepare('UPDATE apps SET is_active=0 WHERE id=?').bind(APP).run();
    assert.equal(ok(await device('state')).status, 'disabled');
    const disabledNew = ok(await device('register', { raw: RAW2 }));
    assert.equal(disabledNew.active, false); assert.equal(disabledNew.expires_at, 0);
    await db.prepare('UPDATE apps SET is_active=1 WHERE id=?').bind(APP).run();
    assert.equal(ok(await device('register', { raw: RAW2 })).active, false);
  });
  await step('J10 dépassé : lecture fermée, sources et identité conservées', async () => {
    // Déplacement temporel dans les seules données de cette fixture : workerd
    // garde sa vraie horloge et doit constater une échéance déjà dépassée.
    const end = Date.now() - 1000, start = end - DURATION;
    await db.batch([
      db.prepare('UPDATE novatube4k_trial_entitlements SET started_at=?,expires_at=? WHERE raw_mac=?').bind(start, end, RAW),
      db.prepare('UPDATE licenses SET started_at=?,expires_at=? WHERE device_id=(SELECT id FROM devices WHERE mac=?)').bind(start, end, first.mac),
    ]);
    for (const action of ['state', 'register']) {
      const expired = ok(await device(action));
      assert.equal(expired.active, false); assert.equal(expired.playback_allowed, false);
      assert.equal(expired.status, 'expired'); assert.equal(expired.trial.status, 'expired');
      assert.equal(expired.expires_at, end); assert.deepEqual(expired.sources, []);
    }
    assert.deepEqual(await db.prepare('SELECT * FROM device_sources WHERE mac=?').bind(first.mac).first(), stored);
  });
  await step('récupération de clé après J10 sans réactivation ni prolongation', async () => {
    const before = await db.prepare('SELECT * FROM licenses WHERE device_id=(SELECT id FROM devices WHERE mac=?)').bind(first.mac).first();
    const offer = ok(await device('register', { key: NEXT }), 409);
    const base = '/api/v1/novatube4k/reassociate';
    const preview = ok(await api('POST', base + '/preview', { token, body: { mac: first.mac, code: offer.recovery.code } }));
    ok(await api('POST', base + '/approve', { token, body: {
      mac: first.mac, code: offer.recovery.code, request_id: preview.candidate.request_id,
    } }));
    const recovered = ok(await device('register', { key: NEXT }));
    assert.equal(recovered.status, 'expired'); assert.equal(recovered.expires_at, before.expires_at);
    assert.deepEqual(await db.prepare('SELECT * FROM licenses WHERE id=?').bind(before.id).first(), before);
    ok(await device('state', { key: KEY }), 401);
  });
  await step('licence payée lifetime conservée sans nouveau trial', async () => {
    ok(await api('POST', '/api/v1/activate', { token, body: { mac: first.mac, plan: 'lifetime' } }), 201);
    const paid = await db.prepare('SELECT * FROM licenses WHERE device_id=(SELECT id FROM devices WHERE mac=?)').bind(first.mac).first();
    const result = ok(await device('register', { key: NEXT }));
    assert.equal(result.active, true); assert.equal(result.access_kind, 'paid');
    assert.equal(result.plan, 'lifetime'); assert.equal(result.expires_at, null);
    assert.equal(result.trial.status, 'not_offered');
    assert.deepEqual(await db.prepare('SELECT * FROM licenses WHERE id=?').bind(paid.id).first(), paid);
  });
  await step('suppression puis réenrôlement : ancre subsiste, aucun nouvel essai', async () => {
    const before = await db.prepare('SELECT * FROM novatube4k_trial_entitlements WHERE raw_mac=?').bind(RAW).first();
    await db.prepare('DELETE FROM devices WHERE mac=?').bind(first.mac).run();
    const replay = ok(await device('register'));
    assert.equal(replay.created, true); assert.equal(replay.active, false); assert.equal(replay.expires_at, 0);
    assert.equal(replay.trial.status, 'unavailable');
    assert.deepEqual(await db.prepare('SELECT * FROM novatube4k_trial_entitlements WHERE raw_mac=?').bind(RAW).first(), before);
    assert.equal(outbound.length, 0);
  });
  console.log(JSON.stringify({ ok: true, passed, fixture_only: true, outbound_requests: outbound.length }));
} catch (error) {
  console.error(JSON.stringify({ ok: false, passed, failed_step: current, error: String(error.message || error) }));
  process.exitCode = 1;
} finally {
  await mf?.dispose();
  rmSync(persist, { recursive: true, force: true });
}
