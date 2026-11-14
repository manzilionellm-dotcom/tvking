// Validation du bundle exact dans workerd : D1 + RealtimeHub locaux,
// aucun réseau externe, aucun identifiant ni activation de production.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes, createHash } from 'node:crypto';
import { Miniflare, Log, LogLevel } from 'miniflare';

const here = dirname(fileURLToPath(import.meta.url));
const candidate = resolve(process.argv[2] || join(here, '../../../atlas4k-evidence/panel-release/novatube4k-live-entry.js'));
const RAW = 'AABBCCDDEE31', RAW2 = 'AABBCCDDEE32';
const KEY = randomBytes(32).toString('hex'), KEY2 = randomBytes(32).toString('hex');
const adminSecret = randomBytes(32).toString('hex');
const outbound = [];
let passed = 0, current = 'startup';
const mf = new Miniflare({
  host: '127.0.0.1', port: 0, modules: true,
  modulesRules: [{ type: 'ESModule', include: ['**/*.js'] }], scriptPath: candidate, modulesRoot: dirname(candidate),
  cf: false, compatibilityDate: '2025-05-01', compatibilityFlags: [],
  d1Databases: { DB: 'novatube4k-panel-fixture' },
  durableObjects: { RT_HUB: { className: 'RealtimeHub', useSQLite: true } },
  bindings: { ADMIN_SECRET: adminSecret, SECRETS_KEY: randomBytes(32).toString('hex'),
    ACCOUNT_ENCRYPTION_KEY: randomBytes(32).toString('hex'), DEVICE_TOKEN_SECRET: randomBytes(32).toString('hex'),
    GOLD_PANEL_API_KEY: 'fixtureOnlyNoRemoteRequest123456', DEFAULT_SERVERS: '[]', PANEL_ORIGINS: 'https://atlas-console-k7q2.vercel.app' },
  outboundService: async (request) => {
    const url = new URL(request.url); outbound.push({ host: url.host, path: url.pathname });
    return Response.json({ error: 'fixture_external_network_denied' }, { status: 503 });
  },
  log: new Log(LogLevel.WARN),
});
async function step(name, run) { current = name; const result = await run(); passed++; console.log('PASS ' + name); return result; }
async function api(method, path, { token, body, text, headers = {} } = {}) {
  const h = { 'content-type': 'application/json', 'cf-connecting-ip': '192.0.2.84', 'cf-ipcountry': 'FR', ...headers };
  if (token) h.authorization = 'Bearer ' + token;
  const response = await mf.dispatchFetch('https://fixture.test' + path, { method, headers: h,
    body: text ?? (body === undefined ? undefined : JSON.stringify(body)) });
  const raw = await response.text(); let data;
  try { data = JSON.parse(raw); } catch { data = null; }
  return { status: response.status, data, raw, headers: response.headers };
}
function device(action, body = {}, key = KEY, raw = RAW) {
  return api('POST', '/api/novatube4k/' + action, { body: { raw_mac: raw, ...body }, headers: { 'X-Device-Key': key } });
}
function status(r, expected) { assert.equal(r.status, expected, 'HTTP status; error=' + (r.data?.error || 'none')); }

