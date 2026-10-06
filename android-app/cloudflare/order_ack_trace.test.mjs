// =========================================================
//  order_ack_trace.test.mjs — Ordres suivis, accusés réels, trace,
//  révisions de listes, retour arrière, chronologie, latence
// =========================================================
//  node --experimental-sqlite cloudflare/order_ack_trace.test.mjs
//  Vrai Worker (worker.js), vraie classe RealtimeHub (Durable Object) sur
//  un stockage en mémoire, base SQLite réelle. Aucune adresse réelle.
//  Ce que ce banc prouve (06/10/2026) :
//    1. chaque action panel crée un ordre CREATED → SENT, publié avec son
//       order_id et son trace_id dans la trame de la box ;
//    2. la box accuse RECEIVED puis APPLIED (ou FAILED) : persisté, heures
//       box et heures serveur ; un accusé ne recule jamais ;
//    3. le même trace_id relie audit, ordre, trame, accusé ;
//    4. une liste mal saisie est refusée avant écriture ; une liste refusée
//       par la box laisse la dernière bonne active, avec retour arrière ;
//    5. la chronologie retrouve tout par MAC, e-mail ou trace ;
//    6. les centiles de latence sont calculés à partir de mesures réelles,
//       `null` quand rien n'est mesuré.
// =========================================================
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createD1, fakeRealtimeHub } from './test_support/d1_sqlite.mjs';
import worker, { RealtimeHub } from './worker.js';

const ctx = { waitUntil() {}, passThroughOnException() {} };
const here = dirname(fileURLToPath(import.meta.url));
let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass += 1; console.log('PASS', m); }
  else { fail += 1; console.log('FAIL', m); }
};

