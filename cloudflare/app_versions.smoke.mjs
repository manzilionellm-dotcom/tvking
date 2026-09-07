// =========================================================
//  app_versions.smoke.mjs — « ancienne version » / « dernière version »
// =========================================================
//  On fait tourner LE VRAI module (cloudflare/app_versions.js) avec un
//  `fetch` simulé qui rejoue la forme EXACTE d'un `version.json` publié
//  par le CI (cf. build-seventv.yml : versionCode, version, buildLabel).
//
//  Ce qui est verrouillé ici, et pourquoi :
//
//    1. ORDRE DES NUMÉROS. 198810 vient APRÈS 19889. En texte, '19889'
//       est plus grand que '198810' — l'inverse de la vérité. Le jour où
//       quelqu'un remplacerait la comparaison numérique par une
//       comparaison de chaînes, le panel dirait « ancienne version » sur
//       la box la plus à jour du parc. Ce test tombe.
//    2. SECOURS versionCode. Les apps installées avant le 07/09/2026 ne
//       connaissent pas le numéro maison. Elles doivent quand même
//       recevoir un verdict — sinon toutes les box du parc actuel
//       s'affichent « inconnu », et l'écran ne sert à rien tant que la
//       mise à jour n'est pas passée partout.
//    3. ON NE BLUFFE PAS. Rien à comparer → 'unknown', jamais 'latest'.
//       Dire « à jour » à tort, c'est envoyer le support chercher la
//       panne ailleurs.
//    4. CANAL. La TV se compare à `seventv-latest`, le mobile à `prod` —
//       les canaux que l'app elle-même interroge (update_service.dart).
//       Viser un autre canal ferait diverger le panel et le bouton de
//       mise à jour de l'app.
//    5. CACHE. Le panel se rafraîchit en boucle : deux lectures dans les
//       10 minutes = UN seul appel à GitHub. Sans ça, on se ferait
//       limiter, et le verdict deviendrait « inconnu » au pire moment.
//    6. PANNE. GitHub qui répond 500 ne doit pas faire tomber la fiche :
//       null, et le panel affiche « inconnu ».
//
//  Exécution : node cloudflare/app_versions.smoke.mjs
// =========================================================
import {
  VERSION_CHANNELS, STORE_ONLY_PLATFORMS, manifestUrl, compareLabels,
  versionVerdict, publishedVersion, publishedVersions, deviceVersionStatus,
  resetPublishedCache, PUBLISHED_TTL_MS,
} from './app_versions.js';

let pass = 0; let fail = 0;
const ok = (cond, label) => {
  if (cond) { pass++; console.log('  PASS ' + label); }
  else { fail++; console.log('  FAIL ' + label); }
};

// ---------------------------------------------------------
//  1. Canaux — les mêmes que ceux que l'app interroge.
// ---------------------------------------------------------
console.log('\n1. Canaux');
ok(VERSION_CHANNELS.tv === 'seventv-latest', 'TV → seventv-latest');
ok(VERSION_CHANNELS.mobile === 'prod', 'Mobile → prod');
ok(
  manifestUrl('tv') ===
    'https://github.com/manzilionellm-dotcom/tvking/releases/download/seventv-latest/version.json',
  'URL du manifeste TV',
);
ok(manifestUrl('windows') === null, 'Plateforme inconnue → pas d’URL');
ok(manifestUrl('') === null, 'Plateforme vide → pas d’URL');

// ---------------------------------------------------------
//  2. L'ordre des numéros (le piège du passage à 2 chiffres).
// ---------------------------------------------------------
console.log('\n2. Ordre des numéros');
ok(compareLabels('19881', '19882') === -1, '19881 est plus ancien que 19882');
ok(compareLabels('19882', '19882') === 0, '19882 = 19882');
ok(compareLabels('19883', '19882') === 1, '19883 est plus récent que 19882');
ok(compareLabels('19889', '198810') === -1, '19889 vient AVANT 198810 (pas du texte)');
ok(compareLabels('198810', '19889') === 1, '198810 vient APRÈS 19889');
ok(compareLabels('', '19882') === null, 'Numéro absent → indécidable');
ok(compareLabels('abc', '19882') === null, 'Numéro illisible → indécidable');

// ---------------------------------------------------------
//  3. Le verdict.
// ---------------------------------------------------------
console.log('\n3. Verdict');
const publie = { buildLabel: '19882', versionCode: 1788127315, version: '0.3.3' };

