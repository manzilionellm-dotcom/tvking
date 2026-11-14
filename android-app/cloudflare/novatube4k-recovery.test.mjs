// Réassociation locale uniquement : vrais JWT du Worker et SQLite transactionnel.
// Toute sortie réseau est refusée, toutes les identités et clés sont des fixtures.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createD1, fakeRealtimeHub } from './test_support/d1_sqlite.mjs';
import { normalizeNovatubeRecoveryCode } from './novatube4k-recovery.js';
import { novatube4kAtlasMac } from './novatube4k.js';

const entry = await import(process.env.NOVATUBE4K_TEST_ENTRY
  ? pathToFileURL(resolve(process.env.NOVATUBE4K_TEST_ENTRY)).href
  : new URL('./novatube4k-entry.js', import.meta.url).href);
const APP = 'app_novatube4k', PATH = '/api/v1/novatube4k/reassociate';
const RAW = 'A21324354671', RAW2 = 'A21324354672';
const KEY = 'a5'.repeat(32), NEXT = 'b6'.repeat(32), THIRD = 'c7'.repeat(32);
const CODE = /^[0-9A-HJKMNP-TV-Z]{4}(?:-[0-9A-HJKMNP-TV-Z]{4}){2}$/;
const hash = (value) => createHash('sha256').update(value).digest('hex');

function fixture(t, jitterMs = 0) {
  const { DB, db, faults } = createD1({ jitterMs,
    extraSql: ['ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT'] });
  const env = { DB, ADMIN_SECRET: crypto.randomUUID(), SECRETS_KEY: crypto.randomUUID(),
    ACCOUNT_ENCRYPTION_KEY: crypto.randomUUID(), DEVICE_TOKEN_SECRET: crypto.randomUUID(),
    GOLD_PANEL_API_KEY: 'fixtureOnlyNoNetwork12345', DEFAULT_SERVERS: '[]',
    PANEL_ORIGINS: 'https://panel.fixture.test' };
  env.RT_HUB = fakeRealtimeHub(env, entry.RealtimeHub);
  const pending = [], outbound = [];
  const ctx = { waitUntil(p) { pending.push(Promise.resolve(p)); }, passThroughOnException() {} };
  t.mock.method(globalThis, 'fetch', async (input) => {
    outbound.push(new URL(input instanceof Request ? input.url : String(input)).host);
    return Response.json({ error: 'fixture_network_denied' }, { status: 503 });
  });
  async function drain() { while (pending.length) await Promise.all(pending.splice(0)); }
  async function api(method, path, { token, body, text, headers = {} } = {}) {
    const h = { 'content-type': 'application/json', 'cf-connecting-ip': '192.0.2.66', ...headers };
    if (token) h.authorization = 'Bearer ' + token;
    const response = await entry.default.fetch(new Request('https://fixture.test' + path,
      { method, headers: h, body: text ?? (body === undefined ? undefined : JSON.stringify(body)) }), env, ctx);
    const raw = await response.text(); let json;
    try { json = JSON.parse(raw); } catch { json = null; }
    await drain();
    return { status: response.status, json, raw, headers: response.headers };
  }
  function device(action = 'register', key = KEY, body = {}, raw = RAW) {
    return api('POST', '/api/novatube4k/' + action, {
      body: { raw_mac: raw, ...body }, headers: key ? { 'X-Device-Key': key } : {},
    });
  }
  async function registered(raw = RAW, key = KEY) {
    const r = await device('register', key, {}, raw); assert.equal(r.status, 200); return r.json.mac;
  }
  async function admin() {
    const r = await api('POST', '/api/v1/auth/login', { body: { email: 'admin', password: env.ADMIN_SECRET } });
    assert.equal(r.status, 200); return r.json.token;
  }
  async function reseller(token) {
    const email = crypto.randomUUID() + '@example.test', password = 'Fixture9Aa!' + crypto.randomUUID();
    const made = await api('POST', '/api/v1/resellers', { token, body: { email, password, name: 'Fixture' } });
    assert.equal(made.status, 201);
    const login = await api('POST', '/api/v1/auth/reseller/login', { body: { email, password } });
    assert.equal(login.status, 200); return login.json.token;
  }
  async function offered(key = NEXT, body = {}, raw = RAW) {
    const r = await device('register', key, body, raw);
    assert.equal(r.status, 409); assert.equal(r.json.error, 'device_key_conflict');
    assert.equal(r.json.ok, false); assert.equal(r.json.app_id, APP);
    assert.match(r.json.recovery.code, CODE); assert.equal(r.json.recovery.status, 'pending');
    assert.ok(Number.isSafeInteger(r.json.server_now));
    assert.ok(Number.isSafeInteger(r.json.recovery.expires_at));
    assert.ok(r.json.recovery.expires_at > r.json.server_now);
    assert.ok(r.json.recovery.expires_at - r.json.server_now <= 600_000);
    return r;
  }
  function capability(token, mac) { return api('GET', PATH + '?mac=' + encodeURIComponent(mac), { token }); }
  function preview(token, mac, code) { return api('POST', PATH + '/preview', { token, body: { mac, code } }); }
  async function approve(token, mac, code, request_id) {
    if (request_id === undefined) {
      const viewed = await preview(token, mac, code);
      if (viewed.status !== 200) return viewed;
      request_id = viewed.json.candidate.request_id;
    }
    return api('POST', PATH + '/approve', { token, body: { mac, code, request_id } });
  }
  function rows(table) {
    if (!db.prepare('SELECT name FROM sqlite_master WHERE type=\'table\' AND name=?').get(table)) return [];
    return db.prepare('SELECT * FROM ' + table + ' ORDER BY rowid').all().map((r) => ({ ...r }));
  }
  function protectedData() {
    return Object.fromEntries(['licenses', 'device_sources', 'source_revisions', 'box_orders',
      'credit_ledger', 'payments', 'customers', 'resellers', 'apps'].map((table) => [table, rows(table)]));
  }
  t.after(async () => { await drain(); assert.deepEqual(outbound, [], 'aucun appel fournisseur ou Gold'); db.close(); });
  return { DB, db, faults, env, api, device, registered, admin, reseller, offered,
    capability, preview, approve, rows, protectedData };
}

