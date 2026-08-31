// =========================================================
//  device_profiles.smoke.mjs — Les profils vus du serveur
// =========================================================
//  On fait tourner LE VRAI worker (worker.js) avec une base D1 simulée en
//  mémoire, et on vérifie ce que les deux routes rendent réellement :
//
//    • GET  /api/device-profiles/:mac  — ce que l'APP reçoit
//    • GET|PUT /admin/profiles/:mac    — ce que le PANEL fait
//
//  Ce qui est testé n'est pas « est-ce que ça répond 200 », mais les trois
//  décisions qui, si elles se retournaient, casseraient quelque chose de
//  visible chez le client :
//
//    1. LA GÉNÉRATION AUTOMATIQUE. « Un seul M3U collé, cinq profils
//       apparaissent » : si elle ne partait pas, l'admin verrait une liste
//       vide et croirait la fonctionnalité absente.
//    2. LE PIN QUI NE RESSORT PAS EN CLAIR. S'il ressortait, il suffirait
//       de lire la réponse HTTP pour contourner le contrôle parental.
//    3. LES TROIS CAS DU PIN AU PUT (poser / effacer / laisser). Sans le
//       troisième, ouvrir puis enregistrer une fiche effacerait tous les
//       codes de la famille sans rien dire.
// =========================================================
import worker from './worker.js';

const MAC = 'MK:BB:BB:BB:BB:01';
const ADMIN = 'secret-de-test';

// --- D1 simulée : une seule table, en mémoire. ---------------------
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
        return null;
      },
      async all() { return { results: [] }; },
    };
  },
};

const ctx = { waitUntil() {}, passThroughOnException() {} };
const env = { DB: db, ADMIN_SECRET: ADMIN, ADMIN_TOKEN: ADMIN, ADMIN_PASSWORD: ADMIN };

const call = (url, init) => worker.fetch(new Request(url, init), env, ctx);
const admin = (path, init = {}) => call('https://app.x' + path, {
  ...init,
  headers: {
    'Content-Type': 'application/json',
    'X-Admin-Secret': ADMIN,
    Authorization: 'Bearer ' + ADMIN,
    ...(init.headers || {}),
  },
});

let pass = 0; let fail = 0;
function ok(cond, label) {
  if (cond) { pass++; console.log('  PASS ' + label); }
  else { fail++; console.log('  FAIL ' + label); }
}

// =========================================================
console.log('\n1. Génération automatique des cinq profils');
// =========================================================
let r = await call('https://app.x/api/device-profiles/' + MAC);
let body = await r.json();
ok(r.status === 200, 'la route publique répond 200');
ok(body.available === true, 'available = true (la base a répondu)');
ok(body.profiles.length === 5, 'cinq profils générés sans rien demander');
const noms = body.profiles.map((p) => p.name).join(', ');
console.log('    → ' + noms);
ok(/Papa/.test(noms) && /Maman/.test(noms), 'papa et maman sont là');
ok(body.profiles.filter((p) => p.kids).length === 3,
  'les trois enfants naissent en mode enfant (défaut le plus sûr)');
ok(body.profiles.every((p) => p.enabled), 'tous actifs au départ');
ok(body.profiles.every((p) => p.pin === null),
  'aucun PIN imposé — un code que personne ne connaît rendrait les profils inutilisables');

// La 2e lecture doit rendre EXACTEMENT la même chose : si elle
// régénérait, chaque appel de l'app écraserait les réglages du panel.
const r2 = await call('https://app.x/api/device-profiles/' + MAC);
const body2 = await r2.json();
ok(JSON.stringify(body2.profiles) === JSON.stringify(body.profiles),
  'une seconde lecture ne régénère rien');

// =========================================================
console.log('\n2. Le panel pose un PIN, et il ne ressort jamais en clair');
// =========================================================
const avecPin = body.profiles.map((p) => (
  p.id === 'papa' ? { ...p, pin: '4242' } : p
));
r = await admin('/admin/profiles/' + MAC, {
  method: 'PUT',
  body: JSON.stringify({ profiles: avecPin }),
});
ok(r.status === 200, 'le PUT est accepté (statut ' + r.status + ')');

