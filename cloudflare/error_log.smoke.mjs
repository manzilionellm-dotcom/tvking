// =========================================================
//  error_log.smoke.mjs — Ingestion des journaux d'erreurs appareils
// =========================================================
//  Vérifie la route publique POST /api/error-log (worker.js) de bout en bout
//  avec un D1 simulé :
//    - POST valide → { ok:true } + 1 INSERT dans error_logs (colonnes bornées)
//    - message vide → 400
//    - méthode GET → 400 (POST only)
//    - niveau inconnu normalisé en 'error', détails/champs tronqués
//
//  Exécution : node cloudflare/error_log.smoke.mjs
// =========================================================
import worker from './worker.js';

const ctx = { waitUntil() {}, passThroughOnException() {} };
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('PASS', m); } else { fail++; console.log('FAIL', m); } };

// ---- D1 simulé : capture les INSERT error_logs, benin pour le rate-limit ----
const inserts = [];
function makeDb() {
  return {
    prepare(sql) {
      return {
        _sql: sql,
        bind(...args) { this._args = args; return this; },
        async run() {
          if (/INSERT INTO error_logs/i.test(this._sql)) {
            inserts.push(this._args);
          }
          return { success: true };
        },
        async first() { return null; },      // rate-limit : « sous le seuil »
        async all() { return { results: [] }; },
      };
    },
  };
}

// 1) POST valide
inserts.length = 0;
let env = { DB: makeDb() };
let r = await worker.fetch(new Request('https://app.x/api/error-log', {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({
    mac: 'MK:11:22:33:44:55', level: 'FATAL', tag: 'player',
    message: 'stream blocked 403', detail: 'x'.repeat(20000),
    app_version: '0.3.3', app_build: '950', platform: 'mobile',
  }),
}), env, ctx);
let body = await r.json();
ok(r.status === 200 && body.ok === true, '1 POST valide → 200 { ok:true }');
ok(inserts.length === 1, '1 un INSERT error_logs émis');
if (inserts.length === 1) {
  const a = inserts[0]; // [mac, level, tag, message, detail, appV, appB, plat, country, ts]
  ok(a[0] === 'MK:11:22:33:44:55', '1 mac');
  ok(a[1] === 'fatal', '1 level normalisé en minuscules (fatal)');
  ok(a[3] === 'stream blocked 403', '1 message');
  ok(a[4].length === 8000, '1 detail tronqué à 8000');
  ok(a[6] === '950', '1 app_build');
}

// 2) message vide → 400
inserts.length = 0;
env = { DB: makeDb() };
r = await worker.fetch(new Request('https://app.x/api/error-log', {
  method: 'POST', headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ mac: 'MK:1', message: '   ' }),
}), env, ctx);
ok(r.status === 400, '2 message vide → 400');
ok(inserts.length === 0, '2 aucun INSERT');

// 3) GET → 400 (POST only)
env = { DB: makeDb() };
r = await worker.fetch(new Request('https://app.x/api/error-log', { method: 'GET' }), env, ctx);
ok(r.status === 400, '3 GET → 400 (POST only)');

// 4) niveau inconnu → 'error'
inserts.length = 0;
env = { DB: makeDb() };
r = await worker.fetch(new Request('https://app.x/api/error-log', {
  method: 'POST', headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ message: 'boom', level: 'weird' }),
}), env, ctx);
await r.json();
ok(inserts.length === 1 && inserts[0][1] === 'error', '4 niveau inconnu → error');

console.log(`\n${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
