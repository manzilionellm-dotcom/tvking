// Smoke test — COPIEUR INTELLIGENT + FAÇADE (gateway).
// Vérifie les briques PURES qui rendent la copie stable + privée :
//   • validateFacadeBase : CONTRAT honnête de façade — ACCEPTE toute origine
//     http(s) valide (la copie ne dépend jamais de Worker→gateway) et CLASSE
//     la vérifiabilité : probe:true (https + domaine → sondable par le relais)
//     vs probe:false (http/IP → joignable par les APPS seulement, sondes du
//     diagnostic informatives). Refuse uniquement l'illisible ;
//   • _cleanGatewayBase : origine propre (compat), '' si illisible ;
//   • _rewriteOrigin    : rebâtit une URL de chaîne SUR la façade (stabilité
//     + confidentialité), sans casser le port ni la query ;
//   • autoDetectSource  : « colle n'importe quoi » (lien Xtream ou URL M3U).
// Lancer : node cloudflare/master_copier.smoke.mjs
import assert from 'node:assert/strict';
import {
  validateFacadeBase, facadeReason, _cleanGatewayBase, _rewriteOrigin, autoDetectSource,
} from './api_v1.js';

let n = 0;
const ok = (m) => { n++; console.log('  ✓', m); };

// --- validateFacadeBase : accepter sans mentir sur la vérifiabilité ---------
let v = validateFacadeBase('https://tv.moi.com/get.php?x=1');
assert.equal(v.ok, true);
assert.equal(v.base, 'https://tv.moi.com'); // path + query retirés
assert.equal(v.probe, true); // https + domaine → sondable par le relais
ok('façade : https + domaine → OK, origine propre, SONDABLE (probe:true)');

v = validateFacadeBase('https://tv.moi.com:8443/');
assert.equal(v.ok, true);
assert.equal(v.base, 'https://tv.moi.com:8443'); // port conservé, slash retiré
assert.equal(v.probe, true);
ok('façade : port conservé, slash final retiré');

// http:// = ACCEPTÉ (les apps la joignent, la copie n'a pas besoin du relais)
// mais NON sondable → le message explique la nuance au lieu d'interdire.
v = validateFacadeBase('http://tv.moi.com');
assert.equal(v.ok, true);
assert.equal(v.base, 'http://tv.moi.com');
assert.equal(v.probe, false);
assert.equal(v.reason, 'not_https');
assert.ok(/apps/i.test(facadeReason(v.reason)));
ok('façade : http:// ACCEPTÉ mais app-seulement (probe:false, message honnête)');

// IP brute (ou nip.io en http) = le cas RÉEL du gateway self-hosté sur VPS :
// accepté (l'app le joint), classé non sondable — fini le blocage 403/530.
v = validateFacadeBase('http://203.0.113.7');
assert.equal(v.ok, true);
assert.equal(v.base, 'http://203.0.113.7');
assert.equal(v.probe, false);
ok('façade : http://IP (VPS nu) ACCEPTÉE en app-seulement — le copieur marche');

v = validateFacadeBase('https://203.0.113.7:8088');
assert.equal(v.ok, true);
assert.equal(v.probe, false);
assert.equal(v.reason, 'ip_literal');
assert.ok(/IP/i.test(facadeReason(v.reason)));
ok('façade : IP brute → acceptée, sonde du relais NON garantie (informatif)');

v = validateFacadeBase('https://localhost');
assert.equal(v.ok, true);
assert.equal(v.probe, false);
assert.equal(v.reason, 'not_domain');
ok('façade : hôte sans domaine (localhost) → app-seulement');

v = validateFacadeBase('pas une url');
assert.equal(v.ok, false);
assert.equal(v.reason, 'no_scheme');
ok('façade : entrée non-URL → refus (jamais d’erreur)');

v = validateFacadeBase('');
assert.equal(v.ok, false);
assert.equal(v.reason, 'empty');
assert.equal(facadeReason('empty'), ''); // vide = lecture directe assumée, pas une erreur
ok('façade : vide → non-OK mais message vide (repli assumé)');

// --- _cleanGatewayBase : compat (chaîne) au-dessus du contrat ---------------
assert.equal(_cleanGatewayBase('https://tv.moi.com/get.php?x=1'), 'https://tv.moi.com');
ok('cleanGatewayBase : façade valide → origine propre');

// http accepté aussi ici : c'est CE chemin qui réécrit les URLs du copieur —
// une façade http/IP doit réécrire quand même (lecture par les apps).
assert.equal(_cleanGatewayBase('http://tv.moi.com:9000/'), 'http://tv.moi.com:9000');
ok('cleanGatewayBase : http:// accepté (réécriture pour les apps)');

assert.equal(_cleanGatewayBase('pas une url'), '');
ok('cleanGatewayBase : illisible → vide');

assert.equal(_cleanGatewayBase(''), '');
ok('cleanGatewayBase : vide → vide');

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
