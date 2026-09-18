// =========================================================
//  stream_proxy.smoke.mjs — le jeton signé ici est accepté là-bas
// =========================================================
//  CE QUE CES TESTS PROTÈGENT (18/09/2026).
//
//  La signature du relais était écrite dans `worker.js`, pour le seul
//  récepteur Cast. Le panneau « Téléphone » du panel en a besoin à son
//  tour, et `api_v1.js` ne peut pas importer `worker.js` sans faire un
//  cercle. On a donc SORTI la fonction dans `stream_proxy.js` au lieu
//  de la recopier.
//
//  Le danger d'une recopie n'est pas théorique : le signataire et le
//  vérificateur doivent produire exactement la même chaîne. Une
//  troncature à 31 au lieu de 32, un séparateur changé, une durée
//  différente — et tout ce qu'un côté signe, l'autre le refuse. Le
//  symptôme, côté client, serait « la chaîne ne démarre pas », sans
//  rien qui pointe vers un jeton.
//
//  On rejoue donc ici le VÉRIFICATEUR tel qu'il est écrit dans
//  `worker.js` (`/cast-proxy`), et on exige qu'il accepte ce que
//  `signProxyUrl` produit.
// =========================================================

import { hmacHex, isSafeUpstream, signProxyUrl } from './stream_proxy.js';

let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass++; console.log('PASS', m); }
  else { fail++; console.log('FAIL', m); }
};

const SECRET = 'secret-de-test';
const ORIGIN = 'https://app.7themotion.com';
const FLUX = 'http://fournisseur.example:8080/live/u/p/42.ts';

// ---------------------------------------------------------
//  Aller-retour : signé ici, accepté par le vérificateur
// ---------------------------------------------------------
{
  const signe = await signProxyUrl(SECRET, ORIGIN, FLUX);
  ok(signe !== null, '1 une URL publique est signée');

  const q = new URL(signe.url);
  ok(q.origin + q.pathname === ORIGIN + '/cast-proxy', '2 pointe sur /cast-proxy');
  ok(q.searchParams.get('u') === FLUX, '3 l’amont est transporté intact');

  //  LE VÉRIFICATEUR, recopié depuis worker.js /cast-proxy. Si cette
  //  ligne cesse de correspondre à celle de worker.js, ce test tombe —
  //  c'est exactement son travail.
  const u = q.searchParams.get('u');
  const e = q.searchParams.get('e');
  const t = q.searchParams.get('t');
  const attendu = (await hmacHex(SECRET, u + '\n' + e)).slice(0, 32);
  ok(t === attendu, '4 le jeton signé est celui que /cast-proxy recalcule');
  ok(t.length === 32, '5 jeton tronqué à 32 — la longueur fait partie du contrat');

  const maintenant = Math.floor(Date.now() / 1000);
  ok(Number(e) > maintenant, '6 l’expiration est dans le futur');
  ok(Number(e) - maintenant <= 12 * 3600 + 5, '7 12 h au plus, comme avant');
  ok(signe.expires_at === Number(e), '8 l’expiration annoncée = celle signée');
}

// ---------------------------------------------------------
//  Un secret différent ne doit RIEN valider
// ---------------------------------------------------------
{
  const a = await signProxyUrl(SECRET, ORIGIN, FLUX);
  const b = await signProxyUrl('autre-secret', ORIGIN, FLUX);
  const ta = new URL(a.url).searchParams.get('t');
  const tb = new URL(b.url).searchParams.get('t');
  ok(ta !== tb, '9 deux secrets donnent deux jetons différents');
}

// ---------------------------------------------------------
//  Pas de secret configuré → on ne signe rien
// ---------------------------------------------------------
ok(await signProxyUrl('', ORIGIN, FLUX) === null, '10 sans secret → null');
ok(await signProxyUrl(null, ORIGIN, FLUX) === null, '11 secret null → null');

// ---------------------------------------------------------
//  ANTI-SSRF : le relais ne doit pas devenir une porte d'entrée
// ---------------------------------------------------------
//  Sans ce filtre, n'importe qui pourrait faire tirer au Worker une
//  adresse du réseau interne et lui en renvoyer le contenu.
for (const mauvais of [
  'http://localhost/x',
  'http://127.0.0.1/x',
  'http://10.0.0.5/x',
  'http://192.168.1.10/x',
  'http://172.16.4.4/x',
  'http://169.254.169.254/latest/meta-data',
  'http://100.64.0.1/x',
  'http://[::1]/x',
  'file:///etc/passwd',
  'ftp://serveur/x',
  'http://machine.local/x',
  'pas-une-url',
]) {
  ok(isSafeUpstream(mauvais) === false, `12 refusé : ${mauvais}`);
  ok(await signProxyUrl(SECRET, ORIGIN, mauvais) === null,
    `13 non signé : ${mauvais}`);
}

for (const bon of [
  'http://fournisseur.example:8080/live/u/p/1.ts',
  'https://cdn.example.com/a.m3u8',
  'http://8.8.8.8/x',
]) {
  ok(isSafeUpstream(bon) === true, `14 accepté : ${bon}`);
}

console.log(`\n${pass} PASS, ${fail} FAIL`);
if (fail > 0) process.exit(1);
