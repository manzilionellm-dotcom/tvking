// Preuves par les vraies routes HTTP et SQLite, sans simuler le stockage.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac, randomBytes } from 'node:crypto';
import worker from './worker.js';
import { createD1 } from './test_support/d1_sqlite.mjs';

const NOW = Date.UTC(2026, 9, 11, 18);
const ctx = { waitUntil() {}, passThroughOnException() {} };

function setup(t) {
  t.mock.timers.enable({ apis: ['Date'], now: NOW });
  const db = createD1();
  t.after(() => db.db.close());
  const env = { DB: db.DB, ADMIN_SECRET: randomBytes(32).toString('hex') };
  for (const [id, role] of [['owner', 'super_admin'], ['staff', 'admin']]) {
    db.db.prepare('INSERT INTO admin_users (id,email,password_hash,role,created_at) VALUES (?,?,?,?,?)')
      .run(id, `${id}@panel.invalid`, 'fixture', role, NOW);
  }
  function auth(id) {
    const h = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
    const p = Buffer.from(JSON.stringify({ sub: id, role: id === 'owner' ? 'super_admin' : 'admin', iat: NOW / 1000, exp: NOW / 1000 + 86400 })).toString('base64url');
    return `${h}.${p}.${createHmac('sha256', env.ADMIN_SECRET).update(`${h}.${p}`).digest('base64url')}`;
  }
  async function call(path, { method = 'GET', body, user = 'owner', country = '', legacyAdmin = false } = {}) {
    const headers = { 'Content-Type': 'application/json', 'CF-IPCountry': country };
    if (user) headers.Authorization = `Bearer ${auth(user)}`;
    if (legacyAdmin) headers['X-Admin-Secret'] = env.ADMIN_SECRET;
    const res = await worker.fetch(new Request(`https://panel.invalid${path}`, {
      method, headers, body: body === undefined ? undefined : JSON.stringify(body),
    }), env, ctx);
    return { status: res.status, data: await res.json() };
  }
  const draft = (extra = {}) => ({ id: crypto.randomUUID(), type: 'advertisement', title: 'Offre découverte', body: 'Une offre à découvrir.', url: 'https://shop.invalid/offre', cta: 'Découvrir', country: '', starts_at: NOW + 60000, ends_at: NOW + 3600000, timezone: 'Europe/Paris', ...extra });
  async function create(extra = {}) {
    const r = await call('/api/v1/campaigns', { method: 'POST', body: draft(extra) });
    assert.equal(r.status, 201);
    return r.data.item;
  }
  async function change(item, action, extra = {}) {
    return call(`/api/v1/campaigns/${item.id}`, { method: 'PATCH', body: { version: item.version, action, ...extra } });
  }
  const publicRead = (after = 0, country = '') => call(`/api/announcement?after=${after}`, { user: null, country });
  return { ...db, env, call, draft, create, change, publicRead };
}

test('un brouillon reste privé ; une campagne due reçoit un nouvel identifiant après le curseur', async (t) => {
  const s = setup(t);
  const item = await s.create();
  assert.equal(item.status, 'draft');
  assert.deepEqual((await s.publicRead()).data, {});
  const published = await s.change(item, 'schedule');
  assert.equal(published.status, 200);
  const immediate = await s.call('/api/v1/announcements', { method: 'POST', body: { title: 'Information', body: 'Déjà disponible' } });
  assert.equal(immediate.status, 201);
  const cursor = immediate.data.id;
  assert.deepEqual((await s.publicRead(cursor)).data.pending, []);
  t.mock.timers.tick(60000);
  const due = (await s.publicRead(cursor)).data.pending;
  assert.equal(due.length, 1);
  assert.ok(due[0].id > cursor);
  assert.equal(due[0].kind, 'promo');
  assert.match(due[0].title, /^Publicité · /);
  assert.deepEqual((await s.publicRead(due[0].id)).data.pending, []);
  t.mock.timers.tick(3540000);
  assert.deepEqual((await s.publicRead(cursor)).data.pending, []);
});

