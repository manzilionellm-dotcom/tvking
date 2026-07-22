// Unit tests — IDENTITÉ DE DIFFUSION (liste de test mutualisée).
// Prouve que l'utilisateur partagé (BROADCAST_USER/PASS) :
//   • est authentifié par le gateway (les URLs de test le portent → jouables) ;
//   • n'est JAMAIS persisté dans users.json ni exposé comme famille éditable ;
//   • borne les TESTEURS simultanés via son maxStreams (≠ connexions amont).
// NB : on pose l'env AVANT d'importer le module (config lit process.env au
// chargement), puis import() dynamique.
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const dir = await mkdtemp(join(tmpdir(), 'gw-bcast-'));
const usersFile = join(dir, 'users.json');
// Un users.json minimal (une famille normale) pour prouver la COEXISTENCE.
await writeFile(usersFile, JSON.stringify({
  families: [{ id: 'famille-a', maxStreams: 3, users: [
    { username: 'papa', password: 'pw', maxStreams: 2 },
  ] }],
}), 'utf8');

process.env.UPSTREAM_BASE = 'http://prov.com:8080';
process.env.UPSTREAM_USER = 'upu';
process.env.UPSTREAM_PASS = 'upp';
process.env.PROVIDER_MAX_CONNECTIONS = '5';
process.env.USERS_FILE = usersFile;
process.env.BROADCAST_USER = 'diffusion';
process.env.BROADCAST_PASS = 'diff-secret-123';
process.env.BROADCAST_MAX_STREAMS = '42';

import test from 'node:test';
import assert from 'node:assert/strict';

const { loadUsers, authenticate, listUsers, listFamilies, getFamily, addUser } =
  await import('../src/users.js');

await loadUsers(usersFile);

test('identité de diffusion — authentifiée par le gateway', () => {
  const u = authenticate('diffusion', 'diff-secret-123');
  assert.ok(u, 'l’identité de diffusion doit s’authentifier');
  assert.equal(u.familyId, '__broadcast__');
  assert.equal(u.maxStreams, 42, 'maxStreams = BROADCAST_MAX_STREAMS (borne les testeurs)');
  assert.equal(u.broadcast, true);
});

test('identité de diffusion — mauvais mot de passe refusé', () => {
  assert.equal(authenticate('diffusion', 'mauvais'), null);
});

test('utilisateur normal — inchangé (coexistence)', () => {
  const p = authenticate('papa', 'pw');
  assert.ok(p);
  assert.equal(p.familyId, 'famille-a');
  assert.equal(p.maxStreams, 2);
});

test('famille de diffusion — dimensionnée pour les testeurs', () => {
  const fam = getFamily('__broadcast__');
  assert.ok(fam);
  assert.equal(fam.maxStreams, 42);
});

test('identité de diffusion — JAMAIS exposée comme famille éditable (CRUD)', () => {
  const fams = listFamilies();
  assert.ok(!fams.some((f) => f.id === '__broadcast__'),
    'la famille de diffusion ne doit pas apparaître dans le CRUD panel');
  assert.ok(fams.some((f) => f.id === 'famille-a'), 'les familles réelles restent listées');
});

test('identité de diffusion — JAMAIS persistée sur disque', async () => {
  // Une écriture (ajout d’un vrai user) persiste le modèle : le secret de
  // diffusion NE DOIT PAS s’y retrouver (il est env-only).
  await addUser('famille-a', { username: 'maman', password: 'mp', maxStreams: 1 });
  const onDisk = JSON.parse(await readFile(usersFile, 'utf8'));
  const raw = JSON.stringify(onDisk);
  assert.ok(!raw.includes('diffusion'), 'l’utilisateur de diffusion ne doit pas être écrit');
  assert.ok(!raw.includes('diff-secret-123'), 'le secret de diffusion ne doit pas toucher le disque');
  assert.ok(!raw.includes('__broadcast__'), 'la famille virtuelle ne doit pas être persistée');
  // …mais l’identité de diffusion reste active après un rechargement.
  await loadUsers(usersFile);
  assert.ok(authenticate('diffusion', 'diff-secret-123'), 'toujours active après reload');
});

test('observabilité — l’identité de diffusion est visible côté admin (statut)', () => {
  // listUsers alimente /admin/status : l’identité active y est visible (sans
  // mot de passe), utile pour le diagnostic. C’est admin-only.
  const us = listUsers();
  const b = us.find((u) => u.username === 'diffusion');
  assert.ok(b, 'l’identité de diffusion doit être visible dans le statut admin');
  assert.equal(b.familyId, '__broadcast__');
  assert.ok(!('password' in b), 'listUsers ne renvoie jamais le mot de passe');
});

test.after(async () => { await rm(dir, { recursive: true, force: true }); });
