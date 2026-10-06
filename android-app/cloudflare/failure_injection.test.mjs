// =========================================================
//  failure_injection.test.mjs — Pannes injectées, concurrence, isolation
// =========================================================
//  node --experimental-sqlite cloudflare/failure_injection.test.mjs
//  Vrai Worker + vraie classe RealtimeHub + harnais D1 fidèle
//  (test_support/d1_sqlite.mjs) avec latence aléatoire par appel : des
//  requêtes lancées ensemble s'entrelacent à chaque accès base.
//
//  Chaque bloc nomme la panne injectée et l'état connu attendu après.
//  La vraie concurrence sur workerd + D1 local est dans concurrency.e2e.mjs.
// =========================================================
import worker, { RealtimeHub } from './worker.js';
import { createD1, fakeRealtimeHub } from './test_support/d1_sqlite.mjs';

const ctx = { waitUntil() {}, passThroughOnException() {} };
let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass += 1; console.log('PASS', m); }
  else { fail += 1; console.log('FAIL', m); }
};
const EXTRA = ['ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT'];

function makeEnv({ jitterMs = 0 } = {}) {
  const t = createD1({ extraSql: EXTRA, jitterMs });
  const env = { DB: t.DB, ADMIN_SECRET: crypto.randomUUID(), SECRETS_KEY: crypto.randomUUID() };
  env.RT_HUB = fakeRealtimeHub(env, RealtimeHub);
  return { env, db: t.db, faults: t.faults };
}

async function api(env, method, path, { token, body, headers: extra } = {}) {
  const headers = { 'content-type': 'application/json', ...(extra || {}) };
  if (token) headers.authorization = `Bearer ${token}`;
  const res = await worker.fetch(new Request(`https://app.test${path}`, {
    method, headers, body: body === undefined ? undefined : JSON.stringify(body),
  }), env, ctx);
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch (_) { json = null; }
  return { status: res.status, json, text, headers: res.headers };
}

async function login(env) {
  const r = await api(env, 'POST', '/api/v1/auth/login', { body: { email: 'admin', password: env.ADMIN_SECRET } });
  return r.json && r.json.token;
}

async function reseller(env, admin, credits) {
  const email = `r-${crypto.randomUUID()}@example.test`;
  const password = crypto.randomUUID();
  const c = await api(env, 'POST', '/api/v1/resellers', { token: admin, body: { email, password, name: 'R', credit_balance: credits } });
  await api(env, 'PATCH', `/api/v1/resellers/${c.json.id}`, { token: admin, body: { permissions: ['activate', 'devices', 'sources'] } });
  const l = await api(env, 'POST', '/api/v1/auth/reseller/login', { body: { email, password } });
  return { id: c.json.id, token: l.json.token };
}

const one = (db, sql, ...a) => db.prepare(sql).get(...a);
const debits = (db, rid) => one(db, "SELECT COUNT(*) AS n FROM credit_ledger WHERE reseller_id = ? AND reason IN ('activation','renew')", rid).n;
const balance = (db, rid) => one(db, 'SELECT credit_balance AS b FROM resellers WHERE id = ?', rid).b;
const licCount = (db, mac) => one(db, 'SELECT COUNT(*) AS n FROM licenses l JOIN devices d ON d.id = l.device_id WHERE d.mac = ?', mac).n;
const DAY = 24 * 3600 * 1000;

