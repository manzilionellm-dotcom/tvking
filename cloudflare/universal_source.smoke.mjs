// =========================================================
//  universal_source.smoke.mjs — Activation UNIVERSELLE (auto-détection)
// =========================================================
//  Vérifie que `normalizeSource` détecte et normalise TOUT SEUL le format
//  d'une source IPTV (M3U vs Xtream) — l'admin colle n'importe quoi, il n'a
//  jamais à choisir le type. Couvre :
//    - lien get.php / player_api.php Xtream → { type:'xtream', server propre }
//    - identifiants Xtream à plat (server+user+pass) sans type
//    - URL de playlist .m3u/.m3u8 → { type:'m3u' }
//    - server_url = URL get.php complète (nettoyage origine + extraction creds)
//    - « M3U » qui est en réalité un lien Xtream → bascule Xtream
//    - rétro-compat : type explicite 'xtream'/'m3u' inchangé
//    - entrées invalides → { error }
//
//  Exécution (aucun runner requis, Node 18+) :
//    node cloudflare/universal_source.smoke.mjs
// =========================================================
import { normalizeSource, parseXtreamUrl } from './api_v1.js';

let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass++; console.log('PASS', m); }
  else { fail++; console.log('FAIL', m); }
};
const eq = (a, b, m) => ok(a === b, `${m} (got ${JSON.stringify(a)})`);

// 1) Lien get.php Xtream collé, type NON précisé → détecté xtream + origine propre
let r = normalizeSource({
  url: 'http://line.example.com:8080/get.php?username=abc&password=def&type=m3u_plus&output=ts',
});
ok(!r.error, '1 get.php auto → pas d\'erreur');
eq(r.source?.type, 'xtream', '1 type=xtream');
eq(r.source?.server_url, 'http://line.example.com:8080', '1 server = origine propre (sans get.php)');
eq(r.source?.username, 'abc', '1 username extrait');
eq(r.source?.password, 'def', '1 password extrait');

// 2) player_api.php (https, sans port) → xtream
r = normalizeSource({ url: 'https://iptv.host/player_api.php?username=U1&password=P1' });
eq(r.source?.type, 'xtream', '2 player_api → xtream');
eq(r.source?.server_url, 'https://iptv.host', '2 server sans port');

// 3) Identifiants à plat, type absent → xtream
r = normalizeSource({ server_url: 'http://srv.tv:2095/', username: 'joe', password: 'x1' });
eq(r.source?.type, 'xtream', '3 creds à plat → xtream');
eq(r.source?.server_url, 'http://srv.tv:2095', '3 slash final retiré');

// 4) URL de playlist .m3u8, type absent → m3u
r = normalizeSource({ url: 'http://cdn.example.net/list/playlist.m3u8' });
eq(r.source?.type, 'm3u', '4 .m3u8 → m3u');
eq(r.source?.m3u_url, 'http://cdn.example.net/list/playlist.m3u8', '4 m3u_url conservé');

// 5) type='xtream' MAIS server_url = URL get.php complète → nettoyée
r = normalizeSource({
  type: 'xtream',
  server_url: 'http://box.tv:8000/get.php?username=aa&password=bb',
});
eq(r.source?.server_url, 'http://box.tv:8000', '5 server_url nettoyé');
eq(r.source?.username, 'aa', '5 username récupéré du lien');
eq(r.source?.password, 'bb', '5 password récupéré du lien');

// 6) type='m3u' mais c'est un lien Xtream → bascule xtream
r = normalizeSource({
  type: 'm3u',
  m3u_url: 'http://host.tv:80/get.php?username=zz&password=yy&type=m3u_plus',
});
eq(r.source?.type, 'xtream', '6 m3u qui est Xtream → bascule xtream');
eq(r.source?.username, 'zz', '6 username récupéré');

// 7) Rétro-compat : xtream explicite complet → inchangé
r = normalizeSource({ type: 'xtream', server_url: 'http://a.b:1', username: 'u', password: 'p' });
eq(r.source?.type, 'xtream', '7 xtream explicite ok');
eq(r.source?.server_url, 'http://a.b:1', '7 server inchangé');

// 8) Rétro-compat : m3u explicite simple → inchangé
r = normalizeSource({ type: 'm3u', m3u_url: 'http://a.b/list.m3u' });
eq(r.source?.type, 'm3u', '8 m3u explicite ok');

// 9) EPG conservé en auto-détection
r = normalizeSource({ url: 'http://x.tv/get.php?username=a&password=b', epg_url: 'http://x.tv/xmltv.php' });
eq(r.source?.epg_url, 'http://x.tv/xmltv.php', '9 epg conservé');

// 10) Invalide : ni URL ni creds → erreur claire
r = normalizeSource({ label: 'rien' });
ok(!!r.error, '10 rien d\'exploitable → erreur');

// 11) Invalide : xtream sans mot de passe → erreur
r = normalizeSource({ type: 'xtream', server_url: 'http://a.b', username: 'u' });
ok(!!r.error, '11 xtream incomplet → erreur');

// 12) parseXtreamUrl direct : URL non-Xtream → null
ok(parseXtreamUrl('http://plain.host/playlist.m3u') === null, '12 m3u simple → parseXtreamUrl null');
ok(parseXtreamUrl('pas une url') === null, '12b non-URL → null');

// 13) type='auto' explicite → détection
r = normalizeSource({ type: 'auto', url: 'http://s.tv:99/get.php?username=q&password=w' });
eq(r.source?.type, 'xtream', '13 type=auto → détecté');

console.log(`\n${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
