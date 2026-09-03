// =========================================================
//  lab_sources.smoke.mjs — LABO DU MAÎTRE (sources de test privées)
// =========================================================
//  Vérifie, avec un D1 simulé (même technique que insights_overview.smoke) :
//    1. auth : /api/v1/lab/sources sans jeton → 401 ; revendeur → 403
//       (même garde que /insights/overview) ;
//    2. POST {name, url} → création + attache AUTOMATIQUE à toutes les
//       MAC maîtres (attached_masters = nb de lignes app_masters) ;
//    3. GET → liste avec URL CAVIARDÉE (jamais de mot de passe en clair) ;
//    4. ÉTANCHÉITÉ PANEL : GET /api/v1/sources/:mac (liste normale) ne
//       touche JAMAIS la table lab_sources ;
//    5. ÉTANCHÉITÉ SYNC (worker.js /api/device-source/:mac) : une MAC
//       maître reçoit les sources labo EN PLUS, une MAC normale ne les
//       reçoit JAMAIS ;
//    6. STATS PROPRES : /insights/overview exclut les MAC maîtres de
//       chaque compteur (NOT EXISTS … app_masters), en LECTURE SEULE ;
//    7. DELETE → détache + supprime (liste vide ensuite, 404 si inconnu).
//
//  Exécution : node cloudflare/lab_sources.smoke.mjs
// =========================================================
import { apiV1 } from './api_v1.js';
import worker from './worker.js';

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

// ---- État partagé du D1 simulé -------------------------------------------
const MASTER = 'MK:AA:AA:AA:AA:01';
const MASTER2 = 'MK:AA:AA:AA:AA:02';
const NORMAL = 'MK:BB:BB:BB:BB:01';
const state = {
  labRows: [],   // lignes lab_sources { id, name, url, source_json, created_at }
  masters: [{ mac: MASTER }, { mac: MASTER2 }],
};

// D1 simulé : route chaque SQL vers l'état ci-dessus (regex, comme les
// autres smoke tests). `log` capture les SQL émis pour les assertions
// d'étanchéité (« tel endpoint n'a jamais touché lab_sources »).
function makeDb(log) {
  return {
    prepare(sql) {
      log.push(sql);
      return {
        _sql: sql, _args: [],
        bind(...args) { this._args = args; return this; },
        async run() {
          const s = this._sql;
          if (/^INSERT INTO lab_sources/.test(s)) {
            const [id, name, url, source_json, created_at] = this._args;
            state.labRows.push({ id, name, url, source_json, created_at });
          }
          if (/^DELETE FROM lab_sources/.test(s)) {
            state.labRows = state.labRows.filter((r) => r.id !== this._args[0]);
          }
          return { success: true };
        },
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
          if (/FROM sqlite_master/.test(s)) return { name: 'app_masters' };
          if (/COUNT\(\*\) AS n FROM app_masters/.test(s)) return { n: state.masters.length };
          if (/SELECT id, name FROM lab_sources WHERE id/.test(s)) {
            return state.labRows.find((r) => r.id === this._args[0]) || null;
          }
          // worker.js d1StatusForMac → appareil inconnu = non bloqué.
          if (/FROM devices WHERE mac = \?/.test(s)) return null;
          // worker.js handlePublicDeviceSource : la MAC NORMALE a une
          // source panel ; la MAC MAÎTRE n'a AUCUNE ligne device_sources.
          if (/FROM device_sources WHERE mac/.test(s)) {
            if (this._args[0] === NORMAL) {
              return { type: 'm3u', label: 'Client', server_url: null,
                username: null, password: null,
                m3u_url: 'https://client.tv/liste.m3u', epg_url: null,
                sources_json: null, updated_at: 1 };
            }
            return null;
          }
          // insights/overview : valeurs DIFFÉRENTES selon que le filtre
          // NOT EXISTS(app_masters) est présent → prouve l'exclusion.
          if (/COUNT\(\*\) AS n FROM devices/.test(s)) {
            return { n: /NOT EXISTS/.test(s) ? 98 : 100 };
          }
          if (/COUNT\(\*\) AS n FROM error_logs/.test(s)) {
            return { n: /NOT EXISTS/.test(s) ? 5 : 7 };
          }
          return null;
        },
        async all() {
          const s = this._sql;
          if (/SELECT mac FROM app_masters/.test(s)) return { results: state.masters };
          if (/FROM lab_sources/.test(s)) return { results: state.labRows };
          return { results: [] };
        },
      };
    },
  };
}

