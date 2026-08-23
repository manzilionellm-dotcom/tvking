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
import { _sameTeam, _isReserveOrWomen, _BIG_TEAMS, _sportsBase,
         _isMajorLeague, _dayStamp, _SPORTS,
         _MAX_BIG_MATCHES, _MAX_PER_LEAGUE,
         _leagueTier, _isWomenLeague } from './worker.js';

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
//  Le repli est « 123 », la clé de démo publique documentée aujourd'hui —
//  et non « 3 », qui était l'ancienne. Aucune des deux n'est utilisable
//  depuis un Worker (limite PAR IP, adresse de sortie mutualisée) : ce
//  repli sert uniquement à ne pas fabriquer une URL cassée.
ok(_sportsBase(undefined).endsWith('/123'), 'sans env → clé de démo');
ok(_sportsBase({}).endsWith('/123'), 'env sans clé → clé de démo');
ok(_sportsBase({ SPORTSDB_KEY: '   ' }).endsWith('/123'),
  'clé faite d\'espaces → clé de démo (pas d\'URL cassée)');
ok(_sportsBase({ SPORTSDB_KEY: ' 987654 ' }).endsWith('/987654'),
  'vraie clé utilisée, espaces retirés');

// ---------------------------------------------------------
//  5. Tous les sports, pas seulement le football
// ---------------------------------------------------------
//  Demande du 23/08 : « la catégorie, tous les sports, même le basket,
//  même le tennis, tout ». Hors football, la notion d'« équipe vedette »
//  n'existe pas — au tennis il n'y a même pas d'équipes. C'est donc la
//  LIGUE qui décide, et ce bloc verrouille ce tri.
ok(_SPORTS.includes('Soccer'), 'football couvert');
ok(_SPORTS.includes('Basketball'), 'basket couvert');
ok(_SPORTS.includes('Tennis'), 'tennis couvert');
ok(_SPORTS.length >= 6, `plusieurs sports couverts (${_SPORTS.length})`);

ok(_isMajorLeague('NBA'), 'NBA retenue');
ok(_isMajorLeague('English Premier League'), 'Premier League retenue');
ok(_isMajorLeague('UEFA Champions League'), 'Ligue des champions retenue');
ok(_isMajorLeague('ATP Cincinnati'), 'tournoi ATP retenu');
ok(_isMajorLeague('Formula 1'), 'F1 retenue');
ok(_isMajorLeague('NHL'), 'NHL retenue');

// ---------------------------------------------------------
//  5-bis. CE QUE LES VRAIES DONNÉES ONT APPRIS (23/08/2026)
// ---------------------------------------------------------
//  Le jour où la clé payante est arrivée, l'amont est passé de 3 à
//  1 005 événements sur 3 jours — 252 ligues distinctes. Le filtre s'est
//  alors trompé DANS LES DEUX SENS, ce que la clé gratuite masquait
//  complètement. Chaque cas ci-dessous a été CONSTATÉ, pas imaginé.

//  a) Un nom de compétition prestigieux réutilisé par une petite
//     fédération. La comparaison par mots entiers ne suffit pas : ici
//     « premier league » EST présent, en entier.
ok(!_isMajorLeague('Faroe Islands Premier League'),
  'iles Feroe ecartees (nom de competition reutilise)');
ok(!_isMajorLeague('Kazakhstan Premier League'), 'Kazakhstan ecarte');
ok(!_isMajorLeague('English Northern Premier League Premier Division'),
  'sixieme division anglaise ecartee');

//  b) Les championnats RÉSERVE. Le rejet doit primer sur le nom
//     prestigieux qui l'accompagne.
ok(!_isMajorLeague('MLS Next Pro'), 'MLS Next Pro = reserve, ecarte');
ok(!_isMajorLeague('NASCAR ARCA Series'), 'ARCA = ecole NASCAR, ecarte');

//  c) LE VRAI MLS, qui était jeté parce que TheSportsDB ne l'écrit pas
//     « MLS ». Un faux negatif est aussi grave qu'un faux positif.
ok(_isMajorLeague('American Major League Soccer'), 'le VRAI MLS retenu');

//  d) Les DEUXIÈMES divisions, attrapées par le début du nom.
ok(!_isMajorLeague('Spanish La Liga 2'), 'Liga 2 ecartee');
ok(_isMajorLeague('Spanish La Liga'), 'La Liga retenue');
ok(!_isMajorLeague('Brazilian Serie B'), 'Serie B bresilienne ecartee');
ok(_leagueTier('Brazilian Serie A') === 3, 'Serie A bresilienne = niveau 3');

//  e) Une compétition FÉMININE confondue avec la masculine.
//     « Italian Serie A Womens Cup » n'est PAS la Serie A.
ok(!_isMajorLeague('Italian Serie A Womens Cup'),
  'coupe feminine != championnat masculin');