test('code Crockford strict : normalisation bornée, aucun alias ambigu', () => {
  assert.equal(normalizeNovatubeRecoveryCode('4x7k p9dm-2r6c'), '4X7K-P9DM-2R6C');
  for (const bad of [null, 123, '', 'O000-0000-0000', 'I000-0000-0000', 'U000-0000-0000',
    'L000-0000-0000', '4X7K-P9DM-2R6C-extra', ' '.repeat(64) + '000000000000']) {
    assert.equal(normalizeNovatubeRecoveryCode(bad), null);
  }
});

test('conflit lié à la nouvelle clé : même code et expiration, aucune autorisation implicite', async (t) => {
  const f = fixture(t), mac = await f.registered(), before = f.protectedData();
  const first = await f.offered(NEXT, { model: 'Fixture API23', appVersion: '334.2.fixture', platform: 'android' });
  const again = await f.offered();
  assert.deepEqual(first.json.recovery, again.json.recovery); assert.equal(first.json.mac, mac);
  assert.deepEqual(f.protectedData(), before);
  assert.equal(f.rows('novatube4k_recovery_requests').length, 1);
  for (const secret of [RAW, KEY, NEXT, hash(KEY), hash(NEXT)]) assert.ok(!first.raw.includes(secret));
  assert.equal((await f.device('state', NEXT)).status, 401);
  assert.equal((await f.device('state')).status, 200);
  assert.match(first.headers.get('cache-control'), /no-store/);
});

test('register concurrents même nouvelle clé : un seul candidat et un seul code', async (t) => {
  const f = fixture(t, 3); await f.registered();
  const results = await Promise.all(Array.from({ length: 6 }, () => f.offered()));
  assert.equal(new Set(results.map((r) => r.json.recovery.code)).size, 1);
  assert.equal(new Set(results.map((r) => r.json.recovery.expires_at)).size, 1);
  assert.equal(f.rows('novatube4k_recovery_requests').length, 1);
});

test('trois candidats maximum même en concurrence, slots expirés réutilisés sans croissance', async (t) => {
  const f = fixture(t, 2); await f.registered();
  const keys = [NEXT, THIRD, 'd8'.repeat(32)];
  await Promise.all(keys.map((key) => f.offered(key)));
  const full = await f.device('register', 'e9'.repeat(32));
  assert.equal(full.status, 409); assert.equal(full.json.ok, false);
  assert.equal(full.json.recovery.status, 'unavailable'); assert.equal(full.json.recovery.code, undefined);
  assert.ok(full.json.recovery.retry_after > 0 && full.json.recovery.retry_after <= 600);
  assert.equal(f.rows('novatube4k_recovery_requests').length, 3);
  assert.equal((await f.device('state')).status, 200);
  f.db.prepare('UPDATE novatube4k_recovery_requests SET expires_at=?').run(Date.now() - 1);
  await f.offered('e9'.repeat(32));
  assert.equal(f.rows('novatube4k_recovery_requests').length, 3);
});

