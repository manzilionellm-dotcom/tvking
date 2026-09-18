// =========================================================
//  bench.smoke.mjs — « le dernier build tient-il mieux ? »
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (18/09/2026) : « Fais l'excellence, et fais
//  un benchmark. »
//
//  Chaque box calcule SA note toute seule (lib/core/observability/
//  banc_essai.dart). Le serveur ne recalcule rien — il regroupe. Ce
//  fichier protège la façon de regrouper, et c'est là que les erreurs
//  de jugement se cachent :
//
//   • LA MÉDIANE, PAS LA MOYENNE. Une seule box pourrie — fournisseur
//     en rade, box qui chauffe dans un meuble fermé — tirerait la
//     moyenne vers le bas et ferait condamner un build sain.
//   • ON GARDE LE PIRE quand même : « la moitié du parc va bien » ne
//     console pas quand l'autre moitié appelle.
//   • TRI NUMÉRIQUE. Les numéros de la maison montent (198876,
//     198877…). En tri alphabétique, « 1988100 » passerait AVANT
//     « 198899 » et le panel afficherait le mauvais build en tête.
// =========================================================

import { resumerBancs } from './api_v1.js';

let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass++; console.log('PASS', m); }
  else { fail++; console.log('FAIL', m); }
};

const run = (build, note, extra = {}) => ({
  build_label: build,
  note,
  minutes: 120,
  crashs: 0, err: 0, mem: 0, nostart: 0, lecture: 0, gels: 0,
  verrou_ko: 0, verrou_ok: 0, updated_at: 1,
  ...extra,
});

// --- Regroupement de base ------------------------------------------
{
  const r = resumerBancs([
    run('198877', 95), run('198877', 90), run('198876', 40),
  ]);
  ok(r.length === 2, '1 deux builds distincts');
  ok(r[0].build === '198877', '2 le plus récent en tête');
  ok(r[0].boxes === 2, '3 deux box ont noté le dernier build');
  ok(r[1].boxes === 1, '4 une seule sur le précédent');
}

// --- LA MÉDIANE PROTÈGE D'UNE SEULE BOX POURRIE --------------------
{
  //  Quatre box à 90 et une à 0. La moyenne dirait 72 — « ce build est
  //  moyen ». La médiane dit 90 : le parc va bien, UNE box a un
  //  problème à elle. Les deux lectures mènent à des journées de
  //  travail complètement différentes.
  const r = resumerBancs([
    run('198877', 90), run('198877', 90), run('198877', 90),
    run('198877', 90), run('198877', 0),
  ]);
  ok(r[0].note_mediane === 90, '5 la médiane ignore la box isolée');
  ok(r[0].note_pire === 0, '6 mais la pire note reste VISIBLE');
  ok(r[0].note_meilleure === 90, '7 et la meilleure aussi');
  const moyenne = (90 * 4 + 0) / 5;
  ok(r[0].note_mediane !== Math.round(moyenne),
    '8 médiane et moyenne diffèrent bien ici — c\'est tout l\'enjeu');
}

// --- Médiane sur un nombre PAIR de box ------------------------------
{
  const r = resumerBancs([run('1', 80), run('1', 90)]);
  ok(r[0].note_mediane === 85, '9 nombre pair → moyenne des deux du milieu');
}
{
  const r = resumerBancs([run('1', 70), run('1', 80), run('1', 99)]);
  ok(r[0].note_mediane === 80, '10 nombre impair → celle du milieu');
}

// --- TRI NUMÉRIQUE, le piège du compteur qui grandit ----------------
{
  //  Le jour où les numéros passent à sept chiffres, un tri
  //  alphabétique mettrait « 1988100 » derrière « 198899 » et le
  //  propriétaire lirait le mauvais build en tête de page.
  const r = resumerBancs([run('198899', 50), run('1988100', 90)]);
  ok(r[0].build === '1988100',
    '11 1988100 passe AVANT 198899 (tri numérique, pas alphabétique)');
}

// --- La plus longue session, et les totaux --------------------------
{
  const r = resumerBancs([
    run('198877', 90, { minutes: 120, mem: 2, nostart: 1 }),
    run('198877', 85, { minutes: 1440, mem: 5, nostart: 0, crashs: 1 }),
  ]);
  ok(r[0].minutes_max === 1440, '12 on retient la plus LONGUE observation');
  ok(r[0].mem === 7, '13 les purges mémoire s\'additionnent');
  ok(r[0].nostart === 1, '14 les démarrages ratés s\'additionnent');
  ok(r[0].crashs === 1, '15 les crashs s\'additionnent');
}

// --- Ce qui ne doit PAS faire tomber le résumé ----------------------
{
  ok(resumerBancs([]).length === 0, '16 aucune donnée → liste vide');
  ok(resumerBancs(null).length === 0, '17 null → liste vide, sans jeter');
  ok(resumerBancs(undefined).length === 0, '18 undefined → liste vide');
}
{
  //  Une ligne sans numéro de build ne se compare à rien : on la
  //  laisse de côté plutôt que d'inventer un build « inconnu » qui
  //  polluerait la page.
  const r = resumerBancs([
    run('', 90), run(null, 90), run('198877', 90),
  ]);
  ok(r.length === 1 && r[0].build === '198877',
    '19 les lignes sans build sont écartées');
}
{
  //  Un build dont aucune box n'a rendu de note n'apparaît pas : une
  //  ligne « — » ferait croire à une régression.
  const r = resumerBancs([run('198877', null), run('198877', undefined)]);
  ok(r.length === 0, '20 aucune note exploitable → le build n\'apparaît pas');
}
{
  const r = resumerBancs([
    { build_label: '198877', note: 90 }, // champs manquants partout
  ]);
  ok(r.length === 1, '21 des champs absents ne font pas tomber le résumé');
  ok(r[0].minutes_max === 0, '22 et valent zéro, pas NaN');
  ok(r[0].crashs === 0, '23 idem pour les compteurs');
}

// --- Le cas qui motive tout : comparer deux builds ------------------
{
  //  Ce que le propriétaire veut lire d'un coup d'œil.
  const r = resumerBancs([
    run('198877', 92, { minutes: 400 }),
    run('198877', 88, { minutes: 380 }),
    run('198876', 55, { minutes: 90, crashs: 1 }),
    run('198876', 60, { minutes: 120 }),
  ]);
  ok(r[0].build === '198877' && r[1].build === '198876', '24 ordre correct');
  ok(r[0].note_mediane > r[1].note_mediane,
    '25 le nouveau build est mesurablement meilleur — la phrase qu\'on '
    + 'ne pouvait pas dire avant aujourd\'hui');
}

console.log(`\n${pass} PASS, ${fail} FAIL`);
if (fail > 0) process.exit(1);
