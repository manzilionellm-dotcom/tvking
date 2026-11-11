// Canal panel → box. Aucun secret, aucun flux, aucun réseau.
// Exécuter : node --test android-app/cloudflare/box_channel.test.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  BROADCAST_MAX,
  broadcastRecentBoxes,
  canonicalKind,
  clampTimeout,
  containsSecretKey,
  createMacMailbox,
  eventsAfter,
  normalizeMac,
  panelMaySee,
  publicEvent,
  realtimePushOff,
  waitBody,
} from './box_channel.js';

function memoryStorage() {
  const map = new Map();
  return {
    async get(key) { return map.get(key); },
    async put(key, value) { map.set(key, value); },
  };
}

const MAC = 'MK:AA:BB:CC:DD:EE';

test('MAC et noms d\'ordres : forme stricte, rien d\'autre', () => {
  assert.equal(normalizeMac(' mk:aa:bb:cc:dd:ee '), MAC);
  assert.equal(normalizeMac('MK%3AAA%3ABB%3ACC%3ADD%3AEE'), MAC);
  assert.equal(normalizeMac('AA:BB:CC:DD:EE'), '');
  assert.equal(canonicalKind('source'), 'source');
  assert.equal(canonicalKind('source_clear'), 'source_clear');
  assert.equal(canonicalKind('password'), '');
  assert.equal(canonicalKind('http://exemple.invalid/liste'), '');
});

test('interrupteur de repli coupé par défaut', () => {
  assert.equal(realtimePushOff({}), false);
  assert.equal(realtimePushOff({ REALTIME_PUSH_OFF: '0' }), false);
  assert.equal(realtimePushOff(undefined), false);
  assert.equal(realtimePushOff({ REALTIME_PUSH_OFF: '1' }), true);
});

test('le corps public n\'a ni secret ni adresse', () => {
  const body = waitBody([
    { v: 1, seq: 4, type: 'source', mac: MAC, at: 10 },
  ], false);
  assert.equal(body.timeout, false);
  assert.equal(body.fleet.length, 0);
  assert.deepEqual(body.box, [{ id: 4, kind: 'source', created_at: 10 }]);
  assert.equal(containsSecretKey(body), false);
  assert.equal(JSON.stringify(body).includes('password'), false);
  assert.equal(JSON.stringify(body).includes('m3u'), false);
  const poisoned = { type: 'source', password: 'x' };
  assert.equal(containsSecretKey(poisoned), true);
  assert.deepEqual(Object.keys(publicEvent({
    seq: 1, type: 'source', mac: MAC, at: 1, password: 'nope', m3u_url: 'nope',
  })), ['v', 'seq', 'type', 'mac', 'at']);
});

test('un push réveille l\'attente tout de suite', async () => {
  const box = createMacMailbox(memoryStorage());
  const pending = box.wait(0, 5000);
  const event = await box.push('source', MAC);
  const body = await pending;
  assert.equal(event.seq, 1);
  assert.equal(body.timeout, false);
  assert.equal(body.box[0].kind, 'source');
  assert.equal(body.box[0].id, 1);
  assert.equal(containsSecretKey(body), false);
});

test('après le curseur, le silence dure jusqu\'au délai', async () => {
  const box = createMacMailbox(memoryStorage());
  await box.push('source', MAC);
  const started = Date.now();
  const body = await box.wait(1, 200);
  assert.equal(body.timeout, true);
  assert.equal(body.box.length, 0);
  assert.ok(Date.now() - started >= 180);
  assert.ok(Date.now() - started < 2000);
});

test('deux écritures : la box en retard reçoit les deux, pas un secret', async () => {
  const box = createMacMailbox(memoryStorage());
  await box.push('source', 'mk:aa:bb:cc:dd:ee');
  await box.push('source_clear', MAC);
  const seen = await box.since(0);
  assert.deepEqual(seen.map((e) => e.type), ['source', 'source_clear']);
  const onlyNew = eventsAfter(seen, 1);
  assert.equal(onlyNew.length, 1);
  assert.equal(onlyNew[0].type, 'source_clear');
  assert.equal(await box.push('nope', MAC), null);
});