test('capacité et aperçu en lecture seule, sans migration ni énumération de code', async (t) => {
  const f = fixture(t), mac = await f.registered(), token = await f.admin();
  const before = f.protectedData();
  const capable = await f.capability(token, mac);
  assert.equal(capable.status, 200);
  assert.ok(Number.isSafeInteger(capable.json.server_now));
  assert.deepEqual(capable.json, { ok: true, supported: true, app_id: APP, mac,
    installation_status: 'unknown', recovery_pending: false,
    server_now: capable.json.server_now, recovery_expires_at: null });
  const missing = await f.preview(token, mac, '0000-0000-0000');
  assert.equal(missing.status, 409); assert.equal(missing.json.error, 'recovery_not_found');
  assert.equal(f.db.prepare('SELECT name FROM sqlite_master WHERE name=?').get('novatube4k_recovery_requests'), undefined);
  assert.deepEqual(f.protectedData(), before);
});

test('activation panel effective mais nouvelle installation bloquée : diagnostic propriétaire sans code ni mutation', async (t) => {
  const f = fixture(t), mac = await f.registered(), token = await f.admin();
  const offer = await f.offered();
  // Les écrans génériques du panneau peuvent envoyer 7 MOTION ou omettre
  // app_id. Le wrapper doit toujours modifier la seule licence NOVATUBE liée.
  assert.equal((await f.api('POST', '/api/v1/activate', { token,
    body: { mac, plan: 'lifetime', app_id: 'app_7motion' } })).status, 201);
  const again = await f.api('POST', '/api/v1/activate', { token, body: { mac, plan: 'lifetime' } });
  assert.equal(again.status, 200); assert.equal(again.json.already_lifetime, true);
  assert.equal(f.rows('licenses').length, 1); assert.equal(f.rows('licenses')[0].app_id, APP);
  assert.equal(f.rows('licenses')[0].status, 'active'); assert.equal(f.rows('licenses')[0].plan, 'lifetime');
  assert.equal((await f.device('state', NEXT)).status, 401);
  const before = f.protectedData(), binding = f.rows('novatube4k_devices'), requests = f.rows('novatube4k_recovery_requests');
  const info = await f.capability(token, mac);
  assert.equal(info.status, 200); assert.match(info.headers.get('cache-control'), /no-store/);
  assert.deepEqual(info.json, { ok: true, supported: true, app_id: APP, mac,
    installation_status: 'verification_required', recovery_pending: true,
    server_now: info.json.server_now, recovery_expires_at: offer.json.recovery.expires_at });
  assert.ok(Number.isSafeInteger(info.json.server_now));
  assert.ok(info.json.recovery_expires_at > info.json.server_now);
  assert.ok(info.json.recovery_expires_at - info.json.server_now <= 600_000);
  for (const secret of [offer.json.recovery.code, requests[0].request_id, RAW, KEY, NEXT, hash(KEY), hash(NEXT)]) {
    assert.ok(!info.raw.includes(secret));
  }
  assert.deepEqual(f.protectedData(), before);
  assert.deepEqual(f.rows('novatube4k_devices'), binding);
  assert.deepEqual(f.rows('novatube4k_recovery_requests'), requests);
});

test('diagnostic exclut les demandes expirées, traitées, incohérentes ou d’une ancienne liaison', async (t) => {
  const f = fixture(t), mac = await f.registered(), token = await f.admin();
  await f.offered();
  const original = f.rows('novatube4k_recovery_requests')[0];
  const update = f.db.prepare(`UPDATE novatube4k_recovery_requests SET state=?, expires_at=?,
    old_key_hash=?, new_key_hash=?, mac=?, device_id=?, created_at=? WHERE request_id=?`);
  for (const change of [
    { expires_at: Date.now() - 1 }, { state: 'approved' }, { state: 'superseded' },
    { old_key_hash: hash(THIRD) }, { new_key_hash: hash(KEY) },
    { mac: 'MK:00:00:00:00:00' }, { device_id: 'fixture_other_device' },
    { created_at: Date.now() + 600_000 }, { expires_at: Date.now() + 1_200_000 },
  ]) {
    const row = { ...original, ...change };
    update.run(row.state, row.expires_at, row.old_key_hash, row.new_key_hash, row.mac,
      row.device_id, row.created_at, row.request_id);
    const info = await f.capability(token, mac);
    assert.equal(info.status, 200);
    assert.equal(info.json.installation_status, 'unknown');
    assert.equal(info.json.recovery_pending, false); assert.equal(info.json.recovery_expires_at, null);
  }
  assert.equal(f.rows('novatube4k_devices')[0].device_key_hash, hash(KEY));
  assert.equal(f.rows('audit_logs').filter((r) => r.action === 'device.key_reassociate').length, 0);
});

