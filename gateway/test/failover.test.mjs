// Test de FAILOVER de ligne fournisseur (cause H2 serveur — SPOF).
// Ligne PRINCIPALE en panne (502 / réseau) → la passerelle bascule
// automatiquement sur la ligne de SECOURS, sans couper le spectateur.
// Live (mutualisé) ET VOD (direct) couverts.

import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const { request } = await import('undici');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Ligne PRINCIPALE : toujours en panne (502) — simule une ligne morte.
const primary = http.createServer((req, res) => {
  res.writeHead(502);
  res.end('line down');
});

// Ligne de SECOURS : sert live (flux TS) + VOD (corps).
const fallback = http.createServer((req, res) => {
  if (/\/movie\//.test(req.url)) {
    res.writeHead(200, { 'content-type': 'video/mp4', 'content-length': '4' });
    res.end('MP4!');
    return;
  }
  const m = /\/live\/[^/]+\/[^/]+\/(\d+)\.ts/.exec(req.url);
  if (!m) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': 'video/mp2t' });
  const iv = setInterval(() => { try { res.write(Buffer.alloc(1316, 7)); } catch { /* */ } }, 20);
  req.on('close', () => clearInterval(iv));
});

let base;
let hub;
let gw;

async function listen(server) {
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  return server.address().port;
}

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
  return { status: res.statusCode, firstChunk, close: () => { try { res.body.destroy(); } catch { /* */ } } };
}

test.before(async () => {
  const pPort = await listen(primary);
  const fPort = await listen(fallback);
  const dir = mkdtempSync(join(tmpdir(), 'gw-fo-'));
  const usersFile = join(dir, 'users.json');
  writeFileSync(usersFile, JSON.stringify({
    families: [{ id: 'f1', maxStreams: 10, users: [{ username: 'papa', password: 'pw', maxStreams: 10 }] }],
  }));

  process.env.UPSTREAM_BASE = `http://127.0.0.1:${pPort}`;          // morte
  process.env.UPSTREAM_BASE_FALLBACKS = `http://127.0.0.1:${fPort}`; // vivante
  process.env.UPSTREAM_USER = 'lineuser';
  process.env.UPSTREAM_PASS = 'linepass';
  process.env.PROVIDER_MAX_CONNECTIONS = '3';
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
  try { primary.close(); } catch { /* */ }
  try { fallback.close(); } catch { /* */ }
});

test('FAILOVER live : principale 502 → bascule sur la secours, flux servi', async () => {
  const c = await openClient('/live/papa/pw/1.ts');
  assert.equal(c.status, 200, 'le client reçoit un flux malgré la ligne principale morte');
  assert.ok(c.firstChunk && c.firstChunk.length > 0, 'octets réellement reçus (via la secours)');
  c.close();
  for (let i = 0; i < 40 && hub.totalUpstream() > 0; i++) await sleep(50);
});

test('FAILOVER VOD : principale 502 → la secours sert le fichier', async () => {
  const res = await request(base + '/movie/papa/pw/99.mp4');
  const body = await res.body.text();
  assert.equal(res.statusCode, 200);
  assert.equal(body, 'MP4!', 'contenu servi par la ligne de secours');
});
