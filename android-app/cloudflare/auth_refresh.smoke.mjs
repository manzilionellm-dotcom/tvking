// =========================================================
//  auth_refresh.smoke.mjs — Session du panel (JWT)
// =========================================================
//  Couvre POST /api/v1/auth/refresh :
//    - un jeton encore valide est renouvelé (admin 30 j, revendeur 7 j) ;
//    - un jeton de 7 jours déjà émis (ancien format, même HMAC) passe
//      encore /auth/me ET peut être renouvelé ;
//    - un jeton expiré est refusé, aucun jeton neuf ;
//    - un jeton falsifié (mauvaise signature) est refusé ;
//    - un compte revendeur suspendu ou un admin désactivé n'est pas
//      prolongé ;
//    - le rate-limit du seau « refresh » répond 429, pas 401.
//
//  Exécution (Node 18+, Web Crypto) :
//    node cloudflare/auth_refresh.smoke.mjs
// =========================================================
import {
  apiV1,
  signJwt,
  verifyJwt,
  ADMIN_SESSION_MINUTES,
  RESELLER_SESSION_MINUTES,
} from './api_v1.js';

const SECRET = 'test-secret-not-the-real-admin-secret';
let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass++; console.log('PASS', m); }
  else { fail++; console.log('FAIL', m); }
};

function claimsOf(token) {
  const p = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
  const padded = p + '='.repeat((4 - (p.length % 4)) % 4);
  return JSON.parse(Buffer.from(padded, 'base64').toString());
}

function headerOf(token) {
  const h = token.split('.')[0].replace(/-/g, '+').replace(/_/g, '/');
  const padded = h + '='.repeat((4 - (h.length % 4)) % 4);
  return JSON.parse(Buffer.from(padded, 'base64').toString());
}

/// Mini D1 : assez pour le rate-limit (fail vers « autorisé ») et les
/// lectures de compte du refresh. `blocked` force le seau refresh à 429.
function memoryDb({ admins = [], resellers = [], blocked = false } = {}) {
  return {
    prepare(sql) {
      const api = (args) => ({
        async first() {
          if (sql.includes('rate_limits')) {
            if (blocked) return { count: 999, window_start: Date.now() };
            return null;
          }
          if (sql.includes('admin_users')) {
            return admins.find((a) => a.id === args[0]) || null;
          }
          if (sql.includes('FROM resellers')) {
            return resellers.find((r) => r.id === args[0]) || null;
          }
          return null;
        },
        async run() { return { success: true }; },
        async all() { return { results: [] }; },
      });
      return {
        bind(...args) { return api(args); },
        first() { return api([]).first(); },
        run() { return api([]).run(); },
        all() { return api([]).all(); },
      };
    },
  };
}

function envFor(opts) {
  return { DB: memoryDb(opts), ADMIN_SECRET: SECRET };
}

async function callRefresh(token, env) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  return apiV1(new Request('https://app.x/api/v1/auth/refresh', {
    method: 'POST',
    headers,
  }), env);
}

const admin = {
  id: 'adm_1', email: 'admin', name: 'Owner', role: 'super_admin', is_active: 1,
};
const reseller = {
  id: 'rsl_1',
  email: 'karim',
  name: 'Karim',
  status: 'active',
  level: 'basique',
  permissions: '["activate"]',
  credit_balance: 4,
};

const WEEK_MIN = 60 * 24 * 7;

// --- Ancien jeton 7 jours : toujours accepté, même signature ---
const oldAdmin = await signJwt(
  { sub: admin.id, email: admin.email, role: admin.role, name: admin.name },
  SECRET,
  WEEK_MIN,
);
const oldClaims = claimsOf(oldAdmin);
ok(oldClaims.exp - oldClaims.iat === WEEK_MIN * 60, 'jeton historique = 7 jours');
ok(headerOf(oldAdmin).alg === 'HS256', 'algorithme inchangé HS256');
ok(!!await verifyJwt(oldAdmin, SECRET), 'verifyJwt accepte le jeton 7 jours');

const me = await apiV1(new Request('https://app.x/api/v1/auth/me', {
  headers: { Authorization: `Bearer ${oldAdmin}` },
}), envFor({ admins: [admin] }));
ok(me.status === 200, 'GET /auth/me accepte un jeton 7 jours déjà émis');
const meBody = await me.json();
ok(meBody.user && meBody.user.role === 'super_admin' && meBody.user.sub === 'adm_1',
  'le rôle du jeton 7 jours est conservé');

// --- Refresh OK (admin) : nouveau jeton 30 jours, même sujet / rôle ---
const refreshed = await callRefresh(oldAdmin, envFor({ admins: [admin] }));
ok(refreshed.status === 200, 'refresh admin 200');
const refreshedBody = await refreshed.json();
ok(typeof refreshedBody.token === 'string' && refreshedBody.token !== oldAdmin,
  'refresh renvoie un jeton neuf');
