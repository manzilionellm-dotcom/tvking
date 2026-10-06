// =========================================================
//  activation_idempotency.test.mjs — Activation sûre au double clic
// =========================================================
//  node --experimental-sqlite cloudflare/activation_idempotency.test.mjs
//  Preuves attendues (06/10/2026) :
//    • même Idempotency-Key, même corps → même réponse, une seule licence,
//      un seul débit, en-tête Idempotent-Replayed ;
//    • même clé, corps différent → 409 ;
//    • deux requêtes jumelles en même temps → une seule s'exécute, l'autre
//      reçoit 409 in_progress ;
//    • sans clé : comportement d'avant (le second appel renouvelle) ;
//    • X-Request-Id renvoyé et écrit dans l'audit avec l'état d'avant/après
//      et la latence mesurée (took_ms).
//  Base SQLite en mémoire, comptes de test, aucune adresse réelle.
// =========================================================
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import worker from './worker.js';

const ctx = { waitUntil() {}, passThroughOnException() {} };
const here = dirname(fileURLToPath(import.meta.url));
let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass += 1; console.log('PASS', m); }
  else { fail += 1; console.log('FAIL', m); }
};

function makeDb() {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON');
  db.exec(readFileSync(join(here, 'schema.sql'), 'utf8'));
  for (const sql of [
    'ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT',
    'ALTER TABLE devices ADD COLUMN block_status TEXT',
  ]) {
    try { db.exec(sql); } catch (_) { /* déjà dans le schéma */ }
  }
  const DB = {
    prepare(sql) {
      const runWith = (args) => {
        const params = args.map((v) => (v === undefined ? null : v));
        return {
          async first() { const row = db.prepare(sql).get(...params); return row === undefined ? null : row; },
          async all() { return { results: db.prepare(sql).all(...params) }; },
          async run() { const info = db.prepare(sql).run(...params); return { success: true, meta: { changes: info.changes } }; },
        };
      };
      return {
        bind(...args) { return runWith(args); },
        first() { return runWith([]).first(); },
        all() { return runWith([]).all(); },
        run() { return runWith([]).run(); },
      };
    },
    async batch(stmts) {
      db.exec('BEGIN');
      try { const out = []; for (const s of stmts) out.push(await s.run()); db.exec('COMMIT'); return out; }
      catch (e) { try { db.exec('ROLLBACK'); } catch (_) { /* déjà annulé */ } throw e; }
    },
  };
  return { db, env: { DB, ADMIN_SECRET: crypto.randomUUID(), SECRETS_KEY: crypto.randomUUID() } };
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

async function makeReseller(env, admin, credits) {
  const email = `r-${crypto.randomUUID()}@example.test`;
  const password = crypto.randomUUID();
  const created = await api(env, 'POST', '/api/v1/resellers', {
    token: admin, body: { email, password, name: 'Revendeur test', credit_balance: credits },
  });
  const id = created.json && created.json.id;
  await api(env, 'PATCH', `/api/v1/resellers/${id}`, { token: admin, body: { permissions: ['activate', 'devices', 'sources'] } });
  const logged = await api(env, 'POST', '/api/v1/auth/reseller/login', { body: { email, password } });
  return { token: logged.json && logged.json.token, id };
}

async function main() {
  const { db, env } = makeDb();
  const admin = await login(env);
  ok(!!admin, 'login admin');
  const reseller = await makeReseller(env, admin, 5);
  const MAC = 'MK:AA:BB:CC:DD:41';
  const key = crypto.randomUUID();
  const body = { mac: MAC, plan: 'yearly' };

  // 1) Première activation avec clé.
  const first = await api(env, 'POST', '/api/v1/activate', {
    token: reseller.token, body, headers: { 'Idempotency-Key': key, 'X-Request-Id': 'req-test-0001' },
  });
  ok(first.status === 201 && first.json && first.json.ok === true, `activation 201 (${first.status} ${first.text.slice(0, 120)})`);
  ok(first.headers.get('x-request-id') === 'req-test-0001', 'X-Request-Id du panel renvoyé tel quel');
  ok(first.json.credits_charged === 1 && first.json.credit_balance === 4, 'un crédit débité, solde 4');

  // 2) Rejeu : même clé, même corps.
  const replay = await api(env, 'POST', '/api/v1/activate', {
    token: reseller.token, body, headers: { 'Idempotency-Key': key },
  });
  ok(replay.status === 201 && replay.headers.get('idempotent-replayed') === 'true', 'rejeu : même statut, Idempotent-Replayed');
  ok(replay.json.license_id === first.json.license_id && replay.json.expires_at === first.json.expires_at, 'rejeu : même licence, même date de fin');
  const lic = db.prepare('SELECT COUNT(*) AS n FROM licenses').get();
  // La création du revendeur écrit déjà une ligne « issue » (+5) : on ne
  // compte que les débits d'activation.
  const ledger = db.prepare("SELECT COUNT(*) AS n FROM credit_ledger WHERE reason IN ('activation', 'renew')").get();
  const bal = db.prepare('SELECT credit_balance FROM resellers WHERE id = ?').get(reseller.id);
  ok(lic.n === 1 && ledger.n === 1 && bal.credit_balance === 4, `une licence, un débit, solde 4 (licences ${lic.n}, ledger ${ledger.n}, solde ${bal.credit_balance})`);

  // 3) Même clé, corps différent.
  const mismatch = await api(env, 'POST', '/api/v1/activate', {
    token: reseller.token, body: { mac: MAC, plan: 'lifetime' }, headers: { 'Idempotency-Key': key },
  });
  ok(mismatch.status === 409 && mismatch.json.error === 'idempotency_mismatch', 'même clé, autre corps : 409');

  // 4) Clé invalide.
  const badKey = await api(env, 'POST', '/api/v1/activate', {
    token: reseller.token, body, headers: { 'Idempotency-Key': 'x' },
  });
  ok(badKey.status === 400, 'clé trop courte : 400');

  // 5) Deux requêtes jumelles en même temps : une seule passe.
  const key2 = crypto.randomUUID();
  const MAC2 = 'MK:AA:BB:CC:DD:42';
  const twins = await Promise.all([0, 1].map(() => api(env, 'POST', '/api/v1/activate', {
    token: reseller.token, body: { mac: MAC2, plan: 'yearly' }, headers: { 'Idempotency-Key': key2 },
  })));
  const statuses = twins.map((t) => t.status).sort();
  ok(statuses[0] === 201 && (statuses[1] === 409 || statuses[1] === 201),
    `jumelles : une 201, l'autre 409 ou rejeu (${statuses.join(',')})`);
  const bal2 = db.prepare('SELECT credit_balance FROM resellers WHERE id = ?').get(reseller.id);
  ok(bal2.credit_balance === 3, `un seul débit pour les jumelles (solde ${bal2.credit_balance})`);

  // 5b) Branche « en cours » prouvée directement : une ligne réservée sans
  //     réponse (requête jumelle encore en vol) → 409, rien n'est exécuté.
  //     (Le banc Node exécute les requêtes l'une après l'autre : la course
  //     réelle n'y est pas reproductible, on pose donc l'état intermédiaire.)
  const key3 = crypto.randomUUID();
  const MAC4 = 'MK:AA:BB:CC:DD:44';
  const bodyText = JSON.stringify({ mac: MAC4, plan: 'yearly' });
  const enc = new TextEncoder().encode(`activate\n${bodyText}`);
  const digest = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', enc)))
    .map((b) => b.toString(16).padStart(2, '0')).join('');
  db.prepare('INSERT INTO idempotency_keys (k, actor_id, request_hash, status, body_json, created_at) VALUES (?, ?, ?, NULL, NULL, ?)')
    .run(`reseller:${reseller.id}:${key3}`, reseller.id, digest, Date.now());
  const inflight = await worker.fetch(new Request('https://app.test/api/v1/activate', {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${reseller.token}`, 'Idempotency-Key': key3 },
    body: bodyText,
  }), env, ctx);
  const inflightJson = await inflight.json();
  ok(inflight.status === 409 && inflightJson.error === 'idempotency_in_progress', 'clé réservée, réponse pas encore écrite : 409 in_progress');
  const dev4 = db.prepare('SELECT COUNT(*) AS n FROM devices WHERE mac = ?').get(MAC4);
  ok(dev4.n === 0, 'rien n’a été exécuté pendant que la jumelle est en vol');

  // 6) Sans clé : le second appel renouvelle (comportement d'avant, documenté).
  const MAC3 = 'MK:AA:BB:CC:DD:43';
  const a = await api(env, 'POST', '/api/v1/activate', { token: admin, body: { mac: MAC3, plan: 'yearly' } });
  const b = await api(env, 'POST', '/api/v1/activate', { token: admin, body: { mac: MAC3, plan: 'yearly' } });
  ok(a.status === 201 && a.json.renewed === false && b.status === 201 && b.json.renewed === true, 'sans clé : création puis renouvellement');
  ok(b.json.expires_at > a.json.expires_at, 'le renouvellement prolonge à partir de la date précédente');

  // 7) Audit : état d'avant / d'après, latence mesurée, corrélation.
  const rows = db.prepare("SELECT action, before_json, after_json, correlation_id FROM audit_logs WHERE action LIKE 'activate.%' ORDER BY created_at ASC").all();
  ok(rows.length >= 3, `audit : ${rows.length} événements d'activation`);
  const firstRow = rows.find((r) => r.correlation_id === 'req-test-0001');
  ok(!!firstRow && firstRow.before_json === null, 'création : état d’avant nul, corrélation = X-Request-Id');
  const after0 = firstRow ? JSON.parse(firstRow.after_json) : {};
  ok(typeof after0.took_ms === 'number' && after0.took_ms >= 0 && after0.status === 'active', `after_json : status active, took_ms mesuré (${after0.took_ms} ms)`);
  const renewRow = rows.find((r) => r.action === 'activate.renew' && r.before_json);
  ok(!!renewRow && JSON.parse(renewRow.before_json).expires_at === a.json.expires_at, 'renouvellement : état d’avant = ancienne date de fin');
  ok(!JSON.stringify(rows).includes(env.ADMIN_SECRET), 'aucun secret dans l’audit');

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}

main().catch((e) => { console.error('TEST CRASH', e && e.message ? e.message : e); process.exit(1); });
