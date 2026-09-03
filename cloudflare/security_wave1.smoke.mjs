// =========================================================
//  security_wave1.smoke.mjs — Les portes sont fermées
// =========================================================
//  Chaque test ci-dessous REJOUE UNE ATTAQUE RÉELLE sur le vrai code du
//  Worker, avec une base D1 simulée. Ce ne sont pas des tests
//  d'implémentation : ce sont les requêtes qu'un attaquant enverrait.
//
//  LE FIL COMMUN DES DÉFAUTS CORRIGÉS ICI : le code confondait
//  « connaître une adresse MK » avec « être cet appareil ». Or l'adresse
//  s'affiche dans l'app (« Réglages → À propos »), le client la dicte au
//  téléphone, l'écrit dans WhatsApp, la colle dans un forum. Ce n'est
//  pas un secret, ça n'en a jamais été un, et tout ce qui reposait
//  dessus était ouvert.
//
//  Exécution : node cloudflare/security_wave1.smoke.mjs
// =========================================================
import worker from './worker.js';

let pass = 0; let fail = 0;
const ok = (cond, label) => {
  if (cond) { pass++; console.log('  PASS ' + label); }
  else { fail++; console.log('  FAIL ' + label); }
};

const VICTIME = 'MK:AA:BB:CC:DD:01';   // un client qui a payé
const PIRATE = 'MK:99:99:99:99:99';    // l'appareil de l'attaquant

// D1 simulée : la victime a une licence PAYÉE et jouable.
const db = {
  prepare(sql) {
    return {
      _sql: sql, _args: [],
      bind(...a) { this._args = a; return this; },
      async run() { return { success: true }; },
      async first() {
        if (/FROM sqlite_master/.test(this._sql)) return { name: 'app_family_links' };
        if (/FROM devices WHERE mac/.test(this._sql)) {
          return { mac: this._args[0], paid: 1, status: 'active',
            paid_until: Date.now() + 30 * 86400000 };
        }
        return null;
      },
      async all() { return { results: [] }; },
    };
  },
};
const env = { DB: db, ADMIN_SECRET: 'test-secret' };
const ctx = { waitUntil() {}, passThroughOnException() {} };

const post = (path, body) => worker.fetch(
  new Request('https://app.x' + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }), env, ctx,
);

// =========================================================
console.log("\n1.1 — Le vol d'abonnement par l'adresse seule");
// =========================================================
//  L'ATTAQUE : le pirate a vu l'adresse de la victime (elle est affichée
//  dans son app). Il demande au serveur de lui transférer l'abonnement.
let r = await post('/api/invite/transfer', {
  mac: VICTIME, target_mac: PIRATE,
});
ok(r.status === 410,
  'transfer avec la seule adresse de la victime → ' + r.status + ' (attendu 410)');

//  Le PRÊT : même faille, en plus discret — la victime perd l'usage sans
//  perdre la propriété, et peut mettre des jours à s'en apercevoir.
r = await post('/api/invite/lend', { mac: VICTIME, guest_mac: PIRATE });
ok(r.status === 410, 'lend avec la seule adresse → ' + r.status);

//  La REPRISE : reprendre un prêt qu'on n'a pas consenti.
r = await post('/api/invite/reclaim', { mac: VICTIME });
ok(r.status === 410, 'reclaim avec la seule adresse → ' + r.status);

//  LE DÉTACHEMENT FAMILLE : un membre rattaché HÉRITE du statut payé de
//  son propriétaire. Le détacher, c'est lui couper son abonnement.
r = await post('/api/family/remove', { mac: VICTIME });
ok(r.status === 410, 'family/remove (auto-détachement) → ' + r.status);

//  Le message doit dire quoi faire, pas seulement « non ». Un client qui
//  tombe dessus légitimement doit savoir vers qui se tourner.
const corps = await r.json();
ok(typeof corps.message === 'string' && /revendeur/i.test(corps.message),
  'la réponse oriente le client vers son revendeur');

// =========================================================
console.log('\nCe qui doit RESTER ouvert');
// =========================================================
//  On ne ferme que ce qui est vulnérable. Fermer plus large « pour être
//  tranquille » casserait des fonctions que les clients utilisent, et la
//  vraie leçon se perdrait dans le bruit.
r = await post('/api/family/remove', { mac: VICTIME, member: 'm_abc' });
ok(r.status !== 410,
  'le propriétaire peut toujours retirer un membre de SA famille ('
  + r.status + ') — le lien doit lui appartenir, et l\'action se répare '
  + 'par un ré-ajout');

// =========================================================
console.log("\n1.2 — Les licences gratuites illimitées");
// =========================================================
//  L'ATTAQUE : un revendeur (ou quiconque a obtenu un jeton de
//  revendeur) demande un « essai » de cent ans. Rien ne bornait la
//  durée, et tout plan commençant par « trial » coûtait 0 crédit.
const b64url = (buf) => Buffer.from(buf).toString('base64url');
async function makeJwt(payload, secret = 'test-secret') {
  const now = Math.floor(Date.now() / 1000);
  const h = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const p = b64url(JSON.stringify({ ...payload, iat: now, exp: now + 3600 }));
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(h + '.' + p));
  return h + '.' + p + '.' + b64url(sig);
}

const { planToDays, planCreditCost, isTrialPlan } = await import('./api_v1.js')
  .then((m) => m).catch(() => ({}));

// La durée : cent ans demandés, sept jours accordés (ou plan payant).
if (typeof planToDays === 'function') {
  //  100 ans demandés → 30 jours accordés, ET payants (isTrialPlan est
  //  faux plus bas, donc le plan est débité). L'attaque visait DEUX
  //  choses à la fois — une durée illimitée et la gratuité — et les deux
  //  tombent. Ce n'est PAS plafonné à 7 jours : un plan inconnu n'est
  //  plus un essai du tout, il retombe sur le plan payant par défaut.
  ok(planToDays('trial_876000h') === 30,
    'trial_876000h (100 ans demandés) → ' + planToDays('trial_876000h')
    + ' jours, et payants');
  ok(planToDays('trial_9999d') <= 30,
    'trial_9999d retombe sur le plan par défaut, pas 9999 jours');
  ok(planToDays('trial_7d') === 7, 'trial_7d vaut toujours 7 jours (rien cassé)');
  ok(planToDays('trial_24h') === 1, 'trial_24h vaut toujours 1 jour');
  ok(planToDays('1y') === 365, 'les plans payants sont intacts');
} else {
  ok(false, 'planToDays non exporté — impossible de tester la durée');
}

// Le coût : « commence par trial » ne suffit plus à être gratuit.
if (typeof isTrialPlan === 'function') {
  ok(isTrialPlan('trial_7d') === true, 'trial_7d reconnu comme essai gratuit');
  ok(isTrialPlan('trial_876000h') === false,
    'trial_876000h n\'est PAS un essai gratuit');
  ok(isTrialPlan('trialXXL') === false, 'trialXXL non plus');
} else {
  ok(false, 'isTrialPlan non exporté');
}

console.log('\n' + pass + ' PASS, ' + fail + ' FAIL');
if (fail) process.exit(1);