async function main() {
  // ===================== C. Idempotence sous panne =====================
  {
    const { env, db, faults } = makeEnv();
    const admin = await login(env);
    const r = await reseller(env, admin, 10);
    const MAC = 'MK:E0:00:00:00:01';

    // C1. Panne D1 AU MILIEU du lot d'activation (écriture de la licence).
    faults.add({ match: /INSERT INTO licenses/, when: 'before', error: new Error('injected: D1 write failed') });
    const key1 = crypto.randomUUID();
    const a = await api(env, 'POST', '/api/v1/activate', { token: r.token, body: { mac: MAC, plan: 'yearly' }, headers: { 'Idempotency-Key': key1 } });
    ok(a.status === 500, `C1. panne D1 dans le lot → 500 (${a.status})`);
    ok(licCount(db, MAC) === 0 && debits(db, r.id) === 0 && balance(db, r.id) === 10, 'C1. lot annulé en entier : ni licence, ni débit, solde intact');
    ok(!one(db, 'SELECT k FROM idempotency_keys WHERE k LIKE ?', `%${key1}`), 'C1. clé non engagée libérée');
    const a2 = await api(env, 'POST', '/api/v1/activate', { token: r.token, body: { mac: MAC, plan: 'yearly' }, headers: { 'Idempotency-Key': key1 } });
    ok(a2.status === 201 && debits(db, r.id) === 1 && licCount(db, MAC) === 1, 'C1. nouvelle tentative (même clé) : exécutée une fois, un débit');

    // C2. Processus mort APRÈS l'engagement, AVANT d'avoir gardé sa réponse.
    const MAC2 = 'MK:E0:00:00:00:02';
    const key2 = crypto.randomUUID();
    faults.add({ match: /UPDATE idempotency_keys SET status = \?, body_json = \? WHERE k = \?$/, when: 'before', error: new Error('injected: isolate killed') });
    const b = await api(env, 'POST', '/api/v1/activate', { token: r.token, body: { mac: MAC2, plan: 'yearly' }, headers: { 'Idempotency-Key': key2 } });
    ok(b.status === 500, `C2. mort après engagement → le client voit 500 (${b.status})`);
    const committed = one(db, 'SELECT committed_at, status, commit_ref FROM idempotency_keys WHERE k LIKE ?', `%${key2}`);
    ok(committed && committed.committed_at > 0 && committed.status === null, 'C2. marqueur d’engagement écrit DANS la transaction, réponse absente');
    ok(licCount(db, MAC2) === 1 && debits(db, r.id) === 2, 'C2. l’activation est bien engagée (1 licence, 1 débit de plus)');
    const b2 = await api(env, 'POST', '/api/v1/activate', { token: r.token, body: { mac: MAC2, plan: 'yearly' }, headers: { 'Idempotency-Key': key2 } });
    const ref = JSON.parse(committed.commit_ref);
    ok(b2.status === 201 && b2.headers.get('idempotent-replayed') === 'recovered' && b2.json.license_id === ref.license_id && b2.json.expires_at === ref.expires_at,
      'C2. rejeu : résultat engagé RETROUVÉ (même licence, même date), rien réexécuté');
    ok(debits(db, r.id) === 2 && licCount(db, MAC2) === 1, 'C2. toujours un seul débit pour cette activation');
    const b3 = await api(env, 'POST', '/api/v1/activate', { token: r.token, body: { mac: MAC2, plan: 'yearly' }, headers: { 'Idempotency-Key': key2 } });
    ok(b3.status === 201 && b3.headers.get('idempotent-replayed') === 'true' && b3.text === b2.text,
      'C2. rejeux suivants : la réponse reconstruite est gardée, octet pour octet identique');

    // C3. Réservation morte (processus tué AVANT tout engagement).
    const MAC3 = 'MK:E0:00:00:00:03';
    const key3 = crypto.randomUUID();
    const bodyText = JSON.stringify({ mac: MAC3, plan: 'yearly' });
    const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`activate\n${bodyText}`))))
      .map((x) => x.toString(16).padStart(2, '0')).join('');
    db.prepare('INSERT INTO idempotency_keys (k, actor_id, request_hash, status, body_json, created_at) VALUES (?, ?, ?, NULL, NULL, ?)')
      .run(`reseller:${r.id}:${key3}`, r.id, hash, Date.now() - 5 * 60 * 1000);
    const c = await worker.fetch(new Request('https://app.test/api/v1/activate', {
      method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${r.token}`, 'Idempotency-Key': key3 }, body: bodyText,
    }), env, ctx);
    ok(c.status === 201 && licCount(db, MAC3) === 1 && debits(db, r.id) === 3, 'C3. réservation morte sans engagement : reprise et exécutée une fois');
    // C4. Réservation récente : la jumelle est peut-être encore vivante.
    const key4 = crypto.randomUUID();
    db.prepare('INSERT INTO idempotency_keys (k, actor_id, request_hash, status, body_json, created_at) VALUES (?, ?, ?, NULL, NULL, ?)')
      .run(`reseller:${r.id}:${key4}`, r.id, hash, Date.now());
    const d = await worker.fetch(new Request('https://app.test/api/v1/activate', {
      method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${r.token}`, 'Idempotency-Key': key4 }, body: bodyText,
    }), env, ctx);
    ok(d.status === 409 && debits(db, r.id) === 3, 'C4. réservation récente : 409 « en cours », rien exécuté');
    // C5. Même clé, autre corps.
    const e = await api(env, 'POST', '/api/v1/activate', { token: r.token, body: { mac: MAC2, plan: 'lifetime' }, headers: { 'Idempotency-Key': key2 } });
    ok(e.status === 409 && e.json.error === 'idempotency_mismatch', 'C5. même clé, corps différent : rejet explicite');
  }

  // ===================== E. Accusés : doublon, inconnu, ancien, perdu, tardif =====================
  {
    const { env, db } = makeEnv();
    const admin = await login(env);
    const MAC = 'MK:E0:00:00:00:10';
    await api(env, 'POST', '/api/v1/activate', { token: admin, body: { mac: MAC, plan: 'yearly' } });
    const p1 = await api(env, 'PUT', `/api/v1/sources/${MAC}`, { token: admin, body: { sources: [{ type: 'm3u', m3u_url: 'http://a.example.test/l.m3u' }] } });
    const p2 = await api(env, 'PUT', `/api/v1/sources/${MAC}`, { token: admin, body: { sources: [{ type: 'm3u', m3u_url: 'http://b.example.test/l.m3u' }] } });
    const ackOne = (o) => api(env, 'POST', `/api/box/ack/${MAC}`, { body: { orders: [o] } });
    const now = Date.now();
    let r = await ackOne({ order_id: p2.json.order_id, state: 'applied', config_rev: 2, result: 'loaded', applied_at: now });
    ok(r.json.results[0].state === 'applied', 'E1. révision 2 appliquée');
    r = await ackOne({ order_id: p2.json.order_id, state: 'applied', config_rev: 2, result: 'loaded', applied_at: now + 5 });
    ok(r.json.results[0].changed === false, 'E2. accusé dupliqué : idempotent (changed: false)');
    r = await ackOne({ order_id: p2.json.order_id, state: 'failed', error_code: 'x' });
    ok(r.json.results[0].changed === false && one(db, 'SELECT state FROM box_orders WHERE order_id = ?', p2.json.order_id).state === 'applied',
      'E3. FAILED après APPLIED : transition impossible refusée');
    r = await ackOne({ order_id: 'ord_00000000-0000-0000-0000-000000000000', state: 'applied' });
    ok(r.json.results[0].status === 404, 'E4. accusé d’un ordre inconnu : 404 (et journalisé)');
    // Un ordre réel, accusé sur la route d'une AUTRE box : refusé, état intact.
    const before4b = one(db, 'SELECT state FROM box_orders WHERE order_id = ?', p1.json.order_id).state;
    const other = await api(env, 'POST', '/api/box/ack/MK:E0:00:00:00:11', { body: { orders: [{ order_id: p1.json.order_id, state: 'failed', error_code: 'x' }] } });
    ok(other.json.results[0].status === 404
      && one(db, 'SELECT state FROM box_orders WHERE order_id = ?', p1.json.order_id).state === before4b,
      `E4b. ordre d’une autre box : 404, état inchangé (${before4b})`);
    // Ancienne révision : l'ordre 1 (révision 1) accuse APRÈS la révision 2.
    r = await ackOne({ order_id: p1.json.order_id, state: 'applied', config_rev: 1, result: 'loaded', applied_at: now + 10 });
    const revs = await api(env, 'GET', `/api/v1/sources/${MAC}/revisions`, { token: admin });
    ok(revs.json.current_revision === 2 && revs.json.last_good_revision === 2
      && revs.json.revisions.find((x) => x.rev === 2).state === 'acknowledged',
      'E5. accusé tardif de la révision 1 : la révision 2 reste courante et dernière bonne');
    // Accusé perdu → EXPIRED ; accusé terminal tardif → APPLIED marqué late_ack.
    const p3 = await api(env, 'PUT', `/api/v1/sources/${MAC}`, { token: admin, body: { sources: [{ type: 'm3u', m3u_url: 'http://c.example.test/l.m3u' }] } });
    db.prepare('UPDATE box_orders SET created_at = ? WHERE order_id = ?').run(Date.now() - 20 * 60 * 1000, p3.json.order_id);
    const listed = await api(env, 'GET', `/api/v1/orders?mac=${MAC}`, { token: admin });
    ok(listed.json.items.find((o) => o.order_id === p3.json.order_id).state === 'expired', 'E6. accusé perdu : EXPIRED après le délai');
    r = await ackOne({ order_id: p3.json.order_id, state: 'received', received_at: Date.now() });
    ok(r.json.results[0].changed === false, 'E7. RECEIVED tardif ne relève pas un EXPIRED');
    r = await ackOne({ order_id: p3.json.order_id, state: 'applied', config_rev: 3, result: 'loaded', applied_at: Date.now() });
    const late = one(db, 'SELECT state, late_ack FROM box_orders WHERE order_id = ?', p3.json.order_id);
    ok(r.json.results[0].state === 'applied' && late.late_ack === 1, 'E8. APPLIED tardif : remplace EXPIRED, marqué late_ack');
    // Reconnexion : la box revenue lit les ordres manqués avec leur order_id.
    const w = await api(env, 'GET', `/api/box/wait/${MAC}?after=0&timeout=100`);
    const ids = (w.json.box || []).map((b) => b.order_id);
    ok([p1, p2, p3].every((p) => ids.includes(p.json.order_id)), 'E9. reconnexion avec ancien curseur : ordres manqués relivrés avec leur order_id');
    // E10. Limite de débit : l'attente longue épuisée sur une IP ne bloque
    // pas les accusés (seaux séparés, défaut trouvé par la mesure locale).
    const ip = { 'CF-Connecting-IP': '203.0.113.50' };
    let lastWait = 0;
    for (let i = 0; i < 61; i++) {
      lastWait = (await api(env, 'GET', `/api/box/wait/${MAC}?after=999999&timeout=1`, { headers: ip })).status;
    }
    const ackAfter = await api(env, 'POST', `/api/box/ack/${MAC}`, { headers: ip, body: { orders: [{ order_id: p1.json.order_id, state: 'received', received_at: Date.now() }] } });
    ok(lastWait === 429 && ackAfter.status === 200, `E10. 61e attente sur une IP → 429, accusé de la même IP → ${ackAfter.status} (seaux séparés)`);
  }

  // ===================== F. Écriture partielle des listes =====================
  {
    const { env, db, faults } = makeEnv();
    const admin = await login(env);
    const MAC = 'MK:E0:00:00:00:20';
    await api(env, 'POST', '/api/v1/activate', { token: admin, body: { mac: MAC, plan: 'yearly' } });
    const good = await api(env, 'PUT', `/api/v1/sources/${MAC}`, { token: admin, body: { sources: [{ type: 'm3u', m3u_url: 'http://bon.example.test/l.m3u' }] } });
    const before = one(db, 'SELECT version, sources_json FROM device_sources WHERE mac = ?', MAC);
    faults.add({ match: /INSERT INTO source_revisions/, when: 'before', error: new Error('injected: revision insert failed') });
    const bad = await api(env, 'PUT', `/api/v1/sources/${MAC}`, { token: admin, body: { sources: [{ type: 'm3u', m3u_url: 'http://neuf.example.test/l.m3u' }] } });
    const after = one(db, 'SELECT version, sources_json FROM device_sources WHERE mac = ?', MAC);
    ok(bad.status === 500 && after.version === before.version && after.sources_json === before.sources_json,
      'F1. panne entre liste et révision : lot annulé, l’ancienne liste reste servie');
    ok(one(db, 'SELECT COUNT(*) AS n FROM source_revisions WHERE mac = ?', MAC).n === 1, 'F1. aucune révision orpheline');
    const retry = await api(env, 'PUT', `/api/v1/sources/${MAC}`, { token: admin, body: { sources: [{ type: 'm3u', m3u_url: 'http://neuf.example.test/l.m3u' }] } });
    ok(retry.status === 200 && retry.json.rev === 2 && good.json.rev === 1, 'F2. nouvelle tentative : révision 2, numérotation continue');
  }

  // ===================== G. Plusieurs bases dans le même isolate =====================
  {
    for (const label of ['base 1', 'base 2', 'base 3']) {
      const { env, db } = makeEnv();
      const admin = await login(env);
      const MAC = 'MK:E0:00:00:00:30';
      const act = await api(env, 'POST', '/api/v1/activate', { token: admin, body: { mac: MAC, plan: 'yearly' }, headers: { 'Idempotency-Key': crypto.randomUUID() } });
      const put = await api(env, 'PUT', `/api/v1/sources/${MAC}`, { token: admin, body: { sources: [{ type: 'm3u', m3u_url: 'http://x.example.test/l.m3u' }] } });
      const bb = await api(env, 'POST', '/api/blackbox', { body: { mac: MAC, text: '06/10 10:00:00 I [TEST] ligne' } });
      const hb = await api(env, 'POST', '/api/heartbeat', { body: { mac: MAC, platform: 'tv' } });
      const tl = await api(env, 'GET', `/api/v1/timeline?q=${MAC}`, { token: admin });
      const tables = ['box_orders', 'source_revisions', 'idempotency_keys', 'device_blackbox', 'presence']
        .filter((t) => one(db, "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'table' AND name = ?", t).n === 1);
      const bbRow = one(db, 'SELECT COUNT(*) AS n FROM device_blackbox WHERE mac = ?', MAC).n;
      ok(act.status === 201 && put.status === 200 && put.json.rev === 1 && bb.status === 200 && bbRow === 1
        && hb.status === 200 && tl.status === 200 && tables.length === 5,
        `G. ${label} neuve dans le même isolate : activation ${act.status}, liste ${put.status} (rév. ${put.json.rev}), boîte noire ${bb.status} (${bbRow} ligne), présence ${hb.status}, tables créées ${tables.length}/5`);
    }
  }

  // ===================== B. Concurrence torture (en processus, latence aléatoire) =====================
  for (const n of [2, 10, 50, 100]) {
    const { env, db } = makeEnv({ jitterMs: 4 });
    const admin = await login(env);
    const r = await reseller(env, admin, 1000);
    // B1. Même clé ×n.
    const MAC = 'MK:F0:00:00:00:01';
    const key = crypto.randomUUID();
    const same = await Promise.all(Array.from({ length: n }, () => api(env, 'POST', '/api/v1/activate', {
      token: r.token, body: { mac: MAC, plan: 'yearly' }, headers: { 'Idempotency-Key': key },
    })));
    const executed = same.filter((x) => x.status === 201 && !x.headers.get('idempotent-replayed'));
    ok(executed.length === 1 && same.every((x) => x.status === 201 || x.status === 409) && debits(db, r.id) === 1 && licCount(db, MAC) === 1,
      `B1 n=${n}. même clé : 1 exécution, ${same.filter((x) => x.status === 409).length} « en cours », 1 débit, 1 licence`);
    // B2. Même renouvellement ×n (clés distinctes).
    const base = one(db, 'SELECT l.expires_at AS e FROM licenses l JOIN devices d ON d.id = l.device_id WHERE d.mac = ?', MAC).e;
    const ren = await Promise.all(Array.from({ length: n }, () => api(env, 'POST', '/api/v1/activate', {
      token: r.token, body: { mac: MAC, plan: 'yearly' }, headers: { 'Idempotency-Key': crypto.randomUUID() },
    })));
    const okRen = ren.filter((x) => x.status === 201).length;
    const end = one(db, 'SELECT l.expires_at AS e FROM licenses l JOIN devices d ON d.id = l.device_id WHERE d.mac = ?', MAC).e;
    ok(!ren.some((x) => x.status >= 500) && end === base + okRen * 365 * DAY && debits(db, r.id) === 1 + okRen && balance(db, r.id) === 1000 - 1 - okRen,
      `B2 n=${n}. renouvellements : ${okRen} succès = ${okRen} débits = ${okRen} × 365 j, aucune 5xx`);
    // B3. Même client neuf ×n.
    const MAC3 = 'MK:F0:00:00:00:02';
    const t0 = Date.now();
    const neu = await Promise.all(Array.from({ length: n }, () => api(env, 'POST', '/api/v1/activate', {
      token: r.token, body: { mac: MAC3, plan: 'yearly' }, headers: { 'Idempotency-Key': crypto.randomUUID() },
    })));
    const okNew = neu.filter((x) => x.status === 201).length;
    const devs = one(db, 'SELECT COUNT(*) AS n FROM devices WHERE mac = ?', MAC3).n;
    const orphans = one(db, 'SELECT COUNT(*) AS n FROM customers c WHERE NOT EXISTS (SELECT 1 FROM devices d WHERE d.customer_id = c.id)').n;
    const e3 = one(db, 'SELECT l.expires_at AS e FROM licenses l JOIN devices d ON d.id = l.device_id WHERE d.mac = ?', MAC3).e;
    ok(!neu.some((x) => x.status >= 500) && devs === 1 && licCount(db, MAC3) === 1 && orphans === 0
      && Math.abs((e3 - t0) / DAY - okNew * 365) < 1,
      `B3 n=${n}. client neuf : 1 appareil, 1 licence, 0 orphelin, durée = ${okNew} × 365 j`);
    // B4. Mêmes crédits : solde 3, n activations.
    const poor = await reseller(env, admin, 3);
    const many = await Promise.all(Array.from({ length: n }, (_, i) => api(env, 'POST', '/api/v1/activate', {
      token: poor.token, body: { mac: `MK:F1:00:00:${(i >> 8).toString(16).padStart(2, '0').toUpperCase()}:${(i & 255).toString(16).padStart(2, '0').toUpperCase()}`, plan: 'yearly' },
      headers: { 'Idempotency-Key': crypto.randomUUID() },
    })));
    const won = many.filter((x) => x.status === 201).length;
    ok(won === Math.min(3, n) && many.filter((x) => x.status === 402).length === n - won && balance(db, poor.id) === 3 - won && debits(db, poor.id) === won,
      `B4 n=${n}. crédits 3 : ${won} réussies, ${n - won} refus 402, solde ${balance(db, poor.id)} (jamais négatif)`);
    // B5. Listes : panel ×n en même temps que des ajouts client ×n.
    const MACL = 'MK:F0:00:00:00:03';
    const mixed = await Promise.all([
      ...Array.from({ length: n }, (_, i) => api(env, 'PUT', `/api/v1/sources/${MACL}`, { token: admin, body: { sources: [{ type: 'm3u', m3u_url: `http://p${i}.example.test/l.m3u` }] } })),
      ...Array.from({ length: Math.min(n, 3) }, (_, i) => api(env, 'POST', `/api/self-source/${MACL}`, { body: { type: 'm3u', m3u_url: `http://perso${i}.example.test/l.m3u`, label: `P${i}` } })),
    ]);
    const panelOk = mixed.slice(0, n).filter((x) => x.status === 200).length;
    const selfOk = mixed.slice(n).filter((x) => x.status === 200).length;
    const conflicts = mixed.filter((x) => x.status === 409).length;
    const row = one(db, 'SELECT version, sources_json FROM device_sources WHERE mac = ?', MACL);
    const items = JSON.parse(row.sources_json);
    const revs = db.prepare('SELECT rev FROM source_revisions WHERE mac = ? ORDER BY rev').all(MACL).map((x) => x.rev);
    const contiguous = revs.every((v, i) => v === i + 1);
    const lastRev = one(db, 'SELECT panel_json FROM source_revisions WHERE mac = ? ORDER BY rev DESC LIMIT 1', MACL);
    const panelNow = items.filter((s) => s.origin !== 'self').map((s) => s.m3u_url);
    const panelRev = JSON.parse(lastRev.panel_json).map((s) => s.m3u_url);
    ok(!mixed.some((x) => x.status >= 500) && items.filter((s) => s.origin === 'self').length === selfOk
      && row.version === panelOk + selfOk && revs.length === panelOk + selfOk && contiguous
      && JSON.stringify(panelNow) === JSON.stringify(panelRev),
      `B5 n=${n}. listes : ${panelOk} envois panel + ${selfOk} ajouts client réussis, ${conflicts} conflits 409 explicites ; `
      + `aucun ajout client perdu, version ${row.version}, révisions 1..${revs.length} continues, dernière révision = liste servie`);
  }

  // ---- H. Table créée par la route self-source (sans reseller_id / version) ----
  // Défaut du 06/10/2026 : le magasin CAS lisait `reseller_id`, colonne que
  // seule la route panel ajoutait. Base neuve, client seul → 500.
  {
    const t = createD1({ schema: false });
    const env = { DB: t.DB, SOURCE_ENCRYPTION_KEY: 'unit-test-source-key-32b' };
    const ctx = { waitUntil() {}, passThroughOnException() {} };
    const MACH = 'MK:0A:0B:0C:0D:0E';
    const post = (url) => worker.fetch(new Request(`https://app.x/api/self-source/${MACH}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: 'm3u', m3u_url: url }),
    }), env, ctx);
    const r1 = await post('http://h1.example.test/a.m3u');
    const r2 = await post('http://h2.example.test/b.m3u');
    const row = t.db.prepare('SELECT version, sources_json FROM device_sources WHERE mac = ?').get(MACH);
    ok(r1.status === 200 && r2.status === 200 && row && row.version === 2
      && JSON.parse(row.sources_json).length === 2,
      'H1. base neuve, aucune écriture panel : deux ajouts client → 200, 200, version 2, 2 listes');

    const { ensureSourcesVersion } = await import('./device_sources_store.js');
    const t2 = createD1({ schema: false });
    await ensureSourcesVersion({ DB: t2.DB });
    t2.db.exec('CREATE TABLE device_sources (mac TEXT PRIMARY KEY, type TEXT NOT NULL, label TEXT, server_url TEXT, username TEXT, password TEXT, m3u_url TEXT, epg_url TEXT, updated_at INTEGER NOT NULL)');
    await ensureSourcesVersion({ DB: t2.DB });
    const cols = t2.db.prepare('PRAGMA table_info(device_sources)').all().map((c) => c.name);
    ok(['sources_json', 'origin', 'reseller_id', 'version'].every((c) => cols.includes(c)),
      'H2. appelé AVANT la création de la table : pas marqué prêt, colonnes posées au tour suivant');
  }

  // ---- I. Serveurs par défaut : position allouée sous concurrence ----
  // Même motif que les révisions (lire MAX puis insérer) : deux créations
  // simultanées recevaient la même position.
  {
    const { env, db } = makeEnv({ jitterMs: 4 });
    const admin = await login(env);
    const rs = await Promise.all(Array.from({ length: 10 }, (_, i) => api(env, 'POST', '/api/v1/servers', {
      token: admin, body: { label: `S${i}`, url: `http://s${i}.example.test` },
    })));
    const pos = db.prepare('SELECT position FROM default_servers ORDER BY position').all().map((r) => r.position);
    ok(rs.every((r) => r.status === 201) && new Set(pos).size === 10 && pos[0] === 1 && pos[9] === 10,
      `I1. 10 serveurs créés en même temps : positions ${JSON.stringify(pos)} (attendu 1..10, sans doublon)`);
  }

  // ---- J. Premier compte admin créé par des connexions simultanées ----
  // Motif « compter puis insérer » : deux premières connexions voyaient 0
  // admin, insertion en double → contrainte UNIQUE → connexion en échec.
  {
    const { env, db } = makeEnv({ jitterMs: 4 });
    const rs = await Promise.all(Array.from({ length: 10 }, () => api(env, 'POST', '/api/v1/auth/login', {
      body: { email: 'admin', password: env.ADMIN_SECRET },
    })));
    const admins = one(db, 'SELECT COUNT(*) AS n FROM admin_users').n;
    ok(rs.every((r) => r.status === 200 && r.json && r.json.token) && admins === 1,
      `J1. 10 premières connexions simultanées : statuts ${JSON.stringify(rs.map((r) => r.status))}, ${admins} compte admin (attendu 10 × 200, 1 compte)`);
  }

  // ---- K. Inscription revendeur : même identifiant, envois simultanés ----
  {
    const { env, db } = makeEnv({ jitterMs: 4 });
    const email = 'meme-identifiant@example.test';
    const rs = await Promise.all(Array.from({ length: 5 }, (_, i) => api(env, 'POST', '/api/v1/auth/reseller/signup', {
      body: { email, password: `mdp-test-${i}`, name: `R${i}` },
      headers: { 'CF-Connecting-IP': `203.0.113.${i + 1}` },
    })));
    const st = rs.map((r) => r.status).sort();
    const rows = one(db, 'SELECT COUNT(*) AS n FROM resellers WHERE email = ?', email).n;
    ok(JSON.stringify(st) === JSON.stringify([201, 409, 409, 409, 409]) && rows === 1,
      `K1. 5 inscriptions simultanées du même identifiant : statuts ${JSON.stringify(st)}, ${rows} compte (attendu 201 + 4 × 409, 1 compte)`);
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}

main().catch((e) => { console.error('TEST CRASH', e && e.stack ? e.stack : e); process.exit(1); });
