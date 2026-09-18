// =========================================================
//  device_channels.smoke.mjs — « je vois les chaînes qu'il a »
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (18/09/2026) :
//
//    « Je mets l'adresse MAC et le téléphone vient. Je vois les
//      chaînes qu'il a. Et j'efface ou j'ajoute les listes. »
//
//  `GET /devices/:id/channels` lit la liste chez le fournisseur. Tout
//  ce qui touche au réseau ne se teste pas ici (il faudrait un vrai
//  fournisseur au bout). Ce qui SE teste, et qui est la seule vraie
//  décision de la route : QUELLE liste on montre quand l'appareil en a
//  plusieurs.
//
//  Pourquoi ça compte : montrer la mauvaise liste est pire que ne rien
//  montrer. Lionel dirait au client « tu as bien TF1 » en regardant la
//  liste n°2 pendant que le client en regarde une autre.
// =========================================================

import {
  pickSourceIndex, resellerMaySeeDevice, xtreamLiveUrl,
  expliquerEchecLecture,
} from './api_v1.js';

let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass++; console.log('PASS', m); }
  else { fail++; console.log('FAIL', m); }
};

const trois = [
  { type: 'm3u', m3u_url: 'http://a/1.m3u' },
  { type: 'xtream', server_url: 'http://b', active: true },
  { type: 'm3u', m3u_url: 'http://c/3.m3u' },
];

// --- L'onglet demandé gagne ---------------------------------------
ok(pickSourceIndex(trois, '0') === 0, '1 index demandé 0 → 0');
ok(pickSourceIndex(trois, '2') === 2, '2 index demandé 2 → 2');
ok(pickSourceIndex(trois, 2) === 2, '3 index numérique accepté aussi');

// --- Rien de demandé → celle que le CLIENT regarde -----------------
ok(pickSourceIndex(trois, null) === 1, '4 sans index → la liste ACTIVE');
ok(pickSourceIndex(trois, '') === 1, '5 index vide → la liste ACTIVE');
ok(pickSourceIndex(trois, undefined) === 1, '6 index absent → la liste ACTIVE');

// --- Aucune active → la première ----------------------------------
const sansActive = [{ type: 'm3u' }, { type: 'm3u' }];
ok(pickSourceIndex(sansActive, null) === 0, '7 aucune active → la première');

// --- HORS BORNES : on ne casse pas, on retombe sur l'active --------
//  Le cas réel : le panel affiche trois onglets, quelqu'un retire une
//  liste, Lionel clique sur le troisième. Une erreur rouge à cet
//  instant-là ne l'aide en rien.
ok(pickSourceIndex(trois, '9') === 1, '8 index trop grand → l\'active');
ok(pickSourceIndex(trois, '-1') === 1, '9 index négatif → l\'active');
ok(pickSourceIndex(trois, 'abc') === 1, '10 index illisible → l\'active');
ok(pickSourceIndex(trois, '1.5') === 1, '11 index décimal → l\'active');

// --- Aucune liste : on répond 0 sans jeter -------------------------
//  L'appelant traite le « aucune liste » AVANT (404 avec une phrase
//  utile). Ici on garantit seulement qu'on ne jette pas.
ok(pickSourceIndex([], '0') === 0, '12 liste vide → 0, sans exception');
ok(pickSourceIndex(null, null) === 0, '13 null → 0, sans exception');
ok(pickSourceIndex(undefined, '2') === 0, '14 undefined → 0, sans exception');

// --- Une entrée nulle dans le tableau ne fait pas tomber -----------
ok(pickSourceIndex([null, { active: true }], null) === 1,
  '15 trou dans le tableau → on trouve quand même l\'active');

