// Contrats owner privés, outbox transactionnelle et diagnostics de fixture.
// Aucun navigateur ni service Push réel n'est inscrit ou appelé.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createD1, fakeRealtimeHub } from './test_support/d1_sqlite.mjs';
import { ensurePanelAlertsSchema, collectConfirmedOrderFailures, panelAlertPayload } from './panel-alerts.js';
import { validatePanelPushEndpoint } from './panel-alerts-api.js';
import { parseConfirmedNovatubeIncidents, collectNovatubeBlackboxIncidents } from './panel-alerts-blackbox.js';

const entry = await import(process.env.PANEL_ALERTS_TEST_ENTRY
  ? pathToFileURL(resolve(process.env.PANEL_ALERTS_TEST_ENTRY)).href : new URL('./novatube4k-entry.js', import.meta.url).href);
const ROOT = '/api/v1/panel-alerts', RAW = 'AABBCCDDEE91', KEY = 'a9'.repeat(32);
const pair = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
const PUBLIC = Buffer.from(await crypto.subtle.exportKey('raw', pair.publicKey)).toString('base64url');
const AUTH = Buffer.alloc(16, 19).toString('base64url');
const PREFS = { enabled: true, types: { new_device: true, activation: true, problem: true } };
const subscription = (n = 1) => ({ endpoint: 'https://fcm.googleapis.com/fcm/send/fixture-' + n,
  keys: { p256dh: PUBLIC, auth: AUTH }, expirationTime: null, label: 'Téléphone fixture', permission: 'granted', consent: true });

async function fixture(t, jitterMs = 0) {
  const { DB, db, faults } = createD1({ jitterMs, extraSql: ['ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT'] });
  const env = { DB, ADMIN_SECRET: crypto.randomUUID(), SECRETS_KEY: crypto.randomUUID(),
    ACCOUNT_ENCRYPTION_KEY: crypto.randomUUID(), DEVICE_TOKEN_SECRET: crypto.randomUUID(),
    DEFAULT_SERVERS: '[]', PANEL_PUSH_PUBLIC_KEY: PUBLIC, PANEL_ORIGINS: 'https://panel.fixture.test' };
  env.RT_HUB = fakeRealtimeHub(env, entry.RealtimeHub);
  const pending = [], outbound = [];
  const ctx = { waitUntil(p) { pending.push(Promise.resolve(p)); }, passThroughOnException() {} };
  t.mock.method(globalThis, 'fetch', async () => { outbound.push(true); return new Response('fixture external denied', { status: 503 }); });
  async function drain() { while (pending.length) await Promise.all(pending.splice(0)); }
  async function api(method, path, { token, body, text, headers = {} } = {}) {
    const h = { 'content-type': 'application/json', 'cf-connecting-ip': '192.0.2.91', ...headers };
    if (token) h.authorization = 'Bearer ' + token;
    const response = await entry.default.fetch(new Request('https://fixture.test' + path, {
      method, headers: h, body: text ?? (body === undefined ? undefined : JSON.stringify(body)),
    }), env, ctx);
    const raw = await response.text(); let json;
    try { json = JSON.parse(raw); } catch { json = null; }
    await drain(); return { status: response.status, json, raw, headers: response.headers };
  }
  async function login(email = 'admin') {
    const r = await api('POST', '/api/v1/auth/login', { body: { email, password: env.ADMIN_SECRET } });
    assert.equal(r.status, 200); return r.json.token;
  }
  const token = await login();
  const claims = JSON.parse(Buffer.from(token.split('.')[1], 'base64url'));
  async function secondOwner() {
    const id = 'adm_fixture_second', email = 'second@example.test';
    db.prepare(`INSERT INTO admin_users(id,email,password_hash,name,role,is_active,created_at)
      SELECT ?,?,password_hash,'Fixture2','super_admin',1,? FROM admin_users WHERE id=?`)
      .run(id, email, Date.now(), claims.sub);
    return { id, token: await login(email) };
  }
  async function device(action = 'register', body = {}, key = KEY) {
    return api('POST', '/api/novatube4k/' + action, { body: { raw_mac: RAW, ...body }, headers: { 'X-Device-Key': key } });
  }
  async function register() { const r = await device(); assert.equal(r.status, 200); return r.json.mac; }
  async function prefs(value = PREFS, useToken = token) {
    return api('PUT', ROOT + '/preferences', { token: useToken, body: value });
  }
  function subscribe(body = subscription(), useToken = token) {
    return api('POST', ROOT + '/subscriptions', { token: useToken, body });
  }
  function events() { return db.prepare('SELECT * FROM panel_alert_events ORDER BY seq').all().map((r) => ({ ...r })); }
  await ensurePanelAlertsSchema(env);
  t.after(async () => { await drain(); assert.deepEqual(outbound, [], 'aucun envoi Push ou fournisseur'); db.close(); });
  return { env, DB, db, faults, api, token, claims, login, secondOwner, device, register, prefs, subscribe, events };
}

