// Smoke test — GARDE-FOU FAUTE DE FRAPPE sur l'adresse MAC.
//
// Demande du propriétaire (09/09/2026) : « si je me trompe d'un chiffre,
// ça active quand même. Il faut me corriger : ça doit me dire que
// l'adresse MAC n'existe pas. »
//
// Le serveur refuse une MAC jamais vue, et joint la correction probable :
// les MAC connues qui ne diffèrent que d'UN caractère. Ce test prouve que
// la recherche trouve bien ces voisines — et RIEN d'autre.
//
// La base est simulée, mais le `LIKE` ne l'est pas : on l'évalue avec la
// vraie sémantique SQL (« _ » = un caractère, insensible à la casse pour
// l'ASCII), sinon on ne prouverait que nos propres suppositions.
//
// Lancer : node cloudflare/mac_typo.smoke.mjs
import assert from 'node:assert/strict';
import { macTypoSuggestions } from './api_v1.js';

let n = 0;
const ok = (m) => { n++; console.log('  ✓', m); };

// --- Un vrai évaluateur LIKE (les seuls jokers utilisés ici : « _ ») ---
function likeMatch(valeur, motif) {
  const rx = new RegExp(
    '^' + motif.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/_/g, '.') + '$',
    'i',
  );
  return rx.test(valeur);
}

// --- Fausse base D1 : LIT le SQL généré, ne le devine pas -------------
//
// Un faux qui suppose la forme du SQL ne prouve rien : on peut casser la
// clause `mac != ?` sans qu'aucun test ne bouge (vérifié — c'est arrivé).
// Celui-ci découpe donc le WHERE en conjonctions, les évalue une par une,
// et consomme les « ? » DANS L'ORDRE, comme le ferait SQLite. Il exige
// aussi autant de valeurs liées que de « ? » : un décalage entre le SQL
// et les `bind()` — que D1 rejetterait — fait échouer le test ici.
function fakeDb(rows) {
  const vues = [];
  const db = {
    prepare(sql) {
      return {
        bind(...args) {
          return {
            async all() {
              vues.push({ sql, args });
              const attendus = (sql.match(/\?/g) || []).length;
              assert.equal(args.length, attendus,
                `SQL et bind() désaccordés : ${attendus} « ? » pour ` +
                `${args.length} valeurs liées`);
              const where = /WHERE ([\s\S]*?)(?: LIMIT \d+)?$/.exec(sql)[1];
              const limite = Number(/LIMIT (\d+)/.exec(sql)?.[1] ?? 1e9);
              // Découpe sur les « AND » de premier niveau (hors parenthèses).
              const conjonctions = [];
              let prof = 0, debut = 0;
              for (let i = 0; i < where.length; i++) {
                if (where[i] === '(') prof++;
                else if (where[i] === ')') prof--;
                else if (prof === 0 && where.startsWith(' AND ', i)) {
                  conjonctions.push(where.slice(debut, i));
                  i += 4; debut = i + 1;
                }
              }
              conjonctions.push(where.slice(debut));
              const gardees = rows.filter((r) => {
                let k = 0; // curseur sur les valeurs liées, comme SQLite
                return conjonctions.every((c) => {
                  const nu = c.replace(/^\(|\)$/g, '').trim();
                  return nu.split(' OR ').map((t) => t.trim()).reduce(
                    (acc, terme) => {
                      const [col, op] = terme.split(/\s+/);
                      const val = terme.includes('?')
                        ? args[k++]
                        : terme.split(/\s+/).slice(2).join(' ').replace(/^'|'$/g, '');
                      const champ = col === 'mac' ? r.mac : r[col];
                      const vrai = op === 'LIKE' ? likeMatch(champ ?? '', val)
                        : op === '!=' ? champ !== val
                        : champ === val;
                      return acc || vrai;
                    }, false);
                });
              });
              return { results: gardees.slice(0, limite) };
            },
          };
        },
      };
    },
  };
  return { vues, DB: db };
}

const CIBLE = 'MK:1A:2B:3C:4D:5E';

// 1) Une MAC à UN caractère près est proposée — le cœur de la demande.
{
  const f = fakeDb([{ mac: 'MK:1A:2B:3C:4D:6E', reseller_id: 'r1' }]);
  const s = await macTypoSuggestions(f, CIBLE, null);
  assert.deepEqual(s, ['MK:1A:2B:3C:4D:6E']);
  ok('un chiffre de travers → la bonne MAC est proposée');
}