// =========================================================
//  LA CLOISON ENTRE REVENDEURS
// =========================================================
//  Les chaînes d'un appareil disent quelle LIGNE il utilise. Un
//  revendeur qui lirait celles du client d'un autre revendeur verrait
//  son fournisseur. Cette règle vaut donc autant que l'affichage.
//
//  Elle vit dans UNE fonction lue par la fiche 360° ET par le panneau
//  Téléphone : deux copies, c'est un jour où l'une des deux laisse
//  passer.
const owner = { role: 'owner', sub: 'u-owner' };
const vendeurA = { role: 'reseller', sub: 'u-a' };
const vendeurB = { role: 'reseller', sub: 'u-b' };
const appareilDeA = { id: 'd1', reseller_id: 'u-a' };
const appareilSansProprio = { id: 'd2', reseller_id: null };

ok(resellerMaySeeDevice(owner, appareilDeA) === true,
  '16 l\'owner voit tout');
ok(resellerMaySeeDevice(vendeurA, appareilDeA) === true,
  '17 un revendeur voit SON appareil');
ok(resellerMaySeeDevice(vendeurB, appareilDeA) === false,
  '18 un revendeur NE voit PAS celui d\'un autre');
ok(resellerMaySeeDevice(vendeurA, appareilSansProprio) === false,
  '19 appareil sans propriétaire : un revendeur ne le voit pas');
ok(resellerMaySeeDevice(owner, appareilSansProprio) === true,
  '20 mais l\'owner, si');
ok(resellerMaySeeDevice(vendeurA, null) === false,
  '21 aucune fiche : un revendeur ne peut rien prouver, donc rien voir');
ok(resellerMaySeeDevice(owner, null) === true,
  '22 aucune fiche : l\'owner voit quand même');
ok(resellerMaySeeDevice(null, appareilDeA) === true,
  '23 appel interne sans utilisateur : pas de cloison à appliquer');

// =========================================================
//  L'URL DE LECTURE — « même faire play à tous »
// =========================================================
//  Le Worker la fabrique avec les identifiants qu'il a en base, la
//  signe, et ne renvoie que le lien du relais. Ce qui se teste ici sans
//  réseau, c'est la CONSTRUCTION — et surtout ce qu'elle REFUSE.
const xt = {
  type: 'xtream',
  server_url: 'http://fournisseur.example:8080',
  username: 'jean',
  password: 'motdepasse',
};

ok(xtreamLiveUrl(xt, '42')
  === 'http://fournisseur.example:8080/live/jean/motdepasse/42.ts',
  '24 URL Xtream au format que le lecteur de l\'app utilise');

ok(xtreamLiveUrl({ ...xt, server_url: 'http://s:8080///' }, '7')
  === 'http://s:8080/live/jean/motdepasse/7.ts',
  '25 les slashs en trop sont retirés');

ok(xtreamLiveUrl({ ...xt, username: 'jean dupont', password: 'a/b' }, '9')
  === 'http://fournisseur.example:8080/live/jean%20dupont/a%2Fb/9.ts',
  '26 espace et slash dans les identifiants sont échappés');

//  L'IDENTIFIANT VIENT DE LA REQUÊTE. Sans filtre, on collerait
//  n'importe quoi dans un chemin que le Worker ira chercher lui-même.
for (const mauvais of ['../../etc/passwd', '1 2', 'abc', '', '  ', '1;2', '-5']) {
  ok(xtreamLiveUrl(xt, mauvais) === null,
    `27 identifiant refusé : « ${mauvais} »`);
}
ok(xtreamLiveUrl(xt, null) === null, '28 identifiant absent → null');

//  M3U : on n'invente PAS d'adresse. Une liste M3U porte les siennes.
ok(xtreamLiveUrl({ type: 'm3u', m3u_url: 'http://x/l.m3u' }, '42') === null,
  '29 M3U → null, on ne fabrique rien');

//  Xtream incomplet : on ne bricole pas une URL qui ne jouera pas.
ok(xtreamLiveUrl({ ...xt, password: '' }, '42') === null,
  '30 mot de passe manquant → null');
ok(xtreamLiveUrl({ ...xt, username: '' }, '42') === null,
  '31 identifiant manquant → null');
ok(xtreamLiveUrl({ ...xt, server_url: '' }, '42') === null,
  '32 serveur manquant → null');
ok(xtreamLiveUrl(null, '42') === null, '33 aucune source → null');

