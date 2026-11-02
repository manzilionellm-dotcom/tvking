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
  async function raw(path, method = 'GET', body, authorized = true, headers = {}) {
    const response = await gold.fetch(new Request(`https://fixture.example${path}`, {
      method, headers: { 'Content-Type': 'application/json', ...headers, ...(authorized ? { Authorization: `Bearer ${token}` } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }), env, { waitUntil: promise => tasks.push(promise) });
    await Promise.all(tasks.splice(0));
    return { response, body: await response.json() };
  }
  async function call(path, method = 'GET', body) {
    const result = await raw(path, method, body);
    assert.ok(result.response.ok, `${path}: ${result.response.status}`);
    return result.body;
  }
  return { ...f, call, raw, async close() { await Promise.allSettled(tasks); f.db.close(); } };
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

test('tarifs admin absents : aucun prix par défaut présenté comme enregistré', async () => {
  const f = fixture();
  try {
    const value = await f.call('/api/v1/pricing');
    assert.equal(value.lifetime, ''); assert.equal(value.yearly, '');
    assert.equal((await f.call('/api/pricing')).configured, false);
  } finally { await f.close(); }
});

test('effacer les prix : PUT, GET admin et API app restent vides sans modifier les licences', async () => {
  const f = fixture();
  try {
    const config = { currency: 'SEK', lifetime: '99', yearly: '45', trialDays: 3,
      promoEnabled: false, promoMessage: '', blockTitleFr: 'Votre offre',
      payUrl: 'https://payments.example.invalid/offers' };
    f.db.exec("INSERT INTO apps(id,name,package_name,created_at,updated_at) VALUES ('fixture-app','Fixture','invalid.fixture',1,1)");
    f.db.exec("INSERT INTO customers(id,created_at,updated_at) VALUES ('fixture-customer',1,1)");
    f.db.exec("INSERT INTO devices(id,customer_id,mac,first_seen_at,last_seen_at) VALUES ('fixture-device','fixture-customer','MK:11:22:33:44:55',1,1)");
    f.db.exec("INSERT INTO licenses(id,customer_id,device_id,app_id,status,plan,started_at,expires_at,created_at,updated_at) VALUES ('paid-license','fixture-customer','fixture-device','fixture-app','active','lifetime',1,NULL,1,1)");
    await f.call('/api/v1/pricing', 'PUT', config);
    const licensesBefore = f.db.prepare('SELECT * FROM licenses').all();
    const first = await f.call('/api/v1/pricing', 'PUT', { ...config, lifetime: '   ' });
    assert.equal(first.lifetime, ''); assert.equal(first.yearly, '45');
    for (const path of ['/api/v1/pricing', '/api/pricing']) {
      const value = await f.call(path);
      assert.equal(value.lifetime, ''); assert.equal(value.yearly, '45');
    }
    const second = await f.call('/api/v1/pricing', 'PUT', { ...config, lifetime: '', yearly: null });
    assert.equal(second.lifetime, ''); assert.equal(second.yearly, '');
    for (const path of ['/api/v1/pricing', '/api/pricing']) {
      const value = await f.call(path);
      assert.equal(value.lifetime, ''); assert.equal(value.yearly, '');
      assert.equal(value.currency, 'SEK'); assert.equal(value.trialDays, 3);
      assert.equal(value.blockTitleFr, config.blockTitleFr); assert.equal(value.payUrl, config.payUrl);
    }
    // configured décrit les textes/liens enregistrés ; offers côté app dépend
    // aussi d'un montant non vide. Aucun prix de remplacement n'est inventé.
    assert.equal((await f.call('/api/pricing')).configured, true);
    assert.deepEqual(f.db.prepare('SELECT * FROM licenses').all(), licensesBefore);
  } finally { await f.close(); }
});

test('prix vidés sans autorisation : refus inchangé et aucune écriture', async () => {
  const f = fixture();
  try {
    await f.call('/api/v1/pricing', 'PUT', { lifetime: '72', yearly: '21', currency: 'EUR', trialDays: 0 });
    const before = f.db.prepare('SELECT * FROM app_config ORDER BY key').all();
    for (const method of ['GET', 'PUT']) {
      const denied = await f.raw('/api/v1/pricing', method,
        method === 'PUT' ? { lifetime: '', yearly: '' } : undefined, false);
      assert.ok([401, 403].includes(denied.response.status));
    }
    assert.deepEqual(f.db.prepare('SELECT * FROM app_config ORDER BY key').all(), before);
    const value = await f.call('/api/pricing');
    assert.equal(value.lifetime, '72'); assert.equal(value.yearly, '21');
  } finally { await f.close(); }
});

test('audit des prix vidés : seule la requête exacte est corrigée malgré une corrélation client réutilisée', async () => {
  const f = fixture();
  try {
    const headers = { 'X-Request-Id': 'fixture-reused-correlation' };
    const config = { lifetime: '72', yearly: '21', currency: 'EUR', trialDays: 0 };
    await f.raw('/api/v1/pricing', 'PUT', config, true, headers);
    const original = f.db.prepare("SELECT * FROM audit_logs WHERE action='pricing.save'").get();
    const first = await f.raw('/api/v1/pricing', 'PUT', { ...config, lifetime: '' }, true, headers);
    const second = await f.raw('/api/v1/pricing', 'PUT', { ...config, lifetime: '', yearly: '' }, true, headers);
    assert.equal(first.response.status, 200); assert.equal(second.response.status, 200);
    const firstId = first.response.headers.get('X-Request-Id');
    const secondId = second.response.headers.get('X-Request-Id');
    assert.notEqual(firstId, headers['X-Request-Id']); assert.notEqual(firstId, secondId);
    const readAudit = id => f.db.prepare("SELECT * FROM audit_logs WHERE action='pricing.save' AND correlation_id=?").get(id);
    const firstAudit = readAudit(firstId), secondAudit = readAudit(secondId);
    assert.equal(firstAudit.actor_id, original.actor_id);
    assert.equal(secondAudit.actor_id, original.actor_id);
    assert.deepEqual(JSON.parse(firstAudit.after_json), { lifetime: '', yearly: '21', currency: 'EUR', trialDays: 0, promoEnabled: '0' });
    assert.deepEqual(JSON.parse(secondAudit.after_json), { lifetime: '', yearly: '', currency: 'EUR', trialDays: 0, promoEnabled: '0' });
    assert.deepEqual(readAudit(headers['X-Request-Id']), original);
    assert.equal(f.db.prepare("SELECT COUNT(*) n FROM audit_logs WHERE action='pricing.save'").get().n, 3);
  } finally { await f.close(); }
});
