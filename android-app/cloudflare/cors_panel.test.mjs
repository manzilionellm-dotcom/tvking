// =========================================================
//  cors_panel.test.mjs — Le navigateur laisse passer chaque écriture du panel
// =========================================================
//  Défaut mis en ligne le 06/10/2026 puis corrigé le même jour : le panel
//  envoie X-Request-Id, X-Client-Sent-At (toute écriture) et
//  Idempotency-Key (activation) ; le Worker ne les autorisait pas dans sa
//  réponse de pré-vol (OPTIONS). Le navigateur bloquait la requête et le
//  panel affichait « Connexion impossible » sur toute modification.
//
//  Ce test lit les en-têtes que le PANEL pose vraiment (src/lib/api.ts) :
//  un en-tête ajouté côté panel sans être autorisé ici fait échouer le test.
//
//  Exécution : node --experimental-sqlite cloudflare/cors_panel.test.mjs
// =========================================================
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import worker from './worker.js';
import { createD1 } from './test_support/d1_sqlite.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const ORIGIN = 'https://tvking-admin.pages.dev';
const ctx = { waitUntil() {}, passThroughOnException() {} };
let pass = 0;
let fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('PASS', m); } else { fail++; console.log('FAIL', m); } };

// En-têtes posés par le panel : headers['X'] = … et { 'X': … } dans api.ts.
const api = readFileSync(join(here, '..', 'admin-panel', 'src', 'lib', 'api.ts'), 'utf8');
const sent = new Set(['authorization', 'content-type']);
for (const m of api.matchAll(/headers\[['"]([A-Za-z-]+)['"]\]\s*=/g)) sent.add(m[1].toLowerCase());
for (const m of api.matchAll(/\{\s*['"]([A-Z][A-Za-z]*-[A-Za-z-]+)['"]\s*:/g)) sent.add(m[1].toLowerCase());
ok(sent.has('x-request-id') && sent.has('x-client-sent-at') && sent.has('idempotency-key'),
  `en-têtes du panel lus dans api.ts : ${[...sent].sort().join(', ')}`);

const t = createD1({ extraSql: ['ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT'] });
const env = { DB: t.DB, ADMIN_SECRET: 'unit-test-admin-secret-not-real' };

for (const [method, path] of [
  ['PUT', '/api/v1/sources/MK:80:78:60:07:4F'],
  ['DELETE', '/api/v1/sources/MK:80:78:60:07:4F'],
  ['POST', '/api/v1/activate'],
  ['POST', '/api/v1/sources/MK:80:78:60:07:4F/reset'],
]) {
  const res = await worker.fetch(new Request(`https://app.x${path}`, {
    method: 'OPTIONS',
    headers: {
      Origin: ORIGIN,
      'Access-Control-Request-Method': method,
      'Access-Control-Request-Headers': [...sent].join(','),
    },
  }), env, ctx);
  const allowH = (res.headers.get('access-control-allow-headers') || '').toLowerCase().split(/\s*,\s*/);
  const allowM = (res.headers.get('access-control-allow-methods') || '').toUpperCase();
  const missing = [...sent].filter((h) => !allowH.includes(h));
  ok(res.status === 204 && missing.length === 0 && allowM.includes(method),
    `pré-vol ${method} ${path} : ${missing.length ? `REFUSÉ, manque ${missing.join(', ')}` : 'tous les en-têtes du panel autorisés'}`);
}

// La vraie réponse porte l'origine du panel (sinon le navigateur la cache).
const real = await worker.fetch(new Request('https://app.x/api/v1/auth/me', {
  headers: { Origin: ORIGIN, 'X-Request-Id': 'trace-cors-0001' },
}), env, ctx);
ok(real.headers.get('access-control-allow-origin') === ORIGIN, 'réponse réelle : Access-Control-Allow-Origin = origine du panel');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