test('endpoints Push bornés : seulement services connus, aucun SSRF ni redirect fourni', () => {
  for (const url of ['https://fcm.googleapis.com/fcm/send/token:fixture', 'https://fcm.googleapis.com/wp/token',
    'https://updates.push.services.mozilla.com/wpush/v2/token', 'https://web.push.apple.com/Qfixture']) assert.equal(validatePanelPushEndpoint(url), true);
  for (const url of ['http://fcm.googleapis.com/fcm/send/token', 'https://localhost/fcm/send/token',
    'https://127.0.0.1/fcm/send/token', 'https://fcm.googleapis.com.evil.test/fcm/send/token',
    'https://user:pass@fcm.googleapis.com/fcm/send/token', 'https://fcm.googleapis.com:8443/fcm/send/token',
    'https://fcm.googleapis.com/fcm/send/token?redirect=https://evil.test', 'https://fcm.googleapis.com/fcm/send/token#secret',
    'https://fcm.googleapis.com/anything', 'https://notify.windows.com/w/?token=unverified']) assert.equal(validatePanelPushEndpoint(url), false);
});

test('préférences désactivées par défaut, clé publique seule et session réelle obligatoire', async (t) => {
  const f = await fixture(t);
  const r = await f.api('GET', ROOT + '/preferences', { token: f.token });
  assert.equal(r.status, 200); assert.equal(r.json.enabled, false); assert.deepEqual(r.json.types, PREFS.types);
  assert.equal(r.json.public_key, PUBLIC); assert.equal(r.json.push_available, true);
  const noSid = { ...f.claims }; delete noSid.sid;
  const input = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url') + '.' + Buffer.from(JSON.stringify(noSid)).toString('base64url');
  const legacy = input + '.' + createHmac('sha256', f.env.ADMIN_SECRET).update(input).digest('base64url');
  assert.equal((await f.api('GET', '/api/v1/auth/me', { token: legacy })).status, 200);
  assert.equal((await f.api('GET', ROOT + '/preferences', { token: legacy })).json.error, 'session_required');
  delete f.env.PANEL_PUSH_PUBLIC_KEY;
  const missing = await f.api('GET', ROOT + '/preferences', { token: f.token });
  assert.equal(missing.json.push_available, false); assert.equal(missing.json.public_key, null);
});