// 2) Le premier chiffre saisi compte autant que le dernier : la faute de
//    frappe n'arrive pas qu'à la fin du numéro.
{
  const f = fakeDb([{ mac: 'MK:2A:2B:3C:4D:5E' }]);
  const s = await macTypoSuggestions(f, CIBLE, null);
  assert.deepEqual(s, ['MK:2A:2B:3C:4D:5E']);
  ok('faute sur le PREMIER caractère → trouvée aussi');
}

// 3) DEUX caractères d'écart : ce n'est plus une faute de frappe, c'est
//    une autre adresse. On ne propose rien plutôt que d'induire en erreur.
{
  const f = fakeDb([{ mac: 'MK:1A:2B:3C:6D:6E' }]);
  const s = await macTypoSuggestions(f, CIBLE, null);
  assert.deepEqual(s, []);
  ok('deux caractères d\'écart → aucune suggestion');
}

// 4) On ne se propose jamais soi-même (le motif « _ » matche aussi la
//    MAC d'origine ; sans le « mac != ? » on répondrait « vouliez-vous
//    dire la MAC que vous venez de taper ? »).
{
  const f = fakeDb([{ mac: CIBLE }, { mac: 'MK:1A:2B:3C:4D:5F' }]);
  const s = await macTypoSuggestions(f, CIBLE, null);
  assert.deepEqual(s, ['MK:1A:2B:3C:4D:5F']);
  ok('la MAC saisie elle-même est exclue des suggestions');
}

// 5) CLOISONNEMENT : un revendeur ne doit pas apprendre l'existence des
//    MAC d'un autre revendeur. C'est une fuite, pas un confort.
{
  const f = fakeDb([
    { mac: 'MK:1A:2B:3C:4D:6E', reseller_id: 'moi' },
    { mac: 'MK:1A:2B:3C:4D:7E', reseller_id: 'un_autre' },
  ]);
  const s = await macTypoSuggestions(f, CIBLE, 'moi');
  assert.deepEqual(s, ['MK:1A:2B:3C:4D:6E']);
  ok('revendeur : seules SES MAC sont proposées');
}

// 6) Le propriétaire (pas de revendeur) voit tout le parc.
{
  const f = fakeDb([
    { mac: 'MK:1A:2B:3C:4D:6E', reseller_id: 'moi' },
    { mac: 'MK:1A:2B:3C:4D:7E', reseller_id: 'un_autre' },
  ]);
  const s = await macTypoSuggestions(f, CIBLE, null);
  assert.equal(s.length, 2);
  ok('propriétaire : tout le parc est consulté');
}

// 7) Bornage : au-delà de 5, ce n'est plus une aide, c'est une liste.
{
  const many = ['6', '7', '8', '9', 'A', 'B', 'C']
    .map((c) => ({ mac: `MK:1A:2B:3C:4D:${c}E` }));
  const f = fakeDb(many);
  const s = await macTypoSuggestions(f, CIBLE, null);
  assert.equal(s.length, 5);
  ok('au plus 5 suggestions');
}

// 8) Le préfixe « MK: » et les « : » ne sont JAMAIS remplacés : un motif
//    qui les toucherait proposerait des chaînes qui ne sont pas des MAC.
{
  const f = fakeDb([]);
  await macTypoSuggestions(f, CIBLE, null);
  const motifs = f.vues[0].args.filter((a) => String(a).includes('_'));
  assert.equal(motifs.length, 10, '10 caractères hexadécimaux');
  for (const m of motifs) {
    assert.ok(m.startsWith('MK:'), `préfixe intact : ${m}`);
    for (const pos of [5, 8, 11, 14]) {
      assert.equal(m[pos], ':', `séparateur intact en ${pos} : ${m}`);
    }
  }
  ok('préfixe MK: et séparateurs jamais remplacés (10 motifs)');
}

// 9) FAIL-SOFT. La suggestion est un confort : si la base tousse, on rend
//    une liste vide. L'avertissement principal (« cette MAC n'existe
//    pas ») doit partir même quand la recherche de voisines échoue.
{
  const casse = { DB: { prepare() { throw new Error('D1 down'); } } };
  const s = await macTypoSuggestions(casse, CIBLE, null);
  assert.deepEqual(s, []);
  ok('base en panne → liste vide, jamais d\'exception');
}

console.log(`\n${n} assertions OK — garde-fou faute de frappe MAC validé.`);
