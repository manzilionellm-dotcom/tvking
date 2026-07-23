// Smoke test — LECTURE DE LIGNE ROBUSTE (repli get.php + retry).
// `provider_bad_streams` était fragile en prod : un player_api qui renvoie du
// HTML, un objet JSON ou un 5xx fugace faisait échouer TOUTE la copie. Le
// copieur doit maintenant :
//   • réessayer UNE fois (timeout/5xx passager absorbé) ;
//   • replier sur get.php (M3U officiel de la même ligne) si player_api reste
//     illisible — en substituant l'identité de diffusion dans les chemins
//     Xtream (les identifiants fournisseur ne fuient JAMAIS) ;
//   • ne renoncer qu'après avoir tout tenté, avec une erreur parlante.
// Lancer : node cloudflare/copy_fallback.smoke.mjs
import assert from 'node:assert/strict';
import { _copyXtream, parseM3uChannelsText } from './api_v1.js';

let n = 0;
const ok = (m) => { n++; console.log('  ✓', m); };

const SRC = {
  type: 'xtream',
  server_url: 'http://fournisseur.test:8080',
  username: 'jean',
  password: 'secret',
};

// Petit M3U « get.php » représentatif (2 chaînes, identifiants dans le chemin).
const GET_PHP_M3U = [
  '#EXTM3U',
  '#EXTINF:-1 tvg-logo="a.png" group-title="Sport",Foot 1',
  'http://fournisseur.test:8080/live/jean/secret/1.ts',
  '#EXTINF:-1 group-title="News",Info 24',
  'http://fournisseur.test:8080/live/jean/secret/2.ts',
].join('\n');

// Mock fetch scripté : on enregistre chaque appel et on répond selon l'URL.
let calls = [];
function mockFetch(script) {
  calls = [];
  globalThis.fetch = async (url) => {
    const u = String(url);
    calls.push(u);
    const r = await script(u, calls.length);
    if (r instanceof Error) throw r;
    return r;
  };
}
const resp = (status, body, isJson = false) => ({
  ok: status >= 200 && status < 300,
  status,
  json: async () => { if (isJson) return body; throw new Error('not json'); },
  text: async () => String(body),
});

// --- 1) player_api renvoie un OBJET (pas un tableau) → repli get.php --------
mockFetch(async (u) => {
  if (u.includes('player_api.php')) return resp(200, { user_info: {} }, true);
  if (u.includes('get.php')) return resp(200, GET_PHP_M3U);
  throw new Error('URL inattendue : ' + u);
});
let out = await _copyXtream(SRC);
assert.equal(out.fallback, 'get_php');
assert.equal(out.total, 2);
assert.equal(out.categories.length, 2);
assert.ok(out.categories[0].channels[0].url.includes('/live/jean/secret/1.ts'));
ok('player_api illisible (objet) → repli get.php, chaînes rangées par catégorie');

// --- 2) player_api renvoie du HTML → repli get.php --------------------------
mockFetch(async (u) => {
  if (u.includes('player_api.php')) return resp(200, '<html>maintenance</html>');
  if (u.includes('get.php')) return resp(200, GET_PHP_M3U);
});
out = await _copyXtream(SRC);
assert.equal(out.fallback, 'get_php');
assert.equal(out.total, 2);
ok('player_api renvoie du HTML → repli get.php (jamais un crash JSON)');

// --- 3) 5xx FUGACE sur player_api : le RETRY suffit (pas besoin du repli) ---
{
  let apiCalls = 0;
  mockFetch(async (u) => {
    if (u.includes('get_live_streams')) {
      apiCalls++;
      if (apiCalls === 1) return resp(512, 'boom'); // 1er essai : 5xx passager
      return resp(200, [{ stream_id: 7, name: 'Foot', category_id: '1' }], true);
    }
    if (u.includes('get_live_categories')) return resp(200, [{ category_id: '1', category_name: 'Sport' }], true);
  });
  out = await _copyXtream(SRC);
  assert.equal(apiCalls, 2); // un échec + UN retry, pas plus
  assert.equal(out.fallback, undefined);
  assert.equal(out.total, 1);
  assert.equal(out.categories[0].name, 'Sport');
  ok('5xx fugace sur player_api → absorbé par UN retry (chemin normal conservé)');
}

// --- 4) IDENTITÉ DE DIFFUSION dans le repli : identifiants JAMAIS fuités ----
mockFetch(async (u) => {
  if (u.includes('player_api.php')) return resp(500, 'down');
  if (u.includes('get.php')) return resp(200, GET_PHP_M3U);
});
out = await _copyXtream(SRC, 'https://gw.moi.tld', 'diffusion', 'partage');
assert.equal(out.fallback, 'get_php');
const urls = out.categories.flatMap((c) => c.channels.map((ch) => ch.url));
for (const u of urls) {
  assert.ok(u.startsWith('https://gw.moi.tld/'), 'origine = façade : ' + u);
  assert.ok(!u.includes('jean') && !u.includes('secret'), 'identifiants fournisseur fuités : ' + u);
  assert.ok(u.includes('/live/diffusion/partage/'), 'identité de diffusion attendue : ' + u);
}
ok('repli get.php + façade + identité : URLs sur le gateway, ligne fournisseur masquée');

// --- 5) TOUT échoue → erreur remontée (la plus parlante : player_api) -------
mockFetch(async (u) => {
  if (u.includes('player_api.php')) return resp(403, 'forbidden');
  if (u.includes('get.php')) return resp(403, 'forbidden');
});
await assert.rejects(() => _copyXtream(SRC), /provider_http_403/);
ok('player_api ET get.php morts → erreur franche (identifiants refusés)');

// --- 6) parseM3uChannelsText : brique pure du repli --------------------------
const parsed = parseM3uChannelsText(GET_PHP_M3U, '');
assert.equal(parsed.total, 2);
assert.deepEqual(parsed.categories.map((c) => c.name).sort(), ['News', 'Sport']);
ok('parseM3uChannelsText : catégories + chaînes lues depuis un texte M3U');

// Doublons d'URL ignorés (qualité VIP), lignes # ignorées.
const dup = parseM3uChannelsText(GET_PHP_M3U + '\n#EXTINF:-1,Copie\nhttp://fournisseur.test:8080/live/jean/secret/1.ts\n');
assert.equal(dup.total, 2);
ok('doublon d’URL ignoré au parse (pas de chaîne en double)');

console.log(`\n${n} assertions OK — lecture de ligne robuste (retry + repli get.php) validée.`);
