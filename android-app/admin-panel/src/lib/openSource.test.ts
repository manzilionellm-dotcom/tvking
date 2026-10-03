// =========================================================
//  Le panel ne propose plus « Serveur 1 ». On vérifie la saisie
//  libre et le retrait du menu. Hôtes bidons, pas de vrai secret.
//  Lancer : node --experimental-strip-types --test src/lib/openSource.test.ts
// =========================================================

import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  ERR_NEED_PLAYER,
  ERR_NEED_URL,
  ERR_NEED_XTREAM,
  SERVER_CATALOG_PATH,
  buildPushedSource,
  hideServerCatalog,
} from './openSource.ts';

test('le menu ne garde pas la page Serveurs', () => {
  const visible = hideServerCatalog([
    { to: '/activate' },
    { to: SERVER_CATALOG_PATH },
    { to: '/customers' },
  ]);
  assert.deepEqual(visible.map((item) => item.to), ['/activate', '/customers']);
});

test('Xtream et M3U : n\'importe quel hôte, plusieurs blocs', () => {
  const a = buildPushedSource({
    type: 'xtream',
    serverUrl: 'fournisseur.invalid:8080',
    username: 'demo',
    password: 'jeton',
    link: '',
  });
  assert.ok('source' in a);
  if ('source' in a && a.source.type === 'xtream') {
    assert.equal(a.source.server_url, 'http://fournisseur.invalid:8080');
    assert.equal(a.source.username, 'demo');
  }

  const b = buildPushedSource({
    type: 'm3u',
    serverUrl: '',
    username: '',
    password: '',
    link: 'https://autre.invalid/liste.m3u8',
  });
  assert.ok('source' in b && b.source.type === 'm3u');
  if ('source' in b && b.source.type === 'm3u') {
    assert.equal(b.source.m3u_url, 'https://autre.invalid/liste.m3u8');
  }
});

test('lien lecteur get.php et erreurs en français', () => {
  const ok = buildPushedSource({
    type: 'player',
    serverUrl: '',
    username: '',
    password: '',
    link: 'http://lecteur.invalid/get.php?username=demo&password=jeton',
  });
  assert.ok('source' in ok && ok.source.type === 'xtream');
  if ('source' in ok && ok.source.type === 'xtream') {
    assert.equal(ok.source.server_url, 'http://lecteur.invalid');
    assert.equal(ok.source.password, 'jeton');
  }

  const missing = buildPushedSource({
    type: 'player',
    serverUrl: '',
    username: '',
    password: '',
    link: 'http://lecteur.invalid/get.php',
  });
  assert.ok('error' in missing);
  if ('error' in missing) assert.equal(missing.error, ERR_NEED_PLAYER);

  const empty = buildPushedSource({
    type: 'xtream',
    serverUrl: '',
    username: 'demo',
    password: '',
    link: '',
  });
  assert.ok('error' in empty && empty.error === ERR_NEED_XTREAM);

  const bad = buildPushedSource({
    type: 'm3u',
    serverUrl: '',
    username: '',
    password: '',
    link: 'ftp://fichiers.invalid/a.m3u',
  });
  assert.ok('error' in bad && bad.error === ERR_NEED_URL);
});

test('un M3U avec identifiants dans l\'adresse est gardé tel quel', () => {
  const kept = buildPushedSource({
    type: 'm3u',
    serverUrl: '',
    username: '',
    password: '',
    link: 'http://demo:jeton@boite.invalid/liste.m3u',
  });
  assert.ok('source' in kept && kept.source.type === 'm3u');
  if ('source' in kept && kept.source.type === 'm3u') {
    assert.ok(kept.source.m3u_url.includes('demo:jeton@'));
  }
});
