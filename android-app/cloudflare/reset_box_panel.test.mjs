// =========================================================
//  reset_box_panel.test.mjs — Remise à neuf d'une box depuis le panel
// =========================================================
//  node --experimental-sqlite cloudflare/reset_box_panel.test.mjs
//  Demande du propriétaire (06/10/2026) : un bouton qui rend l'application
//  vierge, y compris la liste ajoutée par le client, pour tout renvoyer à
//  distance. Route : POST /api/v1/sources/:mac/reset. Base SQLite en
//  mémoire, mêmes comptes que self_source_panel.test.mjs, adresses en
//  example.test.
// =========================================================
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createD1, fakeRealtimeHub } from './test_support/d1_sqlite.mjs';
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
  // Harnais D1 partagé et fidèle (test_support/d1_sqlite.mjs).
  const t = createD1({ extraSql: ['ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT', 'ALTER TABLE devices ADD COLUMN block_status TEXT'] });
  return { db: t.db, faults: t.faults, env: { DB: t.DB, ADMIN_SECRET: crypto.randomUUID(), SECRETS_KEY: crypto.randomUUID() } };
}

async function api(env, method, path, { token, body } = {}) {
  const headers = { 'content-type': 'application/json' };
  if (token) headers.authorization = `Bearer ${token}`;
  const res = await worker.fetch(new Request(`https://app.test${path}`, {
    method, headers, body: body === undefined ? undefined : JSON.stringify(body),
  }), env, ctx);
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch (_) { json = null; }
  return { status: res.status, json, text };
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

async function main() {
  const { env } = makeDb();
  const admin = await login(env);
  ok(!!admin, 'login admin');
  const MAC = 'MK:AA:BB:CC:DD:31';
  const a = await makeReseller(env, admin);
  const b = await makeReseller(env, admin);
  await api(env, 'GET', `/api/status/${MAC}`);
  const claim = await api(env, 'POST', '/api/v1/activate', { token: admin, body: { mac: MAC, plan: 'trial_7d', reseller_id: a.id } });
  ok(claim.status === 200 || claim.status === 201, 'MAC rattachée au revendeur A');

  // Avant : une liste du panel + une liste du client.
  const put = await api(env, 'PUT', `/api/v1/sources/${MAC}`, {
    token: admin, body: { sources: [{ type: 'm3u', m3u_url: 'http://panel.example.test/get.php?username=u&password=p', label: 'Panel' }] },
  });
  ok(put.status === 200, 'liste du panel posée');
  const self = await api(env, 'POST', `/api/self-source/${MAC}`, {
    body: { type: 'm3u', m3u_url: 'http://perso.example.test/get.php?username=c&password=s', label: 'Perso' },
  });
  ok(self.status === 200, 'liste du client ajoutée');
  let served = await api(env, 'GET', `/api/device-source/${MAC}`);
  ok((served.json.sources || []).length === 2, 'la box reçoit 2 listes avant la remise à neuf');
  let status = await api(env, 'GET', `/api/status/${MAC}`);
  ok(status.json && (status.json.reset_at || 0) === 0, 'statut : reset_at absent ou 0 avant');

  // Refus : sans jeton, autre revendeur, MAC inconnue.
  let r = await api(env, 'POST', `/api/v1/sources/${MAC}/reset`);
  ok(r.status === 401, 'sans jeton : 401');
  r = await api(env, 'POST', `/api/v1/sources/${MAC}/reset`, { token: b.token });
  ok(r.status === 403, 'autre revendeur : 403');
  r = await api(env, 'POST', `/api/v1/sources/MK:00:00:00:00:99/reset`, { token: admin });
  ok(r.status === 404, `MAC jamais vue : 404 (${r.status})`);

  // Le revendeur propriétaire remet la box à neuf.
  const before = Date.now();
  r = await api(env, 'POST', `/api/v1/sources/${MAC}/reset`, { token: a.token });
  ok(r.status === 200 && r.json && r.json.ok === true && r.json.reset_at >= before, `remise à neuf par le revendeur (${r.status} ${r.text.slice(0, 160)})`);
  served = await api(env, 'GET', `/api/device-source/${MAC}`);
  ok((served.json && served.json.sources ? served.json.sources : []).length === 0, 'la box ne reçoit plus aucune liste, celle du client comprise');
  ok(!served.text.includes('password=s') && !served.text.includes('password=p'), 'aucun secret ne reste dans la réponse');
  status = await api(env, 'GET', `/api/status/${MAC}`);
  ok(status.json && status.json.reset_at === r.json.reset_at, 'statut : reset_at = heure du clic (la box l’applique à son prochain tour)');
  ok(status.json.status === 'active', 'la licence n’est pas touchée');

  // Deuxième clic : reset_at avance (la box rejoue l’effacement).
  await new Promise((res) => setTimeout(res, 5));
  const again = await api(env, 'POST', `/api/v1/sources/${MAC}/reset`, { token: admin });
  ok(again.status === 200 && again.json.reset_at > r.json.reset_at, 'second clic : reset_at plus récent');

  // Le revendeur renvoie ensuite une liste : elle repart normalement.
  const after = await api(env, 'PUT', `/api/v1/sources/${MAC}`, {
    token: a.token, body: { sources: [{ type: 'm3u', m3u_url: 'http://neuf.example.test/get.php?username=n&password=q', label: 'Neuf' }] },
  });
  ok(after.status === 200, 'une nouvelle liste se pose après la remise à neuf');
  served = await api(env, 'GET', `/api/device-source/${MAC}`);
  ok((served.json.sources || []).length === 1, 'la box reçoit la nouvelle liste seule');

  // Sécurité : lecture des codes par MAC limitée à 120 / minute / IP.
  const ipHeaders = { 'CF-Connecting-IP': '203.0.113.7' };
  let last = 0; let firstLimited = 0;
  for (let i = 1; i <= 121; i++) {
    const res = await worker.fetch(new Request(`https://app.test/api/device-source/${MAC}`, { headers: ipHeaders }), env, ctx);
    last = res.status;
    if (res.status === 429 && !firstLimited) firstLimited = i;
  }
  ok(firstLimited === 121 && last === 429, `device-source : 120 lectures passent, la 121e reçoit 429 (première 429 au n°${firstLimited})`);
  const other = await worker.fetch(new Request(`https://app.test/api/device-source/${MAC}`, { headers: { 'CF-Connecting-IP': '203.0.113.8' } }), env, ctx);
  ok(other.status === 200, 'une autre IP n’est pas touchée');

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}

main().catch((e) => { console.error('TEST CRASH', e && e.message ? e.message : e); process.exit(1); });