function makeDb() {
  const t = createD1({ extraSql: ['ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT', 'ALTER TABLE devices ADD COLUMN block_status TEXT'] });
  const env = { DB: t.DB, ADMIN_SECRET: crypto.randomUUID(), SECRETS_KEY: crypto.randomUUID() };
  env.RT_HUB = fakeRealtimeHub(env, RealtimeHub);
  return { db: t.db, faults: t.faults, env };
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

async function makeReseller(env, admin) {
  const email = `r-${crypto.randomUUID()}@example.test`;
  const password = crypto.randomUUID();
  const created = await api(env, 'POST', '/api/v1/resellers', {
    token: admin, body: { email, password, name: 'Revendeur test', credit_balance: 5 },
  });
  const id = created.json && created.json.id;
  await api(env, 'PATCH', `/api/v1/resellers/${id}`, { token: admin, body: { permissions: ['activate', 'devices', 'sources'] } });
  const logged = await api(env, 'POST', '/api/v1/auth/reseller/login', { body: { email, password } });
  return { token: logged.json && logged.json.token, id };
}

const ack = (env, mac, orders) => api(env, 'POST', `/api/box/ack/${mac}`, { body: { orders } });

async function main() {
  const { db, env } = makeDb();
  const admin = await login(env);
  ok(!!admin, 'login admin');
  const MAC = 'MK:AA:BB:CC:DD:51';
  const TRACE = 'trace-e2e-activation-0001';
  const EMAIL = `client-${crypto.randomUUID()}@example.test`;

  // ---- 1. Activation : ordre CREATED → SENT, trace dans la trame ----
  const t0 = Date.now() - 40;
  const act = await api(env, 'POST', '/api/v1/activate', {
    token: admin, body: { mac: MAC, plan: 'yearly', customer_email: EMAIL },
    headers: { 'X-Request-Id': TRACE, 'X-Client-Sent-At': String(t0) },
  });
  ok(act.status === 201 && /^ord_/.test(act.json.order_id || '') && act.json.trace_id === TRACE,
    `activation : order_id et trace_id rendus (${act.status})`);
  const orderId = act.json.order_id;
  let row = db.prepare('SELECT * FROM box_orders WHERE order_id = ?').get(orderId);
  ok(row && row.state === 'sent' && row.trace_id === TRACE && row.seq > 0, `ordre SENT, publié au Durable Object (seq ${row && row.seq})`);
  ok(row.t0_client === t0 && row.t1_api > 0 && row.t2_commit >= row.t1_api && row.t3_published >= row.t2_commit,
    'T0 navigateur, T1 réception API, T2 transaction, T3 publication : enregistrés et ordonnés');

  const wait = await api(env, 'GET', `/api/box/wait/${MAC}?after=0&timeout=200`);
  const frame = (wait.json && wait.json.box || []).find((b) => b.order_id === orderId);
  ok(!!frame && frame.trace_id === TRACE && frame.kind === 'activate', 'la trame lue par la box porte order_id et trace_id');
  ok(!/password|username|m3u_url/i.test(wait.text), 'la trame ne contient aucun identifiant de liste');

  // ---- 2. Accusés réels ----
  const recvAt = Date.now();
  let r = await ack(env, MAC, [{ order_id: orderId, state: 'received', received_at: recvAt, trace_id: TRACE }]);
  ok(r.status === 200 && r.json.results[0].state === 'received', 'accusé RECEIVED persisté');
  r = await ack(env, MAC, [{ order_id: orderId, state: 'applied', applied_at: recvAt + 30, result: 'status:active', trace_id: TRACE, app_version: '107-test' }]);
  ok(r.json.results[0].state === 'applied', 'accusé APPLIED persisté');
  r = await ack(env, MAC, [{ order_id: orderId, state: 'received', received_at: recvAt + 99 }]);
  ok(r.json.results[0].changed === false && r.json.results[0].state === 'applied', 'un RECEIVED en retard ne fait pas reculer APPLIED');
  row = db.prepare('SELECT * FROM box_orders WHERE order_id = ?').get(orderId);
  ok(row.received_at === recvAt && row.received_srv > 0 && row.applied_at === recvAt + 30 && row.applied_srv >= row.received_srv && row.result === 'status:active',
    'heures box ET heures serveur gardées pour reçu et appliqué');
  r = await ack(env, 'MK:AA:BB:CC:DD:99', [{ order_id: orderId, state: 'applied' }]);
  ok(r.json.results[0].status === 404, 'une autre box ne peut pas accuser cet ordre');
  r = await ack(env, MAC, [{ order_id: orderId, state: 'done' }]);
  ok(r.json.results[0].status === 400, 'état inconnu refusé');
  r = await api(env, 'POST', `/api/box/ack/${MAC}`, { body: { box: [1], fleet: [] } });
  ok(r.status === 200 && r.json.ok === true, 'ancien corps d’accusé (box 106) toujours accepté');

  // ---- 3. Trace de bout en bout ----
  const byTrace = await api(env, 'GET', `/api/v1/orders?trace=${TRACE}`, { token: admin });
  ok(byTrace.status === 200 && byTrace.json.items.length === 1 && byTrace.json.items[0].state === 'applied', 'GET /orders?trace= : l’ordre et son état réel');
  const audit = db.prepare('SELECT action, correlation_id FROM audit_logs WHERE correlation_id = ?').all(TRACE);
  ok(audit.some((a) => a.action === 'activate.create'), 'même trace_id dans le journal d’audit');

  // ---- 4. Révisions de listes ----
  const A_URL = 'http://liste-a.example.test/get.php?username=ua&password=pa&type=m3u';
  const B_URL = 'http://liste-b.example.test/get.php?username=ub&password=pb&type=m3u';
  const putA = await api(env, 'PUT', `/api/v1/sources/${MAC}`, {
    token: admin, body: { sources: [{ type: 'm3u', m3u_url: A_URL }] }, headers: { 'X-Request-Id': 'trace-e2e-liste-a' },
  });
  ok(putA.status === 200 && putA.json.rev === 1 && putA.json.order_id, `liste A : révision 1 publiée (${putA.status})`);
  let pub = await api(env, 'GET', `/api/device-source/${MAC}`);
  ok(pub.json.rev === 1, 'la box reçoit le numéro de révision servi');
  await ack(env, MAC, [{ order_id: putA.json.order_id, state: 'applied', config_rev: 1, result: 'loaded', applied_at: Date.now() }]);
  let revs = await api(env, 'GET', `/api/v1/sources/${MAC}/revisions`, { token: admin });
  ok(revs.json.current_revision === 1 && revs.json.last_good_revision === 1 && revs.json.revisions[0].state === 'acknowledged',
    'révision 1 ACKNOWLEDGED par la box : dernière bonne');
  ok(!/pa|ua/.test(JSON.stringify(revs.json.revisions.map((x) => x.hosts))) && !revs.text.includes('password='), 'la vue des révisions ne montre que les hôtes');

  for (const [bad, why] of [
    [`${A_URL}http://liste-a.example.test/get.php?username=ua&password=pa`, 'lien collé deux fois'],
    ['http://liste-a.example.test/get.php?username=ua&password=p%E2%80%99a', 'apostrophe de téléphone encodée'],
    ['http://liste-a.example.test/get.php?username=ua&password=p’a', 'apostrophe de téléphone'],
    ['http://liste-a.example.test/get.php?username=ua&password=pa%CC%81', 'accent flottant'],
    ['pas-une-url', 'adresse invalide'],
  ]) {
    const res = await api(env, 'PUT', `/api/v1/sources/${MAC}`, { token: admin, body: { sources: [{ type: 'm3u', m3u_url: bad }] } });
    ok(res.status === 400, `refusée avant écriture : ${why}`);
  }
  pub = await api(env, 'GET', `/api/device-source/${MAC}`);
  ok(pub.json.rev === 1 && pub.json.sources[0].m3u_url === A_URL, 'après 5 saisies refusées, la box reçoit toujours la révision 1 saine');

  const putB = await api(env, 'PUT', `/api/v1/sources/${MAC}`, { token: admin, body: { sources: [{ type: 'm3u', m3u_url: B_URL }] } });
  ok(putB.json.rev === 2, 'liste B : révision 2 publiée');
  r = await ack(env, MAC, [{ order_id: putB.json.order_id, state: 'failed', config_rev: 2, result: 'refused',
    error_code: 'source_failed', error_message: `refusée après 120 s : ${B_URL}`, applied_at: Date.now() }]);
  ok(r.json.results[0].state === 'failed', 'la box accuse FAILED sur la révision 2');
  const failedRow = db.prepare('SELECT error_message FROM box_orders WHERE order_id = ?').get(putB.json.order_id);
  ok(failedRow.error_message && !failedRow.error_message.includes('pb') && !failedRow.error_message.includes('ub'), `message d’erreur expurgé : « ${failedRow.error_message} »`);
  revs = await api(env, 'GET', `/api/v1/sources/${MAC}/revisions`, { token: admin });
  ok(revs.json.current_revision === 2 && revs.json.current_state === 'rejected_by_box' && revs.json.last_good_revision === 1 && revs.json.rollback_available === true,
    'révision 2 REJECTED_BY_BOX, dernière bonne = 1, retour arrière disponible');
  const back = await api(env, 'POST', `/api/v1/sources/${MAC}/rollback`, { token: admin, body: {}, headers: { 'X-Request-Id': 'trace-e2e-rollback' } });
  ok(back.status === 200 && back.json.rev === 3 && back.json.rollback_of === 1, `retour arrière : révision 3 = copie de la 1 (${back.status})`);
  pub = await api(env, 'GET', `/api/device-source/${MAC}`);
  ok(pub.json.rev === 3 && pub.json.sources.length === 1 && pub.json.sources[0].m3u_url === A_URL, 'la box reçoit de nouveau la liste A, révision 3');
  const notGood = await api(env, 'POST', `/api/v1/sources/${MAC}/rollback`, { token: admin, body: { rev: 2 } });
  ok(notGood.status === 409, 'impossible de republier une révision refusée par la box');
  const allRevs = db.prepare('SELECT COUNT(*) AS n FROM source_revisions WHERE mac = ?').get(MAC);
  ok(allRevs.n === 3, 'aucune révision effacée (3 gardées)');

  // ---- 5. Expiration : jamais d'état ambigu ----
  db.prepare('UPDATE box_orders SET created_at = ? WHERE order_id = ?').run(Date.now() - 11 * 60 * 1000, back.json.order_id);
  const listed = await api(env, 'GET', `/api/v1/orders?mac=${MAC}`, { token: admin });
  const exp = listed.json.items.find((o) => o.order_id === back.json.order_id);
  ok(exp && exp.state === 'expired', 'un ordre sans réponse depuis 10 min devient EXPIRED');
  ok(db.prepare('SELECT state FROM box_orders WHERE order_id = ?').get(back.json.order_id).state === 'expired', 'EXPIRED écrit en base au passage');

  // ---- 6. Chronologie ----
  for (const [q, label] of [[MAC, 'MAC'], [EMAIL, 'e-mail'], [TRACE, 'trace']]) {
    const tl = await api(env, 'GET', `/api/v1/timeline?q=${encodeURIComponent(q)}`, { token: admin });
    const types = (tl.json && tl.json.events || []).filter((e) => e.trace_id === TRACE).map((e) => e.type);
    ok(tl.status === 200 && ['activate.create', 'ORDER_CREATED', 'ORDER_SENT', 'BOX_RECEIVED', 'BOX_APPLIED'].every((t) => types.includes(t)),
      `chronologie par ${label} : audit → créé → envoyé → reçu → appliqué (${types.join(' → ')})`);
  }
  const tlMac = await api(env, 'GET', `/api/v1/timeline?q=${MAC}`, { token: admin });
  const evTypes = tlMac.json.events.map((e) => e.type);
  ok(['CONFIG_REVISION_PUBLISHED', 'CONFIG_REVISION_ACKNOWLEDGED', 'CONFIG_REVISION_REJECTED_BY_BOX', 'BOX_FAILED', 'ORDER_EXPIRED'].every((t) => evTypes.includes(t)),
    'chronologie : révisions publiée / confirmée / refusée, échec box et expiration visibles');
  ok(!/password=|pa&|pb&/.test(tlMac.text), 'la chronologie ne contient aucun identifiant de liste');
  const searches = db.prepare("SELECT after_json FROM audit_logs WHERE action = 'blackbox.search'").all();
  ok(searches.length >= 4 && searches.every((s) => !s.after_json.includes(EMAIL)), 'chaque recherche est auditée, sans recopier l’e-mail');
  const res = await makeReseller(env, admin);
  const foreign = await api(env, 'GET', `/api/v1/timeline?q=${MAC}`, { token: res.token });
  ok(foreign.status === 200 && foreign.json.devices.length === 0 && foreign.json.events.length === 0, 'un revendeur ne voit pas la chronologie d’un appareil qui n’est pas à lui');

  // ---- 7. Latence : centiles réels, null sans mesure ----
  const m = await api(env, 'GET', '/api/v1/metrics/latency?hours=1', { token: admin });
  const actSeg = m.json.ops.activation && m.json.ops.activation.segments;
  ok(m.status === 200 && actSeg && actSeg.end_to_end.n === 1 && Number.isFinite(actSeg.end_to_end.p50) && actSeg.api.n === 1,
    `latence activation mesurée (api p50 ${actSeg && actSeg.api.p50} ms, bout en bout ${actSeg && actSeg.end_to_end.p50} ms, n=1)`);
  // Avant le 06/10/2026 un échec était écrit dans applied_srv et compté comme
  // « appliqué » (2) ; un accusé FAILED a maintenant son propre segment.
  ok(m.json.ops.source && m.json.ops.source.segments.applied.n === 1 && m.json.ops.source.segments.failed.n === 1,
    'latence liste : 1 accusé APPLIED et 1 accusé FAILED mesurés séparément');
  ok(!m.json.ops.renewal, 'renouvellement : aucune mesure, aucun chiffre');
  const forbidden = await api(env, 'GET', '/api/v1/metrics/latency', { token: res.token });
  ok(forbidden.status === 403, 'métriques réservées à l’administrateur');

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}

main().catch((e) => { console.error('TEST CRASH', e && e.stack ? e.stack : e); process.exit(1); });