test('le délai demandé est borné', () => {
  assert.equal(clampTimeout(undefined), 20000);
  assert.equal(clampTimeout(50), 200);
  assert.equal(clampTimeout(999999), 20000);
});

test('un revendeur ne voit pas la MAC d\'un autre', () => {
  assert.equal(panelMaySee({ id: 'r1', role: 'reseller' }, 'r1'), true);
  assert.equal(panelMaySee({ id: 'r1', role: 'reseller' }, 'r2'), false);
  assert.equal(panelMaySee({ id: 'r1', role: 'reseller' }, ''), false);
  assert.equal(panelMaySee({ id: 'admin', role: 'super_admin' }, 'r2'), true);
  assert.equal(panelMaySee(null, 'r1'), false);
});

// --- Envoi groupé d'un réglage global (publicité) ---------------------

function fakeEnv(rows, { failMac = null, pushOff = false } = {}) {
  const sent = [];
  let lastBind = null;
  return {
    sent,
    get lastBind() { return lastBind; },
    REALTIME_PUSH_OFF: pushOff ? '1' : undefined,
    DB: {
      prepare(sql) {
        return {
          bind(...args) {
            lastBind = { sql, args };
            return { async all() { return { results: rows }; } };
          },
        };
      },
    },
    RT_HUB: {
      idFromName(name) { return name; },
      get(id) {
        return {
          async fetch(url, init) {
            if (id === failMac) throw new Error('hub indisponible');
            sent.push({ id, url, body: JSON.parse(init.body) });
            return { ok: true };
          },
        };
      },
    },
  };
}

const NOW = 1794430000000;

test('publicité : chaque box vue récemment reçoit « ad », sans secret ni ligne d\'ordre', async () => {
  const env = fakeEnv([
    { mac: 'MK:00:00:00:00:01' },
    { mac: 'mk:00:00:00:00:02' }, // forme normalisée
    { mac: 'pas-une-mac' },          // ignorée
    { mac: 'MK:00:00:00:00:01' }, // doublon
  ]);
  const r = await broadcastRecentBoxes(env, 'ad', { now: NOW });
  assert.deepEqual(r, { notified: 2, skipped: 0 });
  assert.deepEqual(env.sent.map((x) => x.id), ['MK:00:00:00:00:01', 'MK:00:00:00:00:02']);
  for (const s of env.sent) {
    assert.equal(s.url, 'https://hub/notify');
    assert.deepEqual(Object.keys(s.body).sort(), ['kind', 'mac']);
    assert.equal(s.body.kind, 'ad');
    assert.equal(containsSecretKey(s.body), false);
  }
  // Fenêtre de 15 min, en millisecondes ET en secondes (anciennes dates).
  const [sinceMs, ceiling, sinceSec, limit] = env.lastBind.args;
  assert.equal(sinceMs, NOW - 15 * 60 * 1000);
  assert.equal(ceiling, 100000000000);
  assert.equal(sinceSec, Math.floor((NOW - 15 * 60 * 1000) / 1000));
  assert.equal(limit, BROADCAST_MAX + 1);
});

test('publicité : plafond par requête, une panne de box ne bloque pas les autres', async () => {
  const rows = Array.from({ length: 7 }, (_, i) => ({ mac: `MK:00:00:00:00:0${i}` }));
  const env = fakeEnv(rows, { failMac: 'MK:00:00:00:00:01' });
  const r = await broadcastRecentBoxes(env, 'ad', { now: NOW, max: 5 });
  assert.equal(r.skipped, 2);
  assert.equal(r.notified, 4); // 5 visées, une en panne
});

test('publicité : interrupteur de repli, ordre inconnu ou base absente → rien', async () => {
  const rows = [{ mac: 'MK:00:00:00:00:01' }];
  assert.deepEqual(await broadcastRecentBoxes(fakeEnv(rows, { pushOff: true }), 'ad'), { notified: 0, skipped: 0 });
  assert.deepEqual(await broadcastRecentBoxes(fakeEnv(rows), 'mot_de_passe'), { notified: 0, skipped: 0 });
  assert.deepEqual(await broadcastRecentBoxes({}, 'ad'), { notified: 0, skipped: 0 });
});
