// =========================================================
//  device_profiles.smoke.mjs — Les profils, des deux côtés
// =========================================================
//  On fait tourner LE VRAI code avec une base D1 simulée, sur les deux
//  routes qui existent :
//
//    • GET|PUT /api/v1/profiles/:mac — ce que le PANEL (admin-panel,
//      React) appelle, avec le jeton du revendeur ;
//    • GET /api/device-profiles/:mac — ce que l'APP lit, sans jeton.
//
//  Ce qui est testé n'est pas « est-ce que ça répond 200 », mais les
//  décisions qui, si elles se retournaient, casseraient quelque chose de
//  visible chez le client :
//
//    1. LA GÉNÉRATION AUTOMATIQUE. « Un seul M3U collé, cinq profils
//       apparaissent » : si elle ne partait pas, l'admin verrait une
//       liste vide et croirait la fonctionnalité absente.
//    2. LE PIN QUI NE RESSORT PAS EN CLAIR. S'il ressortait, il suffirait
//       de lire la réponse HTTP pour contourner le contrôle parental.
//    3. LES TROIS CAS DU PIN AU PUT (poser / effacer / laisser). Sans le
//       troisième, ouvrir puis enregistrer une fiche effacerait tous les
//       codes de la famille sans rien dire.
//    4. LES DROITS. Un revendeur « basique » ne peut pas lever le
//       contrôle parental d'un enfant chez un client.
//    5. LES DEUX ROUTES VOIENT LA MÊME CHOSE. Elles partagent
//       device_profiles.js ; ce test le prouve au lieu de le supposer.
//
//  Exécution : node cloudflare/device_profiles.smoke.mjs
// =========================================================
import { apiV1 } from './api_v1.js';
import worker from './worker.js';

const MAC = 'MK:BB:BB:BB:BB:01';
const SECRET = 'test-secret';

let pass = 0; let fail = 0;
const ok = (cond, label) => {
  if (cond) { pass++; console.log('  PASS ' + label); }
  else { fail++; console.log('  FAIL ' + label); }
};

// ---- JWT HS256, signé comme api_v1.js (même secret que ADMIN_SECRET) ----
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

// ---- D1 simulée : une seule table, en mémoire. -------------------------
const store = new Map(); // mac -> profiles_json
const db = {
  prepare(sql) {
    return {
      _sql: sql, _args: [],
      bind(...a) { this._args = a; return this; },
      async run() {
        if (/INSERT INTO device_profiles/.test(this._sql)) {
          store.set(this._args[0], this._args[1]);
        }
        return { success: true };
      },
      async first() {
        if (/FROM device_profiles WHERE mac/.test(this._sql)) {
          const j = store.get(this._args[0]);
          return j ? { profiles_json: j } : null;
        }
        // worker.js : appareil inconnu = non bloqué.
        return null;
      },
      async all() { return { results: [] }; },
    };
  },
};
const env = { DB: db, ADMIN_SECRET: SECRET };
const ctx = { waitUntil() {}, passThroughOnException() {} };

const admin = await makeJwt({ sub: 'adm_1', role: 'super_admin' });
const resellerFull = await makeJwt({
  sub: 'rsl_1', role: 'reseller', permissions: ['activate', 'sources'],
});
const resellerBasic = await makeJwt({
  sub: 'rsl_2', role: 'reseller', permissions: ['activate'],
});

