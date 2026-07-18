// Tests de STABILITÉ de transmission (correctifs C1 / H4 / H1) :
//   1) Zapping : une session laissée « au chaud » (idle-grace) ne bloque plus
//      l'ouverture d'une nouvelle chaîne — elle est récupérée au lieu de 503.
//   2) M3U streamé : la playlist est réécrite ligne par ligne, résultat
//      STRICTEMENT identique à la réécriture du texte entier (équivalence).
//   3) Timeouts serveur : phase requête bornée, inactivité socket illimitée.
//
// Faux fournisseur local (live + get.php) + vraie passerelle par-dessus.

import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const { request } = await import('undici');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let upPort;
const upstream = http.createServer((req, res) => {
  if (req.url.startsWith('/get.php')) {
    // Playlist multi-lignes référençant la base + identifiants FOURNISSEUR.
    const b = `http://127.0.0.1:${upPort}`;
    const m3u = [
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="1",Chaîne 1',
      `${b}/live/lineuser/linepass/1.ts`,
      '#EXTINF:-1 tvg-id="2",Chaîne 2',
      `${b}/live/lineuser/linepass/2.ts`,
      `${b}/get.php?username=lineuser&password=linepass&type=m3u`,
      '',
    ].join('\n');
    res.writeHead(200, { 'content-type': 'application/x-mpegurl' });
    res.end(m3u);
    return;
  }
  const m = /\/live\/[^/]+\/[^/]+\/(\d+)\.ts/.exec(req.url);
  if (!m) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': 'video/mp2t' });
  const iv = setInterval(() => { try { res.write(Buffer.alloc(1316, 1)); } catch { /* */ } }, 20);
  req.on('close', () => clearInterval(iv));
});

let base;
let hub;
let gw;
let createServer;
let makeM3URewriter;

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

async function drainUpstream() {
  for (let i = 0; i < 60 && hub.totalUpstream() > 0; i++) await sleep(50);
}

test.before(async () => {
  upPort = await listen(upstream);
  const dir = mkdtempSync(join(tmpdir(), 'gw-stab-'));
  const usersFile = join(dir, 'users.json');
  writeFileSync(usersFile, JSON.stringify({
    families: [{ id: 'f1', maxStreams: 10, users: [{ username: 'papa', password: 'pw', maxStreams: 10 }] }],
  }));

  process.env.UPSTREAM_BASE = `http://127.0.0.1:${upPort}`;
  process.env.UPSTREAM_USER = 'lineuser';
  process.env.UPSTREAM_PASS = 'linepass';
  process.env.PROVIDER_MAX_CONNECTIONS = '2';
  // Grace LONGUE : la session quittée reste « au chaud » pendant le test →
  // c'est bien la RÉCUPÉRATION (pas l'expiration) qui libère le slot.
  process.env.STREAM_IDLE_GRACE_MS = '5000';
  process.env.PUBLIC_BASE = 'https://gw.example.com';
  process.env.HEADERS_TIMEOUT_MS = '60000';
  process.env.REQUEST_TIMEOUT_MS = '60000';
  process.env.USERS_FILE = usersFile;
  process.env.LOG_LEVEL = 'error';

  const { loadUsers } = await import('../src/users.js');
  const server = await import('../src/server.js');
  ({ hub } = await import('../src/hub.js'));
  ({ makeM3URewriter } = await import('../src/xtream.js'));
  createServer = server.createServer;
  await loadUsers();
  gw = createServer();
  const port = await listen(gw);
  base = `http://127.0.0.1:${port}`;
});

test.after(() => {
  try { gw && gw.close(); } catch { /* */ }
  try { upstream.close(); } catch { /* */ }
});

test('ZAPPING : une session en idle-grace est récupérée, pas de 503', async () => {
  await drainUpstream();
  const ch1 = await openClient('/live/papa/pw/1.ts');
  const ch2 = await openClient('/live/papa/pw/2.ts');
  assert.equal(ch1.status, 200);
  assert.equal(ch2.status, 200);
  assert.equal(hub.totalUpstream(), 2, 'ligne pleine (max 2)');

  // On quitte la chaîne 1 → sa session reste « au chaud » (grace 5 s).
  ch1.close();
  await sleep(150);
  assert.equal(hub.totalUpstream(), 2, 'la session quittée occupe encore le slot (grace)');

  // Ouvrir une 3e chaîne DIFFÉRENTE : sans le correctif → 503. Avec → on
  // récupère le slot en grace et ça passe.
  const ch3 = await openClient('/live/papa/pw/3.ts');
  assert.equal(ch3.status, 200, 'la 3e chaîne passe en récupérant le slot au chaud');
  assert.equal(hub.totalUpstream(), 2, 'toujours ≤ limite fournisseur');

  ch2.close(); ch3.close();
  await drainUpstream();
});

test('LIMITE : deux chaînes ACTIVES bloquent toujours une 3e (503)', async () => {
  await drainUpstream();
  const ch1 = await openClient('/live/papa/pw/4.ts');
  const ch2 = await openClient('/live/papa/pw/5.ts');
  assert.equal(hub.totalUpstream(), 2);
  // Les deux ont un spectateur ACTIF → aucun slot récupérable → 503.
  const ch3 = await openClient('/live/papa/pw/6.ts');
  assert.equal(ch3.status, 503, 'aucune session en grace : la limite protège toujours');
  ch1.close(); ch2.close();
  await drainUpstream();
});

test('M3U streamé : réécriture = réécriture texte entier (équivalence)', async () => {
  const res = await request(base + '/get.php?username=papa&password=pw&type=m3u_plus');
  assert.equal(res.statusCode, 200);
  const body = await res.body.text();

  // La ligne réelle ne fuit jamais : base + identifiants fournisseur masqués.
  assert.ok(body.includes('https://gw.example.com'), 'base passerelle présente');
  assert.ok(!body.includes(`127.0.0.1:${upPort}`), 'base fournisseur masquée');
  assert.ok(!body.includes('lineuser'), 'user fournisseur masqué');
  assert.ok(!body.includes('linepass'), 'pass fournisseur masqué');
  assert.ok(body.includes('/live/papa/pw/'), 'identifiants passerelle en place');

  // Équivalence stricte avec la réécriture du texte ENTIER.
  const b = `http://127.0.0.1:${upPort}`;
  const raw = [
    '#EXTM3U',
    '#EXTINF:-1 tvg-id="1",Chaîne 1',
    `${b}/live/lineuser/linepass/1.ts`,
    '#EXTINF:-1 tvg-id="2",Chaîne 2',
    `${b}/live/lineuser/linepass/2.ts`,
    `${b}/get.php?username=lineuser&password=linepass&type=m3u`,
    '',
  ].join('\n');
  const rewrite = makeM3URewriter('papa', 'pw');
  assert.equal(body, rewrite(raw), 'streaming ligne-par-ligne == texte entier');
});

test('TIMEOUTS serveur : phase requête bornée, inactivité socket illimitée', () => {
  const s = createServer();
  assert.equal(s.timeout, 0, 'pas de timeout d’inactivité (flux live sans fin)');
  assert.equal(s.headersTimeout, 60000, 'phase en-têtes bornée (anti slow-loris)');
  assert.equal(s.requestTimeout, 60000, 'phase requête bornée');
  try { s.close(); } catch { /* */ }
});
