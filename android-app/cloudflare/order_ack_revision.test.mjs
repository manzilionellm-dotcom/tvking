// =========================================================
//  order_ack_revision.test.mjs — Un accusé appartient à SA révision
// =========================================================
//  Vrai Worker, SQLite en mémoire, aucun fournisseur ni secret réel.
//  Un numéro fourni qui diffère de celui de l'ordre ne doit modifier
//  ni cet ordre ni une autre révision. L'ancien accusé sans numéro
//  reste accepté : on ne casse pas les clients qui n'en envoient pas.
//  node --experimental-sqlite cloudflare/order_ack_revision.test.mjs
import { createD1, fakeRealtimeHub } from './test_support/d1_sqlite.mjs';
import worker, { RealtimeHub } from './worker.js';

const t = createD1({ extraSql: [
  'ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT',
  'ALTER TABLE devices ADD COLUMN block_status TEXT',
] });
const env = { DB: t.DB, ADMIN_SECRET: crypto.randomUUID(), SECRETS_KEY: crypto.randomUUID() };
env.RT_HUB = fakeRealtimeHub(env, RealtimeHub);
const ctx = { waitUntil() {}, passThroughOnException() {} };
const MAC = 'MK:AA:BB:CC:DD:61';
let passed = 0;
let failed = 0;
function check(condition, label) {
  if (condition) { passed++; console.log('PASS', label); }
  else { failed++; console.log('FAIL', label); }
}
async function api(method, path, body, token) {
  const res = await worker.fetch(new Request('https://app.test' + path, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: 'Bearer ' + token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  }), env, ctx);
  return { status: res.status, json: await res.json() };
}
function snapshot(orderId) {
  return JSON.stringify({
    order: t.db.prepare('SELECT * FROM box_orders WHERE order_id = ?').get(orderId),
    revisions: t.db.prepare('SELECT * FROM source_revisions WHERE mac = ? ORDER BY rev').all(MAC),
  });
}
async function ack(orderId, state, rev, mac = MAC) {
  const out = await api('POST', '/api/box/ack/' + mac, { orders: [{
    order_id: orderId, state,
    ...(rev === undefined ? {} : { config_rev: rev }),
    received_at: Date.now(), applied_at: Date.now(),
    result: state === 'failed' ? 'refused' : 'loaded',
  }] });
  return out.json.results[0];
}

const login = await api('POST', '/api/v1/auth/login', { email: 'admin', password: env.ADMIN_SECRET });
const token = login.json.token;
check(login.status === 200 && !!token, 'login admin');
await api('POST', '/api/v1/activate', { mac: MAC, plan: 'yearly' }, token);
const licenses = JSON.stringify(t.db.prepare('SELECT * FROM licenses ORDER BY id').all());
const first = await api('PUT', '/api/v1/sources/' + MAC,
  { sources: [{ type: 'm3u', m3u_url: 'https://one.example.test/l.m3u' }] }, token);
const second = await api('PUT', '/api/v1/sources/' + MAC,
  { sources: [{ type: 'm3u', m3u_url: 'https://two.example.test/l.m3u' }] }, token);
check(first.json.rev === 1 && second.json.rev === 2, 'deux ordres et deux révisions distinctes');

// L'ancien ordre ne doit pas confirmer (ni refuser) la nouvelle révision.
for (const state of ['received', 'applied', 'failed']) {
  const before = snapshot(first.json.order_id);
  const out = await ack(first.json.order_id, state, second.json.rev);
  check(out.status === 409 && out.error === 'config_revision_mismatch',
    state + ' : autre révision explicitement refusée');
  check(snapshot(first.json.order_id) === before,
    state + ' : ordre et révisions inchangés après refus');
}

const foreign = await ack(first.json.order_id, 'applied', second.json.rev, 'MK:AA:BB:CC:DD:99');
check(foreign.status === 404 && foreign.error === 'unknown_order',
  'une autre MAC ne reçoit pas les détails de la révision');
const received = await ack(second.json.order_id, 'received');
check(received.status === 200 && received.state === 'received', 'RECEIVED sans révision reste accepté');
const applied = await ack(second.json.order_id, 'applied', second.json.rev);
check(applied.status === 200 && applied.state === 'applied', 'APPLIED confirme la révision exacte');
const rows = t.db.prepare('SELECT rev, state FROM source_revisions WHERE mac = ? ORDER BY rev').all(MAC);
check(rows[0].state === 'published' && rows[1].state === 'acknowledged',
  'seule la révision de cet ordre est confirmée');
const duplicate = await ack(second.json.order_id, 'applied', second.json.rev);
check(duplicate.status === 200 && duplicate.changed === false, 'accusé identique idempotent');

const clear = await api('DELETE', '/api/v1/sources/' + MAC, undefined, token);
const beforeClear = snapshot(clear.json.order_id);
const badClear = await ack(clear.json.order_id, 'applied', second.json.rev);
check(badClear.status === 409 && snapshot(clear.json.order_id) === beforeClear,
  'source_clear : ancienne révision refusée sans écriture');
const legacy = await ack(clear.json.order_id, 'applied');
check(legacy.status === 200 && legacy.state === 'applied', 'ancien client APPLIED sans révision toujours accepté');
check(t.db.prepare('SELECT state FROM source_revisions WHERE mac = ? AND rev = ?').get(MAC, clear.json.rev).state === 'published',
  'sans numéro, aucune révision n’est prétendue confirmée');
check(JSON.stringify(t.db.prepare('SELECT * FROM licenses ORDER BY id').all()) === licenses,
  'aucune licence modifiée par les listes ou leurs accusés');
console.log(`${passed} passed, ${failed} failed`);
process.exitCode = failed ? 1 : 0;
