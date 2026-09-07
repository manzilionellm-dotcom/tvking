// =========================================================
//  device_build_label.smoke.mjs — Le numéro maison remonté par la box
// =========================================================
//  On fait tourner LE VRAI worker sur POST /api/heartbeat avec un D1
//  simulé, et on regarde l'écriture qu'il produit dans `devices`.
//
//  POURQUOI CE TEST EXISTE, précisément. L'enrichissement appareil
//  (updateDeviceInfo) est UNE SEULE requête UPDATE avec dix clauses
//  « CASE WHEN ? != '' THEN ? ELSE colonne END » — donc VINGT paramètres
//  positionnels, dans un ordre qui doit correspondre exactement à
//  l'ordre des clauses. En ajoutant `build_label` au milieu de la liste,
//  une paire mal placée aurait écrit le numéro de version DANS LA
//  COLONNE PLATEFORME, silencieusement : aucune erreur SQL, juste un
//  panel qui affiche n'importe quoi. Ce test relie chaque clause à ses
//  deux paramètres et vérifie la correspondance.
//
//  Il verrouille aussi la règle « on n'écrase jamais avec du vide » :
//  une app d'avant le 07/09/2026 n'envoie pas de numéro maison, et son
//  passage ne doit pas effacer ce qu'on savait déjà.
//
//  Exécution : node cloudflare/device_build_label.smoke.mjs
// =========================================================
import worker from './worker.js';

const ctx = { waitUntil(p) { this._q.push(p); }, _q: [], passThroughOnException() {} };
let pass = 0; let fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('PASS', m); } else { fail++; console.log('FAIL', m); } };

// ---- D1 simulé : capture les UPDATE devices ----
let updates = [];
function makeDb() {
  return {
    prepare(sql) {
      return {
        _sql: sql,
        bind(...args) { this._args = args; return this; },
        async run() {
          if (/UPDATE devices SET/i.test(this._sql)) {
            updates.push({ sql: this._sql, args: this._args });
          }
          return { success: true };
        },
        async first() { return null; },
        async all() { return { results: [] }; },
      };
    },
  };
}

/// Relie les clauses « colonne = CASE … » à leurs deux paramètres.
/// Renvoie { colonne: [param1, param2] } — c'est LA correspondance que
/// le test doit vérifier, pas le simple fait que la valeur soit présente
/// quelque part dans la liste.
function clausesEtParams(u) {
  const setPart = u.sql.slice(u.sql.indexOf('SET') + 3, u.sql.indexOf('WHERE'));
  const cols = setPart
    .split(/,\s*(?=[a-z_]+ = CASE)/)
    .map((c) => c.trim().split(' ')[0])
    .filter((c) => /^[a-z_]+$/.test(c));
  const map = {};
  cols.forEach((col, i) => { map[col] = [u.args[2 * i], u.args[2 * i + 1]]; });
  map._mac = u.args[u.args.length - 1];
  map._nbClauses = cols.length;
  map._nbArgs = u.args.length;
  return map;
}

// KV simulé : notre D1 bouchon ne renvoie aucune ligne famille, donc le
// worker retombe sur son ancien chemin KV. On le stubbe pour que le
// heartbeat réponde 200 — ce test-ci parle de l'ÉCRITURE `devices`, pas
// du repli KV (couvert ailleurs).
const makeKv = () => ({ async get() { return null; }, async put() {} });

const battement = (body) =>
  worker.fetch(new Request('https://app.x/api/heartbeat', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  }), { DB: makeDb(), KV_7MOTION: makeKv() }, ctx);

// ---------------------------------------------------------
//  1. Une box récente remonte son numéro maison.
// ---------------------------------------------------------
updates = [];
let r = await battement({
  mac: 'MK:11:22:33:44:55',
  model: 'Chromecast HD', android: '12', build: 'STTE.240', androidId: 'abc123',
  appVersion: '0.3.3', appBuild: 1788127315, buildLabel: '19882', platform: 'tv',
});
await Promise.all(ctx._q); ctx._q = [];
ok(r.status === 200, '1 heartbeat accepté');
ok(updates.length === 1, '1 une seule écriture devices');

if (updates.length === 1) {
  const m = clausesEtParams(updates[0]);
  ok(m._nbArgs === m._nbClauses * 2 + 1,
     `1 ${m._nbClauses} clauses ↔ ${m._nbArgs} paramètres (2 par clause + la MAC)`);
  ok(m.build_label && m.build_label[0] === '19882' && m.build_label[1] === '19882',
     '1 build_label reçoit BIEN le numéro maison (bonne position)');
  ok(m.platform[0] === 'tv' && m.platform[1] === 'tv',
     '1 platform reçoit toujours la plateforme (pas décalée par l’ajout)');
  ok(m.app_version[0] === '0.3.3', '1 app_version intacte');
  ok(m.app_build[0] === 1788127315, '1 app_build intact');
  ok(m.android_id[0] === 'abc123', '1 android_id intact');
  ok(m.device_model[0] === 'Chromecast HD', '1 device_model intact');
  ok(m._mac === 'MK:11:22:33:44:55', '1 la MAC est le dernier paramètre');
}

// ---------------------------------------------------------
//  2. Une app d'AVANT le numéro maison : on n'écrase pas.
// ---------------------------------------------------------
updates = [];
r = await battement({
  mac: 'MK:11:22:33:44:55',
  model: 'Mi Box', appVersion: '0.3.1', appBuild: 1788122176, platform: 'tv',
});
await Promise.all(ctx._q); ctx._q = [];
ok(updates.length === 1, '2 une écriture devices');
if (updates.length === 1) {
  const m = clausesEtParams(updates[0]);
  ok(m.build_label[0] === '' && m.build_label[1] === '',
     '2 numéro absent → paramètre vide (le CASE conserve l’ancienne valeur)');
  ok(/build_label = CASE WHEN \? != '' THEN \? ELSE build_label END/.test(updates[0].sql),
     '2 la clause CONSERVE l’existant quand le paramètre est vide');
}

// ---------------------------------------------------------
//  3. Un numéro délirant est BORNÉ (jamais écrit tel quel).
// ---------------------------------------------------------
updates = [];
await battement({
  mac: 'MK:11:22:33:44:55', platform: 'tv', buildLabel: '9'.repeat(500),
});
await Promise.all(ctx._q); ctx._q = [];
if (updates.length === 1) {
  const m = clausesEtParams(updates[0]);
  ok(m.build_label[0].length === 16, '3 numéro borné à 16 caractères');
}

// ---------------------------------------------------------
//  4. Un heartbeat SANS aucune info d'appareil n'écrit rien.
// ---------------------------------------------------------
updates = [];
await battement({ mac: 'MK:11:22:33:44:55' });
await Promise.all(ctx._q); ctx._q = [];
ok(updates.length === 0, '4 rien à enrichir → aucune écriture devices');

// ---------------------------------------------------------
//  5. Le numéro maison SEUL suffit à déclencher l'écriture.
// ---------------------------------------------------------
updates = [];
await battement({ mac: 'MK:11:22:33:44:55', buildLabel: '19882' });
await Promise.all(ctx._q); ctx._q = [];
ok(updates.length === 1, '5 le numéro maison seul déclenche l’écriture');

console.log(`\n${pass} PASS, ${fail} FAIL`);
process.exit(fail === 0 ? 0 : 1);
