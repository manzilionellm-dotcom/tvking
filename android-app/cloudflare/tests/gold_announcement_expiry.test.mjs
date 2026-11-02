// Contrat réel panel → bundle exporté → API publique, entièrement en SQLite
// locale : aucune annonce, vidéo ou modification chez les clients réels.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHmac } from 'node:crypto';
import { createD1 } from '../test_support/d1_sqlite.mjs';
import '../prepare_gold_runtime.mjs';
const gold = (await import('../gold.js')).default;

function fixture() {
  const f = createD1({ schema: false });
  f.db.exec(readFileSync(new URL('../production/schema.sql', import.meta.url), 'utf8'));
  f.db.exec("INSERT INTO admin_users(id,email,password_hash,role,is_active,created_at) VALUES ('admin','fixture@example.invalid','unused','super_admin',1,1)");
  const secret = 'fixture-announcements-local-only';
  const enc = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const h = enc({ alg: 'HS256', typ: 'JWT' });
  const p = enc({ sub: 'admin', role: 'super_admin', iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + 3600 });
  const token = `${h}.${p}.${createHmac('sha256', secret).update(`${h}.${p}`).digest('base64url')}`;
  const tasks = [], ctx = { waitUntil: promise => tasks.push(promise) };
  const env = { DB: f.DB, ADMIN_SECRET: secret };
  async function call(path, method = 'GET', body, auth = false) {
    const response = await gold.fetch(new Request(`https://fixture.example${path}`, {
      method, headers: { 'Content-Type': 'application/json', 'CF-IPCountry': 'SE',
        ...(auth ? { Authorization: `Bearer ${token}` } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }), env, ctx);
    assert.ok(response.ok, `${path}: ${response.status}`);
    return { response, body: await response.json() };
  }
  return { ...f, call, async close() { await Promise.allSettled(tasks); f.db.close(); } };
}

test('annonces : expiration ajoutée au latest/pending sans élargir pays, actif ou curseur', async () => {
  const f = fixture();
  try {
    const send = body => f.call('/api/v1/announcements', 'POST', body, true);
    const one = (await send({ title: 'Global', durationMin: 10 })).body;
    const two = (await send({ title: 'Suède', country: 'SE', durationMin: 30, kind: 'info', cta: 'Lire', url: 'https://example.invalid/info' })).body;
    await send({ title: 'Autre pays privé', country: 'FR', durationMin: 30 });
    const disabled = (await send({ title: 'Désactivée', durationMin: 30 })).body;
    await f.call(`/api/v1/announcements/${disabled.id}`, 'PATCH', { active: false }, true);
    const expired = (await send({ title: 'Expirée', durationMin: 30 })).body;
    f.db.prepare('UPDATE app_broadcasts SET expires_at=? WHERE id=?').run(Date.now() - 1000, expired.id);
    const { body, response } = await f.call('/api/announcement');
    assert.equal(body.id, two.id);
    assert.equal(body.kind, 'info'); assert.equal(body.cta, 'Lire');
    assert.ok(body.expires_at > Date.now());
    assert.deepEqual(body.pending.map(row => row.id), [one.id, two.id]);
    assert.ok(body.pending.every(row => row.expires_at > Date.now()));
    assert.doesNotMatch(JSON.stringify(body), /Autre pays privé|Désactivée|Expirée/);
    assert.match(response.headers.get('content-type'), /application\/json/);
    const after = (await f.call(`/api/announcement?after=${one.id}`)).body;
    assert.deepEqual(after.pending.map(row => row.id), [two.id]);
  } finally { await f.close(); }
});

test('annonces : interrupteur OFF, suppression et absence d’expiration restent compatibles', async () => {
  const f = fixture();
  try {
    const created = (await f.call('/api/v1/announcements', 'POST', { title: 'Sans durée', durationMin: 0 }, true)).body;
    assert.equal((await f.call('/api/announcement')).body.expires_at, 0);
    await f.call('/api/v1/announcements/settings', 'PUT', { enabled: false }, true);
    assert.deepEqual((await f.call('/api/announcement')).body, {});
    await f.call('/api/v1/announcements/settings', 'PUT', { enabled: true }, true);
    assert.equal((await f.call('/api/announcement')).body.id, created.id);
    await f.call(`/api/v1/announcements/${created.id}`, 'DELETE', undefined, true);
    assert.deepEqual((await f.call('/api/announcement')).body, {});
  } finally { await f.close(); }
});

test('une panne de la métadonnée expiration conserve la réponse historique valide', async () => {
  const f = fixture();
  try {
    const created = (await f.call('/api/v1/announcements', 'POST', { title: 'Toujours lisible', durationMin: 30 }, true)).body;
    f.faults.add({ match: /SELECT id,expires_at FROM app_broadcasts/, times: 1 });
    const before = (await f.call('/api/announcement')).body;
    assert.equal(before.id, created.id); assert.equal(before.expires_at, undefined);
    assert.ok((await f.call('/api/announcement')).body.expires_at > Date.now());
  } finally { await f.close(); }
});

test('publicité : configuration enregistrée par le panel relue identiquement par l’app', async () => {
  const f = fixture();
  try {
    const ad = { enabled: true, url: 'https://example.invalid/fixture.mp4', skip: 4, freq: 'daily' };
    await f.call('/api/v1/ad', 'PUT', ad, true);
    assert.deepEqual((await f.call('/api/ad')).body, ad);
    await f.call('/api/v1/ad', 'PUT', { ...ad, enabled: false }, true);
    assert.equal((await f.call('/api/ad')).body.enabled, false);
  } finally { await f.close(); }
});