test('droits serveur : visiteur et employé ne peuvent ni lire ni publier', async (t) => {
  const s = setup(t);
  for (const [user, status] of [[null, 401], ['staff', 403]]) {
    for (const method of ['GET', 'POST', 'PATCH']) {
      const path = method === 'PATCH' ? '/api/v1/campaigns/inconnue' : '/api/v1/campaigns';
      assert.equal((await s.call(path, { method, user, body: method === 'GET' ? undefined : s.draft() })).status, status);
    }
  }
});

test('le même identifiant de création ne produit pas deux brouillons', async (t) => {
  const s = setup(t);
  const body = s.draft();
  const results = await Promise.all(Array.from({ length: 8 }, () => s.call('/api/v1/campaigns', { method: 'POST', body })));
  assert.ok(results.every(r => [200, 201].includes(r.status)));
  assert.equal((await s.call('/api/v1/campaigns')).data.items.length, 1);
  assert.equal((await s.call('/api/v1/campaigns', { method: 'POST', body: { ...body, title: 'Autre' } })).status, 409);
});

test('deux modifications concurrentes : une seule gagne, l’autre reçoit 409', async (t) => {
  const s = setup(t);
  const item = await s.create();
  const results = await Promise.all(['Premier', 'Second'].map(title => s.change(item, 'save', { ...s.draft({ id: item.id, title }) })));
  assert.deepEqual(results.map(r => r.status).sort(), [200, 409]);
  assert.equal((await s.call('/api/v1/campaigns')).data.items[0].version, 2);
});

test('diffusions concurrentes : un seul message ; pause et reprise sans nouvelle notification', async (t) => {
  const s = setup(t);
  let item = await s.create({ starts_at: NOW });
  item = (await s.change(item, 'schedule')).data.item;
  await Promise.all(Array.from({ length: 12 }, () => s.publicRead()));
  const pending = (await s.publicRead()).data.pending;
  assert.equal(pending.length, 1);
  const cursor = pending[0].id;
  item = (await s.change(item, 'pause')).data.item;
  assert.deepEqual((await s.publicRead()).data, {});
  item = (await s.change(item, 'schedule')).data.item;
  assert.equal((await s.publicRead()).data.id, cursor);
  assert.deepEqual((await s.publicRead(cursor)).data.pending, []);
  assert.equal(item.status, 'scheduled');
});

test('une annonce supprimée ne revient pas ; tout retirer annule aussi les campagnes futures', async (t) => {
  const s = setup(t);
  let item = await s.create({ starts_at: NOW });
  await s.change(item, 'schedule');
  const id = (await s.publicRead()).data.id;
  assert.equal((await s.call(`/api/v1/announcements/${id}`, { method: 'DELETE' })).status, 200);
  assert.deepEqual((await s.publicRead()).data, {});
  item = await s.create();
  await s.change(item, 'schedule');
  await s.call('/api/v1/announcements', { method: 'DELETE' });
  t.mock.timers.tick(60000);
  assert.deepEqual((await s.publicRead()).data, {});
});

test('ciblage pays et interrupteur global existant respectés', async (t) => {
  const s = setup(t);
  const item = await s.create({ starts_at: NOW, country: 'FR', type: 'event' });
  await s.change(item, 'schedule');
  await s.call('/api/v1/announcements/settings', { method: 'PUT', body: { enabled: false } });
  assert.deepEqual((await s.publicRead(0, 'FR')).data, {});
  await s.call('/api/v1/announcements/settings', { method: 'PUT', body: { enabled: true } });
  assert.deepEqual((await s.publicRead(0, 'CA')).data, {});
  const delivered = (await s.publicRead(0, 'FR')).data;
  assert.equal(delivered.kind, 'info');
  assert.match(delivered.title, /^Événement · /);
});