test('panne de lecture du diagnostic : erreur explicite et aucune confirmation factice', async (t) => {
  const f = fixture(t), mac = await f.registered(), token = await f.admin();
  await f.offered(); const before = f.protectedData(), binding = f.rows('novatube4k_devices');
  f.faults.add({ match: /SELECT MAX\(r\.expires_at\)/, times: 1, when: 'before' });
  const info = await f.capability(token, mac);
  assert.equal(info.status, 503); assert.equal(info.json.error, 'recovery_unavailable');
  assert.equal(info.json.installation_status, undefined);
  assert.deepEqual(f.protectedData(), before); assert.deepEqual(f.rows('novatube4k_devices'), binding);
});

test('boîte noire : clé en conflit refusée puis journal persisté et visible après approbation légitime', async (t) => {
  const f = fixture(t), mac = await f.registered(), token = await f.admin();
  assert.equal((await f.api('POST', '/api/v1/activate', { token, body: { mac, plan: 'lifetime' } })).status, 201);
  const offer = await f.offered();
  const ask = await f.api('POST', '/api/v1/blackbox/' + encodeURIComponent(mac) + '/ask', { token, body: {} });
  assert.equal(ask.status, 200); assert.ok(ask.json.requested_at > 0);
  const before = f.rows('device_blackbox');
  assert.equal(before.length, 1); assert.equal(before[0].body, ''); assert.equal(before[0].updated_at, 0);
  const refused = await f.device('blackbox', NEXT, { text: 'FIXTURE AVANT VERIFICATION' });
  assert.equal(refused.status, 401); assert.equal(refused.json.error, 'device_auth_required');
  assert.deepEqual(f.rows('device_blackbox'), before);
  assert.equal((await f.capability(token, mac)).json.installation_status, 'verification_required');
  assert.equal((await f.approve(token, mac, offer.json.recovery.code)).status, 200);
  const state = await f.device('register', NEXT);
  assert.equal(state.status, 200); assert.equal(state.json.active, true);
  assert.equal(state.json.blackbox_pull, ask.json.requested_at);
  const commercial = f.protectedData();
  const sent = await f.device('blackbox', NEXT, {
    raw_mac: RAW.toLowerCase().match(/../g).join(':'), mac: 'MK:00:00:00:00:00',
    text: 'NOVATUBE JOURNAL FIXTURE\napp_version=334.2.fixture',
  });
  assert.equal(sent.status, 200); assert.equal(sent.json.ok, true); assert.ok(sent.json.updated_at > 0);
  const stored = f.rows('device_blackbox');
  assert.equal(stored.length, 1); assert.equal(stored[0].mac, mac);
  assert.equal(stored[0].updated_at, sent.json.updated_at); assert.ok(stored[0].body.includes('NOVATUBE JOURNAL FIXTURE'));
  const path = '/api/v1/blackbox/' + encodeURIComponent(mac);
  assert.equal((await f.api('GET', path)).status, 401);
  const journal = await f.api('GET', path, { token });
  assert.equal(journal.status, 200); assert.equal(journal.json.updated_at, sent.json.updated_at);
  assert.ok(journal.json.text.includes('NOVATUBE JOURNAL FIXTURE'));
  assert.equal((await f.device('blackbox', KEY, { text: 'ANCIENNE CLE' })).status, 401);
  assert.deepEqual(f.rows('device_blackbox'), stored); assert.deepEqual(f.protectedData(), commercial);
});

