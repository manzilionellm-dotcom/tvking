// =========================================================
//  realtime.smoke.mjs — Tests de fumée de la couche temps réel
// =========================================================
//  Vérifie SANS runtime Cloudflare (Node 18+ suffit) :
//    - realtime.js et worker.js s'importent sans erreur (syntaxe/module) ;
//    - RealtimeHub est bien exporté (classe) par realtime.js ET ré-exporté
//      par worker.js (exigence wrangler : la classe DO doit sortir du
//      module principal) ;
//    - publishRt est FAIL-OPEN : sans binding RT_HUB → {delivered:0,
//      id:null}, et même un binding qui EXPLOSE ne fait jamais planter ;
//    - rtAvailable reflète la présence du binding ;
//    - les routes rt du Worker répondent proprement sans binding :
//      /api/rt/device sans Upgrade → 426, /api/v1/rt/ws sans token → 401.
//
//  Exécution :
//    node cloudflare/realtime.smoke.mjs
// =========================================================
import { RealtimeHub, publishRt, rtAvailable } from './realtime.js';
import worker, { RealtimeHub as ReExported } from './worker.js';

const ctx = { waitUntil() {}, passThroughOnException() {} };
let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass++; console.log('PASS', m); }
  else { fail++; console.log('FAIL', m); }
};

// 1) Exports : la classe DO existe et worker.js la ré-exporte (wrangler
//    cherche class_name = "RealtimeHub" dans le module main).
ok(typeof RealtimeHub === 'function', 'RealtimeHub exporte par realtime.js');
ok(ReExported === RealtimeHub, 'worker.js re-exporte la MEME classe RealtimeHub');

// 2) publishRt FAIL-OPEN : env sans RT_HUB → {delivered:0, id:null}.
let r = await publishRt({}, { targets: ['MK:AA:BB:CC:DD:EE'], event: { type: 'sync', what: 'status' } });
ok(r && r.delivered === 0 && r.id === null, 'publishRt sans RT_HUB -> {delivered:0, id:null}');
r = await publishRt(undefined, {});
ok(r && r.delivered === 0 && r.id === null, 'publishRt sans env -> {delivered:0, id:null}');

// 3) publishRt FAIL-OPEN même si le binding EXPLOSE (pas d'exception).
const boomEnv = {
  RT_HUB: {
    idFromName() { return 'id'; },
    get() { return { fetch() { throw new Error('BOOM-INTERNAL'); } }; },
  },
};
r = await publishRt(boomEnv, { targets: 'admins', event: { type: 'changed', scope: 'devices' } });
ok(r && r.delivered === 0 && r.id === null, 'publishRt binding qui throw -> fail-open {delivered:0}');

// 4) rtAvailable reflète le binding.
ok(rtAvailable({ RT_HUB: {} }) === true, 'rtAvailable(env avec RT_HUB) = true');
ok(rtAvailable({}) === false, 'rtAvailable(env sans RT_HUB) = false');

// 5) Routes rt du Worker (sans binding RT_HUB) :
//    device sans header Upgrade → 426 (jamais un 500).
r = await worker.fetch(
  new Request('https://app.x/api/rt/device?mac=MK%3AAA%3ABB%3ACC%3ADD%3AEE'), {}, ctx);
ok(r.status === 426, '/api/rt/device sans Upgrade -> 426');

//    SANS SECRET DE SIGNATURE → 503 (03/09/2026).
//    Avant, le Worker retombait sur la chaine publique 'dev-secret' :
//    n'importe qui pouvait forger un jeton d'administrateur et ecouter
//    le flux temps reel de TOUT le parc. Desormais, pas de secret, pas
//    de service — et on le DIT, au lieu de fonctionner faussement.
r = await worker.fetch(
  new Request('https://app.x/api/v1/rt/ws', { headers: { Upgrade: 'websocket' } }), {}, ctx);
let body = await r.json();
ok(r.status === 503 && body.error === 'server_unconfigured',
  '/api/v1/rt/ws sans JWT_SECRET/ADMIN_SECRET -> 503 (plus de repli dev-secret)');

//    AVEC un secret configure mais SANS token → 401 forme api_v1.
r = await worker.fetch(
  new Request('https://app.x/api/v1/rt/ws', { headers: { Upgrade: 'websocket' } }),
  { ADMIN_SECRET: 'un-vrai-secret' }, ctx);
body = await r.json();
ok(r.status === 401 && body.error === 'unauthorized' && !!body.message,
  '/api/v1/rt/ws sans token -> 401 {error:unauthorized, message}');

//    device avec Upgrade mais SANS binding → 503 rt_unavailable.
r = await worker.fetch(
  new Request('https://app.x/api/rt/device?mac=MK%3AAA%3ABB%3ACC%3ADD%3AEE',
    { headers: { Upgrade: 'websocket' } }), {}, ctx);
body = await r.json();
ok(r.status === 503 && body.error === 'rt_unavailable',
  '/api/rt/device sans binding -> 503 rt_unavailable');

//    MAC invalide (avec Upgrade + binding factice) → 400 avant tout forward.
r = await worker.fetch(
  new Request('https://app.x/api/rt/device?mac=nope',
    { headers: { Upgrade: 'websocket' } }), { RT_HUB: {} }, ctx);
ok(r.status === 400, '/api/rt/device mac invalide -> 400');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
