// Deux onglets peuvent lire les mêmes listes avant d'ajouter chacun une liste.
// La précondition du snapshot doit refuser le deuxième envoi, jamais effacer
// silencieusement la liste du premier. Worker réel, D1 sur SQLite en mémoire.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createD1, fakeRealtimeHub } from './test_support/d1_sqlite.mjs';
import worker from './worker.js';
import { RealtimeHub } from './box_channel.js';

const MAC = 'MK:AA:BB:CC:DD:71';
const OTHER = 'MK:AA:BB:CC:DD:72';
const sourcePath = mac => '/api/v1/sources/' + encodeURIComponent(mac);
const original = { type: 'm3u', m3u_url: 'http://original.example.test/list.m3u', enabled: false };
const added = { type: 'm3u', m3u_url: 'http://added.example.test/list.m3u' };
const xtream = { type: 'xtream', server_url: 'http://xtream.example.test', username: 'fixture', password: 'fixture' };
const ctx = { waitUntil() {}, passThroughOnException() {} };

async function fixture(run) {
  const t = createD1({ extraSql: [
    'ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT',
    'ALTER TABLE devices ADD COLUMN block_status TEXT',
  ] });
  const env = { DB: t.DB, ADMIN_SECRET: crypto.randomUUID(), SECRETS_KEY: crypto.randomUUID() };
  env.RT_HUB = fakeRealtimeHub(env, RealtimeHub);
  async function request(method, path, body, auth = true) {
    const headers = { 'content-type': 'application/json' };
    if (auth && token) headers.authorization = 'Bearer ' + token;
    const res = await worker.fetch(new Request('https://snapshot.test' + path, {
      method, headers, body: body === undefined ? undefined : JSON.stringify(body),
    }), env, ctx);
    return { status: res.status, json: await res.json() };
  }
  let token;
  const login = await request('POST', '/api/v1/auth/login', { email: 'admin', password: env.ADMIN_SECRET }, false);
  assert.equal(login.status, 200);
  token = login.json.token;
  const get = mac => request('GET', sourcePath(mac));
  const put = (mac, sources, rev) => request('PUT', sourcePath(mac), {
    sources, ...(rev === undefined ? {} : { expected_rev: rev }),
  });
  const clear = (mac, rev) => request('DELETE', sourcePath(mac), rev === undefined ? undefined : { expected_rev: rev });
  const snapshot = () => ({
    sources: t.db.prepare('SELECT * FROM device_sources ORDER BY mac').all(),
    revisions: t.db.prepare('SELECT * FROM source_revisions ORDER BY mac, rev').all(),
    orders: t.db.prepare('SELECT * FROM box_orders ORDER BY order_id').all(),
    licenses: t.db.prepare('SELECT * FROM licenses ORDER BY id').all(),
  });
  try {
    await run({ ...t, env, request, get, put, clear, snapshot });
  } finally {
    t.db.close();
  }
}

test('deux snapshots : le second ajout est refusé, listes, autre MAC et licences intactes', async () => {
  await fixture(async ({ request, get, put, snapshot }) => {
    for (const mac of [MAC, OTHER]) {
      assert.equal((await request('POST', '/api/v1/activate', { mac, plan: 'yearly' })).status, 201);
    }
    assert.equal((await put(MAC, [original])).status, 200);
    assert.equal((await put(OTHER, [xtream])).status, 200);
    assert.equal((await request('POST', '/api/self-source/' + MAC,
      { type: 'm3u', m3u_url: 'http://self.example.test/list.m3u' }, false)).status, 200);
    const otherBefore = await get(OTHER);
    const licensesBefore = snapshot().licenses;
    const firstTab = await get(MAC);
    const secondTab = await get(MAC);
    assert.ok(Number.isSafeInteger(firstTab.json.rev));
    assert.equal(firstTab.json.rev, secondTab.json.rev);
    assert.equal((await put(MAC, [original, added], firstTab.json.rev)).status, 200);
    const beforeRejected = snapshot();
    const stale = await put(MAC, [original, xtream], secondTab.json.rev);
    assert.equal(stale.status, 409);
    assert.equal(stale.json.error, 'sources_conflict');
    assert.deepEqual(snapshot(), beforeRejected, 'aucune source/révision/ordre/licence créée sur conflit');
    const final = await get(MAC);
    assert.ok(final.json.sources.some(s => s.m3u_url === added.m3u_url));
    assert.ok(final.json.sources.some(s => s.m3u_url === original.m3u_url && s.enabled === false));
    assert.ok(final.json.sources.some(s => s.origin === 'self'));
    assert.deepEqual(await get(OTHER), otherBefore);
    assert.deepEqual(snapshot().licenses, licensesBefore);
  });
});

