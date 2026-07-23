// Smoke test — VERROU DU DOMAINE D'EXEMPLE + URLS QUI SUIVENT LA FAÇADE.
// Les deux bugs d'écran noir constatés en PRODUCTION :
//   1. Un exploitant enregistre le domaine d'EXEMPLE (« tv.mondomaine.com »)
//      comme façade → toutes les URLs de test pointent dans le vide → 530 →
//      écran noir partout. → validateFacadeBase doit REFUSER net.
//   2. Les chaînes déjà cochées gardaient l'URL bâtie sur l'ANCIENNE façade ;
//      changer la façade + Enregistrer ne les corrigeait pas. →
//      rewriteM3uFacade doit reconstruire ces URLs (et JAMAIS toucher au reste).
// Lancer : node cloudflare/facade_guard.smoke.mjs
import assert from 'node:assert/strict';
import {
  validateFacadeBase, facadeReason, rewriteM3uFacade, _swapXtreamCreds,
  _copyErrorMessage,
} from './api_v1.js';

let n = 0;
const ok = (m) => { n++; console.log('  ✓', m); };

// --- 1) REJET du domaine d'exemple (toutes variantes) -----------------------
for (const bad of [
  'https://tv.mondomaine.com',
  'http://mondomaine.com',
  'https://x.y.mondomaine.com:8443',
  'https://tv.ton-domaine.com',
  'http://gw.example.com',
  'https://tv.exemple.fr',
]) {
  const v = validateFacadeBase(bad);
  assert.equal(v.ok, false, bad + ' devrait être refusée');
  assert.equal(v.reason, 'example_domain');
}
ok('toutes les façades sur un domaine d’EXEMPLE sont REFUSÉES (reason example_domain)');

// Le message est ACTIONNABLE : il dit pourquoi (domaine inexistant) et quoi
// faire (vrai domaine, ou champ vide).
const msg = facadeReason('example_domain');
assert.ok(/EXEMPLE/i.test(msg) && /écran noir/i.test(msg) && /vide/i.test(msg));
ok('message de refus actionnable (explique le piège + le geste correct)');

// Les VRAIS domaines passent toujours — y compris ceux qui CONTIENNENT le mot
// sans être le domaine d'exemple (pas de faux positif).
for (const good of ['https://tv.moi.com', 'https://pasmondomaine.com', 'https://mondomaine.io']) {
  assert.equal(validateFacadeBase(good).ok, true, good + ' devrait passer');
}
ok('les vrais domaines passent (aucun faux positif sur des noms proches)');

// --- 2) rewriteM3uFacade : les URLs SUIVENT la façade -----------------------
const OLD = 'https://ancienne.gw.tld1';
const NEW = 'https://nouvelle.gw.tld2';
const m3u = [
  '#EXTM3U',
  '#EXTINF:-1 tvg-logo="l" group-title="Sport",Chaîne 1',
  'https://ancienne.gw.tld1/live/u/p/1.ts',
  '#EXTINF:-1,Chaîne 2 (exemple hérité)',
  'http://tv.mondomaine.com/live/u/p/2.ts',
  '#EXTINF:-1,Ajout manuel (autre hôte, à NE PAS toucher)',
  'https://cdn.publique.net/flux.m3u8?token=xyz',
].join('\n');

// Changement de façade : ancienne → nouvelle, exemple → nouvelle, manuel intact.
let r = rewriteM3uFacade(m3u, OLD, NEW);
assert.equal(r.changed, 2);
assert.equal(r.stale, 0);
assert.ok(r.m3u.includes('https://nouvelle.gw.tld2/live/u/p/1.ts'));
assert.ok(r.m3u.includes('https://nouvelle.gw.tld2/live/u/p/2.ts'));
assert.ok(r.m3u.includes('https://cdn.publique.net/flux.m3u8?token=xyz'));
assert.ok(!r.m3u.includes('ancienne.gw.tld1') && !r.m3u.includes('mondomaine.com'));
ok('façade changée → URLs de l’ancienne façade ET du domaine d’exemple reconstruites');

