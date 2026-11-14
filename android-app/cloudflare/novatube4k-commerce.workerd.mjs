// Entrée de production exacte, Workerd + D1 locaux. Tous les appels Stripe
// sont interceptés avant le réseau ; aucune carte ni clé réelle n'est utilisée.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash, createHmac, randomBytes } from 'node:crypto';
import { Miniflare, Log, LogLevel } from 'miniflare';

const here = dirname(fileURLToPath(import.meta.url));
const candidate = resolve(process.argv[2] || join(here, '../../../novatube-commerce-evidence/backend-release/novatube4k-live-entry.js'));
const RAW = 'AABBCCDDEE91', KEY = randomBytes(32).toString('hex');
const RAW2 = 'AABBCCDDEE92', KEY2 = randomBytes(32).toString('hex');
const secret = 'whsec_' + randomBytes(24).toString('hex');
const sessions = new Map(), outbound = [], denied = [];
let passed = 0, current = 'startup';
assert.equal(readFileSync(join(dirname(candidate), 'novatube4k-commerce.js'), 'utf8'), readFileSync(join(here, 'novatube4k-commerce.js'), 'utf8'));
const mf = new Miniflare({
  host: '127.0.0.1', port: 0, modules: true,
  modulesRules: [{ type: 'ESModule', include: ['**/*.js'] }], scriptPath: candidate, modulesRoot: dirname(candidate),
  cf: false, compatibilityDate: '2025-05-01', compatibilityFlags: [],
  d1Databases: { DB: 'novatube4k-commerce-fixture' },
  durableObjects: { RT_HUB: { className: 'RealtimeHub', useSQLite: true } },
  bindings: {
    ADMIN_SECRET: randomBytes(32).toString('hex'), SECRETS_KEY: randomBytes(32).toString('hex'),
    ACCOUNT_ENCRYPTION_KEY: randomBytes(32).toString('hex'), DEVICE_TOKEN_SECRET: randomBytes(32).toString('hex'),
    GOLD_PANEL_API_KEY: 'fixtureOnlyNoNetwork1234', DEFAULT_SERVERS: '[]', PANEL_ORIGINS: 'https://panel.fixture.test',
    NOVATUBE_COMMERCE_ENABLED: '1', NOVATUBE_STRIPE_MODE: 'test',
    NOVATUBE_STRIPE_SECRET_KEY: 'sk_test_' + randomBytes(24).toString('hex'), NOVATUBE_STRIPE_WEBHOOK_SECRET: secret,
    NOVATUBE_PAID_DURATION: '365', NOVATUBE_CHECKOUT_ORIGIN: 'https://novatube-owned.example.com',
  },
  outboundService: async request => { try {
    const url = new URL(request.url);
    if (url.origin !== 'https://api.stripe.com') {
      denied.push(url.origin); return Response.json({ error: 'external_network_denied' }, { status: 503 });
    }
    assert.equal(request.headers.get('Stripe-Version'), '2026-10-28.endive');
    outbound.push({ method: request.method, path: url.pathname });
    if (request.method === 'POST') {
      const form = new URLSearchParams(await request.text());
      assert.equal(form.get('mode'), 'payment'); assert.equal(form.get('line_items[0][price_data][unit_amount]'), '999');
      assert.equal(form.get('adaptive_pricing[enabled]'), 'false');
      const order = form.get('client_reference_id'), id = 'cs_test_' + order.replaceAll('_', '');
      assert.equal(request.headers.get('Idempotency-Key'), order);
      if (!sessions.has(id)) sessions.set(id, {
        id, object: 'checkout.session', mode: 'payment', livemode: false,
        amount_total: 999, currency: 'eur', payment_status: 'unpaid', status: 'open',
        expires_at: Number(form.get('expires_at')), client_reference_id: order,
        metadata: Object.fromEntries(['order_id','app_id','device_id','license_id'].map(key => [key, form.get('metadata[' + key + ']')])),
        url: 'https://checkout.stripe.com/c/pay/' + id,
      });
      return Response.json(sessions.get(id));
    }
    assert.equal(request.method, 'GET');
    return Response.json(sessions.get(url.pathname.split('/').at(-1)) || {}, { status: sessions.has(url.pathname.split('/').at(-1)) ? 200 : 404 });
  } catch (error) { console.error('FIXTURE_OUTBOUND_FAILURE ' + error.message); throw error; }
  }, log: new Log(LogLevel.WARN),
});