let v = versionVerdict({ buildLabel: '19882', appBuild: 1788127315 }, publie);
ok(v.state === 'latest' && v.basis === 'buildLabel', 'Même numéro → dernière version');
ok(v.installed === '19882' && v.latest === '19882', 'Les deux numéros sont rendus');

v = versionVerdict({ buildLabel: '19881', appBuild: 1788122176 }, publie);
ok(v.state === 'outdated', 'Numéro plus petit → ancienne version');

v = versionVerdict({ buildLabel: '19883', appBuild: 1788999999 }, publie);
ok(v.state === 'ahead', 'Numéro plus grand → build de test (labo)');

// Secours : app d'avant le numéro maison (le parc au 07/09/2026).
v = versionVerdict({ buildLabel: '', appBuild: 1788122176 }, publie);
ok(v.state === 'outdated' && v.basis === 'versionCode',
   'Sans numéro maison, on compare les versionCode → ancienne version');
ok(v.installed === '1788122176', 'On affiche le versionCode, pas un numéro inventé');
ok(v.latest === '19882', 'La référence reste le numéro publié lisible');

v = versionVerdict({ buildLabel: '', appBuild: 1788127315 }, publie);
ok(v.state === 'latest' && v.basis === 'versionCode',
   'Sans numéro maison mais même versionCode → à jour');

// On ne bluffe pas.
v = versionVerdict({ buildLabel: '', appBuild: 0 }, publie);
ok(v.state === 'unknown' && v.basis === 'none', 'Rien de comparable → inconnu');
v = versionVerdict({ buildLabel: '19882', appBuild: 1788127315 }, null);
ok(v.state === 'unknown', 'Manifeste absent → inconnu, jamais « à jour »');
v = versionVerdict(null, null);
ok(v.state === 'unknown', 'Aucune donnée → inconnu (et pas d’exception)');

// Le versionCode ne sert PAS de secours quand le publié n'en a pas.
v = versionVerdict({ buildLabel: '', appBuild: 1788127315 }, { buildLabel: '', versionCode: 0 });
ok(v.state === 'unknown', 'Manifeste sans numéro exploitable → inconnu');

// ---------------------------------------------------------
//  4. Lecture du manifeste + cache.
// ---------------------------------------------------------
console.log('\n4. Lecture du manifeste');
// FORME RÉELLE du manifeste, relevée le 07/09 sur la release
// seventv-latest en ligne : le champ s'appelle « versionName », PAS
// « version ». Le CI l'écrit ainsi (build-seventv.yml, build-android.yml).
// Ce test existe parce que la première version de ce module lisait
// `version` : le panel n'aurait jamais affiché « v0.3.3 », sans erreur
// nulle part.
const manifeste = {
  versionCode: 1788127315,
  versionName: '0.3.3',
  buildLabel: '19882',
  url: 'https://github.com/…/seven-tv.apk',
  mandatory: false,
};
let appels = [];
let mode = 'ok';
globalThis.fetch = async (url) => {
  appels.push(String(url));
  if (mode === 'boom') return new Response('nope', { status: 500 });
  if (mode === 'html') {
    return new Response('<html>rate limited</html>', {
      status: 200, headers: { 'content-type': 'text/html' },
    });
  }
  return new Response(JSON.stringify(manifeste), {
    status: 200, headers: { 'content-type': 'application/json' },
  });
};

resetPublishedCache();
let p = await publishedVersion('tv');
ok(p !== null && p.buildLabel === '19882', 'Le numéro publié est lu');
ok(p.versionCode === 1788127315 && p.version === '0.3.3', 'versionCode et version lus');
ok(p.channel === 'seventv-latest', 'Le canal est rappelé dans la réponse');
ok(appels.length === 1 && appels[0].includes('seventv-latest/version.json'),
   'Un seul appel, sur le bon canal');
ok(appels[0].startsWith('https://github.com/'), 'On lit GitHub, pas notre propre domaine');

// 2e lecture dans la fenêtre → AUCUN nouvel appel.
appels = [];
p = await publishedVersion('tv');
ok(appels.length === 0 && p.buildLabel === '19882', 'Deuxième lecture servie par le cache');

// Passé le délai, on relit.
appels = [];
p = await publishedVersion('tv', { now: Date.now() + PUBLISHED_TTL_MS + 1000 });
ok(appels.length === 1, 'Cache expiré → une nouvelle lecture');

