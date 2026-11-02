// Le tarif est une information publique, jamais une attribution de licence.
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
  const secret = 'fixture-pricing-local-only';
  const enc = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const h = enc({ alg: 'HS256', typ: 'JWT' });
  const p = enc({ sub: 'admin', role: 'super_admin', iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + 3600 });
  const token = `${h}.${p}.${createHmac('sha256', secret).update(`${h}.${p}`).digest('base64url')}`;
  const tasks = [], env = { DB: f.DB, ADMIN_SECRET: secret };
  async function call(path, method = 'GET', body) {
    const response = await gold.fetch(new Request(`https://fixture.example${path}`, {
      method, headers: { 'Content-Type': 'application/json', ...(method === 'GET' ? {} : { Authorization: `Bearer ${token}` }) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }), env, { waitUntil: promise => tasks.push(promise) });
    assert.ok(response.ok, `${path}: ${response.status}`);
    return response.json();
  }
  return { ...f, call, async close() { await Promise.allSettled(tasks); f.db.close(); } };
}

test('tarifs absents : aucun prix inventé, configuration explicitement inconnue', async () => {
  const f = fixture();
  try {
    const value = await f.call('/api/pricing');
    assert.equal(value.configured, false);
    for (const key of ['lifetime', 'yearly', 'currency', 'payUrl', 'blockTitleFr']) assert.equal(value[key], '');
    assert.equal(f.db.prepare('SELECT COUNT(*) n FROM licenses').get().n, 0);
  } finally { await f.close(); }
});

test('tarifs panel : montants, textes FR/EN et lien HTTPS relus, aucune licence modifiée', async () => {
  const f = fixture();
  try {
    const config = { currency: 'SEK', lifetime: '99', yearly: '45,50', trialDays: 0,
      promoEnabled: true, promoMessage: 'Offre configurée', blockTitleFr: 'Titre FR', blockBodyFr: 'Texte FR',
      blockTitleEn: 'Title EN', blockBodyEn: 'Text EN', payUrl: 'https://payments.example.invalid/offers' };
    await f.call('/api/v1/pricing', 'PUT', config);
    const value = await f.call('/api/pricing');
    for (const [key, expected] of Object.entries(config)) assert.equal(value[key], expected, key);
    assert.equal(value.configured, true);
    assert.equal(f.db.prepare('SELECT COUNT(*) n FROM licenses').get().n, 0);
    assert.equal(f.db.prepare('SELECT COUNT(*) n FROM trial_anchors').get().n, 0);
    assert.equal(f.db.prepare("SELECT COUNT(*) n FROM sqlite_master WHERE name='device_secrets'").get().n, 0);
  } finally { await f.close(); }
});

test('tarifs publics : lien avec identifiants et clés privées exclus', async () => {
  const f = fixture();
  try {
    f.db.exec("INSERT INTO app_config(key,value) VALUES ('trial_pay_url','https://private:secret@payments.example.invalid/'),('gold_key_enc','never-expose'),('trial_block_title_fr','Titre valide')");
    const value = await f.call('/api/pricing');
    assert.equal(value.payUrl, '');
    assert.equal(value.blockTitleFr, 'Titre valide');
    assert.doesNotMatch(JSON.stringify(value), /private|secret|never-expose/);
  } finally { await f.close(); }
});