try {
  console.log(JSON.stringify({ runtime: 'workerd', compatibility_date: '2025-05-01', compatibility_flags: [],
    candidate, candidate_sha256: createHash('sha256').update(readFileSync(candidate)).digest('hex'), external_network: 'intercepted and denied' }));
  await mf.ready;
  const db = await mf.getD1Database('DB');
  await step('schéma local et Durable Object réels', async () => {
    for (const sql of readFileSync(join(here, 'schema.sql'), 'utf8').split(/;\s*(?:\n|$)/)
      .map((s) => s.replace(/^\s*--.*$/gm, '').trim()).filter(Boolean)) await db.prepare(sql).run();
    try { await db.prepare('ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT').run(); } catch (_) {}
    assert.ok(await mf.getDurableObjectNamespace('RT_HUB'));
  });
  await step('panel et diagnostic inconnus refusés sans enrôlement', async () => {
    status(await device('panel'), 401); status(await device('blackbox', { text: 'fixture' }), 401);
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM devices').first()).n, 0);
  });
  const [mac, secondMac] = await step('deux inscriptions inactives sans essai', async () => {
    const a = await device('register'), b = await device('register', {}, KEY2, RAW2);
    status(a, 200); status(b, 200); assert.equal(a.data.active, false); assert.equal(b.data.active, false);
    status(await device('panel', {}, KEY2), 401);
    return [a.data.mac, b.data.mac];
  });
  await step('présence, inventaire expurgé et inconnus null sans accès licence', async () => {
    const r = await device('panel', { appVersion: '334.2.fixture', appBuild: Math.floor(Date.now() / 1000),
      platform: 'tv', model: 'Fixture API23', channel: 'Canal fixture', quality: null,
      sources: [{ type: 'm3u', name: 'Liste Atlas M3U', active: true }], recent: ['channel-1'] });
    status(r, 200); assert.equal(r.data.telemetry_ok, true); assert.equal(r.data.commands_ok, true);
    const row = await db.prepare('SELECT local_sources_json FROM devices WHERE mac=?').bind(mac).first();
    assert.equal(JSON.parse(row.local_sources_json)[0].channels, null);
    assert.equal((await db.prepare('SELECT quality FROM presence WHERE mac=?').bind(mac).first()).quality, null);
    assert.equal((await device('state')).data.active, false);
    assert.equal((await db.prepare('SELECT channel FROM presence WHERE mac=?').bind(mac).first()).channel, 'Canal fixture');
  });
  const token = await step('JWT admin et origine contrôlés par le Worker exact', async () => {
    const login = await api('POST', '/api/v1/auth/login', { body: { email: 'admin', password: adminSecret } });
    status(login, 200); assert.ok(login.data.token);
    status(await api('GET', '/api/v1/insights'), 401);
    status(await api('GET', '/api/v1/insights', { token: login.data.token, headers: { Origin: 'https://untrusted.test' } }), 403);
    return login.data.token;
  });
  await step('Analyses disponible et inscription inactive non comptée comme vente', async () => {
    const r = await api('GET', '/api/v1/insights', { token }); status(r, 200);
    assert.equal(r.data.money.newPaid30, 0); assert.equal(r.data.money.paidExpired, 0);
  });
  await step('configuration plateforme, etag, URL APK dédiée, aucun build Flutter écrit', async () => {
    status(await api('PUT', '/api/v1/theme?platform=tv', { token, body: { accent: '#125ACD', bg: 'dark', appName: 'Nom historique' } }), 200);
    const r = await device('panel'); status(r, 200); assert.deepEqual(r.data.config_errors, []);
    assert.equal(r.data.config.theme.accent, '#125ACD'); assert.equal(r.data.config_scope, 'platform');
    assert.equal(r.data.config.app_version.download_url, 'https://novatube4k-apk.vercel.app/');
    assert.equal(Number(r.data.config.app_version.latestBuildTs || 0), 0);
    const cached = await device('panel', { config_etag: r.data.config_etag });
    assert.equal(cached.data.config_unchanged, true); assert.equal(cached.data.config, undefined);
  });
  let cursor = 0;
  await step('attente longue authentifiée réveillée par mutation globale en moins de deux secondes', async () => {
    const backlog = await device('wait', { after: 0, timeout: 200 }); status(backlog, 200);
    cursor = Math.max(0, ...backlog.data.events.map((e) => e.seq));
    const start = Date.now();
    const waiting = device('wait', { after: cursor, timeout: 20000 });
    const saved = await api('POST', '/api/v1/featured', { token, body: { name: 'Canal fixture', note: 'Événement fixture' } }); status(saved, 200);
    const wake = await waiting; status(wake, 200); assert.equal(wake.data.timeout, false);
    assert.ok(wake.data.events.some((e) => e.type === 'featured' && e.mac === mac));
    assert.ok(Date.now() - start < 2000);
    cursor = Math.max(cursor, ...wake.data.events.map((e) => e.seq));
  });
  await step('demande boîte noire réveille, remonte et filtre avant affichage panel', async () => {
    const waiting = device('wait', { after: cursor, timeout: 20000 });
    const ask = await api('POST', '/api/v1/blackbox/' + encodeURIComponent(mac) + '/ask', { token, body: {} }); status(ask, 200);
    const wake = await waiting; status(wake, 200); assert.equal(wake.data.timeout, false);
    assert.equal((await device('panel')).data.blackbox_pull, ask.data.requested_at);
    const sent = await device('blackbox', { text: 'TV READY\nhttps://secret.test/user/password/42.ts\nX-Device-Key=' + KEY + '\nraw_mac=' + RAW });
    status(sent, 200); assert.ok(sent.data.updated_at > 0);
    const journal = await api('GET', '/api/v1/blackbox/' + encodeURIComponent(mac), { token }); status(journal, 200);
    assert.ok(journal.data.text.includes('TV READY'));
    for (const secret of [KEY, RAW, 'secret.test']) assert.ok(!journal.raw.includes(secret));
    status(await api('POST', '/api/blackbox', { body: { mac, text: 'spoof' } }), 401);
  });
  const activation = await step('activation fixture sans Gold ; ordre réellement délivré puis confirmé', async () => {
    const r = await api('POST', '/api/v1/activate', { token, body: { mac, plan: 'yearly', app_id: 'app_7motion' } }); status(r, 201);
    assert.ok(r.data.order_id);
    const early = await device('orders-ack', { orders: [{ order_id: r.data.order_id, state: 'applied' }] });
    assert.equal(early.data.results[0].status, 404);
    const panel = await device('panel'); assert.ok(panel.data.commands.some((order) => order.order_id === r.data.order_id));
    const received = await device('orders-ack', { orders: [{ order_id: r.data.order_id, state: 'received', received_at: Date.now() }] });
    assert.equal(received.data.results[0].status, 200);
    const applied = await device('orders-ack', { orders: [{ order_id: r.data.order_id, state: 'applied', result: 'license_synced', applied_at: Date.now() }] });
    assert.equal(applied.data.results[0].status, 200);
    return r.data;
  });
  const pushed = await step('source reste protégée par ACK de révision et retour partiel explicite', async () => {
    const r = await api('PUT', '/api/v1/sources/' + encodeURIComponent(mac), { token,
      body: { sources: [{ type: 'm3u', m3u_url: 'https://fixture.test/list.m3u?token=fixture-only' }] } }); status(r, 200);
    await device('panel');
    const wrong = await device('orders-ack', { orders: [{ order_id: r.data.order_id, state: 'applied' }] });
    assert.equal(wrong.data.results[0].status, 409);
    const cross = await device('orders-ack', { orders: [{ order_id: r.data.order_id, state: 'received' }] }, KEY2, RAW2);
    assert.equal(cross.data.results[0].status, 404);
    const state = await device('state'); status(state, 200); assert.equal(state.data.sources.length, 1);
    const ack = await device('ack', { source_rev: state.data.source_rev, applied: true }); status(ack, 200);
    assert.equal((await db.prepare('SELECT state FROM box_orders WHERE order_id=?').bind(r.data.order_id).first()).state, 'applied');
    return r.data;
  });
  await step('feedback et sauvegarde limités à la clé, secret d’installation refusé', async () => {
    status(await device('feedback', { rating: 5, message: 'Lecture fixture', mac: secondMac }), 200);
    const feedback = await db.prepare('SELECT mac FROM feedback').first(); assert.equal(feedback.mac, mac);
    status(await device('backup', { op: 'put', data: { deviceKey: KEY } }), 400);
    status(await device('backup', { op: 'put', data: { favorites: ['channel-1'] } }), 200);
    assert.deepEqual((await device('backup', { op: 'get' })).data.data, { favorites: ['channel-1'] });
    status(await device('backup', { op: 'get' }, KEY2, RAW2), 403);
  });
  await step('limites de corps refusées sans promesse bloquante', async () => {
    status(await device('panel', { extra: 'x'.repeat(20000) }), 413);
    status(await device('blackbox', { text: 'x'.repeat(270000) }), 413);
  });
  await step('transfert atomique vers enrôlement vierge, temps et clés préservés', async () => {
    const before = await db.prepare('SELECT raw_mac,mac,device_id,device_key_hash FROM novatube4k_devices ORDER BY raw_mac').all();
    const body = { old_mac: mac, new_mac: secondMac };
    status(await api('POST', '/api/v1/transfer', { body }), 401);
    const transferred = await api('POST', '/api/v1/transfer', { token, body }); status(transferred, 200);
    assert.equal(transferred.data.moved_licenses, 1);
    const after = await db.prepare('SELECT raw_mac,mac,device_id,device_key_hash FROM novatube4k_devices ORDER BY raw_mac').all();
    assert.deepEqual(after.results, before.results);
    assert.equal((await device('state')).data.active, false);
    const state = await device('state', {}, KEY2, RAW2); assert.equal(state.data.active, true);
    assert.equal(state.data.expires_at, activation.expires_at); assert.equal(state.data.sources.length, 1);
    assert.ok(state.data.source_rev > 0);
    status(await api('POST', '/api/v1/transfer', { token, body }), 409);
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM credit_ledger').first()).n, 0);
  });
  await step('remise à neuf garde licence et clé ; source effacée et signal reset remonté', async () => {
    const reset = await api('POST', '/api/v1/sources/' + encodeURIComponent(secondMac) + '/reset', { token, body: {} }); status(reset, 200);
    const state = await device('state', {}, KEY2, RAW2); status(state, 200);
    assert.equal(state.data.active, true); assert.ok(state.data.reset_at > 0); assert.deepEqual(state.data.sources, []);
    const panel = await device('panel', {}, KEY2, RAW2);
    assert.equal(panel.data.reset_at, state.data.reset_at); assert.ok(panel.data.commands.some((order) => order.kind === 'reset'));
  });
  await step('essai manuel refuse payé/inactif et prolonge seulement un essai préexistant de fixture', async () => {
    status(await api('POST', '/api/v1/trial-extend', { token, body: { mac, days: 2 } }), 409);
    status(await api('POST', '/api/v1/trial-extend', { token, body: { mac: secondMac, days: 2 } }), 409);
    const until = Date.now() + 86400000;
    await db.prepare("UPDATE licenses SET status='active',plan='trial7',expires_at=? WHERE app_id='app_novatube4k'").bind(until).run();
    const extended = await api('POST', '/api/v1/trial-extend', { token, body: { mac: secondMac, days: 2 } }); status(extended, 200);
    assert.equal(extended.data.previous_until, until); assert.equal(extended.data.trial_until, until + 2 * 86400000);
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM trial_extensions').first()).n, 1);
  });
  await step('bouton global historique inchangé : prolongation existante, aucun enrôlement ni coût', async () => {
    const r = await api('POST', '/api/v1/grant-trial-all', { token, body: { days: 7 } }); status(r, 200);
    assert.equal(r.data.updated, 1); assert.equal((await device('state')).data.active, false);
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM credit_ledger').first()).n, 0);
  });
  await step('routes publiques MAC protégées et compteurs licence/coût sans fuite', async () => {
    for (const path of ['/api/device-source/', '/api/status/', '/api/history/', '/api/backup/']) status(await api('GET', path + secondMac), 401);
    assert.equal((await db.prepare("SELECT COUNT(*) n FROM licenses WHERE app_id='app_novatube4k'").first()).n, 1);
    assert.equal(outbound.length, 0);
  });
  console.log(JSON.stringify({ ok: true, passed, outbound_requests: outbound.length, fixture_only: true }));
} catch (error) {
  console.error(JSON.stringify({ ok: false, passed, failed_step: current, error: String(error.message || error) }));
  process.exitCode = 1;
} finally { await mf.dispose(); }