test('seul super_admin authentifié peut voir ou approuver, origine et JWT d’origine conservés', async (t) => {
  const f = fixture(t), mac = await f.registered(), token = await f.admin();
  const code = (await f.offered()).json.recovery.code;
  const seller = await f.reseller(token);
  for (const [method, path, body] of [['GET', PATH + '?mac=' + mac],
    ['POST', PATH + '/preview', { mac, code }], ['POST', PATH + '/approve', { mac, code }]]) {
    assert.equal((await f.api(method, path, { body })).status, 401);
    assert.equal((await f.api(method, path, { body, token: 'invalid.fixture.token' })).status, 401);
    assert.equal((await f.api(method, path, { body, headers: { 'X-Device-Key': NEXT } })).status, 401);
    assert.equal((await f.api(method, path, { body, token: seller })).status, 403);
    assert.equal((await f.api(method, path, { body, token, headers: { Origin: 'https://untrusted.test' } })).status, 403);
  }
  assert.equal(f.rows('novatube4k_devices')[0].device_key_hash, hash(KEY));
  assert.equal(f.rows('audit_logs').filter((r) => r.action === 'device.key_reassociate').length, 0);
});

test('preview limité aux métadonnées déclarées, code normalisé et secrets absents', async (t) => {
  const f = fixture(t), mac = await f.registered(), token = await f.admin();
  const code = (await f.offered(NEXT, { model: 'Fixture\nhttps://fixture.test/private?secret=one ' + NEXT,
    appVersion: '334.2.fixture', platform: 'android' })).json.recovery.code;
  const r = await f.preview(token, mac.toLowerCase(), code.toLowerCase().replace(/-/g, ' '));
  assert.equal(r.status, 200); assert.equal(r.json.mac, mac); assert.equal(r.json.app_id, APP);
  assert.deepEqual(Object.keys(r.json.candidate).sort(),
    ['app_version', 'created_at', 'expires_at', 'model', 'platform', 'request_id']);
  assert.equal(r.json.candidate.app_version, '334.2.fixture'); assert.equal(r.json.candidate.platform, 'android');
  assert.ok(r.json.candidate.expires_at - r.json.candidate.created_at === 600_000);
  for (const value of [code, RAW, KEY, NEXT, hash(KEY), hash(NEXT), 'https://fixture.test', 'secret=one']) {
    assert.ok(!r.raw.includes(value), 'preview expurgé');
  }
});

test('code incorrect, mauvaise fiche, corps malformé ou trop grand : aucun effet', async (t) => {
  const f = fixture(t), mac = await f.registered(), other = await f.registered(RAW2, THIRD), token = await f.admin();
  const code = (await f.offered()).json.recovery.code, before = f.rows('novatube4k_devices');
  assert.equal((await f.preview(token, other, code)).json.error, 'recovery_not_found');
  assert.equal((await f.approve(token, mac, '0000-0000-0000')).json.error, 'recovery_not_found');
  for (const body of [{ mac }, { code }, { mac, code: 'O000-0000-0000' }, [], null,
    { mac, code }, { mac, code, request_id: 'not-a-uuid' }]) {
    assert.equal((await f.api('POST', PATH + '/approve', { token, body })).status, 400);
  }
  assert.equal((await f.api('POST', PATH + '/approve', { token, text: '{bad json' })).status, 400);
  assert.equal((await f.api('POST', PATH + '/approve', { token, text: 'x'.repeat(4097) })).status, 413);
  assert.equal((await f.api('POST', PATH, { token, body: { mac, code } })).status, 405);
  assert.equal((await f.api('GET', PATH + '/approve', { token })).status, 405);
  assert.deepEqual(f.rows('novatube4k_devices'), before);
});

