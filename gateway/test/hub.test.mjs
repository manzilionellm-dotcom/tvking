// hub.test.mjs — Tests unitaires du Hub (mutualisation + limite fournisseur +
// backpressure), sans réseau réel : on injecte un amont factice.
//
// Lancement : node gateway/test/hub.test.mjs

import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { Hub } = require('../src/hub.js');

// ---- Doubles de test --------------------------------------------------------

/** Faux upstream : on garde la main pour émettre des octets à la demande. */
function makeFakeHttpGet() {
  const opened = []; // liste des connexions amont ouvertes
  const httpGet = (url, options, cb) => {
    const req = new EventEmitter();
    req.destroy = () => {};
    req.setTimeout = () => {};
    const res = new EventEmitter();
    res.statusCode = 200;
    res.headers = { 'content-type': 'video/MP2T' };
    res.resume = () => {};
    res.destroy = () => res.emit('close');
    opened.push({ url, res });
    // On appelle le callback de façon asynchrone (comme le vrai http.get).
    setImmediate(() => cb(res));
    return req;
  };
  return { httpGet, opened };
}

/** Faux client (http.ServerResponse minimal) avec file simulée. */
function makeFakeRes() {
  const res = new EventEmitter();
  res.writableLength = 0; // octets « tamponnés » simulés
  res.headersSent = false;
  res.written = 0;
  res.ended = false;
  res.destroyed = false;
  res.setHeader = () => {};
  res.write = (chunk) => {
    res.written += chunk.length;
    return true;
  };
  res.end = () => {
    res.ended = true;
    res.emit('close');
  };
  res.destroy = () => {
    res.destroyed = true;
    res.writableLength = 0;
    res.emit('close');
  };
  return res;
}

const baseCfg = {
  PROVIDER_MAX_CONNECTIONS: 1,
  BROADCAST_MAX_STREAMS: 500,
  CLIENT_BUFFER_MAX_BYTES: 1024 * 1024,
  GLOBAL_CLIENT_BUFFER_MAX_BYTES: 8 * 1024 * 1024,
  SWEEP_INTERVAL_MS: 100000, // on appellera _sweepBackpressure() à la main
  UPSTREAM_TIMEOUT_MS: 1000,
  KEEPALIVE_MS: 1000,
  UPSTREAM_MAX_RETRIES: 0,
  UPSTREAM_RETRY_BASE_MS: 10,
  LOG_LEVEL: 'error',
};

let passed = 0;
function ok(name) {
  console.log(`  \x1b[32m✓\x1b[0m ${name}`);
  passed += 1;
}

async function tick() {
  await new Promise((r) => setImmediate(r));
}

// ---- Test 1 : mutualisation — N abonnés, 1 seule connexion amont -----------
async function testMutualisation() {
  const { httpGet, opened } = makeFakeHttpGet();
  const hub = new Hub(baseCfg, { httpGet, logger: silent() });

  const clients = [];
  for (let i = 0; i < 50; i += 1) {
    const res = makeFakeRes();
    const r = hub.subscribe('chan-A', 'http://up/live/1.ts', res);
    assert.equal(r.ok, true);
    clients.push(res);
  }
  await tick();

  assert.equal(opened.length, 1, '1 seule connexion amont pour 50 abonnés');
  assert.equal(hub.activeUpstreams, 1);
  assert.equal(hub.totalSubscribers, 50);

  // L'amont émet un chunk → tous les clients le reçoivent (fan-out).
  const chunk = Buffer.alloc(1000, 1);
  opened[0].res.emit('data', chunk);
  for (const res of clients) assert.equal(res.written, 1000, 'chaque client reçoit le chunk');

  hub.close();
  ok('mutualisation : 50 abonnés → 1 upstream, fan-out à tous');
}

// ---- Test 2 : limite fournisseur — 2ᵉ chaîne distincte refusée (503) -------
async function testProviderLimit() {
  const { httpGet, opened } = makeFakeHttpGet();
  const hub = new Hub(baseCfg, { httpGet, logger: silent() });

  const r1 = hub.subscribe('chan-A', 'http://up/live/1.ts', makeFakeRes());
  assert.equal(r1.ok, true);
  await tick();

  // Chaîne distincte alors que PROVIDER_MAX_CONNECTIONS = 1 → refus.
  const r2 = hub.subscribe('chan-B', 'http://up/live/2.ts', makeFakeRes());
  assert.equal(r2.ok, false);
  assert.equal(r2.code, 503);
  assert.equal(opened.length, 1, 'aucune 2ᵉ connexion amont ouverte');

  hub.close();
  ok('limite fournisseur : 2ᵉ chaîne distincte → 503, pas de 2ᵉ upstream');
}