const v1 = (path, opts = {}) => apiV1(
  new Request('https://app.x/api/v1/' + path, {
    method: opts.method || 'GET',
    headers: {
      ...(opts.token ? { Authorization: 'Bearer ' + opts.token } : {}),
      ...(opts.body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  }),
  env,
);
const app = (mac) => worker.fetch(
  new Request('https://app.x/api/device-profiles/' + mac), env, ctx,
);

// =========================================================
console.log('\n1. Génération automatique des cinq profils');
// =========================================================
let r = await v1('profiles/' + encodeURIComponent(MAC), { token: admin });
ok(r.status === 200, 'le panel lit les profils (statut ' + r.status + ')');
let body = await r.json();
ok(body.profiles.length === 5, 'cinq profils générés sans rien demander');
const noms = body.profiles.map((p) => p.name).join(', ');
console.log('    → ' + noms);
ok(/Papa/.test(noms) && /Maman/.test(noms), 'papa et maman sont là');
ok(body.profiles.filter((p) => p.kids).length === 3,
  'les trois enfants naissent en mode enfant (défaut le plus sûr)');
ok(body.profiles.every((p) => p.enabled), 'tous actifs au départ');
ok(body.profiles.every((p) => p.pin === null),
  'aucun PIN imposé — un code que personne ne connaît rendrait les profils inutilisables');

// Une 2e lecture doit rendre EXACTEMENT la même chose : si elle
// régénérait, chaque ouverture de la page écraserait les réglages.
const encore = await (await v1('profiles/' + encodeURIComponent(MAC), { token: admin })).json();
ok(JSON.stringify(encore.profiles) === JSON.stringify(body.profiles),
  'une seconde lecture ne régénère rien');

// =========================================================
console.log('\n2. Les deux routes voient la MÊME chose');
// =========================================================
const vuParLApp = await (await app(MAC)).json();
ok(vuParLApp.available === true, "l'app reçoit available = true");
ok(JSON.stringify(vuParLApp.profiles) === JSON.stringify(body.profiles),
  'panel et app lisent des profils identiques (device_profiles.js partagé)');

// =========================================================
console.log('\n3. Le panel pose un PIN, et il ne ressort jamais en clair');
// =========================================================
const avecPin = body.profiles.map((p) => (p.id === 'papa' ? { ...p, pin: '4242' } : p));
r = await v1('profiles/' + encodeURIComponent(MAC), {
  token: admin, method: 'PUT', body: { profiles: avecPin },
});
ok(r.status === 200, 'le PUT est accepté (statut ' + r.status + ')');

body = await (await v1('profiles/' + encodeURIComponent(MAC), { token: admin })).json();
const papa = body.profiles.find((p) => p.id === 'papa');
ok(papa && papa.pin && papa.pin.salt && papa.pin.hash, 'papa a une empreinte salée');
ok(!JSON.stringify(body).includes('4242'),
  'le code « 4242 » n\'apparaît nulle part dans la réponse du panel');
ok(!JSON.stringify(await (await app(MAC)).json()).includes('4242'),
  '…ni dans celle que reçoit l\'app');

// =========================================================
console.log('\n4. Les trois cas du PIN au PUT');
// =========================================================
// (a) PIN ABSENT du corps → code CONSERVÉ. C'est ce qui se produit chaque
//     fois qu'on ouvre la page et qu'on enregistre sans toucher au champ.
const empreinteAvant = JSON.stringify(papa.pin);
const sansChamp = body.profiles.map(({ pin, ...reste }) => reste);
await v1('profiles/' + encodeURIComponent(MAC), {
  token: admin, method: 'PUT', body: { profiles: sansChamp },
});
body = await (await v1('profiles/' + encodeURIComponent(MAC), { token: admin })).json();
ok(JSON.stringify(body.profiles.find((p) => p.id === 'papa').pin) === empreinteAvant,
  '(a) champ absent → le code est conservé');

// (b) PIN = "" → effacement explicite.
const vide = body.profiles.map((p) => (p.id === 'papa' ? { ...p, pin: '' } : p));
await v1('profiles/' + encodeURIComponent(MAC), {
  token: admin, method: 'PUT', body: { profiles: vide },
});
body = await (await v1('profiles/' + encodeURIComponent(MAC), { token: admin })).json();
ok(body.profiles.find((p) => p.id === 'papa').pin === null,
  '(b) chaîne vide → le code est effacé');

// (c) PIN invalide → refus net, plutôt qu'un code silencieusement ignoré.
const mauvais = body.profiles.map((p) => (p.id === 'papa' ? { ...p, pin: '12' } : p));
r = await v1('profiles/' + encodeURIComponent(MAC), {
  token: admin, method: 'PUT', body: { profiles: mauvais },
});
ok(r.status >= 400, '(c) « 12 » (trop court) est REFUSÉ, pas ignoré');

// =========================================================
console.log('\n5. Les droits');
// =========================================================
r = await v1('profiles/' + encodeURIComponent(MAC));
ok(r.status === 401, 'sans jeton → 401');

body = await (await v1('profiles/' + encodeURIComponent(MAC), { token: admin })).json();
const coupe = body.profiles.map((p) => (p.id === 'enfant1' ? { ...p, enabled: false } : p));

r = await v1('profiles/' + encodeURIComponent(MAC), {
  token: resellerBasic, method: 'PUT', body: { profiles: coupe },
});
ok(r.status === 403,
  'revendeur BASIQUE → 403 : il ne peut pas lever le contrôle parental d\'un enfant');

r = await v1('profiles/' + encodeURIComponent(MAC), {
  token: resellerFull, method: 'PUT', body: { profiles: coupe },
});
ok(r.status === 200, 'revendeur avec le droit « sources » → autorisé');

// =========================================================
console.log('\n6. Désactiver un profil à distance');
// =========================================================
body = await (await app(MAC)).json();
const e1 = body.profiles.find((p) => p.id === 'enfant1');
ok(e1 && e1.enabled === false, "enfant1 revient désactivé jusqu'à l'app");
ok(body.profiles.length === 5,
  'il reste VISIBLE dans la liste (grisé côté app, pas disparu)');

// =========================================================
console.log('\n7. Cas limites');
// =========================================================
r = await v1('profiles/pas-une-mac', { token: admin });
ok(r.status >= 400, 'MAC invalide → ' + r.status);

r = await worker.fetch(
  new Request('https://app.x/api/device-profiles/' + MAC), { DB: null }, ctx,
);
body = await r.json();
ok(body.available === false && body.profiles.length === 0,
  'sans base : available=false et liste VIDE — et non des profils sans PIN');
console.log('    (l\'app garde alors son cache : une panne D1 d\'une minute');
console.log('     ne doit pas effacer les codes de toutes les box)');

// L'ancien panel intégré est supprimé : son adresse doit REDIRIGER, pas
// mourir — quelqu'un peut l'avoir en favori.
r = await worker.fetch(new Request('https://app.x/admin/panel'), env, ctx);
ok(r.status === 301 && /tvking-admin\.pages\.dev/.test(r.headers.get('location') || ''),
  '/admin/panel redirige vers le vrai panel (' + r.status + ')');

console.log('\n' + pass + ' PASS, ' + fail + ' FAIL');
if (fail) process.exit(1);
