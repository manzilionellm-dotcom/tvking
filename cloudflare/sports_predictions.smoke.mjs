// =========================================================
//  sports_predictions.smoke.mjs — Pronostics des fans, côté serveur
// =========================================================
//  On fait tourner LE VRAI code (worker.js → sports_predictions.js) avec
//  une base D1 simulée. Ce qui est verrouillé :
//
//    1. VALIDATION : un choix hors home/draw/away, un identifiant de
//       match ou une MAC mal formés n'entrent JAMAIS en base ;
//    2. UNE VOIX PAR APPAREIL : revoter remplace, ne s'ajoute pas ;
//    3. FERMETURE : après le coup d'envoi déclaré, 409, la base ne bouge pas ;
//    4. POURCENTAGES : entiers, somme = 100 même à 1/3 – 1/3 – 1/3 ;
//    5. ANONYMAT : la lecture renvoie des comptes, jamais la liste des MAC.
//
//  Exécution : node cloudflare/sports_predictions.smoke.mjs
// =========================================================
import worker from './worker.js';
import { percentages, voteOpen } from './sports_predictions.js';

let pass = 0; let fail = 0;
const ok = (cond, label) => {
  if (cond) { pass++; console.log('  PASS ' + label); }
  else { fail++; console.log('  FAIL ' + label); }
};

// ---- D1 simulée : la table match_predictions, en mémoire. -------------
const rows = new Map(); // `${match}|${mac}` -> { match, mac, pick, kickoff, at }
const db = {
  prepare(sql) {
    return {
      _sql: sql, _args: [],
      bind(...a) { this._args = a; return this; },
      async run() {
        if (/INSERT INTO match_predictions/.test(this._sql)) {
          const [match, mac, pick, kickoff, at] = this._args;
          rows.set(`${match}|${mac}`, { match, mac, pick, kickoff, at });
        }
        return { success: true };
      },
      async first() {
        if (/SELECT pick FROM match_predictions WHERE match_id = \? AND mac = \?/.test(this._sql)) {
          const r = rows.get(`${this._args[0]}|${this._args[1]}`);
          return r ? { pick: r.pick } : null;
        }
        if (/FROM rate_limits/.test(this._sql)) return null;
        return null;
      },
      async all() {
        if (/COUNT\(\*\) AS n FROM match_predictions/.test(this._sql)) {
          const counts = {};
          for (const r of rows.values()) {
            if (r.match !== this._args[0]) continue;
            counts[r.pick] = (counts[r.pick] || 0) + 1;
          }
          return { results: Object.entries(counts).map(([pick, n]) => ({ pick, n })) };
        }
        return { results: [] };
      },
    };
  },
};
const env = { DB: db, ADMIN_SECRET: 'x' };

const call = (method, path, body) => worker.fetch(
  new Request('https://app.example' + path, {
    method,
    headers: { 'content-type': 'application/json', 'cf-connecting-ip': '1.2.3.4' },
    body: body === undefined ? undefined : JSON.stringify(body),
  }),
  env,
  { waitUntil() {} },
);

const future = Date.now() + 3600 * 1000;
const past = Date.now() - 60 * 1000;

console.log('1. validation');
{
  let r = await call('POST', '/api/sports/predict', { mac: 'MK:AA:AA:AA:AA:01', match: '2052478', pick: 'lol' });
  ok(r.status === 400, 'choix inconnu → 400');
  r = await call('POST', '/api/sports/predict', { mac: 'MK:AA:AA:AA:AA:01', match: 'x; DROP', pick: 'home' });
  ok(r.status === 400, 'identifiant de match mal formé → 400');
  r = await call('POST', '/api/sports/predict', { mac: 'pas une mac', match: '2052478', pick: 'home' });
  ok(r.status === 400, 'MAC mal formée → 400');
  ok(rows.size === 0, 'rien de tout cela n\'est entré en base');
  r = await call('GET', '/api/sports/predict/bad%20id');
  ok(r.status === 400, 'lecture avec identifiant mal formé → 400');
}

console.log('2. une voix par appareil, revoter remplace');
{
  let r = await call('POST', '/api/sports/predict', { mac: 'MK:AA:AA:AA:AA:01', match: '2052478', pick: 'home', kickoff: future });
  ok(r.status === 200, 'vote accepté');
  let j = await r.json();
  ok(j.mine === 'home' && j.total === 1 && j.counts.home === 1, 'mon vote est compté');
  r = await call('POST', '/api/sports/predict', { mac: 'MK:AA:AA:AA:AA:01', match: '2052478', pick: 'away', kickoff: future });
  j = await r.json();
  ok(j.total === 1 && j.counts.away === 1 && j.counts.home === 0, 'revoter REMPLACE : toujours 1 voix');
  await call('POST', '/api/sports/predict', { mac: 'MK:AA:AA:AA:AA:02', match: '2052478', pick: 'draw', kickoff: future });
  await call('POST', '/api/sports/predict', { mac: 'MK:AA:AA:AA:AA:03', match: '2052478', pick: 'draw', kickoff: future });
  r = await call('GET', '/api/sports/predict/2052478?mac=MK:AA:AA:AA:AA:02');
  j = await r.json();
  ok(j.total === 3 && j.counts.draw === 2 && j.counts.away === 1, 'trois appareils, trois voix');
  ok(j.percent.draw === 67 && j.percent.away === 33 && j.percent.home === 0, 'pourcentages 67 / 33 / 0');
  ok(j.mine === 'draw', 'la lecture rend MON vote');
  ok(JSON.stringify(j).indexOf('MK:AA:AA:AA:AA:01') === -1, 'ANONYMAT : aucune MAC ne ressort');
  r = await call('GET', '/api/sports/predict/2052478');
  j = await r.json();
  ok(j.mine === null, 'sans MAC : pas de « mon vote », mais les comptes oui');
}

console.log('3. fermeture au coup d\'envoi');
{
  const before = rows.size;
  const r = await call('POST', '/api/sports/predict', { mac: 'MK:AA:AA:AA:AA:09', match: '2052478', pick: 'home', kickoff: new Date(past).toISOString() });
  ok(r.status === 409, 'coup d\'envoi passé → 409');
  ok(rows.size === before, 'la base n\'a pas bougé');
  ok(voteOpen(Date.now(), null), 'sans horaire connu : ouvert (client ancien)');
  ok(!voteOpen(10, 5), 'après le coup d\'envoi : fermé');
  ok(voteOpen(5, 10), 'avant : ouvert');
}

console.log('4. pourcentages qui font 100');
{
  const p = percentages({ home: 1, draw: 1, away: 1 });
  ok(p.home + p.draw + p.away === 100, '1/1/1 → somme 100 (' + JSON.stringify(p) + ')');
  const q = percentages({ home: 0, draw: 0, away: 0 });
  ok(q.home === 0 && q.draw === 0 && q.away === 0, 'aucun vote → 0/0/0, pas de division par zéro');
  const s = percentages({ home: 2, draw: 0, away: 1 });
  ok(s.home === 67 && s.away === 33, '2/0/1 → 67 / 0 / 33');
}

console.log(`\n${pass} PASS, ${fail} FAIL`);
process.exit(fail ? 1 : 0);