// Plateforme inconnue : aucun appel réseau du tout.
appels = [];
ok((await publishedVersion('windows')) === null, 'Plateforme inconnue → null');
ok(appels.length === 0, 'Plateforme inconnue → aucun appel réseau');

// ---------------------------------------------------------
//  5. Pannes d'amont — la fiche ne doit jamais tomber.
// ---------------------------------------------------------
console.log('\n5. Pannes');
resetPublishedCache();
mode = 'boom';
ok((await publishedVersion('tv')) === null, 'GitHub en 500 → null (pas d’exception)');
resetPublishedCache();
mode = 'html';
ok((await publishedVersion('tv')) === null, 'Page HTML au lieu du JSON → null');
resetPublishedCache();
appels = [];
globalThis.fetch = async () => { appels.push('x'); throw new Error('réseau coupé'); };
ok((await publishedVersion('tv')) === null, 'Réseau coupé → null');
ok(appels.length === 1, 'L’échec est tenté une fois');
// Échec mis en cache 60 s : on ne martèle pas l'amont pendant une panne.
appels = [];
ok((await publishedVersion('tv')) === null, 'Toujours null');
ok(appels.length === 0, 'L’échec est mis en cache : pas de martèlement');

// ---------------------------------------------------------
//  6. Le raccourci « fiche MAC » (ce que le panel appelle).
// ---------------------------------------------------------
console.log('\n6. Fiche MAC');
resetPublishedCache();
mode = 'ok';
globalThis.fetch = async (url) => {
  appels.push(String(url));
  const body = String(url).includes('/prod/')
    ? { versionCode: 1788100000, version: '0.3.2', buildLabel: '19881' }
    : manifeste;
  return new Response(JSON.stringify(body), {
    status: 200, headers: { 'content-type': 'application/json' },
  });
};

let s = await deviceVersionStatus({ platform: 'tv', build_label: '19882', app_build: 1788127315 });
ok(s.state === 'latest' && s.latest === '19882', 'Box TV à jour');
ok(s.channel === 'seventv-latest' && s.latestVersion === '0.3.3', 'Canal + version publiés rendus');

s = await deviceVersionStatus({ platform: 'tv', build_label: '19881', app_build: 1788122176 });
ok(s.state === 'outdated', 'Box TV en retard');

s = await deviceVersionStatus({ platform: 'mobile', build_label: '19881', app_build: 1788100000 });
ok(s.state === 'latest' && s.channel === 'prod',
   'Le mobile se compare à SON canal (prod), pas à celui de la TV');

s = await deviceVersionStatus({ platform: '', build_label: '', app_build: 0 });
ok(s.state === 'unknown' && s.platform === null, 'Plateforme non remontée → inconnu');

const deux = await publishedVersions();
ok(deux.tv.buildLabel === '19882' && deux.mobile.buildLabel === '19881',
   'Les deux plateformes d’un coup, chacune sur son canal');

// ---------------------------------------------------------
//  7. Le téléphone n'a PLUS de manifeste (décision du 22/08).
// ---------------------------------------------------------
//  Vérifié le 07/09 : les releases `prod` et `latest` n'existent plus,
//  l'app téléphone est distribuée par le Play Store. Le panel doit dire
//  CETTE raison-là, pas un « inconnu » qui ressemble à une panne.
console.log('\n7. Téléphone sans manifeste (Play Store)');
ok(STORE_ONLY_PLATFORMS.mobile === 'Play Store', 'Le mobile est marqué « magasin »');
resetPublishedCache();
globalThis.fetch = async () => new Response('Not Found', { status: 404 });

s = await deviceVersionStatus({ platform: 'mobile', build_label: '', app_build: 1788127315 });
ok(s.state === 'unknown', '404 sur le canal téléphone → inconnu (jamais « à jour »)');
ok(s.store === 'Play Store', 'Le panel apprend POURQUOI : distribution magasin');

resetPublishedCache();
s = await deviceVersionStatus({ platform: 'tv', build_label: '19882', app_build: 1788127315 });
ok(s.state === 'unknown' && s.store === '',
   'La TV, elle, n’est pas « magasin » : un manifeste injoignable reste une panne');

console.log(`\n${pass} PASS, ${fail} FAIL`);
process.exit(fail === 0 ? 0 : 1);