const callV1 = (path, { token, method = 'GET', body, log = [] } = {}) => apiV1(
  new Request('https://app.x/api/v1/' + path, {
    method,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  }),
  { DB: makeDb(log), ADMIN_SECRET: SECRET },
);

const admin = await makeJwt({ sub: 'adm_1', role: 'super_admin' });
const reseller = await makeJwt({ sub: 'rsl_1', role: 'reseller' });

// 1) Auth : sans jeton → 401 ; revendeur → 403 (le labo lui est invisible).
let r = await callV1('lab/sources');
ok(r.status === 401, '1 sans Authorization → 401');
r = await callV1('lab/sources', { token: reseller });
ok(r.status === 403, '1 revendeur → 403 (même garde que /insights/overview)');
r = await callV1('lab/sources', { token: reseller, method: 'POST', body: { name: 'x', url: 'https://a.b/c.m3u' } });
ok(r.status === 403, '1 revendeur → 403 aussi en POST');

// 2) POST admin : création + attache automatique à TOUS les maîtres.
r = await callV1('lab/sources', {
  token: admin, method: 'POST',
  body: { name: 'Ligne test', url: 'http://srv:8080/get.php?username=jean&password=supersecret' },
});
let b = await r.json();
ok(r.status === 200 && b.ok === true && /^lab_/.test(b.id), '2 POST → 200 + id lab_…');
ok(b.attached_masters === 2, '2 attache automatique aux 2 MAC maîtres');
ok(b.type === 'xtream', '2 lien get.php auto-détecté (activation universelle)');
const labId = b.id;

// URL invalide → 400 explicite, rien d'inséré.
r = await callV1('lab/sources', { token: admin, method: 'POST', body: { name: 'x', url: 'bonjour' } });
ok(r.status === 400 && state.labRows.length === 1, '2 URL invalide → 400 (pas de ligne créée)');

// 3) GET : liste avec URL caviardée — JAMAIS le mot de passe en clair.
r = await callV1('lab/sources', { token: admin });
b = await r.json();
ok(r.status === 200 && b.items.length === 1 && b.items[0].id === labId, '3 GET → la source labo listée');
ok(b.items[0].attached_masters === 2, '3 attached_masters présent par item');
ok(!JSON.stringify(b).includes('supersecret'), '3 mot de passe JAMAIS en clair dans la liste');
ok(/\*\*\*/.test(b.items[0].url), '3 caviardage visible (***) dans l’URL');
// CONTRAT DU PANEL : LabPage.tsx fait `Array.isArray(r.sources)` et bascule
// sur la carte « Le Labo arrive bientôt » dès que la clé manque — un 200
// sans `sources` a exactement l'apparence d'un endpoint non déployé.
ok(Array.isArray(b.sources) && b.sources.length === 1 && b.sources[0].id === labId,
  '3 clé `sources` servie au panel (contrat LabPage.tsx)');
ok(JSON.stringify(b.sources) === JSON.stringify(b.items),
  '3 `sources` et `items` portent exactement la même liste');