test('dates, formats, fuseau et liens dangereux refusés sans insertion', async (t) => {
  const s = setup(t);
  for (const fields of [{ ends_at: NOW }, { starts_at: 'demain' }, { title: 'x'.repeat(109) }, { timezone: 'Inconnu/Zone' }, { url: 'javascript:alert(1)' }, { url: 'https://shop.invalid/?token=factice' }, { type: 'inconnu' }, { country: '???' }, { title: '' }]) {
    const r = await s.call('/api/v1/campaigns', { method: 'POST', body: s.draft(fields) });
    assert.equal(r.status, 400);
  }
  assert.equal((await s.call('/api/v1/campaigns')).data.items.length, 0);
});

test('une campagne déjà diffusée doit être dupliquée pour modifier son contenu', async (t) => {
  const s = setup(t);
  let item = await s.create({ starts_at: NOW });
  item = (await s.change(item, 'schedule')).data.item;
  await s.publicRead();
  item = (await s.change(item, 'pause')).data.item;
  assert.equal((await s.change(item, 'save', s.draft({ id: item.id, title: 'Autre' }))).status, 409);
});

test('panne pendant la diffusion : transaction annulée et 503 explicite, puis une seule diffusion', async (t) => {
  const s = setup(t);
  const item = await s.create({ starts_at: NOW });
  await s.change(item, 'schedule');
  s.faults.add({ match: /UPDATE panel_campaigns SET broadcast_id/, error: new Error('panne simulée') });
  assert.equal((await s.publicRead()).status, 503);
  assert.equal(s.db.prepare('SELECT COUNT(*) AS n FROM app_broadcasts').get().n, 0);
  assert.equal((await s.publicRead()).data.pending.length, 1);
});

test('audit obligatoire : une panne annule le brouillon et le journal ne contient pas le message', async (t) => {
  const s = setup(t);
  s.faults.add({ match: /INSERT INTO audit_logs/, error: new Error('audit indisponible') });
  const rejected = await s.call('/api/v1/campaigns', { method: 'POST', body: s.draft() });
  assert.equal(rejected.status, 500);
  assert.equal((await s.call('/api/v1/campaigns')).data.items.length, 0);
  const item = await s.create();
  const audit = s.db.prepare('SELECT after_json FROM audit_logs WHERE target_id = ?').get(item.id);
  assert.deepEqual(JSON.parse(audit.after_json), { status: 'draft', version: 1 });
});

test('repli global : les annonces historiques gardent le même contrat', async (t) => {
  const s = setup(t);
  const created = await s.call('/api/v1/announcements', { method: 'POST', body: { title: 'Information classique', body: 'Message existant' } });
  assert.equal(created.status, 201);
  const legacy = (await s.publicRead()).data;
  assert.equal(legacy.id, created.data.id);
  assert.equal(legacy.title, 'Information classique');
  assert.equal(legacy.pending.length, 1);
  await s.call('/api/v1/announcements/settings', { method: 'PUT', body: { enabled: false } });
  assert.deepEqual((await s.publicRead()).data, {});
});

test('reprendre une annonce effacée renvoie 409 avec une explication, jamais un faux succès', async (t) => {
  const s = setup(t);
  const created = await s.create({ starts_at: NOW });
  await s.change(created, 'schedule');
  await s.publicRead();
  await s.call('/api/v1/announcements', { method: 'DELETE' });
  const item = (await s.call('/api/v1/campaigns')).data.items[0];
  const result = await s.change(item, 'schedule');
  assert.equal(result.status, 409);
  assert.match(result.data.message, /retirée.*dupliquer/i);
  assert.deepEqual((await s.publicRead()).data, {});
});

