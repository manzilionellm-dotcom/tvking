// Unit tests — parsing + réécriture (aucune E/S réseau).
// NB : en ESM les `import` sont hoistés AVANT le corps ; on pose donc l'env
// puis on charge le module en import() dynamique (sinon config lit un env vide).
process.env.UPSTREAM_BASE = 'http://prov.com:8080';
process.env.UPSTREAM_USER = 'upu';
process.env.UPSTREAM_PASS = 'upp';
process.env.PUBLIC_BASE = 'https://gw.com';

import test from 'node:test';
import assert from 'node:assert/strict';

const { parseStreamPath, streamKey, rewriteM3U } = await import('../src/xtream.js');

test('parseStreamPath — live long', () => {
  assert.deepEqual(parseStreamPath('/live/papa/pw/55.ts'), {
    kind: 'live', user: 'papa', pass: 'pw', streamId: '55', ext: 'ts',
  });
});

test('parseStreamPath — movie (VOD)', () => {
  const r = parseStreamPath('/movie/papa/pw/9.mp4');
  assert.equal(r.kind, 'movie');
  assert.equal(r.streamId, '9');
  assert.equal(r.ext, 'mp4');
});

test('parseStreamPath — live court sans /live/', () => {
  assert.deepEqual(parseStreamPath('/papa/pw/77'), {
    kind: 'live', user: 'papa', pass: 'pw', streamId: '77', ext: 'ts',
  });
});

test('parseStreamPath — non-flux', () => {
  assert.equal(parseStreamPath('/player_api.php'), null);
});

test('streamKey — indépendante de l’utilisateur (mutualisation)', () => {
  assert.equal(streamKey('live', '55', 'ts'), 'live:55.ts');
});

test('rewriteM3U — masque la ligne réelle', () => {
  const input =
    '#EXTM3U\n' +
    '#EXTINF:-1,Chaine 1\n' +
    'http://prov.com:8080/live/upu/upp/123.ts\n' +
    '#EXTINF:-1,VOD\n' +
    'http://prov.com:8080/get.php?username=upu&password=upp&type=m3u_plus\n';
  const out = rewriteM3U(input, 'papa', 'secret');
  assert.ok(!out.includes('prov.com'), 'la base fournisseur ne doit pas fuiter');
  assert.ok(out.includes('https://gw.com/live/papa/secret/123.ts'));
  assert.ok(!out.includes('upu'), 'l’identifiant de ligne ne doit pas fuiter');
  assert.ok(!out.includes('upp'), 'le mot de passe de ligne ne doit pas fuiter');
  assert.ok(out.includes('username=papa'));
  assert.ok(out.includes('password=secret'));
});