test('DELETE refuse un snapshot périmé et la révision survit à suppression/recréation', async () => {
  await fixture(async ({ get, put, clear, snapshot }) => {
    const empty = await get(MAC);
    assert.equal(empty.json.rev, 0);
    assert.equal((await put(MAC, [original], empty.json.rev)).status, 200);
    const first = await get(MAC);
    assert.equal((await put(MAC, [original, added], first.json.rev)).status, 200);
    const before = snapshot();
    assert.equal((await clear(MAC, first.json.rev)).status, 409);
    assert.deepEqual(snapshot(), before);
    const current = await get(MAC);
    assert.equal((await clear(MAC, current.json.rev)).status, 200);
    const cleared = await get(MAC);
    assert.deepEqual(cleared.json.sources, []);
    assert.ok(cleared.json.rev > current.json.rev);
    assert.equal((await put(MAC, [xtream], cleared.json.rev)).status, 200);
    const recreated = await get(MAC);
    assert.ok(recreated.json.rev > cleared.json.rev);
    const beforeStale = snapshot();
    assert.equal((await put(MAC, [added], first.json.rev)).status, 409);
    assert.deepEqual(snapshot(), beforeStale, 'une version de ligne recyclée ne réautorise pas l’ancien snapshot');
  });
});

test('une écriture entre lecture et transaction est refusée par la condition SQL', async () => {
  await fixture(async ({ env, get, put, snapshot }) => {
    assert.equal((await put(MAC, [original])).status, 200);
    const old = await get(MAC);
    assert.ok(Number.isSafeInteger(old.json.rev));
    const realBatch = env.DB.batch.bind(env.DB);
    let release, reached;
    const held = new Promise(resolve => { release = resolve; });
    const atBatch = new Promise(resolve => { reached = resolve; });
    let intercept = true;
    env.DB.batch = async statements => {
      if (intercept && statements.some(s => /(?:UPDATE|INSERT INTO) device_sources/.test(s.sql))) {
        intercept = false;
        reached();
        await held;
      }
      return realBatch(statements);
    };
    const delayed = put(MAC, [original, xtream], old.json.rev);
    await atBatch;
    assert.equal((await put(MAC, [original, added])).status, 200, 'ancien client sans précondition reste compatible');
    const before = snapshot();
    release();
    assert.equal((await delayed).status, 409);
    assert.deepEqual(snapshot(), before);
    assert.ok((await get(MAC)).json.sources.some(s => s.m3u_url === added.m3u_url));
  });
});

test('précondition invalide : 400 sans changement ; absence compatible avec les anciens clients', async () => {
  await fixture(async ({ get, put, clear, snapshot }) => {
    assert.equal((await put(MAC, [original])).status, 200);
    const before = snapshot();
    for (const rev of [-1, 0.5, '1', null, Number.MAX_SAFE_INTEGER + 1]) {
      assert.equal((await put(MAC, [added], rev)).status, 400);
      assert.equal((await clear(MAC, rev)).status, 400);
    }
    assert.deepEqual(snapshot(), before);
    assert.equal((await put(MAC, [xtream])).status, 200);
    assert.equal((await clear(MAC)).status, 200);
    assert.deepEqual((await get(MAC)).json.sources, []);
  });
});

test('effacement sans ligne : la révision zéro ne passe pas si une source arrive avant la transaction', async () => {
  await fixture(async ({ env, get, put, clear, snapshot }) => {
    assert.equal((await get(MAC)).json.rev, 0);
    const realBatch = env.DB.batch.bind(env.DB);
    let release, reached;
    const held = new Promise(resolve => { release = resolve; });
    const atBatch = new Promise(resolve => { reached = resolve; });
    let intercept = true;
    env.DB.batch = async statements => {
      if (intercept && statements.some(s => /INSERT INTO source_revisions/.test(s.sql))) {
        intercept = false;
        reached();
        await held;
      }
      return realBatch(statements);
    };
    const delayed = clear(MAC, 0);
    await atBatch;
    assert.equal((await put(MAC, [added], 0)).status, 200);
    const before = snapshot();
    release();
    assert.equal((await delayed).status, 409);
    assert.deepEqual(snapshot(), before, 'aucun tombstone, ordre ou révision vide publié sur l’ancienne révision');
    assert.ok((await get(MAC)).json.sources.some(s => s.m3u_url === added.m3u_url));
  });
});