ok(!!await verifyJwt(refreshedBody.token, SECRET),
  'le jeton neuf se vérifie avec le MÊME secret');
const newClaims = claimsOf(refreshedBody.token);
ok(newClaims.sub === 'adm_1' && newClaims.role === 'super_admin',
  'refresh admin garde sub + rôle');
ok(newClaims.exp - newClaims.iat === ADMIN_SESSION_MINUTES * 60,
  'session admin renouvelée = 30 jours');
ok(refreshedBody.expires_in === ADMIN_SESSION_MINUTES * 60, 'expires_in admin = 30 j');
ok(headerOf(refreshedBody.token).alg === 'HS256', 'jeton neuf toujours HS256');

// --- Refresh OK (revendeur) : 7 jours, droits relus en base ---
const staleReseller = await signJwt({
  sub: reseller.id,
  email: reseller.email,
  role: 'reseller',
  name: reseller.name,
  level: 'confiance',
  // Droits périmés DANS le jeton : la base n'a plus que « activate ».
  permissions: ['activate', 'sources', 'resellers'],
}, SECRET, WEEK_MIN);
const rRef = await callRefresh(staleReseller, envFor({ resellers: [reseller] }));
ok(rRef.status === 200, 'refresh revendeur 200');
const rBody = await rRef.json();
const rClaims = claimsOf(rBody.token);
ok(rClaims.role === 'reseller' && rClaims.sub === 'rsl_1',
  'refresh revendeur ne promeut pas en admin');
ok(rClaims.exp - rClaims.iat === RESELLER_SESSION_MINUTES * 60,
  'session revendeur renouvelée = 7 jours');
ok(Array.isArray(rBody.user.permissions) && rBody.user.permissions.length === 1
  && rBody.user.permissions[0] === 'activate',
  'les droits revendeur viennent de la base, pas du vieux jeton');

// --- Jeton expiré : refusé, pas de jeton neuf ---
const expired = await signJwt(
  { sub: admin.id, email: admin.email, role: admin.role, name: admin.name },
  SECRET,
  -5,
);
ok(await verifyJwt(expired, SECRET) === null, 'verifyJwt refuse un jeton expiré');
const expResp = await callRefresh(expired, envFor({ admins: [admin] }));
const expBody = await expResp.json();
ok(expResp.status === 401 && expBody.error === 'bad_token' && !expBody.token,
  'refresh refuse un jeton expiré sans en émettre un neuf');

// --- Jeton falsifié : signature modifiée ---
const parts = oldAdmin.split('.');
const last = parts[2].slice(-1) === 'a' ? 'b' : 'a';
const forged = `${parts[0]}.${parts[1]}.${parts[2].slice(0, -1)}${last}`;
ok(await verifyJwt(forged, SECRET) === null, 'verifyJwt refuse une signature falsifiée');
const forgedResp = await callRefresh(forged, envFor({ admins: [admin] }));
const forgedBody = await forgedResp.json();
ok(forgedResp.status === 401 && forgedBody.error === 'bad_token' && !forgedBody.token,
  'refresh refuse un jeton falsifié sans en émettre un neuf');

// --- Mauvais secret (autre clé HMAC) ---
const other = await signJwt(
  { sub: admin.id, email: admin.email, role: admin.role, name: admin.name },
  'another-secret',
  WEEK_MIN,
);
const otherResp = await callRefresh(other, envFor({ admins: [admin] }));
ok(otherResp.status === 401, 'jeton signé avec un autre secret refusé');

// --- Compte coupé : on ne prolonge pas ---
const inactive = { ...admin, is_active: 0 };
const deadAdmin = await callRefresh(oldAdmin, envFor({ admins: [inactive] }));
ok(deadAdmin.status === 401, 'admin désactivé : refresh refusé');

const suspended = { ...reseller, status: 'suspended' };
const deadReseller = await callRefresh(
  staleReseller,
  envFor({ resellers: [suspended] }),
);
ok(deadReseller.status === 401, 'revendeur suspendu : refresh refusé');

// --- Rate limit : 429, la session n'est pas déclarée invalide ---
const limited = await callRefresh(oldAdmin, envFor({ admins: [admin], blocked: true }));
const limitedBody = await limited.json();
ok(limited.status === 429 && limitedBody.error === 'rate_limited' && !limitedBody.token,
  'rate-limit refresh = 429 sans nouveau jeton');

// --- Pas de jeton ---
const anon = await callRefresh(null, envFor({ admins: [admin] }));
ok(anon.status === 401, 'refresh sans Authorization = 401');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