test('auth historique, origine, rôle courant et révocation de session protègent toutes les routes', async (t) => {
  const f = await fixture(t);
  for (const path of ['/preferences','/events','/subscriptions']) {
    assert.equal((await f.api('GET', ROOT + path)).status, 401);
    assert.equal((await f.api('GET', ROOT + path, { token: f.token, headers: { Origin: 'https://evil.test' } })).status, 403);
  }
  for (const role of ['admin', 'support']) {
    f.db.prepare('UPDATE admin_users SET role=? WHERE id=?').run(role, f.claims.sub);
    assert.equal((await f.api('GET', ROOT + '/events', { token: f.token })).status, 403);
    assert.equal((await f.subscribe()).status, 403);
  }
  f.db.prepare("UPDATE admin_users SET role='super_admin' WHERE id=?").run(f.claims.sub);
  f.db.prepare('DELETE FROM auth_sessions WHERE id=?').run(f.claims.sid);
  assert.equal((await f.api('GET', ROOT + '/events', { token: f.token })).status, 401);
});

test('consentement compte et navigateur explicite, clés sur courbe et expiration de session', async (t) => {
  const f = await fixture(t);
  assert.equal((await f.subscribe()).json.error, 'consent_required');
  assert.equal((await f.prefs()).status, 200);
  for (const body of [{ ...subscription(), consent: false }, { ...subscription(), permission: 'denied' }]) {
    assert.equal((await f.subscribe(body)).json.error, 'consent_required');
  }
  const badPoint = Buffer.concat([Buffer.from([4]), Buffer.alloc(64)]).toString('base64url');
  for (const body of [{ ...subscription(), keys: { auth: AUTH, p256dh: badPoint } },
    { ...subscription(), keys: { auth: 'bad', p256dh: PUBLIC } }, { ...subscription(), expirationTime: Date.now() - 1 }]) {
    assert.equal((await f.subscribe(body)).json.error, 'invalid_subscription');
  }
  const r = await f.subscribe(); assert.equal(r.status, 201); assert.equal(r.json.delivery_confirmed, false);
  assert.equal(r.json.expires_at, f.db.prepare('SELECT expires_at FROM auth_sessions WHERE id=?').get(f.claims.sid).expires_at);
  assert.ok(r.json.consented_at > 0);
});

test('liste des abonnements et audit ne révèlent endpoint, auth, p256dh ou session_id', async (t) => {
  const f = await fixture(t); await f.prefs(); const made = await f.subscribe();
  const listed = await f.api('GET', ROOT + '/subscriptions', { token: f.token });
  assert.equal(listed.status, 200); assert.equal(listed.json.items[0].id, made.json.id);
  assert.equal(listed.json.items[0].current_session, true);
  const audit = JSON.stringify(f.db.prepare("SELECT after_json FROM audit_logs WHERE action='panel.push.subscribe'").all());
  for (const secret of [subscription().endpoint, AUTH, PUBLIC, f.claims.sid]) {
    assert.ok(!listed.raw.includes(secret)); assert.ok(!audit.includes(secret));
  }
});

test('souscriptions concurrentes même endpoint retrouvent un ID réel ; plafond atomique de cinq', async (t) => {
  const f = await fixture(t, 2); await f.prefs();
  const twins = await Promise.all([f.subscribe(), f.subscribe()]);
  assert.equal(new Set(twins.map((r) => r.json.id)).size, 1);
  assert.equal(f.db.prepare('SELECT COUNT(*) n FROM panel_push_subscriptions').get().n, 1);
  const extra = await Promise.all(Array.from({ length: 6 }, (_, n) => f.subscribe(subscription(n + 2))));
  assert.equal(extra.filter((r) => r.status < 300).length, 4);
  assert.equal(extra.filter((r) => r.status === 409).length, 2);
  assert.equal(f.db.prepare('SELECT COUNT(*) n FROM panel_push_subscriptions WHERE enabled=1').get().n, 5);
});