// Les lignes #EXTINF (nom, logo, dossier) ne bougent JAMAIS.
assert.ok(r.m3u.includes('#EXTINF:-1 tvg-logo="l" group-title="Sport",Chaîne 1'));
ok('les métadonnées #EXTINF restent intactes');

// Idempotence : re-réécrire avec la même façade ne change plus rien.
const r2 = rewriteM3uFacade(r.m3u, NEW, NEW);
assert.equal(r2.changed, 0);
assert.equal(r2.m3u, r.m3u);
ok('idempotent : une liste déjà sur la bonne façade ne bouge plus');

// Façade RETIRÉE (newBase vide) : impossible de deviner l'URL fournisseur →
// lignes laissées telles quelles mais COMPTÉES stale (le panel conseille
// « Recopier mes chaînes »).
r = rewriteM3uFacade(m3u, OLD, '');
assert.equal(r.changed, 0);
assert.equal(r.stale, 2); // ancienne façade + domaine d'exemple
assert.equal(r.m3u, m3u);
ok('façade retirée → rien de cassé, lignes périmées comptées (conseil honnête)');

// Sans ancienne façade (oldBase vide) : SEULES les lignes sur un domaine
// d'exemple sont réécrites (filet au moment du service pour les listes héritées).
r = rewriteM3uFacade(m3u, '', NEW);
assert.equal(r.changed, 1);
assert.ok(r.m3u.includes('https://nouvelle.gw.tld2/live/u/p/2.ts'));
assert.ok(r.m3u.includes('https://ancienne.gw.tld1/live/u/p/1.ts')); // pas à moi → intact
ok('filet au service : seuls les hôtes d’exemple hérités sont réécrits');

// M3U vide / null : jamais d'erreur.
assert.equal(rewriteM3uFacade('', OLD, NEW).changed, 0);
assert.equal(rewriteM3uFacade(null, OLD, NEW).m3u, '');
ok('entrées vides → jamais d’erreur');

// --- 3) _swapXtreamCreds : identité de diffusion dans le repli get.php ------
assert.equal(
  _swapXtreamCreds('http://prov:8080/live/jean/secret/55.ts', 'jean', 'secret', 'diff', 'partage'),
  'http://prov:8080/live/diff/partage/55.ts',
);
ok('chemin /live/u/p/… → identité de diffusion substituée');

assert.equal(
  _swapXtreamCreds('http://prov:8080/movie/jean/secret/9.mp4', 'jean', 'secret', 'diff', 'partage'),
  'http://prov:8080/movie/diff/partage/9.mp4',
);
ok('chemin /movie/… (VOD) substitué aussi');

// Variante « courte » sans préfixe /live (répandue chez les panels Xtream).
assert.equal(
  _swapXtreamCreds('http://prov:8080/jean/secret/55.ts', 'jean', 'secret', 'diff', 'partage'),
  'http://prov:8080/diff/partage/55.ts',
);
ok('variante courte /u/p/… substituée');

// Identifiants qui ne correspondent PAS → URL intacte (on ne casse jamais).
assert.equal(
  _swapXtreamCreds('http://prov:8080/live/autre/mdp/55.ts', 'jean', 'secret', 'diff', 'partage'),
  'http://prov:8080/live/autre/mdp/55.ts',
);
ok('identifiants inconnus → URL inchangée (robustesse)');

assert.equal(_swapXtreamCreds('pas-une-url', 'a', 'b', 'c', 'd'), 'pas-une-url');
ok('URL invalide → inchangée (jamais d’erreur)');

// --- 4) Messages d'erreur de copie ACTIONNABLES -----------------------------
assert.ok(/identifiants/i.test(_copyErrorMessage(new Error('provider_http_403'))));
assert.ok(/réessaie/i.test(_copyErrorMessage(new Error('provider_http_512'))));
assert.ok(/M3U/i.test(_copyErrorMessage(new Error('provider_bad_streams'))));
assert.ok(/délai/i.test(_copyErrorMessage(new Error('This operation was aborted'))));
ok('erreurs de copie traduites en messages actionnables (403 / 5xx / illisible / délai)');

console.log(`\n${n} assertions OK — verrou façade d’exemple + URLs qui suivent la façade validés.`);