async function step(name, run) { current = name; const value = await run(); passed++; console.log('PASS ' + name); return value; }
async function api(path, body, headers = {}, method = 'POST') {
  const r = await mf.dispatchFetch('https://fixture.test' + path, { method,
    headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '192.0.2.91', ...headers },
    body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
  });
  const text = await r.text(); let data; try { data = JSON.parse(text); } catch { data = null; }
  return { status: r.status, data, text };
}
const device = (action, raw = RAW, key = KEY) => api('/api/novatube4k/' + action, { raw_mac: raw }, { 'X-Device-Key': key });
function paid(session) {
  session.status = 'complete'; session.payment_status = 'paid';
  session.line_items = { has_more: false, data: [{ quantity: 1, amount_total: 999, currency: 'eur',
    price: { unit_amount: 999, currency: 'eur', type: 'one_time' } }] };
  session.payment_intent = { id: 'pi_' + session.metadata.order_id.replaceAll('_', ''), object: 'payment_intent',
    status: 'succeeded', currency: 'eur', amount: 999, amount_received: 999, livemode: false, metadata: { ...session.metadata } };
}
async function webhook(session, options = {}) {
  const event = { id: 'evt_fixtureCommerce', object: 'event', livemode: false, type: 'checkout.session.completed',
    data: { object: { id: session.id, object: 'checkout.session' } }, ...options.event };
  const body = JSON.stringify(event), timestamp = Math.floor(Date.now() / 1000);
  const signature = createHmac('sha256', options.secret || secret).update(timestamp + '.' + body).digest('hex');
  return api('/api/novatube4k/payments/stripe-webhook', body, { 'Stripe-Signature': 't=' + timestamp + ',v1=' + signature });
}

