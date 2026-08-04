// Smoke test — LIEN DE PARTAGE /play
//
// L'URL du Play Store contient l'identifiant de l'application, qui porte
// le nom du propriétaire, et que Google ne permet JAMAIS de changer.
// `/play` existe pour qu'on n'ait plus à donner cette adresse-là : c'est
// le lien qu'on met sur les cartes de visite et dans les messages.
//
// Ce que ces tests protègent : la redirection existe, elle pointe au bon
// endroit, elle reste TEMPORAIRE (302) — un 301 serait mis en cache
// pendant des mois par les navigateurs, et on ne pourrait plus changer
// de destination sans casser les liens déjà partagés.
//
// Lancer : node cloudflare/play_link.smoke.mjs
import assert from 'node:assert/strict';
import worker from './worker.js';

let n = 0;
const ok = (m) => { n++; console.log('  ✓', m); };

const call = (path, method = 'GET') =>
  worker.fetch(new Request(`https://app.7themotion.com${path}`, { method }), {}, {
    waitUntil() {},
  });

const r = await call('/play');
assert.equal(r.status, 302);
ok('/play redirige (302, temporaire — un 301 se cacherait pour des mois)');

const dest = r.headers.get('location');
assert.equal(
  dest,
  'https://play.google.com/store/apps/details?id=com.manzilionellm.tvking',
);
ok('la destination est bien la fiche Play de l’application');

const head = await call('/play', 'HEAD');
assert.equal(head.status, 302);
ok('HEAD redirige aussi (les messageries pré-chargent les liens en HEAD)');

const post = await call('/play', 'POST');
assert.notEqual(post.status, 302);
ok('POST ne redirige pas — /play est une porte de sortie, pas une API');

console.log(`\n${n} assertions OK — lien de partage /play`);
