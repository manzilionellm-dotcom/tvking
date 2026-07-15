// Tests admin : CRUD familles/clones + protection par jeton + CORS.
import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { writeFileSync, mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const { request } = await import('undici');
let base;
let gw;
let usersFile;

async function listen(server) {
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  return server.address().port;
}
const TOKEN = 'secret-admin';
const authH = { authorization: `Bearer ${TOKEN}` };

test.before(async () => {
  const dir = mkdtempSync(join(tmpdir(), 'gwadm-'));
  usersFile = join(dir, 'users.json');
  writeFileSync(usersFile, JSON.stringify({ families: [] }));

  process.env.UPSTREAM_BASE = 'http://127.0.0.1:1';
  process.env.UPSTREAM_USER = 'u';
  process.env.UPSTREAM_PASS = 'p';
  process.env.PROVIDER_MAX_CONNECTIONS = '5';
  process.env.USERS_FILE = usersFile;
  process.env.ADMIN_TOKEN = TOKEN;
  process.env.LOG_LEVEL = 'error';

  const { loadUsers } = await import('../src/users.js');
  const server = await import('../src/server.js');
  await loadUsers();
  gw = server.createServer();
  const port = await listen(gw);
  base = `http://127.0.0.1:${port}`;
});

test.after(() => { try { gw && gw.close(); } catch { /* */ } });

test('sans jeton → 404 (endpoint masqué)', async () => {
  const r = await request(base + '/admin/families');
  assert.equal(r.statusCode, 404);
});

test('CORS preflight OPTIONS → 204 + entêtes', async () => {
  const r = await request(base + '/admin/families', { method: 'OPTIONS' });
  assert.equal(r.statusCode, 204);
  assert.equal(r.headers['access-control-allow-origin'], '*');
});

test('CRUD complet : créer famille, ajouter clone, persister, supprimer', async () => {
  // Créer la famille
  let r = await request(base + '/admin/families', {
    method: 'POST', headers: { ...authH, 'content-type': 'application/json' },
    body: JSON.stringify({ id: 'famille-karim', maxStreams: 5 }),
  });
  assert.equal(r.statusCode, 201);

  // Doublon → 409
  r = await request(base + '/admin/families', {
    method: 'POST', headers: { ...authH, 'content-type': 'application/json' },
    body: JSON.stringify({ id: 'famille-karim' }),
  });
  assert.equal(r.statusCode, 409);

  // Ajouter papa
  r = await request(base + '/admin/families/famille-karim/users', {
    method: 'POST', headers: { ...authH, 'content-type': 'application/json' },
    body: JSON.stringify({ username: 'papa', password: 'pw', maxStreams: 2 }),
  });
  assert.equal(r.statusCode, 201);

  // Username déjà pris → 409
  r = await request(base + '/admin/families/famille-karim/users', {
    method: 'POST', headers: { ...authH, 'content-type': 'application/json' },
    body: JSON.stringify({ username: 'papa', password: 'x' }),
  });
  assert.equal(r.statusCode, 409);

  // Lister
  r = await request(base + '/admin/families', { headers: authH });
  const body = await r.body.json();
  assert.equal(body.families.length, 1);
  assert.equal(body.families[0].users[0].username, 'papa');

  // Persistance sur disque
  const onDisk = JSON.parse(readFileSync(usersFile, 'utf8'));
  assert.equal(onDisk.families[0].users[0].username, 'papa');

  // Supprimer le clone
  r = await request(base + '/admin/families/famille-karim/users/papa', {
    method: 'DELETE', headers: authH,
  });
  assert.equal(r.statusCode, 200);

  // Supprimer la famille
  r = await request(base + '/admin/families/famille-karim', {
    method: 'DELETE', headers: authH,
  });
  assert.equal(r.statusCode, 200);

  r = await request(base + '/admin/families', { headers: authH });
  const after = await r.body.json();
  assert.equal(after.families.length, 0);
});
