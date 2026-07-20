// Smoke test — COPIEUR INTELLIGENT + FAÇADE (gateway).
// Vérifie les briques PURES qui rendent la copie stable + privée :
//   • _cleanGatewayBase : normalise l'URL de façade collée par le maître ;
//   • _rewriteOrigin    : rebâtit une URL de chaîne SUR la façade (stabilité
//     + confidentialité), sans casser le port ni la query ;
//   • autoDetectSource  : « colle n'importe quoi » (lien Xtream ou URL M3U).
// Lancer : node cloudflare/master_copier.smoke.mjs
import assert from 'node:assert/strict';
import { _cleanGatewayBase, _rewriteOrigin, autoDetectSource } from './api_v1.js';

let n = 0;
const ok = (m) => { n++; console.log('  ✓', m); };

// --- _cleanGatewayBase : origine propre, sans path ni slash final ----------
assert.equal(_cleanGatewayBase('https://tv.moi.com/get.php?x=1'), 'https://tv.moi.com');
ok('façade : path + query retirés → origine propre');

assert.equal(_cleanGatewayBase('http://tv.moi.com:9000/'), 'http://tv.moi.com:9000');
ok('façade : port conservé, slash final retiré');

assert.equal(_cleanGatewayBase('pas une url'), '');
ok('façade : entrée non-URL → vide (jamais d’erreur)');

assert.equal(_cleanGatewayBase(''), '');
ok('façade : vide → vide');

// --- _rewriteOrigin : lecture reconstruite SUR la façade -------------------
// Façade sans port → l'ancien port du fournisseur DOIT disparaître (bug WHATWG
// du setter .host évité en posant hostname + port séparément).
assert.equal(
  _rewriteOrigin('http://prov.com:8080/live/u/p/55.ts', 'https://tv.moi.com'),
  'https://tv.moi.com/live/u/p/55.ts',
);
ok('URL Xtream .ts → façade (port fournisseur effacé)');

// Façade AVEC port → ce port remplace celui du fournisseur.
assert.equal(
  _rewriteOrigin('http://prov.com:8080/live/u/p/55.ts', 'http://tv.moi.com:9000'),
  'http://tv.moi.com:9000/live/u/p/55.ts',
);
ok('URL Xtream .ts → façade avec port dédié');

// Query préservée (HLS avec paramètres).
assert.equal(
  _rewriteOrigin('http://prov:8080/abc/def.m3u8?token=xyz', 'https://tv.moi.com'),
  'https://tv.moi.com/abc/def.m3u8?token=xyz',
);
ok('path + query M3U préservés lors de la réécriture');

// Pas de façade → URL inchangée (lecture directe, repli).
assert.equal(_rewriteOrigin('http://prov/55.ts', ''), 'http://prov/55.ts');
ok('sans façade → URL inchangée (repli direct)');

// URL invalide → renvoyée telle quelle (best-effort, jamais d’erreur).
assert.equal(_rewriteOrigin('pas-une-url', 'https://tv.moi.com'), 'pas-une-url');
ok('URL de chaîne invalide → inchangée (robustesse)');

// --- autoDetectSource : « colle n'importe quoi » ---------------------------
const xt = autoDetectSource({ url: 'http://serveur:8080/get.php?username=jean&password=secret' });
assert.equal(xt.source.type, 'xtream');
assert.equal(xt.source.server_url, 'http://serveur:8080');
assert.equal(xt.source.username, 'jean');
assert.equal(xt.source.password, 'secret');
ok('lien get.php → source Xtream (serveur + identifiants extraits)');

const m3 = autoDetectSource({ url: 'https://host.tv/playlist.m3u' });
assert.equal(m3.source.type, 'm3u');
assert.equal(m3.source.m3u_url, 'https://host.tv/playlist.m3u');
ok('URL simple → source M3U');

assert.ok(autoDetectSource({ url: 'bonjour' }).error);
ok('blob non exploitable → erreur explicite (pas de crash)');

console.log(`\n${n} assertions OK — copieur (façade + auto-détection) validé.`);
