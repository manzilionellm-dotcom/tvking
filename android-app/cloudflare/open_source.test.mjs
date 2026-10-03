// =========================================================
//  open_source.test.mjs — Source libre + ancien catalogue
// =========================================================
//  node cloudflare/open_source.test.mjs
//  Hôtes bidons seulement. Aucun mot de passe réel.
// =========================================================
import worker from './worker.js';
import {
  buildOpenSource,
  parsePlayerLink,
  resolveRegisteredServer,
} from './open_source.js';

const ctx = { waitUntil() {}, passThroughOnException() {} };
let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass += 1; console.log('PASS', m); }
  else { fail += 1; console.log('FAIL', m); }
};

const xt = buildOpenSource({
  type: 'xtream',
  server_url: 'http://fournisseur.invalid:8080',
  username: 'demo',
  password: 'jeton',
});
ok(xt.source && xt.source.server_url === 'http://fournisseur.invalid:8080',
  'Xtream : n\'importe quel hôte');
ok(!xt.error, 'Xtream complet : pas d\'erreur');

const other = buildOpenSource({
  type: 'm3u',
  m3u_url: 'https://autre.invalid/liste.m3u8',
});
ok(other.source && other.source.m3u_url.includes('autre.invalid'),
  'M3U8 : second fournisseur accepté');

const withCreds = buildOpenSource({
  type: 'm3u',
  m3u_url: 'http://demo:jeton@boite.invalid/liste.m3u',
});
ok(withCreds.source.m3u_url.includes('demo:jeton@'),
  'M3U avec identifiants dans l\'adresse');

const player = buildOpenSource({
  type: 'player',
  m3u_url: 'http://lecteur.invalid:8000/get.php?username=demo&password=jeton&type=m3u_plus',
});
ok(player.source.type === 'xtream', 'get.php devient un compte Xtream');
ok(player.source.server_url === 'http://lecteur.invalid:8000', 'origine sans get.php');
ok(player.source.username === 'demo' && player.source.password === 'jeton',
  'identifiants lus dans le lien');

const incomplete = parsePlayerLink('http://lecteur.invalid/get.php');
ok(incomplete.error && incomplete.error.includes('nom d\'utilisateur'),
  'get.php sans identifiants : phrase française');

const empty = buildOpenSource({ type: 'xtream', server_url: '', username: '', password: '' });
ok(empty.error === 'xtream requires server_url, username, password',
  'Xtream vide refusé');

const ftp = buildOpenSource({ type: 'm3u', m3u_url: 'ftp://fichiers.invalid/a.m3u' });
ok(ftp.error && ftp.error.includes('http'), 'schéma ftp refusé');

const known = resolveRegisteredServer(
  [{ id: 'ancien', label: 'Serveur 1', url: 'http://ancien.invalid:8080' }],
  'ancien',
);
ok(known && known.url === 'http://ancien.invalid:8080' && !known.label,
  'serveur déjà enregistré : adresse retrouvée, libellé non renvoyé');
ok(resolveRegisteredServer([{ id: 'ancien', url: 'http://ancien.invalid' }], 'autre') === null,
  'identifiant inconnu : rien inventé');

function dbWith(rows) {
  return {
    prepare(sql) {
      const q = String(sql);
      const api = {
        bind() { return api; },
        async all() {
          if (q.includes('default_servers')) return { results: rows };
          return { results: [] };
        },
        async first() { return null; },
        async run() { return {}; },
      };
      return api;
    },
  };
}

const res = await worker.fetch(
  new Request('https://exemple.invalid/api/servers'),
  { DB: dbWith([{ id: 'ancien', label: 'Serveur 1', url: 'http://ancien.invalid:8080', enabled: 1 }]) },
  ctx,
);
const body = await res.json();
ok(res.status === 200, 'GET /api/servers répond encore');
ok(body.servers && body.servers[0] && body.servers[0].url === 'http://ancien.invalid:8080',
  'une box déjà installée retrouve l\'adresse enregistrée');

const fallback = await worker.fetch(
  new Request('https://exemple.invalid/api/servers'),
  {
    DB: { prepare() { throw new Error('table absente'); } },
    DEFAULT_SERVERS: JSON.stringify([
      { id: 'legacy', label: 'S1', url: 'http://legacy.invalid' },
    ]),
  },
  ctx,
);
const fb = await fallback.json();
ok(fb.servers && fb.servers[0] && fb.servers[0].url === 'http://legacy.invalid',
  'repli interne si la table est absente');

console.log(fail === 0 ? `OK ${pass}` : `ECHEC ${fail}/${pass + fail}`);
if (fail) process.exit(1);