test('approbation conserve licence lifetime, sources, expiration et crédits ; ancienne clé refusée', async (t) => {
  const f = fixture(t), mac = await f.registered(), token = await f.admin();
  assert.equal((await f.api('POST', '/api/v1/activate', { token, body: { mac, plan: 'lifetime' } })).status, 201);
  assert.equal((await f.api('PUT', '/api/v1/sources/' + encodeURIComponent(mac), { token, body: {
    sources: [{ type: 'm3u', label: 'Fixture', m3u_url: 'https://fixture.test/list.m3u?token=fixture-only' }],
  } })).status, 200);
  const previousState = await f.device('state'); assert.equal(previousState.json.active, true);
  const request = await f.offered(), code = request.json.recovery.code;
  const preview = await f.preview(token, mac, code); assert.equal(preview.status, 200);
  const before = f.protectedData(), binding = f.rows('novatube4k_devices')[0];
  const approved = await f.approve(token, mac, code, preview.json.candidate.request_id);
  assert.equal(approved.status, 200); assert.equal(approved.json.result, 'device_reassociated');
  assert.deepEqual(f.protectedData(), before);
  const after = f.rows('novatube4k_devices')[0];
  for (const key of ['raw_mac', 'mac', 'device_id', 'created_at']) assert.equal(after[key], binding[key]);
  assert.equal(after.device_key_hash, hash(NEXT)); assert.equal(after.last_served_rev, null);
  assert.equal((await f.device('state')).status, 401);
  assert.equal((await f.device('ack', NEXT, { applied: true, source_rev: previousState.json.source_rev })).status, 409);
  const state = await f.device('register', NEXT);
  assert.equal(state.status, 200); assert.equal(state.json.active, true); assert.equal(state.json.created, false);
  assert.equal(state.json.plan, 'lifetime'); assert.equal(state.json.expires_at, null);
  assert.deepEqual(state.json.sources, previousState.json.sources);
  const audit = f.rows('audit_logs').filter((r) => r.action === 'device.key_reassociate');
  assert.equal(audit.length, 1); assert.equal(audit[0].target_id, binding.device_id);
  assert.equal(audit[0].actor_type, 'admin'); assert.ok(audit[0].actor_id);
  const auditText = JSON.stringify(audit);
  for (const value of [code, RAW, KEY, NEXT, hash(KEY), hash(NEXT)]) assert.ok(!auditText.includes(value));
  assert.equal(f.rows('novatube4k_recovery_guard').length, 0);
  const diagnostic = await f.capability(token, mac);
  assert.equal(diagnostic.json.installation_status, 'unknown');
  assert.equal(diagnostic.json.recovery_pending, false); assert.equal(diagnostic.json.recovery_expires_at, null);
});

test('réassociation ne transforme pas une inscription inactive ni une licence expirée en accès', async (t) => {
  const f = fixture(t), mac = await f.registered(), other = await f.registered(RAW2, THIRD), token = await f.admin();
  // L'inscription nouvelle ouvre désormais un essai. Ce scénario vise une
  // licence explicitement inactive et vérifie que recovery ne l'active pas.
  f.db.prepare("UPDATE licenses SET status='inactive',plan='custom',expires_at=0 WHERE device_id=(SELECT id FROM devices WHERE mac=?)").run(mac);
  const expiry = Date.now() - 86_400_000;
  f.db.prepare('UPDATE licenses SET status=\'active\',plan=\'yearly\',expires_at=? WHERE device_id=(SELECT id FROM devices WHERE mac=?)')
    .run(expiry, other);
  const before = f.protectedData();
  const code = (await f.offered()).json.recovery.code;
  assert.equal((await f.approve(token, mac, code)).status, 200);
  const otherKey = 'd8'.repeat(32), code2 = (await f.offered(otherKey, {}, RAW2)).json.recovery.code;
  assert.equal((await f.approve(token, other, code2)).status, 200);
  assert.deepEqual(f.protectedData(), before);
  const inactive = await f.device('state', NEXT), expired = await f.device('state', otherKey, {}, RAW2);
  assert.equal(inactive.json.active, false); assert.equal(inactive.json.status, 'inactive');
  assert.equal(expired.json.active, false); assert.equal(expired.json.status, 'expired');
  assert.equal(expired.json.expires_at, expiry);
});

test('réassociation d’un essai automatique conserve exactement son ancre et son échéance J10', async (t) => {
  const f = fixture(t), mac = await f.registered(), token = await f.admin();
  const before = f.protectedData();
  const anchor = f.rows('novatube4k_trial_entitlements');
  const initial = await f.device('state');
  assert.equal(initial.json.plan, 'trial10');
  const code = (await f.offered()).json.recovery.code;
  assert.equal((await f.approve(token, mac, code)).status, 200);
  const recovered = await f.device('register', NEXT);
  assert.equal(recovered.status, 200);
  assert.equal(recovered.json.created, false);
  assert.equal(recovered.json.expires_at, initial.json.expires_at);
  assert.deepEqual(recovered.json.trial, initial.json.trial);
  assert.deepEqual(f.rows('novatube4k_trial_entitlements'), anchor);
  assert.deepEqual(f.protectedData(), before);
  assert.equal((await f.device('state', KEY)).status, 401);
});