test('aucune prise de souscription d’un autre owner, lectures propres et révocation idempotente', async (t) => {
  const f = await fixture(t); await f.prefs(); const sub = await f.subscribe(); const second = await f.secondOwner();
  await f.prefs(PREFS, second.token);
  assert.equal((await f.subscribe(subscription(), second.token)).json.error, 'subscription_conflict');
  assert.deepEqual((await f.api('GET', ROOT + '/subscriptions', { token: second.token })).json.items, []);
  assert.equal((await f.api('DELETE', ROOT + '/subscriptions/' + sub.json.id, { token: second.token })).status, 404);
  assert.equal((await f.api('DELETE', ROOT + '/subscriptions/' + sub.json.id, { token: f.token })).status, 200);
  assert.equal((await f.api('DELETE', ROOT + '/subscriptions/' + sub.json.id, { token: f.token })).status, 200);
  assert.equal(f.db.prepare('SELECT enabled FROM panel_push_subscriptions').get().enabled, 0);
});

test('échec audit opt-in : souscription non engagée, aucun faux succès', async (t) => {
  const f = await fixture(t); await f.prefs();
  f.faults.add({ match: /INSERT INTO audit_logs[\s\S]*panel\.push\.subscribe/, times: 1, when: 'after' });
  assert.equal((await f.subscribe()).status, 503);
  assert.equal(f.db.prepare('SELECT COUNT(*) n FROM panel_push_subscriptions').get().n, 0);
});

test('réactivation d’une catégorie relève enabled_at et corps incomplets rejetés sans journal privé', async (t) => {
  const f = await fixture(t); await f.prefs({ enabled: true, types: { ...PREFS.types, problem: false } });
  f.db.prepare('UPDATE panel_alert_preferences SET enabled_at=1').run();
  assert.equal((await f.prefs()).status, 200);
  assert.ok(f.db.prepare('SELECT enabled_at FROM panel_alert_preferences').get().enabled_at > 1);
  for (const value of [{ enabled: true }, { ...PREFS, types: { ...PREFS.types, secret: 'must-not-store' } },
    { ...PREFS, types: { ...PREFS.types, problem: 1 } }]) assert.equal((await f.prefs(value)).status, 400);
  assert.equal((await f.api('PUT', ROOT + '/preferences', { token: f.token, text: 'x'.repeat(8193) })).status, 413);
  assert.ok(!JSON.stringify(f.db.prepare('SELECT * FROM audit_logs').all()).includes('must-not-store'));
});

test('nouvel enrôlement atomique une seule fois, licence inactive sans fausse activation', async (t) => {
  const f = await fixture(t), mac = await f.register(); await f.register();
  const events = f.events(); assert.equal(events.length, 1); assert.equal(events[0].type, 'new_device');
  assert.equal(events[0].mac, mac); assert.equal(events[0].url, '/devices?mac=' + mac);
  assert.ok(!JSON.stringify(events).includes(RAW)); assert.ok(!JSON.stringify(events).includes(KEY));
});

test('activation engagée avec ou sans Idempotency-Key, renouvellement, no-op lifetime dédupliqué', async (t) => {
  const f = await fixture(t), mac = await f.register();
  const body = { mac, plan: 'yearly' }, headers = { 'Idempotency-Key': 'fixture-owner-alert-idem-001' };
  assert.equal((await f.api('POST', '/api/v1/activate', { token: f.token, body, headers })).status, 201);
  assert.equal((await f.api('POST', '/api/v1/activate', { token: f.token, body, headers })).status, 201);
  assert.equal(f.events().filter((r) => r.type === 'activation').length, 1);
  assert.equal((await f.api('POST', '/api/v1/activate', { token: f.token, body })).status, 201);
  assert.equal(f.events().filter((r) => r.type === 'activation').length, 2);
  const id = f.db.prepare('SELECT id FROM licenses').get().id;
  assert.equal((await f.api('POST', '/api/v1/licenses/' + id + '/renew', { token: f.token, body: { plan: 'yearly' } })).status, 200);
  assert.equal(f.events().filter((r) => r.type === 'activation').length, 3);
  assert.equal((await f.api('POST', '/api/v1/activate', { token: f.token, body: { mac, plan: 'lifetime' } })).status, 201);
  assert.equal((await f.api('POST', '/api/v1/activate', { token: f.token, body: { mac, plan: 'lifetime' } })).status, 200);
  assert.equal(f.events().filter((r) => r.type === 'activation').length, 4);
});

