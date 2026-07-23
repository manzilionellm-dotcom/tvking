// =========================================================
//  selftest.test.mjs — endpoint /admin/selftest (auto-test lisible à distance)
// =========================================================
//  On vérifie trois choses ESSENTIELLES :
//   1) l'endpoint est protégé par le jeton admin (masqué en 404 sinon) ;
//   2) en https + domaine + identité de diffusion + ligne fournisseur, il
//      renvoie l'état « vert » (ok:true, level:0) — le contrat de vérifiabilité ;
//   3) GARDE-FOU : la réponse ne fuit AUCUN secret (mot de passe de diffusion
//      ou fournisseur). C'est le point non négociable du projet.
import test from 'node:test';
import assert from 'node:assert/strict';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const { request } = await import('undici');

// Secrets DISTINCTIFS : s'ils apparaissaient dans la réponse, l'assertion
// d'absence les repérerait à coup sûr.
const BROADCAST_PASS = 'zzz-secret-diffusion-9x7';
const UPSTREAM_PASS = 'zzz-secret-fournisseur-4k2';
const TOKEN = 'secret-admin-selftest';
const authH = { authorization: `Bearer ${TOKEN}` };

let base;
let gw;

test.before(async () => {
  const dir = mkdtempSync(join(tmpdir(), 'gwself-'));
  const usersFile = join(dir, 'users.json');
  writeFileSync(usersFile, JSON.stringify({ families: [] }));

  // État « vert » : façade https + domaine, identité de diffusion, ligne amont.
  process.env.PUBLIC_BASE = 'https://gw.7themotion.com';
  process.env.UPSTREAM_BASE = 'http://127.0.0.1:1';
  process.env.UPSTREAM_USER = 'ligne_user';
  process.env.UPSTREAM_PASS = UPSTREAM_PASS;
  process.env.PROVIDER_MAX_CONNECTIONS = '5';
  process.env.BROADCAST_USER = 'diffusion';
  process.env.BROADCAST_PASS = BROADCAST_PASS;
  process.env.BROADCAST_MAX_STREAMS = '100';
  process.env.USERS_FILE = usersFile;
  process.env.ADMIN_TOKEN = TOKEN;
  process.env.LOG_LEVEL = 'error';

  const { loadUsers } = await import('../src/users.js');
  const server = await import('../src/server.js');
  await loadUsers();
  gw = server.createServer();
  await new Promise((r) => gw.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${gw.address().port}`;
});

test.after(() => { try { gw && gw.close(); } catch { /* */ } });

test('sans jeton → 404 (endpoint masqué)', async () => {
  const r = await request(base + '/admin/selftest');
  assert.equal(r.statusCode, 404);
});

test('avec jeton → 200, état « vert » vérifiable', async () => {
  const r = await request(base + '/admin/selftest', { headers: authH });
  assert.equal(r.statusCode, 200);
  const body = await r.body.json();
  assert.equal(body.ok, true, 'doit être vert');
  assert.equal(body.level, 0);
  assert.equal(body.version, 'v500');
  // Façade sondable (https + domaine).
  assert.equal(body.facade.probe, true);
  assert.equal(body.facade.base, 'https://gw.7themotion.com');
  // Identité de diffusion présente (nom OK, jamais le mot de passe).
  assert.equal(body.broadcast.configured, true);
  assert.equal(body.broadcast.user, 'diffusion');
  assert.equal(body.broadcast.maxStreams, 100);
  // Ligne fournisseur présente, plafond exposé, identifiants JAMAIS.
  assert.equal(body.provider.configured, true);
  assert.equal(body.provider.maxConnections, 5);
  // Aucun avertissement en état vert.
  assert.deepEqual(body.warnings, []);
});

test('GARDE-FOU : la réponse ne fuit AUCUN secret', async () => {
  const r = await request(base + '/admin/selftest', { headers: authH });
  const raw = await r.body.text();
  assert.ok(!raw.includes(BROADCAST_PASS), 'le mot de passe de diffusion ne doit jamais apparaître');
  assert.ok(!raw.includes(UPSTREAM_PASS), 'le mot de passe fournisseur ne doit jamais apparaître');
  assert.ok(!raw.includes('ligne_user'), 'l’identifiant fournisseur ne doit jamais apparaître');
  // Le champ provider n'expose ni identifiants ni hôte fournisseur.
  const body = JSON.parse(raw);
  assert.equal(body.provider.user, undefined);
  assert.equal(body.provider.pass, undefined);
  assert.equal(body.provider.base, undefined);
  assert.equal(body.broadcast.pass, undefined);
  assert.equal(body.broadcast.password, undefined);
});
