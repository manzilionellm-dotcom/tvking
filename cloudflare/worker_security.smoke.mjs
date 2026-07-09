// =========================================================
//  worker_security.smoke.mjs — Tests de non-régression SÉCURITÉ
// =========================================================
//  Couvre le durcissement P0-3(compat)/P0-4/P1-7/P1-8/P1-9 du Worker :
//    - préflight CORS (OPTIONS) ;
//    - route inconnue → 404 (pas de redirect APK trompeur) ;
//    - rate-limit FAIL-OPEN sans D1 (ne casse jamais un client légitime) ;
//    - FILET GLOBAL : toute exception → 500 { error:'internal_error',
//      request_id } SANS fuite du message/stack interne.
//
//  Exécution (aucun runner requis, Node 18+ fournit Request/Response/URL) :
//    node cloudflare/worker_security.smoke.mjs
// =========================================================
import worker from './worker.js';

const ctx = { waitUntil() {}, passThroughOnException() {} };
let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass++; console.log('PASS', m); }
  else { fail++; console.log('FAIL', m); }
};

// 1) OPTIONS → 204 (préflight CORS)
let r = await worker.fetch(
  new Request('https://app.x/api/heartbeat', { method: 'OPTIONS' }), {}, ctx);
ok(r.status === 204, 'OPTIONS preflight = 204');

// 2) Route inconnue (3 segments) → 404
r = await worker.fetch(new Request('https://app.x/zzz/yyy/www'), {}, ctx);
ok(r.status === 404, 'unknown route = 404');

// 3) Rate-limit FAIL-OPEN sans D1 : la route est atteinte (400 POST-only).
r = await worker.fetch(
  new Request('https://app.x/api/heartbeat', { method: 'GET' }), {}, ctx);
ok(r.status === 400, 'rate-limit fail-open (no D1) -> route atteinte');

// 4) FILET GLOBAL : env qui throw à l'accès .DB → 500 générique, sans fuite.
const boom = new Proxy({}, {
  get(_, p) { if (p === 'DB') throw new Error('SECRET-INTERNAL-XYZ'); return undefined; },
});
r = await worker.fetch(
  new Request('https://app.x/api/heartbeat', { method: 'GET' }), boom, ctx);
const body = await r.json();
ok(r.status === 500, 'unhandled throw -> 500');
ok(body.error === 'internal_error' && !!body.request_id,
  '500 body = {error:internal_error, request_id}');
ok(!JSON.stringify(body).includes('SECRET-INTERNAL-XYZ'),
  'no internal message leak in 500 body');

// 5) SYNC INSTANTANÉ : /api/sync/:mac sans D1 → rev 0 stable (fail-open,
//    l'app garde son cycle lent), MAC invalide → 400.
r = await worker.fetch(
  new Request('https://app.x/api/sync/MK:11:22:33:44:55'), {}, ctx);
let sync = await r.json();
ok(r.status === 200 && sync.ok === true && sync.rev === 0,
  '/api/sync/:mac sans D1 -> {ok, rev:0} (fail-open)');
r = await worker.fetch(new Request('https://app.x/api/sync/xx'), {}, ctx);
ok(r.status === 400, '/api/sync MAC invalide -> 400');

// 6) ACCÈS APP : sans D1 → mode 'open' par défaut (jamais de blocage à tort).
r = await worker.fetch(new Request('https://app.x/api/app-access'), {}, ctx);
let access = await r.json();
ok(r.status === 200 && access.mode === 'open',
  '/api/app-access sans D1 -> open (fail-open)');

// 7) PRODUITS : sans D1 → liste vide, jamais d'erreur.
r = await worker.fetch(new Request('https://app.x/api/products'), {}, ctx);
let prods = await r.json();
ok(r.status === 200 && Array.isArray(prods.items) && prods.items.length === 0,
  '/api/products sans D1 -> items []');

// 8) CLÉ API inconnue → 401 (jamais de fallback silencieux vers le JWT).
r = await worker.fetch(new Request('https://app.x/api/v1/devices', {
  headers: { Authorization: 'Bearer 7mk_deadbeefdeadbeefdeadbeefdeadbeefdeadbeef' },
}), { DB: null }, ctx);
ok(r.status >= 400, 'API key inconnue -> refusée');

// 9) SORTIE RÉSEAU : /api/device-net/:mac sans D1 → { proxy:'', label:'' }
//    (fail-open : jamais de proxy imposé à tort → le client reste en direct).
r = await worker.fetch(
  new Request('https://app.x/api/device-net/MK:11:22:33:44:55'), {}, ctx);
let net = await r.json();
ok(r.status === 200 && net.proxy === '' && 'label' in net,
  '/api/device-net sans D1 -> direct (proxy vide)');
r = await worker.fetch(new Request('https://app.x/api/device-net/nope'), {}, ctx);
ok(r.status === 400, '/api/device-net MAC invalide -> 400');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