test('le retrait historique coupe aussi les campagnes futures et conserve son authentification', async (t) => {
  const s = setup(t);
  const current = await s.create({ starts_at: NOW });
  const future = await s.create();
  await s.change(current, 'schedule');
  await s.change(future, 'schedule');
  assert.equal((await s.publicRead()).data.pending.length, 1);
  assert.equal((await s.call('/api/announcement', { method: 'DELETE', user: null })).status, 401);
  const cleared = await s.call('/api/announcement', { method: 'DELETE', user: null, legacyAdmin: true });
  assert.equal(cleared.status, 200);
  t.mock.timers.tick(60000);
  assert.deepEqual((await s.publicRead()).data, {});
  const items = (await s.call('/api/v1/campaigns')).data.items;
  assert.ok(items.every(item => item.status === 'paused'));
});

test('panne de retrait historique : annonces et programmation restent ensemble', async (t) => {
  const s = setup(t);
  const item = await s.create({ starts_at: NOW });
  await s.change(item, 'schedule');
  const id = (await s.publicRead()).data.id;
  s.faults.add({ match: /DELETE FROM app_broadcasts/, error: new Error('panne de retrait simulée') });
  const rejected = await s.call('/api/announcement', { method: 'DELETE', user: null, legacyAdmin: true });
  assert.equal(rejected.status, 500);
  assert.equal((await s.call('/api/v1/campaigns')).data.items[0].status, 'scheduled');
  assert.equal((await s.publicRead()).data.id, id);
});

test('les boutons des annonces immédiates ne contournent ni pause ni archivage de campagne', async (t) => {
  const s = setup(t);
  for (const action of ['pause', 'archive']) {
    let item = await s.create({ starts_at: NOW });
    item = (await s.change(item, 'schedule')).data.item;
    const id = (await s.publicRead()).data.id;
    item = (await s.change(item, action)).data.item;
    const rejected = await s.call(`/api/v1/announcements/${id}`, { method: 'PATCH', body: { active: true } });
    assert.equal(rejected.status, 409);
    assert.match(rejected.data.message, /Publicités et événements/);
    assert.deepEqual((await s.publicRead()).data, {});
    const stored = (await s.call('/api/v1/campaigns')).data.items.find(c => c.id === item.id);
    assert.equal(stored.status, item.status);
    assert.equal(stored.version, item.version);
  }
  // Les annonces immédiates gardent leur interrupteur historique.
  const created = await s.call('/api/v1/announcements', { method: 'POST', body: { title: 'Annonce classique', body: 'Information' } });
  for (const active of [false, true]) {
    const toggled = await s.call(`/api/v1/announcements/${created.data.id}`, { method: 'PATCH', body: { active } });
    assert.equal(toggled.status, 200);
    assert.equal(toggled.data.active, active);
  }
});

const visual = {version:1,template:'orbit',palette:'ice',image_url:'https://images.example.com/product.png',badge:'NOUVEAU',motion:'gentle',duration_seconds:8};
test('création 3D : brouillon privé, transmission additive, pause et ancien message préservés',async t=>{
 const s=setup(t);let item=await s.create({creative:visual,starts_at:NOW});
 assert.deepEqual(item.creative,visual);assert.deepEqual((await s.publicRead()).data,{});
 item=(await s.change(item,'schedule')).data;
 const published=(await s.publicRead()).data;assert.deepEqual(published.creative,visual);assert.deepEqual(published.pending[0].creative,visual);
 assert.match(published.title,/Publicité/);assert.equal(published.body,'Une offre à découvrir.');
 await s.change(item.item,'pause');assert.deepEqual((await s.publicRead()).data,{});
});
test('création 3D : aucun code, modèle arbitraire ou URL dangereuse accepté',async t=>{
 const s=setup(t);
 for(const creative of [{...visual,html:'<script/>'},{...visual,version:2},{...visual,template:'custom'},{...visual,duration_seconds:1000},{...visual,image_url:'http://x.invalid/image.png'},{...visual,image_url:'https://127.0.0.1/x'},{...visual,image_url:'https://image.invalid/?token=secret'}]){
 assert.equal((await s.call('/api/v1/campaigns',{method:'POST',body:s.draft({creative})})).status,400);
 }
});