ok(_isWomenLeague('UEFA Womens Champions League'), 'competition feminine reconnue');
ok(!_isWomenLeague('UEFA Champions League'), 'competition masculine non marquee');
//  On ne CACHE pas le feminin : on le NOMME, et il reste affiche.
ok(_leagueTier('UEFA Womens Champions League') > 0,
  'la Ligue des champions feminine reste affichee');

//  f) LE piège le plus coûteux : chaque confédération a sa « Champions
//     League ». Un tour préliminaire de l'AFC raflait 16 des 60 places
//     et éjectait la Premier League.
ok(_leagueTier('UEFA Champions League') === 1, 'UEFA C1 = niveau 1');
ok(_leagueTier('AFC Champions League') === 3, 'AFC = niveau 3, apres les sommets');
//  Les versions feminines sont listees une par une : « AFC Womens
//  Champions League » ne contient pas « afc champions league » d'un seul
//  tenant. Sans cela elle disparaissait PAR ACCIDENT de comparaison.
ok(_leagueTier('AFC Womens Champions League') === 3,
  'AFC feminine = niveau 3 (par decision, pas par accident)');
ok(_leagueTier('AFC Champions League') > _leagueTier('UEFA Champions League'),
  'l AFC passe APRES l UEFA');

//  g) Les niveaux doivent vraiment se classer, sinon le tri ne sert a rien.
ok(_leagueTier('English Premier League') === 2, 'Premier League = niveau 2');
ok(_leagueTier('Faroe Islands Premier League') === 0, 'niveau 0 = ecartee');
ok(_leagueTier('') === 0 && _leagueTier(null) === 0,
  'ligue vide ou absente = 0, sans planter');

//  h) Le quota par competition. Sans lui, la MLB (37 matchs le meme
//     jour) prenait la moitie de l ecran.
ok(Number.isInteger(_MAX_PER_LEAGUE) && _MAX_PER_LEAGUE > 0,
  'le quota par competition est un entier positif');
ok(_MAX_PER_LEAGUE * 4 <= _MAX_BIG_MATCHES,
  `le quota force au moins 4 competitions differentes (${_MAX_PER_LEAGUE}/${_MAX_BIG_MATCHES})`);
// Le tri doit VRAIMENT trier : sans ça on annoncerait des rencontres de
// quatrième division à trois heures du matin.
ok(!_isMajorLeague('French National 3 Group F'), 'quatrième division écartée');
ok(!_isMajorLeague('American USL Championship'), 'division mineure écartée');
// LE faux positif constaté le 23/08 contre la vraie API : « euro » est un
// morceau de « europe ». Un match de ligue mineure remontait comme s'il
// s'agissait d'un Championnat d'Europe.
ok(!_isMajorLeague('American Football League Europe'),
  'European ≠ Euro (le piège euro/europe)');
ok(_isMajorLeague('Brazilian Serie A'), 'Serie A brésilienne retenue');
ok(_isMajorLeague('UEFA Euro 2028'), 'le vrai Championnat d\'Europe reste retenu');
ok(!_isMajorLeague(''), 'ligue vide écartée');
ok(!_isMajorLeague(null), 'ligue absente écartée, sans planter');

// La fenêtre de jours doit produire des dates ISO valides et avancer.
const t0 = Date.UTC(2026, 7, 23, 22, 30); // 23 août 2026, 22 h 30 UTC
ok(_dayStamp(t0, 0) === '2026-08-23', `jour 0 = ${_dayStamp(t0, 0)}`);
ok(_dayStamp(t0, 1) === '2026-08-24', `jour +1 = ${_dayStamp(t0, 1)}`);
// Passage de mois : le 31 août + 1 jour doit donner le 1er septembre,
// pas « 2026-08-32 ».
const t1 = Date.UTC(2026, 7, 31, 12, 0);
ok(_dayStamp(t1, 1) === '2026-09-01', `changement de mois = ${_dayStamp(t1, 1)}`);

// ---------------------------------------------------------
//  6. Plafond de sortie
// ---------------------------------------------------------
//  L'offre gratuite tronque chaque appel a 3 evenements ; une cle
//  premium en rend jusqu'a 1500. Sur 24 appels, la reponse passerait
//  de quelques kilo-octets a plusieurs mega-octets — a telecharger et
//  a analyser sur un telephone qui n'a parfois que 256 Mo.
//  Mesure sur le code reel avec une source simulee a 1500 evenements
//  par appel : 36 000 evenements bruts, 7 500 retenus, 60 renvoyes,
//  13,9 Ko. Sans plafond : ~1,7 Mo.
ok(Number.isInteger(_MAX_BIG_MATCHES), 'le plafond est un entier');
ok(_MAX_BIG_MATCHES >= 20,
  `assez d'affiches pour remplir un ecran (${_MAX_BIG_MATCHES})`);
ok(_MAX_BIG_MATCHES <= 200,
  'assez bas pour tenir sur un petit telephone');

console.log(`\n${pass} PASS, ${fail} FAIL`);
if (fail > 0) process.exit(1);