// 4) ÉTANCHÉITÉ PANEL : la liste NORMALE des sources d'une MAC
//    (GET /api/v1/sources/:mac, celle que voient admin ET revendeurs)
//    ne touche JAMAIS la table lab_sources.
let log4 = [];
r = await callV1('sources/' + encodeURIComponent(NORMAL), { token: admin, log: log4 });
b = await r.json();
ok(r.status === 200, '4 GET /sources/:mac répond');
ok(!JSON.stringify(b).includes('lab_'), '4 aucune source labo dans la réponse');
ok(log4.every((s) => !/lab_sources/.test(s)), '4 aucun SQL vers lab_sources (étanchéité par construction)');

// 5) ÉTANCHÉITÉ SYNC (worker.js) : /api/device-source/:mac.
const ctx = { waitUntil() {}, passThroughOnException() {} };
const wEnv = { DB: makeDb([]) };
//    5a. MAC NORMALE : sa source panel, RIEN du labo.
r = await worker.fetch(new Request('https://app.x/api/device-source/' + NORMAL), wEnv, ctx);
b = await r.json();
ok(r.status === 200 && b.source && b.source.m3u_url === 'https://client.tv/liste.m3u',
  '5a MAC normale → sa source panel');
ok(!JSON.stringify(b).includes('"lab"') && !JSON.stringify(b).includes('supersecret'),
  '5a MAC normale → AUCUNE source labo (rien ne fuit)');
//    5b. MAC MAÎTRE sans source panel : elle reçoit les sources labo.
r = await worker.fetch(new Request('https://app.x/api/device-source/' + MASTER), wEnv, ctx);
b = await r.json();
ok(r.status === 200 && Array.isArray(b.sources) && b.sources.some((s) => s.origin === 'lab'),
  '5b MAC maître → sources labo poussées par le canal de sync');
ok(b.sources.some((s) => s.username === 'jean' && s.password === 'supersecret'),
  '5b la box maître reçoit les identifiants COMPLETS (elle doit pouvoir lire)');

// 6) STATS PROPRES : /insights/overview exclut les maîtres de chaque
//    compteur (le mock renvoie 98/5 si le filtre NOT EXISTS est présent,
//    100/7 sinon) — et reste en lecture seule.
let log6 = [];
r = await callV1('insights/overview', { token: admin, log: log6 });
b = await r.json();
ok(r.status === 200 && b.devices && b.devices.total === 98,
  '6 devices.total SANS les box maîtres (filtre NOT EXISTS actif)');
ok(b.errors_7d && b.errors_7d.count === 5, '6 errors_7d SANS les erreurs du labo');
const devSql = log6.filter((s) => /FROM devices/.test(s));
ok(devSql.length > 0 && devSql.every((s) => /NOT EXISTS \(SELECT 1 FROM app_masters/.test(s)),
  '6 CHAQUE requête devices porte l’exclusion app_masters');
ok(log6.filter((s) => /FROM error_logs/.test(s))
  .every((s) => /NOT EXISTS \(SELECT 1 FROM app_masters/.test(s)),
  '6 CHAQUE requête error_logs porte l’exclusion app_masters');
ok(log6.every((s) => !/^\s*(CREATE|ALTER|UPDATE|INSERT|DELETE)/i.test(s)),
  '6 lecture seule : aucun DDL/écriture émis par /insights/overview');

// 7) DELETE : détache + supprime (l'attache est dynamique → supprimer la
//    ligne suffit, la source disparaît des box au sync suivant).
r = await callV1('lab/sources/inconnu', { token: admin, method: 'DELETE' });
ok(r.status === 404, '7 DELETE id inconnu → 404');
r = await callV1('lab/sources/' + labId, { token: admin, method: 'DELETE' });
b = await r.json();
ok(r.status === 200 && b.ok === true && state.labRows.length === 0, '7 DELETE → supprimée');
r = await callV1('lab/sources', { token: admin });
b = await r.json();
ok(r.status === 200 && b.items.length === 0, '7 liste vide après suppression');

console.log(`\n${pass} PASS, ${fail} FAIL`);
if (fail > 0) process.exit(1);
