// =========================================================
//  sports_big.smoke.mjs — Grandes affiches (/api/sports/big)
// =========================================================
//  Ce fichier existe à cause d'une VRAIE panne, le 22/08.
//
//  L'endpoint répondait 200 avec `{"matches":[]}` — donc « tout va
//  bien, il n'y a simplement pas de grand match ». En réalité DEUX
//  bugs se cachaient derrière ce silence :
//
//   1. les identifiants de clubs étaient INVENTÉS. L'id 133602,
//      annoncé « Real Madrid », renvoyait les matchs de Liverpool.
//      Comme l'adversaire n'était jamais un autre club majeur, le
//      filtre jetait absolument tout ;
//   2. le rapprochement des noms se faisait par simple `includes` de
//      chaînes : « Aris » passait pour un club majeur, parce que
//      « aris » est un morceau de « p·aris· saint-germain ». D'où un
//      « Napoli vs Aris » présenté comme une grande affiche.
//
//  Une panne SILENCIEUSE est la pire : rien ne plante, personne ne
//  reçoit sa notification, et on ne s'en aperçoit qu'en le testant à
//  la main. Ce smoke test verrouille les deux pièges.
//
//  Exécution (aucun runner, aucun réseau) :
//    node cloudflare/sports_big.smoke.mjs
// =========================================================
import { _sameTeam, _isReserveOrWomen, _BIG_TEAMS, _sportsBase } from './worker.js';

let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass++; console.log('PASS', m); }
  else { fail++; console.log('FAIL', m); }
};

// ---------------------------------------------------------
//  1. Rapprochement des noms d'équipes
// ---------------------------------------------------------
// LE piège d'origine : un fragment de mot ne fait pas un club.
ok(!_sameTeam('Aris', 'Paris Saint-Germain'),
  'Aris n\'est PAS le Paris SG (fragment de mot)');
ok(!_sameTeam('Ajax', 'Ajaccio'),
  'un préfixe partiel ne suffit pas non plus');

// Un nom court désigne bien le même club qu'un nom long.
ok(_sameTeam('Tottenham', 'Tottenham Hotspur'), 'Tottenham = Tottenham Hotspur');
ok(_sameTeam('Inter', 'Inter Milan'), 'Inter = Inter Milan');
ok(_sameTeam('Napoli', 'Napoli'), 'nom identique');

// Les accents ne doivent pas séparer deux écritures du même club.
ok(_sameTeam('Atlético Madrid', 'Atletico Madrid'), 'accents ignorés');

// Deux clubs distincts qui partagent un mot restent distincts.
ok(!_sameTeam('Real Sociedad', 'Real Madrid'), 'Real Sociedad ≠ Real Madrid');
ok(!_sameTeam('Manchester City', 'Manchester United'), 'City ≠ United');
ok(!_sameTeam('Inter Milan', 'AC Milan'), 'Inter ≠ AC Milan');

// Cas dégénérés : jamais d'exception, jamais de « vrai » par défaut.
ok(!_sameTeam('', 'Chelsea'), 'nom vide → faux');
ok(!_sameTeam(null, undefined), 'null/undefined → faux, sans planter');

// ---------------------------------------------------------
//  2. Équipes féminines et équipes de jeunes
// ---------------------------------------------------------
//  « Napoli Women » contient « Napoli » : sans ce filtre, un match de
//  l'équipe féminine serait annoncé comme l'affiche de la Ligue des
//  champions masculine.
ok(_isReserveOrWomen('Napoli Women'), 'équipe féminine écartée');
ok(_isReserveOrWomen('Real Madrid U19'), 'équipe de jeunes écartée');
ok(_isReserveOrWomen('Barcelona B'), 'équipe réserve écartée');
ok(!_isReserveOrWomen('Napoli'), 'équipe première gardée');
ok(!_isReserveOrWomen('Manchester United'), 'équipe première gardée (2 mots)');

// ---------------------------------------------------------
//  3. Catalogue de clubs
// ---------------------------------------------------------
const ids = Object.keys(_BIG_TEAMS);
ok(ids.length >= 15, `catalogue fourni (${ids.length} clubs)`);
ok(ids.every((k) => /^\d+$/.test(k)),
  'tous les identifiants sont numériques (ids TheSportsDB)');
ok(new Set(Object.values(_BIG_TEAMS)).size === ids.length,
  'aucun club listé deux fois sous deux identifiants');
// Chaque club doit se reconnaître lui-même : garde-fou contre un nom
// mal orthographié dans le catalogue, qui rendrait son id inutile.
ok(Object.values(_BIG_TEAMS).every((n) => _sameTeam(n, n)),
  'chaque nom du catalogue se reconnaît lui-même');

// ---------------------------------------------------------
//  4. Choix de la clé TheSportsDB
// ---------------------------------------------------------
//  La clé « 3 » est la clé de DÉMO publique : depuis un Worker (adresse
//  de sortie mutualisée) elle répond 429 en permanence. Une vraie clé se
//  pose en secret Worker. Ce bloc verrouille le fait qu'une clé vide, ou
//  faite d'espaces, ne produise JAMAIS une URL cassée du type « /json/ ».
ok(_sportsBase(undefined).endsWith('/3'), 'sans env → clé de démo');
ok(_sportsBase({}).endsWith('/3'), 'env sans clé → clé de démo');
ok(_sportsBase({ SPORTSDB_KEY: '   ' }).endsWith('/3'),
  'clé faite d\'espaces → clé de démo (pas d\'URL cassée)');
ok(_sportsBase({ SPORTSDB_KEY: ' 987654 ' }).endsWith('/987654'),
  'vraie clé utilisée, espaces retirés');

console.log(`\n${pass} PASS, ${fail} FAIL`);
if (fail > 0) process.exit(1);
