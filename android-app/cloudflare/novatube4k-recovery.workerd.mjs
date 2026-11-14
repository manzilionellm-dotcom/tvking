// Validation du candidat exact dans workerd/D1 locaux. Ni clé, code ni session
// de production ; aucun accès réseau extérieur, même pendant une activation fixture.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash, randomBytes } from 'node:crypto';
import { Miniflare, Log, LogLevel } from 'miniflare';

const here = dirname(fileURLToPath(import.meta.url));
const candidate = resolve(process.argv[2] || join(here, '../../../novafix-evidence/recovery-release/novatube4k-live-entry.js'));
const RAW = 'AABBCCDDEE81', KEY = randomBytes(32).toString('hex'), NEXT = randomBytes(32).toString('hex');
const adminSecret = randomBytes(32).toString('hex'), PATH = '/api/v1/novatube4k/reassociate';
const APP = 'app_novatube4k', CODE = /^[0-9A-HJKMNP-TV-Z]{4}(?:-[0-9A-HJKMNP-TV-Z]{4}){2}$/;
const hash = (text) => createHash('sha256').update(text).digest('hex');
const outbound = [];
let passed = 0, current = 'startup';
const mf = new Miniflare({
  host: '127.0.0.1', port: 0, modules: true,
  modulesRules: [{ type: 'ESModule', include: ['**/*.js'] }], scriptPath: candidate, modulesRoot: dirname(candidate),
  cf: false, compatibilityDate: '2025-05-01', compatibilityFlags: [],
  d1Databases: { DB: 'novatube4k-recovery-fixture' },
  durableObjects: { RT_HUB: { className: 'RealtimeHub', useSQLite: true } },
  bindings: { ADMIN_SECRET: adminSecret, SECRETS_KEY: randomBytes(32).toString('hex'),
    ACCOUNT_ENCRYPTION_KEY: randomBytes(32).toString('hex'), DEVICE_TOKEN_SECRET: randomBytes(32).toString('hex'),
    GOLD_PANEL_API_KEY: 'fixtureOnlyNoNetwork1234', DEFAULT_SERVERS: '[]', PANEL_ORIGINS: 'https://panel.fixture.test' },
  outboundService: async (request) => {
    outbound.push(new URL(request.url).host);
    return Response.json({ error: 'fixture_network_denied' }, { status: 503 });
  },
  log: new Log(LogLevel.WARN),
});
async function step(name, run) { current = name; const result = await run(); passed++; console.log('PASS ' + name); return result; }
async function api(method, path, { token, body, headers = {} } = {}) {
  const h = { 'content-type': 'application/json', 'cf-connecting-ip': '192.0.2.81', ...headers };
  if (token) h.authorization = 'Bearer ' + token;
  const response = await mf.dispatchFetch('https://fixture.test' + path, {
    method, headers: h, body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text(); let data;
  try { data = JSON.parse(text); } catch { data = null; }
  return { status: response.status, data, text, headers: response.headers };
}
function device(action, key = KEY, body = {}) {
  return api('POST', '/api/novatube4k/' + action, { body: { raw_mac: RAW, ...body }, headers: { 'X-Device-Key': key } });
}
function status(result, expected) { assert.equal(result.status, expected, 'HTTP; error=' + (result.data?.error || 'none')); }
function preview(token, mac, code) { return api('POST', PATH + '/preview', { token, body: { mac, code } }); }
function approve(token, mac, code, request_id) {
  return api('POST', PATH + '/approve', { token, body: { mac, code, request_id } });
}
async function offered(key) {
  const r = await device('register', key, { model: 'Fixture API23', appVersion: '334.2.fixture', platform: 'android' });
  status(r, 409); assert.equal(r.data.ok, false); assert.equal(r.data.error, 'device_key_conflict');
  assert.equal(r.data.app_id, APP); assert.equal(r.data.recovery.status, 'pending');
  assert.match(r.data.recovery.code, CODE);
  assert.ok(Number.isSafeInteger(r.data.server_now));
  assert.ok(r.data.recovery.expires_at - r.data.server_now > 0 && r.data.recovery.expires_at - r.data.server_now <= 600_000);
  return r;
}

try {
  console.log(JSON.stringify({ runtime: 'workerd', compatibility_date: '2025-05-01', compatibility_flags: [],
    candidate, candidate_sha256: hash(readFileSync(candidate)), external_network: 'intercepted and denied' }));
  await mf.ready;
  const db = await mf.getD1Database('DB');
  await step('schéma D1 local et Durable Object réels', async () => {
    for (const sql of readFileSync(join(here, 'schema.sql'), 'utf8').split(/;\s*(?:\n|$)/)
      .map((s) => s.replace(/^\s*--.*$/gm, '').trim()).filter(Boolean)) await db.prepare(sql).run();
    try { await db.prepare('ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT').run(); } catch {}
    assert.ok(await mf.getDurableObjectNamespace('RT_HUB'));
  });
  const mac = await step('inscription inactive et refus de la nouvelle clé', async () => {
    const r = await device('register'); status(r, 200); assert.equal(r.data.active, false);
    status(await device('state', NEXT), 401);
    return r.data.mac;
  });
  const offer = await step('code réutilisé et TTL non prolongé pour la même nouvelle clé', async () => {
    const [a, b] = await Promise.all([offered(NEXT), offered(NEXT)]);
    assert.deepEqual(a.data.recovery, b.data.recovery);
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM novatube4k_recovery_requests').first()).n, 1);
    for (const secret of [RAW, KEY, NEXT, hash(KEY), hash(NEXT)]) assert.ok(!a.text.includes(secret));
    status(await device('state'), 200); status(await device('state', NEXT), 401);
    return a.data.recovery;
  });
  const token = await step('session administrateur existante et origine vérifiée', async () => {
    const r = await api('POST', '/api/v1/auth/login', { body: { email: 'admin', password: adminSecret } });
    status(r, 200); assert.ok(r.data.token);
    status(await api('GET', PATH + '?mac=' + mac), 401);
    status(await api('POST', PATH + '/approve', { body: { mac, code: offer.code } }), 401);
    status(await api('GET', PATH + '?mac=' + mac, { token: r.data.token, headers: { Origin: 'https://untrusted.test' } }), 403);
    return r.data.token;
  });
  const requestId = await step('capacité et preview expurgés sans code ni empreinte', async () => {
    const capable = await api('GET', PATH + '?mac=' + mac, { token }); status(capable, 200);
    assert.deepEqual(capable.data, { ok: true, supported: true, app_id: APP, mac });
    const r = await preview(token, mac, offer.code.toLowerCase().replaceAll('-', ' ')); status(r, 200);
    assert.equal(r.data.candidate.model, 'Fixture API23');
    for (const secret of [offer.code, RAW, KEY, NEXT, hash(KEY), hash(NEXT)]) assert.ok(!r.text.includes(secret));
    return r.data.candidate.request_id;
  });
  await step('activation lifetime et publication source de fixture par les handlers historiques', async () => {
    status(await api('POST', '/api/v1/activate', { token, body: { mac, plan: 'lifetime' } }), 201);
    status(await api('PUT', '/api/v1/sources/' + mac, { token, body: {
      sources: [{ type: 'm3u', label: 'Fixture', m3u_url: 'https://fixture.test/list.m3u?token=fixture' }],
    } }), 200);
    const r = await device('state'); status(r, 200); assert.equal(r.data.active, true);
    assert.equal(r.data.plan, 'lifetime'); assert.equal(r.data.expires_at, null); assert.equal(r.data.sources.length, 1);
  });
  async function snapshot() {
    const result = {};
    for (const table of ['licenses', 'device_sources', 'source_revisions', 'box_orders', 'credit_ledger', 'payments', 'customers', 'resellers', 'apps']) {
      const exists = await db.prepare('SELECT name FROM sqlite_master WHERE type=\'table\' AND name=?').bind(table).first();
      result[table] = exists ? (await db.prepare('SELECT * FROM ' + table + ' ORDER BY rowid').all()).results : [];
    }
    return result;
  }
  await step('MAC et code seuls insuffisants, request_id exact obligatoire', async () => {
    status(await approve(token, mac, offer.code), 400);
    const wrong = await approve(token, mac, offer.code, crypto.randomUUID());
    status(wrong, 409); assert.equal(wrong.data.error, 'recovery_stale');
  });
  await step('approbation atomique conserve toutes les données commerciales et sources', async () => {
    const before = await snapshot();
    const r = await approve(token, mac, offer.code, requestId); status(r, 200);
    assert.equal(r.data.result, 'device_reassociated'); assert.deepEqual(await snapshot(), before);
    const current = await db.prepare('SELECT * FROM novatube4k_devices').first();
    assert.equal(current.device_key_hash, hash(NEXT)); assert.equal(current.last_served_rev, null);
    const audit = (await db.prepare('SELECT * FROM audit_logs WHERE action=?').bind('device.key_reassociate').all()).results;
    assert.equal(audit.length, 1);
    const serialized = JSON.stringify(audit);
    for (const secret of [offer.code, RAW, KEY, NEXT, hash(KEY), hash(NEXT)]) assert.ok(!serialized.includes(secret));
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM novatube4k_recovery_guard').first()).n, 0);
    status(await device('state'), 401);
    const state = await device('register', NEXT); status(state, 200);
    assert.equal(state.data.active, true); assert.equal(state.data.created, false);
    assert.equal(state.data.sources.length, 1); assert.equal(state.data.expires_at, null);
  });
  await step('rejeu du même approve refusé sans second audit', async () => {
    const r = await approve(token, mac, offer.code, requestId); status(r, 409);
    assert.equal(r.data.error, 'recovery_consumed');
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM audit_logs WHERE action=?').bind('device.key_reassociate').first()).n, 1);
  });
  await step('expiration refuse preview et approve puis le même client reçoit un nouveau code', async () => {
    const key = randomBytes(32).toString('hex'), first = (await offered(key)).data.recovery;
    const id = (await preview(token, mac, first.code)).data.candidate.request_id;
    await db.prepare('UPDATE novatube4k_recovery_requests SET expires_at=? WHERE request_id=?').bind(Date.now() - 1, id).run();
    const expired = await approve(token, mac, first.code, id); status(expired, 409); assert.equal(expired.data.error, 'recovery_expired');
    assert.equal((await preview(token, mac, first.code)).data.error, 'recovery_expired');
    const second = await offered(key); assert.notEqual(second.data.recovery.code, first.code);
    await db.prepare('UPDATE novatube4k_recovery_requests SET expires_at=1 WHERE state=\'pending\'').run();
  });
  let currentKey = NEXT;
  await step('deux approbations concurrentes donnent un seul gagnant et un seul audit supplémentaire', async () => {
    const keys = [randomBytes(32).toString('hex'), randomBytes(32).toString('hex')];
    const offers = await Promise.all(keys.map(offered));
    const previews = await Promise.all(offers.map((r) => preview(token, mac, r.data.recovery.code)));
    const before = await snapshot();
    const results = await Promise.all(offers.map((r, index) =>
      approve(token, mac, r.data.recovery.code, previews[index].data.candidate.request_id)));
    assert.deepEqual(results.map((r) => r.status).sort(), [200, 409]);
    const index = results.findIndex((r) => r.status === 200); currentKey = keys[index];
    status(await device('state', currentKey), 200); status(await device('state', keys[1 - index]), 401);
    status(await device('state', NEXT), 401); assert.deepEqual(await snapshot(), before);
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM audit_logs WHERE action=?').bind('device.key_reassociate').first()).n, 2);
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM novatube4k_recovery_guard').first()).n, 0);
  });
  await step('échec SQLite de l’audit annule la clé et la consommation puis permet un retry', async () => {
    const key = randomBytes(32).toString('hex'), offer = (await offered(key)).data.recovery;
    const id = (await preview(token, mac, offer.code)).data.candidate.request_id;
    const before = await snapshot();
    await db.prepare(`CREATE TRIGGER fixture_recovery_audit_failure BEFORE INSERT ON audit_logs
      WHEN NEW.action = 'device.key_reassociate' BEGIN SELECT RAISE(ABORT, 'fixture audit unavailable'); END`).run();
    try {
      const failed = await approve(token, mac, offer.code, id); status(failed, 503);
      assert.equal(failed.data.error, 'recovery_unavailable');
      assert.equal((await db.prepare('SELECT device_key_hash FROM novatube4k_devices').first()).device_key_hash, hash(currentKey));
      assert.equal((await db.prepare('SELECT state FROM novatube4k_recovery_requests WHERE request_id=?').bind(id).first()).state, 'pending');
      assert.deepEqual(await snapshot(), before);
    } finally { await db.prepare('DROP TRIGGER fixture_recovery_audit_failure').run(); }
    status(await approve(token, mac, offer.code, id), 200); currentKey = key;
  });
  await step('trois slots maximum face à quatre nouvelles clés concurrentes', async () => {
    const keys = Array.from({ length: 4 }, () => randomBytes(32).toString('hex'));
    const results = await Promise.all(keys.map((key) => device('register', key)));
    for (const r of results) status(r, 409);
    assert.equal(results.filter((r) => r.data.recovery.status === 'pending').length, 3);
    assert.equal(results.filter((r) => r.data.recovery.status === 'unavailable').length, 1);
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM novatube4k_recovery_requests').first()).n, 3);
    status(await device('state', currentKey), 200);
  });
  await step('autre application et autres routes publiques ne permettent pas la réparation', async () => {
    await db.prepare('UPDATE apps SET package_name=? WHERE id=?').bind('fixture.other.app', APP).run();
    const r = await api('GET', PATH + '?mac=' + mac, { token }); status(r, 404);
    assert.equal(r.data.error, 'recovery_not_supported');
    await db.prepare('UPDATE apps SET package_name=? WHERE id=?').bind('com.manthefew', APP).run();
    status(await api('GET', '/api/device-source/' + mac), 401);
    status(await api('GET', PATH + '?mac=MK:00:11:22:33:44', { token }), 404);
  });
  await step('aucun appel extérieur et aucune modification de configuration runtime', async () => {
    assert.deepEqual(outbound, []);
  });
  console.log(JSON.stringify({ result: 'PASS', checks: passed, outbound_requests: outbound.length,
    compatibility_date: '2025-05-01', compatibility_flags: [] }));
} catch (error) {
  console.error(JSON.stringify({ result: 'FAIL', step: current, checks_passed: passed, message: String(error.message) }));
  process.exitCode = 1;
} finally { await mf.dispose(); }
