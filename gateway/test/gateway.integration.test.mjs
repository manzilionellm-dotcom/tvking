// Integration test — prouve les DEUX affirmations centrales :
//   1) MUTUALISATION : N spectateurs de la MÊME chaîne = 1 seule connexion
//      vers le fournisseur.
//   2) LIMITE FOURNISSEUR : jamais plus de PROVIDER_MAX_CONNECTIONS
//      connexions distinctes (la 3e chaîne différente est refusée en 503).
//
// On monte un FAUX fournisseur local qui compte ses connexions concurrentes,
// puis la vraie passerelle par-dessus, et on ouvre de vrais clients HTTP.

import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// ---- Faux fournisseur : compte les connexions live concurrentes ----------
let curGlobal = 0;
let maxGlobal = 0;
const perChannelCur = {};
const perChannelMax = {};

const upstream = http.createServer((req, res) => {
  const m = /\/live\/[^/]+\/[^/]+\/(\d+)\.ts/.exec(req.url);
  if (!m) { res.writeHead(404); res.end(); return; }
  const id = m[1];
  curGlobal += 1; maxGlobal = Math.max(maxGlobal, curGlobal);
  perChannelCur[id] = (perChannelCur[id] || 0) + 1;
  perChannelMax[id] = Math.max(perChannelMax[id] || 0, perChannelCur[id]);
  res.writeHead(200, { 'content-type': 'video/mp2t' });
  const iv = setInterval(() => { try { res.write(Buffer.alloc(1316, 1)); } catch { /* */ } }, 20);
  const done = () => {
    clearInterval(iv);
    curGlobal -= 1;
    perChannelCur[id] = Math.max(0, (perChannelCur[id] || 1) - 1);
  };
  req.on('close', done);
});

let base;                 // URL de la passerelle
let hub;                  // instance hub (pour drainer entre les tests)
let gw;                   // serveur passerelle (fermé en teardown)
const { request } = await import('undici');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function listen(server) {
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  return server.address().port;
}

// Ouvre un client sur la passerelle, attend les en-têtes, lit 1 chunk.
async function openClient(path) {
  const res = await request(base + path);
  let firstChunk = null;
  if (res.statusCode === 200) {
    firstChunk = await new Promise((resolve) => {
      res.body.once('data', (d) => resolve(d));
      res.body.once('error', () => resolve(null));
      res.body.once('end', () => resolve(null));
    });
  } else {
    await res.body.text().catch(() => {});
  }
  return {
    status: res.statusCode,
    firstChunk,
    close: () => { try { res.body.destroy(); } catch { /* */ } },
  };
}

async function drainUpstream() {
  for (let i = 0; i < 60 && hub.totalUpstream() > 0; i++) await sleep(50);
}

test.before(async () => {
  const upPort = await listen(upstream);

  // Env AVANT import des modules de la passerelle (config lue au chargement).
  const dir = mkdtempSync(join(tmpdir(), 'gw-'));
  const usersFile = join(dir, 'users.json');
  writeFileSync(usersFile, JSON.stringify({
    families: [{
      id: 'f1', maxStreams: 10,
      users: [{ username: 'papa', password: 'pw', maxStreams: 10 }],
    }],
  }));

  process.env.UPSTREAM_BASE = `http://127.0.0.1:${upPort}`;
  process.env.UPSTREAM_USER = 'lineuser';
  process.env.UPSTREAM_PASS = 'linepass';
  process.env.PROVIDER_MAX_CONNECTIONS = '2';
  process.env.STREAM_IDLE_GRACE_MS = '120';
  process.env.USERS_FILE = usersFile;
  process.env.LOG_LEVEL = 'error';

  const { loadUsers } = await import('../src/users.js');
  const server = await import('../src/server.js');
  ({ hub } = await import('../src/hub.js'));
  await loadUsers();

  gw = server.createServer();
  const port = await listen(gw);
  base = `http://127.0.0.1:${port}`;
});

test.after(() => {
  try { gw && gw.close(); } catch { /* */ }
  try { upstream.close(); } catch { /* */ }
});

test('MUTUALISATION : 3 spectateurs, 1 chaîne = 1 connexion fournisseur', async () => {
  const a = await openClient('/live/papa/pw/1.ts');
  const b = await openClient('/live/papa/pw/1.ts');
  const c = await openClient('/live/papa/pw/1.ts');

  assert.equal(a.status, 200);
  assert.equal(b.status, 200);
  assert.equal(c.status, 200);
  assert.ok(a.firstChunk && a.firstChunk.length > 0, 'le client reçoit des octets');

  // Le fournisseur n'a JAMAIS vu plus d'UNE connexion pour cette chaîne.
  assert.equal(perChannelMax['1'], 1, 'une seule connexion upstream pour 3 clients');
  // Et une seule connexion fournisseur au total à cet instant.
  assert.equal(hub.totalUpstream(), 1);

  a.close(); b.close(); c.close();
  await drainUpstream();
  assert.equal(hub.totalUpstream(), 0, 'connexion libérée quand plus personne ne regarde');
});

test('LIMITE FOURNISSEUR : la 3e chaîne différente est refusée (503)', async () => {
  await drainUpstream();
  const ch1 = await openClient('/live/papa/pw/10.ts'); // upstream #1
  const ch2 = await openClient('/live/papa/pw/11.ts'); // upstream #2
  assert.equal(ch1.status, 200);
  assert.equal(ch2.status, 200);
  assert.equal(hub.totalUpstream(), 2);

  const ch3 = await openClient('/live/papa/pw/12.ts'); // dépasse la ligne
  assert.equal(ch3.status, 503, 'la ligne (max 2) protège : 3e chaîne refusée');

  // Mais un 4e client sur une chaîne DÉJÀ ouverte passe (mutualisé, 0 conn.).
  const again = await openClient('/live/papa/pw/10.ts');
  assert.equal(again.status, 200, 'rejoindre une chaîne ouverte reste possible');
  assert.equal(hub.totalUpstream(), 2, 'toujours 2 connexions fournisseur');

  ch1.close(); ch2.close(); again.close();
  await drainUpstream();
});
