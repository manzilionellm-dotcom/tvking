// =========================================================
//  session_policy.smoke.mjs — Le panel ne déconnecte pas trop tôt
// =========================================================
//  La règle réelle est dans src/lib/sessionPolicy.ts, appelée par
//  request() (api.ts) et par le démarrage (App.tsx).
//
//    node --experimental-strip-types session_policy.smoke.mjs
// =========================================================
import {
  decideBootOutcome,
  isSessionRejection,
  isTimeoutError,
  nextTokenAfterResponse,
  tokenNeedsRefresh,
} from './src/lib/sessionPolicy.ts';

let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass++; console.log('PASS', m); }
  else { fail++; console.log('FAIL', m); }
};

function jwt(iat, exp) {
  const enc = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  return `${enc({ alg: 'HS256', typ: 'JWT' })}.${enc({ iat, exp, sub: 'a' })}.sig`;
}

const TOKEN = 'eyJhbGciOiJIUzI1NiJ9.payload.sig';

// --- Pas de déconnexion sur erreur réseau, timeout, 5xx, 429 ---
ok(
  nextTokenAfterResponse(TOKEN, { kind: 'network' }) === TOKEN,
  'erreur réseau : le jeton est conservé',
);
ok(
  nextTokenAfterResponse(TOKEN, { kind: 'timeout' }) === TOKEN,
  'timeout : le jeton est conservé',
);
ok(
  nextTokenAfterResponse(TOKEN, { kind: 'http', status: 500, code: 'internal_error' }) === TOKEN,
  '5xx : le jeton est conservé',
);
ok(
  nextTokenAfterResponse(TOKEN, { kind: 'http', status: 429, code: 'rate_limited' }) === TOKEN,
  '429 : le jeton est conservé',
);
ok(
  decideBootOutcome({ status: null, code: null }) === 'keep',
  'démarrage sans réponse HTTP : on ne déconnecte pas',
);
ok(
  decideBootOutcome({ status: 500, code: 'internal_error' }) === 'keep',
  'démarrage sur 500 : on ne déconnecte pas',
);
ok(
  decideBootOutcome({ status: 503, code: 'http_error' }) === 'keep',
  'démarrage sur 503 : on ne déconnecte pas',
);

// --- Vrai 401 : on déconnecte ---
ok(
  nextTokenAfterResponse(TOKEN, { kind: 'http', status: 401, code: 'bad_token' }) === null,
  '401 bad_token : le jeton est effacé',
);
ok(
  nextTokenAfterResponse(TOKEN, { kind: 'http', status: 401, code: 'no_auth' }) === null,
  '401 no_auth : le jeton est effacé',
);
ok(
  decideBootOutcome({ status: 401, code: 'bad_token' }) === 'logged_out',
  'démarrage sur jeton expiré : déconnexion',
);
ok(isSessionRejection(401, 'bad_token'), 'bad_token est un rejet de session');

// --- 401 de saisie (mot de passe) : on ne déconnecte pas ---
ok(
  nextTokenAfterResponse(TOKEN, { kind: 'http', status: 401, code: 'bad_current' }) === TOKEN,
  'mauvais mot de passe actuel : session conservée',
);
ok(
  nextTokenAfterResponse(TOKEN, {
    kind: 'http', status: 401, code: 'bad_credentials', noAuth: true,
  }) === TOKEN,
  'login raté : session conservée',
);
ok(
  decideBootOutcome({ status: 401, code: 'bad_current' }) === 'keep',
  'bad_current ne déconnecte pas au démarrage',
);

// Un timeout n'est pas une ApiError de session.
ok(isTimeoutError({ name: 'TimeoutError' }), 'TimeoutError reconnu');
ok(isTimeoutError({ name: 'AbortError' }), 'AbortError reconnu');
ok(!isTimeoutError(new TypeError('Failed to fetch')), 'TypeError réseau ≠ timeout');

// --- Moitié de vie : 7 jours (ancien) et 30 jours (admin) ---
const week = 7 * 24 * 60 * 60;
ok(!tokenNeedsRefresh(jwt(1_000, 1_000 + week), 1_000 + week / 2 - 1),
  'avant la moitié (jeton 7 j) : pas de refresh');
ok(tokenNeedsRefresh(jwt(1_000, 1_000 + week), 1_000 + week / 2),
  'à la moitié (jeton 7 j) : refresh');
const month = 30 * 24 * 60 * 60;
ok(!tokenNeedsRefresh(jwt(5_000, 5_000 + month), 5_000 + 10 * 24 * 60 * 60),
  '10 jours sur 30 : pas encore de refresh');
ok(tokenNeedsRefresh(jwt(5_000, 5_000 + month), 5_000 + month / 2),
  '15 jours sur 30 : refresh');
ok(!tokenNeedsRefresh('pas-un-jwt'), 'jeton illisible : pas de refresh agressif');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