test('code expiré refusé, renouvellement par la même clé sans réutiliser le code ancien', async (t) => {
  const f = fixture(t), mac = await f.registered(), token = await f.admin();
  const code = (await f.offered()).json.recovery.code;
  f.db.prepare('UPDATE novatube4k_recovery_requests SET expires_at=?').run(Date.now() - 1);
  assert.equal((await f.preview(token, mac, code)).json.error, 'recovery_expired');
  assert.equal((await f.approve(token, mac, code)).json.error, 'recovery_expired');
  assert.equal(f.rows('novatube4k_devices')[0].device_key_hash, hash(KEY));
  const renewed = await f.offered(); assert.notEqual(renewed.json.recovery.code, code);
  assert.equal(f.rows('novatube4k_recovery_requests').length, 1);
  assert.equal((await f.approve(token, mac, code)).status, 409);
});

test('request_id incorrect, double clic et rejeu ne réapprouvent jamais le candidat', async (t) => {
  const f = fixture(t), mac = await f.registered(), token = await f.admin();
  const code = (await f.offered()).json.recovery.code;
  assert.equal((await f.approve(token, mac, code, crypto.randomUUID())).json.error, 'recovery_stale');
  assert.equal((await f.approve(token, mac, code)).status, 200);
  const again = await f.approve(token, mac, code);
  assert.equal(again.status, 409); assert.equal(again.json.error, 'recovery_consumed');
  assert.equal((await f.preview(token, mac, code)).json.error, 'recovery_consumed');
  assert.equal(f.rows('audit_logs').filter((r) => r.action === 'device.key_reassociate').length, 1);
});

test('deux approbations concurrentes : un seul CAS, un seul audit, seul le gagnant authentifie', async (t) => {
  const f = fixture(t, 3), mac = await f.registered(), token = await f.admin();
  const a = (await f.offered(NEXT)).json.recovery.code, b = (await f.offered(THIRD)).json.recovery.code;
  const before = f.protectedData();
  const results = await Promise.all([f.approve(token, mac, a), f.approve(token, mac, b)]);
  assert.deepEqual(results.map((r) => r.status).sort(), [200, 409]);
  const winner = results[0].status === 200 ? NEXT : THIRD, loser = winner === NEXT ? THIRD : NEXT;
  assert.equal(f.rows('novatube4k_devices')[0].device_key_hash, hash(winner));
  assert.equal((await f.device('state', winner)).status, 200);
  assert.equal((await f.device('state', loser)).status, 401);
  assert.equal((await f.device('state', KEY)).status, 401);
  assert.equal(f.rows('audit_logs').filter((r) => r.action === 'device.key_reassociate').length, 1);
  assert.equal(f.rows('novatube4k_recovery_guard').length, 0);
  assert.deepEqual(f.protectedData(), before);
});

test('panne après écriture audit : rollback clé et candidat, puis retry sûr', async (t) => {
  const f = fixture(t), mac = await f.registered(), token = await f.admin();
  const code = (await f.offered()).json.recovery.code, before = f.protectedData();
  f.faults.add({ match: /INSERT INTO audit_logs[\s\S]*device\.key_reassociate/, times: 1, when: 'after' });
  const failed = await f.approve(token, mac, code);
  assert.equal(failed.status, 503); assert.equal(failed.json.error, 'recovery_unavailable');
  assert.equal(f.rows('novatube4k_devices')[0].device_key_hash, hash(KEY));
  assert.equal(f.rows('novatube4k_recovery_requests')[0].state, 'pending');
  assert.equal(f.rows('novatube4k_recovery_guard').length, 0);
  assert.equal(f.rows('audit_logs').filter((r) => r.action === 'device.key_reassociate').length, 0);
  assert.deepEqual(f.protectedData(), before);
  assert.equal((await f.approve(token, mac, code)).status, 200);
});

test('CAS relit la clé dans le lot si une modification gagne après les lectures', async (t) => {
  const f = fixture(t), mac = await f.registered(), token = await f.admin();
  const code = (await f.offered()).json.recovery.code;
  const batch = f.DB.batch.bind(f.DB); let raced = false;
  t.mock.method(f.DB, 'batch', async (statements) => {
    if (!raced && statements[0].sql.includes('INSERT INTO novatube4k_recovery_guard')) {
      raced = true; f.db.prepare('UPDATE novatube4k_devices SET device_key_hash=?').run(hash(THIRD));
    }
    return batch(statements);
  });
  const r = await f.approve(token, mac, code);
  assert.equal(r.status, 409); assert.equal(r.json.error, 'recovery_stale'); assert.equal(raced, true);
  assert.equal(f.rows('novatube4k_devices')[0].device_key_hash, hash(THIRD));
  assert.equal(f.rows('novatube4k_recovery_requests')[0].state, 'pending');
  assert.equal(f.rows('novatube4k_recovery_guard').length, 0);
});

