// =========================================================
//  api_v1_robustesse.smoke.mjs
// =========================================================
//  Défauts de robustesse du panel admin (listes, dates, erreurs).
//  Aucun secret réel : le jeton de test est signé avec un libellé
//  local « unit-test-only », jamais journalisé.
//
//    node cloudflare/api_v1_robustesse.smoke.mjs
// =========================================================
import { apiV1 } from './api_v1.js';
import {
  parsePageQuery, pageEnvelope, epochMs, liveLicenseStatus, redact,
} from './page_query.js';

const SECRET = 'unit-test-only';
let pass = 0;
let fail = 0;
const failures = [];
const ok = (c, m) => {
  if (c) { pass++; console.log('PASS', m); }
  else { fail++; failures.push(m); console.log('FAIL', m); }
};

function b64url(bytes) {
  let s = btoa(String.fromCharCode(...bytes));
  return s.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
async function signJwt(payload) {
  const header = { alg: 'HS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const claims = { ...payload, iat: now, exp: now + 3600 };
  const h = b64url(new TextEncoder().encode(JSON.stringify(header)));
  const p = b64url(new TextEncoder().encode(JSON.stringify(claims)));
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(SECRET),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${h}.${p}`)));
  return `${h}.${p}.${b64url(sig)}`;
}

const token = await signJwt({
  sub: 'adm_test', email: 'admin', role: 'super_admin', name: 'Test',
});

function authGet(path) {
  return new Request('https://panel.test' + path, {
    headers: { Authorization: 'Bearer ' + token },
  });
}

/// Fausse D1 : chaque prepare() répond selon le SQL.
function scriptedDb(decide) {
  const calls = [];
  const db = {
    calls,
    prepare(sql) {
      const exec = (args) => {
        calls.push({ sql, args });
        // La session est revalidée en base (compte actif, mot de passe).
        // Ces suites prouvent les listes, pas l'auth : on répond un admin actif
        // pour que le contrôle suivant soit bien celui de la page.
        if (/FROM admin_users/i.test(sql) && /WHERE id/i.test(sql)) {
          return {
            first: {
              id: 'adm_test', email: 'admin', name: 'Test',
              role: 'super_admin', is_active: 1, password_changed_at: null,
            },
          };
        }
        return decide(sql, args);
      };
      const api = (args) => ({
        all: async () => {
          const r = exec(args);
          if (r && r.throw) throw r.throw;
          return { results: (r && r.results) || [] };
        },
        first: async () => {
          const r = exec(args);
          if (r && r.throw) throw r.throw;
          if (r && Object.prototype.hasOwnProperty.call(r, 'first')) return r.first;
          return ((r && r.results) || [])[0] || null;
        },
        run: async () => {
          const r = exec(args);
          if (r && r.throw) throw r.throw;
          return { success: true };
        },
      });
      return { bind: (...args) => api(args), ...api([]) };
    },
  };
  return db;
}

// ----- purs -----
{
  const u = new URL('https://x/api/v1/devices?limit=99999&offset=400');
  const page = parsePageQuery(u);
  ok(page.limit === 200 && page.offset === 400, 'limit 99999 plafonne a 200, offset 400 garde');
  const bad = parsePageQuery(new URL('https://x/api/v1/devices?limit=-3&offset=abc'));
  ok(bad.limit === 200 && bad.offset === 0, 'limit negatif et offset illisible → defaut');
  const env = pageEnvelope([{ id: 1 }], 3500, 200, 0);
  ok(env.truncated === true && env.total === 3500, 'pageEnvelope dit tronque si total > page');
  const futureSec = Math.floor(Date.now() / 1000) + 86400 * 40;
  ok(liveLicenseStatus('active', futureSec, Date.now()) === 'active',
    'licence en secondes futures reste active');
  ok(liveLicenseStatus('active', Date.now() - 60_000, Date.now()) === 'expired',
    'licence active en base mais date passee → expired');
  ok(liveLicenseStatus('banned', Date.now() - 60_000, Date.now()) === 'banned',
    'banni reste banni meme expire');
  ok(liveLicenseStatus('active', null, Date.now()) === 'active', 'expires null = a vie');
  ok(epochMs(futureSec) > Date.now(), 'epochMs convertit les secondes');
  ok(!redact('password=LEAK-MARKER token=abc').includes('LEAK-MARKER'),
    'redact retire le marqueur de fuite');
}

const now = Date.now();
const futureSec = Math.floor(now / 1000) + 86400 * 40;

// ----- devices : pagination + total, pas un LIMIT 200 muet -----
{
  const db = scriptedDb((sql) => {
    if (/COUNT\(\*\)/i.test(sql)) return { first: { n: 3500 } };
    if (/FROM devices/i.test(sql)) {
      return { results: [{ id: 'd1', mac: 'MK:11:22:33:44:55', last_seen_at: now }] };
    }
    return { results: [] };
  });
  const res = await apiV1(authGet('/api/v1/devices?limit=99999&offset=400'), { DB: db, ADMIN_SECRET: SECRET });
  const body = await res.json();
  const listCall = db.calls.find((c) => /FROM devices/i.test(c.sql) && /LIMIT \?/i.test(c.sql));
  ok(res.status === 200, 'devices HTTP 200');
  ok(body.total === 3500, 'devices total 3500 (pas la taille de la page)');
  ok(body.truncated === true, 'devices truncated quand il reste des lignes');
  ok(body.limit === 200 && body.offset === 400, 'devices limit plafonne, offset respecte');
  ok(!!listCall && listCall.args.includes(200) && listCall.args.includes(400),
    'devices SQL lie LIMIT ? OFFSET ? (pas 99999 en clair)');
  ok(body.items.length === 1, 'devices ne renvoie que la page, pas 3500 lignes');
}

// ----- licences : statut recalcule, secondes et ms -----
{
  const db = scriptedDb((sql) => {
    if (/COUNT\(\*\)/i.test(sql)) return { first: { n: 2 } };
    if (/FROM licenses/i.test(sql)) {
      return { results: [
        { id: 'past', status: 'active', expires_at: now - 60_000, plan: 'yearly',
          customer_name: 'A', device_mac: 'MK:AA:BB:CC:DD:01' },
        { id: 'sec', status: 'active', expires_at: futureSec, plan: 'yearly',
          customer_name: 'B', device_mac: 'MK:AA:BB:CC:DD:02' },
        { id: 'ban', status: 'banned', expires_at: now - 60_000, plan: 'yearly',
          customer_name: 'C', device_mac: 'MK:AA:BB:CC:DD:03' },
      ] };
    }
    return { results: [] };
  });
  const res = await apiV1(authGet('/api/v1/licenses'), { DB: db, ADMIN_SECRET: SECRET });
  const body = await res.json();
  const byId = Object.fromEntries((body.items || []).map((r) => [r.id, r]));
  ok(byId.past && byId.past.status === 'expired',
    'licence date passee affichee expired (plus active menteur)');
  ok(byId.sec && byId.sec.status === 'active',
    'licence stockee en secondes futures pas marquee expiree');
  ok(byId.ban && byId.ban.status === 'banned', 'licence bannie pas ecrasee en expired');
  ok(body.total === 2, 'licenses expose le total');
}

// ----- en ligne : compteurs SQL, pas un slice, pas de pays « ?? » -----
{
  const db = scriptedDb((sql, args) => {
    if (/GROUP BY/i.test(sql)) {
      return { results: [{ c: 'FR', n: 10 }, { c: '??', n: 4 }] };
    }
    if (/COUNT\(\*\)/i.test(sql)) {
      const since = args[0] || 0;
      if (since > now - 20 * 60 * 1000) return { first: { n: 2400 } };
      return { first: { n: 5000 } };
    }
    if (/FROM presence/i.test(sql)) {
      return { results: [{ mac: 'MK:11:22:33:44:55', ip: '203.0.113.8', country: '', last_seen: now, channel: '' }] };
    }
    return { results: [] };
  });
  const res = await apiV1(authGet('/api/v1/online'), { DB: db, ADMIN_SECRET: SECRET });
  const body = await res.json();
  ok(body.onlineCount === 2400, 'onlineCount vient du COUNT, pas du nombre de lignes renvoyees');
  ok(body.todayCount === 5000, 'todayCount compte toute la journee, pas un plafond a 1000');
  ok(!body.byCountry || !Object.prototype.hasOwnProperty.call(body.byCountry, '??'),
    'pays vide ne devient pas le code ??');
  ok(body.byCountry && body.byCountry.FR === 10, 'pays FR conserve');
  ok(body.truncated === true, 'liste en ligne tronquee si le compteur depasse la page');
  ok(Array.isArray(body.items) && body.items.length === 1, 'page en ligne bornee');
}

// ----- references : une vraie panne n'est plus une liste vide -----
{
  const down = scriptedDb(() => ({ throw: new Error('D1 disk I/O error') }));
  const res = await apiV1(authGet('/api/v1/references'), { DB: down, ADMIN_SECRET: SECRET });
  const body = await res.json();
  ok(res.status === 500, 'references en panne disque → 500');
  ok(body.error === 'internal_error', 'references panne → error internal_error');
  ok(!(body.items && body.items.length === 0 && res.status === 200),
    'references panne ne pretend pas qu il n y a aucune MAC');

  const missing = scriptedDb(() => ({ throw: new Error('no such table: device_sources') }));
  const res2 = await apiV1(authGet('/api/v1/references'), { DB: missing, ADMIN_SECRET: SECRET });
  const body2 = await res2.json();
  ok(res2.status === 200 && Array.isArray(body2.items) && body2.items.length === 0,
    'references table absente → liste vide (base jamais migree)');
}

// ----- historique : meme regle -----
{
  const down = scriptedDb(() => ({ throw: new Error('D1 disk I/O error') }));
  const res = await apiV1(authGet('/api/v1/audit-logs'), { DB: down, ADMIN_SECRET: SECRET });
  ok(res.status === 500, 'audit-logs en panne disque → 500 (plus une liste vide)');
}

// ----- filet : pas de fuite, journal utile -----
{
  const logs = [];
  const orig = console.error;
  console.error = (...a) => { logs.push(a.map(String).join(' ')); };
  const boom = {
    prepare() { throw new Error('password=LEAK-MARKER at devices'); },
  };
  const res = await apiV1(authGet('/api/v1/devices'), { DB: boom, ADMIN_SECRET: SECRET });
  const text = await res.text();
  console.error = orig;
  ok(res.status === 500, 'exception devices → 500');
  ok(!text.includes('LEAK-MARKER'), 'le corps 500 ne contient pas le marqueur interne');
  ok(text.includes('request_id'), 'le 500 porte un request_id');
  ok(logs.length > 0 && logs.every((l) => !l.includes('LEAK-MARKER')),
    'le journal Worker est redacté (marqueur absent)');
  ok(logs.some((l) => l.includes('request_id') && l.includes('/api/v1/devices')),
    'le journal nomme la route et le request_id');
}

// ----- stats : ligne COUNT nulle ne plante pas le tableau de bord -----
{
  const db = scriptedDb(() => ({ first: null, results: [] }));
  const res = await apiV1(authGet('/api/v1/stats/overview'), { DB: db, ADMIN_SECRET: SECRET });
  const body = await res.json();
  ok(res.status === 200 && body.customers === 0 && body.devices === 0,
    'stats overview sur COUNT null → zeros, pas un 500');
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) {
  console.log('FAILED:', failures.join(' | '));
  process.exit(1);
}