test('rollback de transaction annule aussi l’alerte et SQL changes() garde sa sémantique', async (t) => {
  const f = await fixture(t), mac = await f.register();
  const licence = f.db.prepare('SELECT * FROM licenses').get();
  await assert.rejects(f.DB.batch([
    f.DB.prepare("UPDATE licenses SET status='active',expires_at=?,updated_at=? WHERE id=?").bind(Date.now()+5000, Date.now(), licence.id),
    f.DB.prepare('INSERT INTO fixture_missing_table VALUES(1)'),
  ]));
  assert.equal(f.db.prepare('SELECT status FROM licenses').get().status, 'inactive');
  assert.equal(f.events().filter((r) => r.type === 'activation').length, 0);
  const result = await f.DB.batch([
    f.DB.prepare("UPDATE licenses SET status='active',expires_at=?,updated_at=? WHERE id=?").bind(Date.now()+5000, Date.now(), licence.id),
    f.DB.prepare('SELECT changes() n'),
  ]);
  assert.equal(result[1].results[0].n, 1); assert.equal(f.events().filter((r) => r.type === 'activation').length, 1);
  assert.equal(f.events()[0].mac, mac);
});

test('inbox durable paginée et lecture propre à chaque owner', async (t) => {
  const f = await fixture(t); await f.register(); const second = await f.secondOwner();
  const first = await f.api('GET', ROOT + '/events', { token: f.token });
  assert.equal(first.json.items.length, 1); assert.equal(first.json.unread_count, 1);
  const id = first.json.items[0].event_id;
  assert.equal((await f.api('POST', ROOT + '/read', { token: f.token, body: { event_ids: [id,id] } })).json.updated, 1);
  assert.equal((await f.api('GET', ROOT + '/events?after=' + first.json.next_cursor, { token: f.token })).json.items.length, 0);
  assert.equal((await f.api('GET', ROOT + '/events', { token: f.token })).json.unread_count, 0);
  assert.equal((await f.api('GET', ROOT + '/events', { token: second.token })).json.unread_count, 1);
  assert.equal((await f.api('GET', ROOT + '/events?after=-1', { token: f.token })).status, 400);
});

test('demande recovery récente dédupliquée, aucun code/hash/MAC brute dans l’alerte', async (t) => {
  const f = await fixture(t), mac = await f.register();
  // Création du schéma recovery comme dans un déploiement coordonné, puis
  // nouveau DB binding pour réévaluer les tables optionnelles sans délai.
  await f.device('register', {}, 'b8'.repeat(32));
  await ensurePanelAlertsSchema({ DB: { prepare: f.DB.prepare, batch: f.DB.batch } });
  f.db.prepare('DELETE FROM panel_alert_events WHERE type=\'problem\'').run();
  const a = await f.device('register', {}, 'c7'.repeat(32));
  const b = await f.device('register', {}, 'd6'.repeat(32));
  assert.equal(a.status, 409); assert.equal(b.status, 409);
  const problems = f.events().filter((r) => r.type === 'problem'); assert.equal(problems.length, 1);
  const text = JSON.stringify(problems);
  assert.ok(text.includes(mac));
  for (const secret of [RAW, KEY, a.json.recovery.code, b.json.recovery.code]) assert.ok(!text.includes(secret));
});

test('scan ACK borné, échec persisté unique ; ni expired ni absence de poll ni ancien incident', async (t) => {
  const f = await fixture(t), mac = await f.register(); await f.device('panel');
  const now = Date.now(), started = f.db.prepare('SELECT installed_at FROM panel_alert_meta').get().installed_at;
  for (const [id,state,time] of [['ord_fixture_failed','failed',now],['ord_fixture_expired','expired',now],['ord_fixture_old','failed',started-1]]) {
    f.db.prepare(`INSERT INTO box_orders(order_id,mac,kind,state,created_at,updated_at,failed_srv)
      VALUES(?,?,'restart',?,?,?,?)`).run(id,mac,state,now,now,time);
  }
  assert.equal((await collectConfirmedOrderFailures(f.env, now)).inserted, 1);
  assert.equal((await collectConfirmedOrderFailures(f.env, now)).inserted, 0);
  assert.equal(f.events().filter((r) => r.type === 'problem').length, 1);
});