// ---- Test 3 : libération du slot amont quand la chaîne se vide -------------
async function testSlotRelease() {
  const { httpGet, opened } = makeFakeHttpGet();
  const hub = new Hub(baseCfg, { httpGet, logger: silent() });

  const res = makeFakeRes();
  hub.subscribe('chan-A', 'http://up/live/1.ts', res);
  await tick();
  assert.equal(hub.activeUpstreams, 1);

  // Le client se déconnecte → chaîne vide → amont libéré.
  res.emit('close');
  assert.equal(hub.activeUpstreams, 0, 'slot amont libéré');

  // Maintenant une AUTRE chaîne peut être ouverte.
  const r2 = hub.subscribe('chan-B', 'http://up/live/2.ts', makeFakeRes());
  await tick();
  assert.equal(r2.ok, true);
  assert.equal(opened.length, 2);

  hub.close();
  ok('libération de slot : chaîne vidée → une autre chaîne devient possible');
}

// ---- Test 4 : backpressure — le client lent est coupé, pas les autres ------
async function testBackpressure() {
  const { httpGet, opened } = makeFakeHttpGet();
  const hub = new Hub(baseCfg, { httpGet, logger: silent() });

  const slow = makeFakeRes();
  const fast = makeFakeRes();
  hub.subscribe('chan-A', 'http://up/live/1.ts', slow);
  hub.subscribe('chan-A', 'http://up/live/1.ts', fast);
  await tick();

  // Simule un client lent : sa file dépasse le cap par client.
  slow.writableLength = baseCfg.CLIENT_BUFFER_MAX_BYTES + 1;
  fast.writableLength = 0;

  hub._sweepBackpressure();

  assert.equal(slow.destroyed, true, 'le client lent est coupé (destroy)');
  assert.equal(fast.destroyed, false, 'le client rapide est intact');
  assert.equal(hub.totalSubscribers, 1, 'seul le rapide reste abonné');

  // Le flux continue pour le client sain.
  opened[0].res.emit('data', Buffer.alloc(500, 1));
  assert.equal(fast.written, 500, 'le client sain reçoit toujours le live');

  hub.close();
  ok('backpressure : client lent coupé sans bloquer le client sain');
}

// ---- Test 5 : plafond global — coupe les plus lents jusque sous le cap -----
async function testGlobalCap() {
  const cfg = { ...baseCfg, GLOBAL_CLIENT_BUFFER_MAX_BYTES: 3 * 1024 * 1024 };
  const { httpGet } = makeFakeHttpGet();
  const hub = new Hub(cfg, { httpGet, logger: silent() });

  const clients = [];
  for (let i = 0; i < 4; i += 1) {
    const res = makeFakeRes();
    hub.subscribe('chan-A', 'http://up/live/1.ts', res);
    clients.push(res);
  }
  await tick();

  // Chacun sous le cap par client (1 Mo) mais cumul = 4 Mo > global 3 Mo.
  clients[0].writableLength = 900 * 1024;
  clients[1].writableLength = 900 * 1024;
  clients[2].writableLength = 900 * 1024;
  clients[3].writableLength = 900 * 1024;

  hub._sweepBackpressure();

  // Au moins un client (le plus lent) doit être coupé pour repasser sous le cap.
  assert.ok(hub.totalBuffered <= cfg.GLOBAL_CLIENT_BUFFER_MAX_BYTES, 'repassé sous le plafond global');
  assert.ok(hub.totalSubscribers < 4, 'au moins un client coupé');

  hub.close();
  ok('plafond global : coupe les plus lents jusqu\'à repasser sous le cap');
}

function silent() {
  const noop = () => {};
  return { error: noop, warn: noop, info: noop, debug: noop };
}

async function run() {
  console.log('\nTests Hub :');
  await testMutualisation();
  await testProviderLimit();
  await testSlotRelease();
  await testBackpressure();
  await testGlobalCap();
  console.log(`\n\x1b[32m${passed} tests réussis.\x1b[0m\n`);
}

run().catch((err) => {
  console.error('\x1b[31mÉchec :\x1b[0m', err.stack);
  process.exit(1);
});