try {
  console.log(JSON.stringify({ runtime: 'workerd', candidate,
    module_sha256: createHash('sha256').update(readFileSync(join(dirname(candidate), 'novatube4k-commerce.js'))).digest('hex'),
    external_network: 'all requests intercepted; Stripe fixtures only' }));
  await mf.ready;
  const db = await mf.getD1Database('DB');
  await step('schéma D1 réel local et inscription essai de dix jours', async () => {
    for (const sql of readFileSync(join(here, 'schema.sql'), 'utf8').split(/;\s*(?:\n|$)/)
      .map(s => s.replace(/^\s*--.*$/gm, '').trim()).filter(Boolean)) await db.prepare(sql).run();
    const r = await device('register'); assert.equal(r.status, 200); assert.equal(r.data.active, true);
    assert.equal(r.data.commerce.price_minor, 999); assert.equal(r.data.commerce.checkout_available, true);
    assert.equal(r.data.commerce.license_duration, '365_days');
  });
  await step('Checkout utilise le garde appareil existant, aucune route MAC seule', async () => {
    const missing = await api('/api/novatube4k/checkout', { raw_mac: RAW }); assert.equal(missing.status, 401);
    assert.equal((await device('checkout', RAW, 'ab'.repeat(32))).status, 401);
    assert.equal(outbound.length, 0);
  });
  const checkout = await step('commande authentifiée, prix serveur et rejeu idempotent', async () => {
    const r = await device('checkout'); assert.equal(r.status, 200, r.text);
    assert.equal(r.data.license_duration, '365_days');
    assert.equal(r.data.license_duration, (await db.prepare('SELECT term FROM novatube4k_purchase_orders WHERE id=?').bind(r.data.order_id).first()).term);
    const second = await device('checkout'); assert.equal(second.status, 200); assert.equal(second.data.order_id, r.data.order_id);
    assert.equal(sessions.size, 1); assert.equal((await db.prepare('SELECT COUNT(*) n FROM payments').first()).n, 0);
    return r.data;
  });
  const session = sessions.values().next().value;
  await step('signature erronée et mode étranger rejetés sans accès de lecture Stripe', async () => {
    const before = outbound.length;
    assert.equal((await webhook(session, { secret: secret + 'wrong' })).status, 400);
    assert.equal((await webhook(session, { event: { livemode: true } })).status, 400);
    assert.equal(outbound.length, before);
  });
  await step('commande encore impayée ne donne aucun accès payant', async () => {
    session.status = 'complete';
    const r = await webhook(session); assert.equal(r.status, 200); assert.equal(r.data.pending, true);
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM payments').first()).n, 0);
  });
  await step('paiement confirmé : WebCrypto signature, relire Stripe, transaction D1 unique sous concurrence', async () => {
    paid(session);
    const r = await Promise.all([webhook(session), webhook(session), webhook(session)]);
    for (const item of r) assert.equal(item.status, 200, item.text);
    assert.equal(r.filter(item => item.data.activated).length, 1);
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM payments').first()).n, 1);
    assert.equal((await db.prepare("SELECT COUNT(*) n FROM audit_logs WHERE action='novatube.payment.activate'").first()).n, 1);
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM credit_ledger').first()).n, 0);
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM novatube4k_purchase_guard').first()).n, 0);
  });
  await step('state reflète l’activation et refuse une nouvelle vente de la même licence active', async () => {
    const state = await device('state'); assert.equal(state.status, 200); assert.equal(state.data.active, true);
    const row = await db.prepare("SELECT * FROM licenses WHERE app_id='app_novatube4k'").first();
    assert.equal(row.plan, 'custom'); assert.equal(row.auto_renew, 0); assert.ok(row.expires_at > Date.now() + 364 * 86400000);
    assert.equal((await device('checkout')).data.error, 'already_active');
  });
  await step('retour navigateur ne prétend pas confirmer un paiement et ne change aucune licence', async () => {
    const before = await db.prepare('SELECT * FROM licenses').all();
    const page = await api('/novatube/payment-return?paid=true&order=' + checkout.order_id, undefined, {}, 'GET');
    assert.equal(page.status, 200); assert.match(page.text, /après confirmation du paiement/);
    assert.deepEqual(await db.prepare('SELECT * FROM licenses').all(), before);
  });
  const session2 = await step('seconde box isolée : la commande de la première ne lui donne rien', async () => {
    assert.equal((await device('register', RAW2, KEY2)).status, 200);
    const r = await device('checkout', RAW2, KEY2); assert.equal(r.status, 200, r.text);
    const s = Array.from(sessions.values()).find(item => item.metadata.order_id === r.data.order_id);
    assert.notEqual(s.metadata.device_id, session.metadata.device_id); return s;
  });
  await step('montant manipulé refusé, puis échec d’écriture rollback et rejeu exact', async () => {
    paid(session2); session2.amount_total = 1;
    assert.equal((await webhook(session2)).status, 409);
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM payments').first()).n, 1);
    session2.amount_total = 999;
    await db.prepare("CREATE TRIGGER payment_failure BEFORE INSERT ON payments BEGIN SELECT RAISE(ABORT,'fixture_payment_failure'); END").run();
    const before = await db.prepare('SELECT status,plan,expires_at FROM licenses WHERE id=?').bind(session2.metadata.license_id).first();
    assert.equal((await webhook(session2)).status, 503);
    assert.deepEqual(await db.prepare('SELECT status,plan,expires_at FROM licenses WHERE id=?').bind(session2.metadata.license_id).first(), before);
    await db.prepare('DROP TRIGGER payment_failure').run();
    const retried = await webhook(session2); assert.equal(retried.status, 200); assert.equal(retried.data.activated, true);
    assert.equal((await db.prepare('SELECT COUNT(*) n FROM payments').first()).n, 2);
  });
  assert.deepEqual(denied, []);
  console.log(JSON.stringify({ result: 'PASS', checks: passed, intercepted_stripe_requests: outbound.length,
    external_requests: 0, real_payments: 0, real_devices_changed: 0 }));
} catch (error) {
  console.error(JSON.stringify({ result: 'FAIL', step: current, passed, message: error?.message }));
  process.exitCode = 1;
} finally { await mf.dispose(); }