test('expiration vérifiée dans SQLite même si l’horloge JS de la requête est ancienne', async (t) => {
  const f = fixture(t), mac = await f.registered(), token = await f.admin();
  const code = (await f.offered()).json.recovery.code;
  const now = Date.now(); f.db.prepare('UPDATE novatube4k_recovery_requests SET expires_at=?').run(now - 1_000);
  t.mock.method(Date, 'now', () => now - 2_000);
  const r = await f.approve(token, mac, code);
  assert.equal(r.status, 409); assert.equal(r.json.error, 'recovery_stale');
  assert.equal(f.rows('novatube4k_devices')[0].device_key_hash, hash(KEY));
});

test('portée stricte : autre app, licence NOVATUBE absente et collision non enrôlée exclues', async (t) => {
  const f = fixture(t), mac = await f.registered(), token = await f.admin();
  const code = (await f.offered()).json.recovery.code;
  f.db.prepare('UPDATE apps SET package_name=? WHERE id=?').run('fixture.other.app', APP);
  assert.equal((await f.capability(token, mac)).status, 404);
  assert.equal((await f.approve(token, mac, code)).json.error, 'recovery_not_supported');
  f.db.prepare('UPDATE apps SET package_name=? WHERE id=?').run('com.manthefew', APP);
  f.db.prepare('DELETE FROM licenses WHERE app_id=?').run(APP);
  assert.equal((await f.capability(token, mac)).status, 404);
  const missing = await f.device('register', NEXT);
  assert.equal(missing.status, 409); assert.equal(missing.json.error, 'device_registration_missing');
  assert.equal(missing.json.ok, false); assert.equal(missing.json.app_id, APP); assert.equal(missing.json.mac, mac);
  assert.equal(missing.json.recovery, undefined);
  const other = await novatube4kAtlasMac(RAW2);
  f.db.prepare('INSERT INTO devices (id,customer_id,mac,first_seen_at,last_seen_at) VALUES (?,?,?,?,?)')
    .run('dev_fixture_unbound', f.rows('devices')[0].customer_id, other, Date.now(), Date.now());
  assert.equal((await f.capability(token, other)).status, 404);
  const collision = await f.device('register', THIRD, {}, RAW2);
  assert.equal(collision.status, 409); assert.equal(collision.json.error, 'device_identity_conflict');
  assert.equal(collision.json.ok, false); assert.equal(collision.json.app_id, APP); assert.equal(collision.json.mac, other);
  assert.equal(collision.json.recovery, undefined); assert.ok(Number.isSafeInteger(collision.json.server_now));
});

test('quota admin limite les essais de code sans modifier un candidat', async (t) => {
  const f = fixture(t), mac = await f.registered(), token = await f.admin();
  const code = (await f.offered()).json.recovery.code;
  for (let i = 0; i < 30; i++) assert.equal((await f.preview(token, mac, '0000-0000-0000')).status, 409);
  const throttled = await f.approve(token, mac, code);
  assert.equal(throttled.status, 429); assert.equal(throttled.json.error, 'rate_limited');
  assert.equal(f.rows('novatube4k_devices')[0].device_key_hash, hash(KEY));
  assert.equal(f.rows('novatube4k_recovery_requests')[0].state, 'pending');
});

test('fiche devenue incohérente : tous les 409 d’identité portent le contrat strict sans code', async (t) => {
  const f = fixture(t), mac = await f.registered();
  f.db.prepare('DELETE FROM licenses WHERE app_id=?').run(APP);
  f.db.prepare('DELETE FROM apps WHERE id=?').run(APP);
  for (const action of ['register', 'state', 'ack', 'panel']) {
    const r = await f.device(action, KEY, { source_rev: 1, applied: true });
    assert.equal(r.status, 409); assert.equal(r.json.error, 'device_registration_missing');
    assert.equal(r.json.ok, false); assert.equal(r.json.app_id, APP); assert.equal(r.json.mac, mac);
    assert.ok(Number.isSafeInteger(r.json.server_now)); assert.equal(r.json.recovery, undefined);
  }
});