r = await call('https://app.x/api/device-profiles/' + MAC);
body = await r.json();
const papa = body.profiles.find((p) => p.id === 'papa');
ok(papa && papa.pin && papa.pin.salt && papa.pin.hash,
  'papa a désormais une empreinte salée');
const brut = JSON.stringify(body);
ok(!brut.includes('4242'),
  'le code « 4242 » n\'apparaît NULLE PART dans la réponse');

// =========================================================
console.log('\n3. Les trois cas du PIN au PUT');
// =========================================================
// (a) PIN ABSENT du corps → le code existant est CONSERVÉ. C'est le cas
//     qui se produit à chaque fois que l'admin ouvre la fiche et
//     enregistre sans toucher au champ mot de passe.
const empreinteAvant = JSON.stringify(papa.pin);
const sansChamp = body.profiles.map(({ pin, ...reste }) => reste);
await admin('/admin/profiles/' + MAC, {
  method: 'PUT', body: JSON.stringify({ profiles: sansChamp }),
});
body = await (await call('https://app.x/api/device-profiles/' + MAC)).json();
ok(JSON.stringify(body.profiles.find((p) => p.id === 'papa').pin) === empreinteAvant,
  '(a) champ absent → le code est conservé');

// (b) PIN = "" → effacement explicite.
const vide = body.profiles.map((p) => (p.id === 'papa' ? { ...p, pin: '' } : p));
await admin('/admin/profiles/' + MAC, {
  method: 'PUT', body: JSON.stringify({ profiles: vide }),
});
body = await (await call('https://app.x/api/device-profiles/' + MAC)).json();
ok(body.profiles.find((p) => p.id === 'papa').pin === null,
  '(b) chaîne vide → le code est effacé');

// (c) PIN invalide → refus net, plutôt qu'un code silencieusement ignoré.
const mauvais = body.profiles.map((p) => (p.id === 'papa' ? { ...p, pin: '12' } : p));
r = await admin('/admin/profiles/' + MAC, {
  method: 'PUT', body: JSON.stringify({ profiles: mauvais }),
});
ok(r.status >= 400, '(c) « 12 » (trop court) est REFUSÉ, pas ignoré');

// =========================================================
console.log('\n4. Désactiver un profil à distance');
// =========================================================
body = await (await call('https://app.x/api/device-profiles/' + MAC)).json();
const coupe = body.profiles.map((p) => (
  p.id === 'enfant1' ? { ...p, enabled: false } : p
));
await admin('/admin/profiles/' + MAC, {
  method: 'PUT', body: JSON.stringify({ profiles: coupe }),
});
body = await (await call('https://app.x/api/device-profiles/' + MAC)).json();
const e1 = body.profiles.find((p) => p.id === 'enfant1');
ok(e1 && e1.enabled === false, 'enfant1 revient désactivé');
ok(body.profiles.length === 5,
  'il reste VISIBLE dans la liste (grisé côté app, pas disparu)');

// =========================================================
console.log('\n5. Ce que fait le worker quand la base est absente');
// =========================================================
r = await worker.fetch(
  new Request('https://app.x/api/device-profiles/' + MAC), { DB: null }, ctx,
);
body = await r.json();
ok(body.available === false, 'available = false');
ok(Array.isArray(body.profiles) && body.profiles.length === 0,
  'liste vide — et NON des profils par défaut sans PIN');
console.log('    (l\'app garde alors son cache : une panne D1 d\'une minute');
console.log('     ne doit pas effacer les codes de toutes les box)');

// =========================================================
console.log('\n6. Une MAC mal formée est refusée');
// =========================================================
r = await call('https://app.x/api/device-profiles/pas-une-mac');
ok(r.status >= 400, 'MAC invalide → ' + r.status);

console.log(`\n${pass} PASS, ${fail} FAIL`);
if (fail) process.exit(1);