function journal(mac, lines) { return 'NovaTube — journal de la box\nMAC Atlas : ' + mac + '\nÉvénements récents (UTC) :\n' + lines.join('\n') + '\n'; }
function stamp(time) { return new Date(time).toISOString().slice(0,19).replace('T',' '); }

test('parseur incidents strict : erreurs récentes fixes, succès ultérieur, horloge et journal ancien', () => {
  const now = Date.now(), mac = 'MK:11:22:33:44:55', line = (offset, code) => stamp(now + offset) + '  ' + code;
  const data = journal(mac, [line(-2000,'provider.http_auth'),line(-1000,'source.import_format')]);
  assert.equal(parseConfirmedNovatubeIncidents(data,mac,now).length,2);
  for (const text of [journal(mac,[line(-700000,'provider.http_auth')]),journal(mac,[line(70000,'provider.http_auth')]),
    journal(mac,[line(-1000,'source.import_cancelled')]),journal(mac,[line(-1000,'network.offline')]),
    journal(mac,[line(-1000,'player.state_2')]),journal(mac,[line(-1000,'provider.http_auth') + ' https://private.test']),
    journal(mac,[line(-2000,'provider.http_auth'),line(-1000,'xtream.authenticated')]),
    journal(mac,['2026-02-31 12:00:00  provider.http_auth'])]) assert.deepEqual(parseConfirmedNovatubeIncidents(text,mac,now),[]);
  assert.deepEqual(parseConfirmedNovatubeIncidents(data,'MK:11:22:33:44:56',now),[]);
});

test('journal authentifié enregistré : incident expurgé unique, mauvaise clé ou texte libre sans alerte', async (t) => {
  const f = await fixture(t), mac = await f.register(), now = Date.now();
  const text = journal(mac, [stamp(now-1000)+'  provider.reply_refused']);
  assert.equal((await f.device('blackbox', { text }, 'ff'.repeat(32))).status,401);
  assert.equal(f.events().filter((r)=>r.type==='problem').length,0);
  assert.equal((await f.device('blackbox', { text })).status,200);
  assert.equal((await f.device('blackbox', { text })).status,200);
  const events = f.events().filter((r)=>r.type==='problem'); assert.equal(events.length,1);
  assert.equal(events[0].url,'/blackbox?mac='+mac);
  assert.ok(!JSON.stringify(events).includes(RAW)); assert.ok(!JSON.stringify(events).includes('provider.reply_refused\n'));
  assert.equal((await f.device('blackbox', { text:'Connexion hors ligne, aucune preuve d’échec.' })).status,200);
  assert.equal(f.events().filter((r)=>r.type==='problem').length,1);
});

test('payload Push uniquement borné et liens internes, aucune URL fournisseur', () => {
  const valid = {event_id:'pae_fixture_1234',type:'problem',title:'Échec',message:'Échec signalé par la box.',url:'/blackbox?mac=MK:11:22:33:44:55'};
  assert.deepEqual(panelAlertPayload(valid),{v:1,...valid});
  for(const patch of [{url:'https://evil.test/devices?mac=MK:11:22:33:44:55'},
    {url:'/devices?mac=MK:11:22:33:44:55&token=secret'},{message:'https://private.test/u/p'},
    {title:'x'.repeat(97)},{event_id:'bad'},{url:'/devices?mac=MK:11:22:33:44:55#secret'}]) assert.equal(panelAlertPayload({...valid,...patch}),null);
});
