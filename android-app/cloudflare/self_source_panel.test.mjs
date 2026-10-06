// =========================================================
//  self_source_panel.test.mjs — Le panel retire une liste du client
// =========================================================
//  node --experimental-sqlite cloudflare/self_source_panel.test.mjs
//  Mesuré le 05/10/2026 : le revendeur effaçait les listes du panel,
//  la liste ajoutée par le client (Mon espace) restait et « revenait »
//  sur la fiche. Route : DELETE /api/v1/sources/:mac/self/:id.
//  Base SQLite en mémoire, mêmes comptes que activation_m3u.test.mjs,
//  adresses en example.test.
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
  const MAC = 'MK:AA:BB:CC:DD:21';
  const a = await makeReseller(env, admin);
  const b = await makeReseller(env, admin);
  await api(env, 'GET', `/api/status/${MAC}`);
  const claim = await api(env, 'POST', '/api/v1/activate', { token: admin, body: { mac: MAC, plan: 'trial_7d', reseller_id: a.id } });
  ok(claim.status === 200 || claim.status === 201, 'MAC rattachée au revendeur A');

  // Le panel pousse une liste ; le client en ajoute une autre dans Mon espace.
  const put = await api(env, 'PUT', `/api/v1/sources/${encodeURIComponent(MAC)}`, {
    token: admin, body: { sources: [{ type: 'm3u', m3u_url: 'http://panel.example.test/get.php?username=u&password=p', label: 'Panel' }] },
  });
  ok(put.status === 200, 'liste du panel posée');
  const self = await api(env, 'POST', `/api/self-source/${MAC}`, {
    body: { type: 'm3u', m3u_url: 'http://perso.example.test/get.php?username=c&password=s', label: 'Perso' },
  });
  ok(self.status === 200 && self.json && self.json.ok === true, `liste du client ajoutée (${self.status})`);

  let served = await api(env, 'GET', `/api/device-source/${MAC}`);
  const selfItem = (served.json.sources || []).find((s) => s.origin === 'self');
  ok(!!selfItem && typeof selfItem.id === 'string', 'la liste du client a un id serveur');

  // Avant le correctif : effacer les listes du panel laissait celle du client.
  const panelView = await api(env, 'GET', `/api/v1/sources/${encodeURIComponent(MAC)}`, { token: admin });
  const panelSelf = (panelView.json.sources || []).find((s) => s.origin === 'self');
  ok(!!panelSelf && panelSelf.id === selfItem.id, 'le panel voit la liste du client avec son id');

  // Sans jeton : refusé.
  let r = await api(env, 'DELETE', `/api/v1/sources/${encodeURIComponent(MAC)}/self/${selfItem.id}`);
  ok(r.status === 401, 'retrait sans jeton : 401');
  // Un autre revendeur : refusé.
  r = await api(env, 'DELETE', `/api/v1/sources/${encodeURIComponent(MAC)}/self/${selfItem.id}`, { token: b.token });
  ok(r.status === 403, 'un autre revendeur : 403');
  // Une liste du panel par cette route : refusé (verrouillée).
  r = await api(env, 'DELETE', `/api/v1/sources/${encodeURIComponent(MAC)}/self/pas-un-id`, { token: admin });
  ok(r.status === 404, 'id inconnu : 404');

  // Le revendeur propriétaire retire la liste du client.
  r = await api(env, 'DELETE', `/api/v1/sources/${encodeURIComponent(MAC)}/self/${selfItem.id}`, { token: a.token });
  ok(r.status === 200 && r.json && r.json.ok === true && r.json.remaining === 1, `retrait par le revendeur (${r.status} ${r.text.slice(0, 200)})`);
  served = await api(env, 'GET', `/api/device-source/${MAC}`);
  ok((served.json.sources || []).every((s) => s.origin !== 'self'), 'la box ne reçoit plus la liste du client');
  ok((served.json.sources || []).length === 1, 'la liste du panel est toujours là');
  ok(!served.text.includes('password=s'), 'aucun secret du client dans la réponse'); // la liste est partie

  // La notification de la box (notifyBox → Durable Object) est couverte
  // par box_channel.test.mjs ; ce banc n'a pas de RT_HUB.

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}

main().catch((e) => { console.error('TEST CRASH', e && e.message ? e.message : e); process.exit(1); });