// =========================================================
//  « SA FAIS PA PLAYER » — dire POURQUOI, pas un code
// =========================================================
//  Premier essai de lecture depuis le panel, premier ecran rouge :
//  « Le flux s'est interrompu (HttpStatusCodeInvalid) ». Ce code sort
//  de mpegts.js et veut seulement dire « la reponse n'etait pas 200 ».
//  Le relais, lui, SAIT : il remonte le status du fournisseur. C'est la
//  bibliotheque qui ecrase l'information en chemin.
//
//  LA SEULE QUESTION QUI COMPTE POUR LIONEL : est-ce que SON CLIENT
//  voit la meme chose ? C'est `client_pareil` qui y repond, et se
//  tromper la-dessus coute cher dans les deux sens — annoncer une
//  panne a un client qui n'a rien, ou jurer que tout va bien pendant
//  qu'il regarde un ecran noir.
{
  const r = expliquerEchecLecture(200, '');
  ok(r.ok === true && r.code === 'ok', '34 HTTP 200 → tout va bien');
}
{
  const r = expliquerEchecLecture(206, '');
  ok(r.ok === true, '35 HTTP 206 (contenu partiel) compte aussi comme bon');
}
{
  //  LE CAS LE PLUS PIEGEUX. Le Worker sort d'un centre de donnees ; de
  //  tres nombreux fournisseurs bloquent ces adresses-la. Le client,
  //  sur son reseau, lit la chaine sans probleme. Conclure « panne »
  //  ici ferait deplacer un client pour rien.
  const r = expliquerEchecLecture(0, 'connection refused');
  ok(r.ok === false && r.code === 'injoignable', '36 aucune reponse → injoignable');
  ok(r.client_pareil === false,
    '37 et on DIT que le client ne voit pas forcement la meme chose');
  ok(r.raison.includes('connection refused'),
    '38 la vraie erreur technique est citee, pas masquee');
}
{
  for (const s of [401, 403, 456]) {
    const r = expliquerEchecLecture(s, '');
    ok(r.code === 'refuse', `39 HTTP ${s} → refus du fournisseur`);
    //  On NE TRANCHE PAS entre « limite de connexions » et « blocage
    //  d'adresses » : les deux donnent le meme status, et inventer
    //  l'une des deux enverrait chercher la mauvaise piste.
    ok(r.client_pareil === null,
      `40 HTTP ${s} → on n'invente pas laquelle des deux causes`);
  }
}
{
  const r = expliquerEchecLecture(404, '');
  ok(r.code === 'introuvable', '41 HTTP 404 → chaine disparue');
  ok(r.client_pareil === true, '42 et la, le client a bien le meme probleme');
}
{
  for (const s of [500, 502, 503, 520]) {
    const r = expliquerEchecLecture(s, '');
    ok(r.code === 'panne_fournisseur', `43 HTTP ${s} → panne du fournisseur`);
    ok(r.client_pareil === true, `44 HTTP ${s} → le client voit la meme chose`);
  }
}
{
  //  Un status qu'on n'a pas prevu ne doit pas faire tomber l'ecran ni
  //  inventer une explication.
  const r = expliquerEchecLecture(418, '');
  ok(r.code === 'inattendu', '45 status inconnu → « inattendu », sans invention');
  ok(r.client_pareil === null, '46 et on ne se prononce pas sur le client');
}
{
  const r = expliquerEchecLecture(undefined, undefined);
  ok(r.code === 'injoignable', '47 status absent → traite comme injoignable');
}
{
  //  Chaque verdict doit porter un CONSEIL : un diagnostic sans suite
  //  laisse Lionel devant le meme ecran rouge.
  for (const s of [0, 403, 404, 500, 418, 200]) {
    const r = expliquerEchecLecture(s, '');
    ok(typeof r.conseil === 'string' && r.conseil.length > 20,
      `48 HTTP ${s} → un conseil, pas seulement un constat`);
  }
}

console.log(`\n${pass} PASS, ${fail} FAIL`);
if (fail > 0) process.exit(1);
