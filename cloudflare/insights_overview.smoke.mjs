// =========================================================
//  insights_overview.smoke.mjs — Agrégats du parc (Vague C21)
// =========================================================
//  Vérifie GET /api/v1/insights/overview (api_v1.js) avec un D1 simulé :
//    - sans jeton → 401 ; jeton revendeur → 403 (le parc global est
//      réservé au staff interne) ;
//    - jeton admin → 200 + contrat JSON complet (generated_at, devices,
//      versions, errors_7d) avec les bons mappings de colonnes
//      (last_seen_at → last_seen, expires_at → paid_until) ;
//    - les secrets (password=…, user:pass@host) sont CAVIARDÉS des
//      messages d'erreur avant de partir vers le panel ;
//    - le cache mémoire 60 s sert la 2ᵉ requête SANS retoucher D1.
//
//  Exécution : node cloudflare/insights_overview.smoke.mjs
// =========================================================
import { apiV1 } from './api_v1.js';

let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('PASS', m); } else { fail++; console.log('FAIL', m); } };

// ---- JWT HS256 signé comme api_v1.js (même secret que env.ADMIN_SECRET) ----
const SECRET = 'test-secret';
const b64url = (buf) => Buffer.from(buf).toString('base64url');
async function makeJwt(payload) {
  const now = Math.floor(Date.now() / 1000);
  const h = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const p = b64url(JSON.stringify({ ...payload, iat: now, exp: now + 3600 }));
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(SECRET),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${h}.${p}`));
  return `${h}.${p}.${b64url(sig)}`;
}

// ---- D1 simulé : route chaque requête SQL vers des lignes canned ----
//  On distingue les deux COUNT sur last_seen_at (24 h vs 7 j) par la
//  valeur du bind (fenêtre de 24 h → borne > now - 2 jours).
const t0 = Date.now();
const DAY = 24 * 60 * 60 * 1000;
let sqlSeen = [];
function makeDb() {
  return {
    prepare(sql) {
      sqlSeen.push(sql);
      return {
        _sql: sql, _args: [],
        bind(...args) { this._args = args; return this; },
        async run() { return { success: true }; },
        async first() {
        // Comptes de l'API : depuis le 03/09, requireAuth relit
        // l'identite en base a chaque requete (un revendeur revoque doit
        // perdre l'acces tout de suite, pas dans 7 jours). Une base
        // simulee qui ne connait aucun compte ferait donc echouer toute
        // requete authentifiee — ce qui serait le bon comportement en
        // vrai, et un faux monde ici.
        if (/FROM admin_users WHERE id/.test(this._sql)) {
          return { id: this._args[0], role: 'super_admin', is_active: 1 };
        }
        if (/FROM resellers WHERE id = \?$/.test(this._sql.trim())
            || /SELECT id, status, level, permissions FROM resellers/.test(this._sql)) {
          return { id: this._args[0], status: 'active', level: 'standard',
            permissions: null };
        }

          const s = this._sql;
          if (/FROM devices WHERE last_seen_at >/.test(s)) {
            return { n: this._args[0] > t0 - 2 * DAY ? 40 : 70 };
          }
          if (/FROM devices WHERE first_seen_at >/.test(s)) return { n: 12 };
          if (/COUNT\(\*\) AS n FROM devices/.test(s)) return { n: 100 };
          if (/FROM error_logs WHERE created_at >/.test(s)) return { n: 7 };
          return null;
        },
        async all() {
          const s = this._sql;
          if (/ORDER BY last_seen_at DESC LIMIT 50/.test(s)) {
            return { results: [
              { mac: 'MK:AA:AA:AA:AA:AA', last_seen_at: t0 - 8 * DAY },
              { mac: 'MK:BB:BB:BB:BB:BB', last_seen_at: t0 - 9 * DAY },
            ] };
          }
          if (/AS paid_until/.test(s)) {
            return { results: [{ mac: 'MK:CC:CC:CC:CC:CC', paid_until: t0 + 3 * DAY }] };
          }
          if (/GROUP BY app_version/.test(s)) {
            return { results: [{ version: '0.3.3', n: 60 }, { version: '0.3.2', n: 40 }] };
          }
          if (/GROUP BY message/.test(s)) {
            return { results: [{
              message: 'stream 403 http://jean:supersecret@srv.example.com/live'
                + ' password=topsecret Bearer abc.def.ghi',
              n: 3,
            }] };
          }
          return { results: [] };
        },
      };
    },
  };
}

const call = (token, env) => apiV1(
  new Request('https://app.x/api/v1/insights/overview', {
    method: 'GET',
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  }), env,
);

// 1) Sans jeton → 401.
let env = { DB: makeDb(), ADMIN_SECRET: SECRET };
let r = await call(null, env);
ok(r.status === 401, '1 sans Authorization → 401');

// 2) Jeton revendeur → 403 (jamais le parc global).
r = await call(await makeJwt({ sub: 'rsl_1', role: 'reseller' }), env);
ok(r.status === 403, '2 revendeur → 403');

// 3) Jeton admin → 200 + contrat complet.
sqlSeen = [];
r = await call(await makeJwt({ sub: 'adm_1', role: 'super_admin' }), env);
const b = await r.json();
ok(r.status === 200, '3 admin → 200');
ok(typeof b.generated_at === 'number', '3 generated_at présent');
ok(b.devices && b.devices.total === 100, '3 devices.total');
ok(b.devices.active_24h === 40 && b.devices.active_7d === 70,
  '3 active_24h / active_7d distingués');
ok(b.devices.new_7d === 12, '3 new_7d');
ok(Array.isArray(b.devices.silent_7d) && b.devices.silent_7d.length === 2
  && b.devices.silent_7d[0].mac === 'MK:AA:AA:AA:AA:AA'
  && typeof b.devices.silent_7d[0].last_seen === 'number',
  '3 silent_7d mappé {mac, last_seen}');
ok(Array.isArray(b.devices.expiring_7d)
  && b.devices.expiring_7d[0].mac === 'MK:CC:CC:CC:CC:CC'
  && typeof b.devices.expiring_7d[0].paid_until === 'number',
  '3 expiring_7d mappé {mac, paid_until}');
ok(Array.isArray(b.versions) && b.versions[0].version === '0.3.3'
  && b.versions[0].count === 60, '3 versions [{version, count}]');
ok(b.errors_7d && b.errors_7d.count === 7, '3 errors_7d.count');
const top = (b.errors_7d.top || [])[0] || {};
ok(top.count === 3 && typeof top.message === 'string', '3 errors_7d.top présent');
ok(top.message.length <= 120, '3 message tronqué ≤ 120');
ok(!/supersecret|topsecret|abc\.def\.ghi/.test(top.message),
  '3 secrets caviardés (pas de mot de passe / jeton en clair)');
ok(/\*\*\*/.test(top.message), '3 caviardage visible (***)');
ok(sqlSeen.every((s) => !/^\s*(CREATE|ALTER|UPDATE|INSERT|DELETE)/i.test(s)),
  '3 lecture seule : aucun DDL/écriture émis');

// 4) Cache mémoire 60 s : 2ᵉ appel avec une D1 qui EXPLOSE → réponse
//    identique servie depuis le cache, zéro requête SQL.
const boom = { prepare() { throw new Error('D1 down'); } };
r = await call(await makeJwt({ sub: 'adm_1', role: 'super_admin' }),
  { DB: boom, ADMIN_SECRET: SECRET });
const b2 = await r.json();
ok(r.status === 200 && b2.generated_at === b.generated_at,
  '4 cache 60 s : même réponse sans toucher D1');

console.log(`\n${pass} PASS, ${fail} FAIL`);
if (fail > 0) process.exit(1);
