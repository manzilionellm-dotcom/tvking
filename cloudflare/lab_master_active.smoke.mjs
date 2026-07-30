// Repro : une box MAÎTRE qui a DÉJÀ sa vraie source reçoit en plus la
// source labo. On rejoue ensuite la logique de RemoteSourceRepository.sync()
// (lib/features/playlists/data/remote_source_repository.dart) pour voir
// QUELLE playlist finit ACTIVE côté app.
import worker from './worker.js';

const MASTER = 'MK:AA:AA:AA:AA:01';
const state = {
  labRows: [{
    id: 'lab_1', name: 'ttt',
    url: 'http://thekung.801802.com/get.php?username=jean&password=supersecret&type=m3u_plus',
    source_json: JSON.stringify({
      type: 'xtream', label: 'ttt', server_url: 'http://thekung.801802.com',
      username: 'jean', password: 'supersecret', m3u_url: null, epg_url: null,
    }),
    created_at: 1,
  }],
  masters: [{ mac: MASTER }],
};

const db = {
  prepare(sql) {
    return {
      _sql: sql, _args: [],
      bind(...a) { this._args = a; return this; },
      async run() { return { success: true }; },
      async first() {
        const s = this._sql;
        if (/FROM sqlite_master/.test(s)) return { name: 'app_masters' };
        if (/FROM app_masters WHERE mac/.test(s)) return { x: 1 };
        if (/FROM devices WHERE mac = \?/.test(s)) return null;
        // La box maître a DÉJÀ sa vraie source d'abonnement (cas de Lionel).
        if (/FROM device_sources WHERE mac/.test(s)) {
          return {
            type: 'xtream', label: 'Mon abonnement', server_url: 'http://vrai-serveur.tv',
            username: 'lionel', password: 'vraimdp', m3u_url: null, epg_url: null,
            sources_json: null, updated_at: 1,
          };
        }
        return null;
      },
      async all() {
        const s = this._sql;
        if (/SELECT mac FROM app_masters/.test(s)) return { results: state.masters };
        if (/FROM lab_sources/.test(s)) return { results: state.labRows };
        return { results: [] };
      },
    };
  },
};

const ctx = { waitUntil() {}, passThroughOnException() {} };
const r = await worker.fetch(
  new Request('https://app.x/api/device-source/' + MASTER), { DB: db }, ctx,
);
const body = await r.json();

console.log('--- Réponse du worker à la box maître ---');
body.sources.forEach((s, i) => {
  console.log(`  sources[${i}] : ${s.label}  (${s.server_url})  origin=${s.origin || 'panel'}`);
});
console.log(`  source (champ historique) : ${body.source.label}`);

// --- Rejoue applySources() : boucle SÉQUENTIELLE, chaque import qui a le
// --- droit d'activer appelle setActivePlaylist → le DERNIER autorisé gagne.
// --- `shouldActivate` est la règle ajoutée dans remote_source_repository.dart.
const shouldActivate = (s, all) =>
  s.origin !== 'lab' || !all.some((o) => o.origin !== 'lab');

function run(sources, titre) {
  console.log(`\n--- ${titre} ---`);
  let active = null;
  for (const s of sources) {
    const act = shouldActivate(s, sources);
    console.log(`  import « ${s.label} »${act ? ' → setActivePlaylist()' : ' (import silencieux)'}`);
    if (act) active = s.label;
  }
  console.log(`  >>> PLAYLIST ACTIVE : « ${active} »`);
  return active;
}

const avant = (() => {
  console.log('\n--- AVANT le correctif (la dernière source gagne) ---');
  let a = null;
  for (const s of body.sources) a = s.label;
  console.log(`  >>> PLAYLIST ACTIVE : « ${a} »  ← la box bascule sur le labo`);
  return a;
})();

const apres = run(body.sources, 'APRÈS le correctif');

// Cas limite : box maître SANS abonnement — le labo doit rester utile.
const seulLabo = body.sources.filter((s) => s.origin === 'lab');
const apresSeul = run(seulLabo, 'Box maître SANS abonnement (labo seul)');

let fail = 0;
const ok = (c, m) => { if (c) console.log('PASS', m); else { fail++; console.log('FAIL', m); } };
console.log('');
ok(avant === 'ttt', 'la régression est bien reproduite (avant : le labo gagnait)');
ok(apres === 'Mon abonnement', 'après : la box garde son vrai abonnement');
ok(apresSeul === 'ttt', 'après : sans abonnement, la source labo alimente quand même la box');
console.log(fail ? `\n${fail} FAIL` : '\n3 PASS, 0 FAIL');
process.exit(fail ? 1 : 0);
