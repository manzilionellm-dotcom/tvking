// Les paiements sont entièrement simulés, sur SQLite réel. Aucun appel Stripe,
// aucun encaissement et aucune licence de production ne sont utilisés ici.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { createD1 } from './test_support/d1_sqlite.mjs';
import {
  novatubeCommerceMetadata, createNovatubeCheckout, handleNovatubeStripeWebhook,
  handleNovatubePaymentReturn, verifyNovatubeStripeSignature,
} from './novatube4k-commerce.js';

const APP = 'app_novatube4k';
const MAC = 'MK:11:22:33:44:55';
const WEBHOOK = 'https://fixture.test/api/novatube4k/payments/stripe-webhook';
const secret = 'whsec_' + 'testonly'.repeat(5);
const configured = {
  NOVATUBE_COMMERCE_ENABLED: '1', NOVATUBE_STRIPE_MODE: 'test',
  NOVATUBE_STRIPE_SECRET_KEY: 'sk_test_' + 'testonly'.repeat(5),
  NOVATUBE_STRIPE_WEBHOOK_SECRET: secret, NOVATUBE_PAID_DURATION: '365',
  NOVATUBE_CHECKOUT_ORIGIN: 'https://novatube-owned.example.com',
};

function fixture(t, options = {}) {
  const f = createD1(options);
  t.after(() => f.db.close());
  const now = Date.now();
  f.db.prepare('INSERT INTO apps(id,name,package_name,created_at,updated_at) VALUES (?,?,?,?,?)')
    .run(APP, 'NovaTube', 'com.manthefew', now, now);
  f.db.prepare('INSERT INTO customers(id,name,created_at,updated_at) VALUES (?,?,?,?)')
    .run('cus_nova', 'Fixture NovaTube', now, now);
  f.db.prepare('INSERT INTO devices(id,customer_id,mac,first_seen_at,last_seen_at) VALUES (?,?,?,?,?)')
    .run('dev_nova', 'cus_nova', MAC, now, now);
  f.db.prepare(`INSERT INTO licenses(id,customer_id,device_id,app_id,status,plan,started_at,expires_at,created_at,updated_at)
    VALUES ('lic_nova','cus_nova','dev_nova',?,'active','trial10',?,?,?,?)`)
    .run(APP, now, now + 10 * 86400000, now, now);
  f.db.exec(`CREATE TABLE novatube4k_devices(raw_mac TEXT PRIMARY KEY,mac TEXT UNIQUE,device_id TEXT UNIQUE,device_key_hash TEXT)`);
  f.db.prepare('INSERT INTO novatube4k_devices VALUES (?,?,?,?)').run('001122334455', MAC, 'dev_nova', 'a'.repeat(64));
  f.env = { DB: f.DB, ...configured };
  f.binding = { mac: MAC, device_id: 'dev_nova' };
  f.calls = []; f.sessions = new Map(); f.wakeups = 0;
  f.fetch = async (input, options) => {
    const url = new URL(input);
    assert.equal(url.origin, 'https://api.stripe.com');
    assert.equal(options.redirect, 'manual');
    assert.equal(options.headers['Stripe-Version'], '2026-10-28.endive');
    f.calls.push({ method: options.method, url: url.href, idempotency: options.headers['Idempotency-Key'] });
    if (options.method === 'POST') {
      assert.equal(url.pathname, '/v1/checkout/sessions');
      const form = new URLSearchParams(options.body);
      assert.equal(form.get('mode'), 'payment');
      assert.equal(form.get('adaptive_pricing[enabled]'), 'false');
      assert.equal(form.get('line_items[0][price_data][unit_amount]'), '999');
      assert.equal(form.get('line_items[0][price_data][currency]'), 'eur');
      assert.equal(form.has('subscription_data'), false);
      assert.equal(form.has('payment_intent_data[setup_future_usage]'), false);
      const orderId = form.get('client_reference_id');
      assert.equal(options.headers['Idempotency-Key'], orderId);
      const id = 'cs_test_' + orderId.replaceAll('_', '');
      const meta = Object.fromEntries(['order_id','app_id','device_id','license_id'].map(key => [key, form.get('metadata[' + key + ']')]));
      if (!f.sessions.has(id)) f.sessions.set(id, {
        id, object: 'checkout.session', mode: 'payment', livemode: false,
        amount_total: 999, currency: 'eur', payment_status: 'unpaid', status: 'open',
        expires_at: Number(form.get('expires_at')), client_reference_id: orderId, metadata: meta,
        url: 'https://checkout.stripe.com/c/pay/' + id,
      });
      return Response.json(f.sessions.get(id));
    }
    assert.equal(options.method, 'GET');
    assert.deepEqual(url.searchParams.getAll('expand[]'), ['line_items','payment_intent']);
    const session = f.sessions.get(url.pathname.split('/').at(-1));
    return session ? Response.json(session) : Response.json({}, { status: 404 });
  };
  f.deps = { fetch: f.fetch, notifyBox: async () => { f.wakeups++; } };
  return f;
}

async function create(f, input = {}) {
  const r = await createNovatubeCheckout(f.env, f.binding, input, f.deps);
  return { status: r.status, body: await r.json() };
}
function license(f) { return f.db.prepare("SELECT * FROM licenses WHERE id='lic_nova'").get(); }
function order(f) { return f.db.prepare('SELECT * FROM novatube4k_purchase_orders LIMIT 1').get(); }
function count(f, table) { return f.db.prepare('SELECT COUNT(*) n FROM ' + table).get().n; }
function markPaid(f) {
  const row = order(f), session = f.sessions.get(row.session_id);
  session.status = 'complete'; session.payment_status = 'paid';
  session.line_items = { has_more: false, data: [{ quantity: 1, amount_total: 999, currency: 'eur',
    price: { unit_amount: 999, currency: 'eur', type: 'one_time' } }] };
  session.payment_intent = { id: 'pi_' + row.id.replaceAll('_', ''), object: 'payment_intent',
    status: 'succeeded', currency: 'eur', amount: 999, amount_received: 999, livemode: false, metadata: { ...session.metadata } };
  return session;
}
function eventFor(session, overrides = {}) {
  return { id: 'evt_fixture123', object: 'event', type: 'checkout.session.completed', livemode: false,
    data: { object: { id: session.id, object: 'checkout.session' } }, ...overrides };
}
function signed(event, { timestamp = Math.floor(Date.now() / 1000), key = secret, raw, signature } = {}) {
  const body = raw ?? JSON.stringify(event);
  const hash = createHmac('sha256', key).update(timestamp + '.' + body).digest('hex');
  return new Request(WEBHOOK, { method: 'POST', body, headers: {
    'Content-Type': 'application/json', 'Stripe-Signature': signature ?? 't=' + timestamp + ',v1=' + hash,
  } });
}
async function hook(f, event, options = {}) {
  const r = await handleNovatubeStripeWebhook(signed(event, options), f.env, f.deps);
  return { status: r.status, body: await r.json() };
}

test('commerce fermé par défaut, sans durée inventée ni effet D1/réseau', async (t) => {
  const f = fixture(t); f.env = { DB: f.DB };
  assert.deepEqual(novatubeCommerceMetadata(f.env), { price_minor: 999, currency: 'EUR', auto_renew: false,
    license_duration: null, checkout_available: false, checkout_url: null });
  const before = license(f);
  assert.equal((await create(f)).status, 503);
  assert.equal(f.db.prepare("SELECT name FROM sqlite_master WHERE name='novatube4k_purchase_orders'").get(), undefined);
  assert.deepEqual(license(f), before); assert.equal(f.calls.length, 0);
});

test('configuration complète et cohérente obligatoire, durée explicite seulement', () => {
  assert.equal(novatubeCommerceMetadata(configured).checkout_available, true);
  assert.equal(novatubeCommerceMetadata(configured).license_duration, '365_days');
  for (const key of Object.keys(configured)) {
    const copy = { ...configured }; delete copy[key];
    assert.equal(novatubeCommerceMetadata(copy).checkout_available, false, key);
  }
  for (const value of ['', '0', '-1', '3661', '1.2', 'forever']) assert.equal(novatubeCommerceMetadata({ ...configured, NOVATUBE_PAID_DURATION: value }).checkout_available, false);
  for (const origin of ['http://example.com', 'https://localhost', 'https://127.0.0.1', 'https://owner:pass@example.com', 'https://example.com/path']) {
    assert.equal(novatubeCommerceMetadata({ ...configured, NOVATUBE_CHECKOUT_ORIGIN: origin }).checkout_available, false);
  }
  assert.equal(novatubeCommerceMetadata({ ...configured, NOVATUBE_STRIPE_MODE: 'live' }).checkout_available, false);
  assert.equal(novatubeCommerceMetadata({ ...configured, NOVATUBE_PAID_DURATION: 'lifetime' }).license_duration, 'lifetime');
});

test('Checkout crée une commande unique à 999 EUR sans modifier licence ou crédits', async (t) => {
  const f = fixture(t), before = license(f);
  const a = await create(f, { amount: 1, currency: 'USD', app_id: 'other', device_id: 'other', paid: true });
  const b = await create(f);
  assert.equal(a.status, 200); assert.deepEqual(b, a);
  assert.match(a.body.checkout_url, /^https:\/\/checkout\.stripe\.com\/c\/pay\//);
  assert.equal(a.body.price_minor, 999); assert.equal(a.body.currency, 'EUR');
  assert.equal(a.body.license_duration, '365_days'); assert.equal(a.body.license_duration, order(f).term);
  assert.equal(f.calls.length, 1); assert.equal(count(f, 'novatube4k_purchase_orders'), 1);
  assert.equal(count(f, 'payments'), 0); assert.equal(count(f, 'credit_ledger'), 0);
  assert.deepEqual(license(f), before); assert.equal(f.wakeups, 0);
});

test('deux ouvertures concurrentes réutilisent la même clé idempotente Stripe', async (t) => {
  const f = fixture(t, { jitterMs: 4 });
  const r = await Promise.all([create(f), create(f), create(f)]);
  assert.deepEqual(r.map(x => x.status), [200,200,200]);
  assert.equal(new Set(r.map(x => x.body.order_id)).size, 1);
  assert.equal(new Set(f.calls.filter(x => x.method === 'POST').map(x => x.idempotency)).size, 1);
  assert.equal(f.sessions.size, 1); assert.equal(count(f, 'payments'), 0);
});

test('réponse Stripe perdue : réessai même commande, aucun second achat', async (t) => {
  const f = fixture(t), actual = f.deps.fetch;
  let lost = true;
  f.deps.fetch = async (...args) => { const result = await actual(...args); if (lost) { lost = false; throw new Error('lost response'); } return result; };
  assert.equal((await create(f)).status, 503);
  assert.equal((await create(f)).status, 200);
  assert.equal(new Set(f.calls.map(x => x.idempotency)).size, 1);
  assert.equal(f.sessions.size, 1); assert.equal(count(f, 'payments'), 0);
});

test('redirection HTTP du prestataire refusée, aucune transmission de clé à un autre hôte', async (t) => {
  const f = fixture(t); let requests = 0;
  f.deps.fetch = async (url, options) => {
    requests++; assert.equal(new URL(url).hostname, 'api.stripe.com'); assert.equal(options.redirect, 'manual');
    return new Response(null, { status: 302, headers: { Location: 'https://untrusted.invalid/' } });
  };
  assert.equal((await create(f)).status, 503); assert.equal(requests, 1);
  assert.equal(count(f, 'payments'), 0); assert.equal(license(f).plan, 'trial10');
});

test('ancienne demande payée avec webhook retardé : réconcilier, jamais proposer un deuxième paiement', async (t) => {
  const f = fixture(t); await create(f); markPaid(f);
  f.db.prepare('UPDATE novatube4k_purchase_orders SET expires_at=?').run(Date.now() - 1);
  const r = await create(f);
  assert.equal(r.body.error, 'already_active');
  assert.equal(f.sessions.size, 1); assert.equal(count(f, 'payments'), 1);
  assert.equal(license(f).plan, 'custom');
});

test('nouvelle commande seulement après confirmation Stripe de l’expiration impayée', async (t) => {
  const f = fixture(t); await create(f);
  const first = order(f);
  f.db.prepare('UPDATE novatube4k_purchase_orders SET expires_at=?').run(Date.now() - 1);
  assert.equal((await create(f)).body.error, 'checkout_conflict');
  assert.equal(f.sessions.size, 1);
  f.sessions.get(first.session_id).status = 'expired';
  assert.equal((await create(f)).status, 200);
  assert.equal(f.sessions.size, 2); assert.equal(count(f, 'payments'), 0);
  assert.equal(f.db.prepare('SELECT state FROM novatube4k_purchase_orders WHERE id=?').get(first.id).state, 'expired');
});

test('licence déjà payée, gel, blocage ou autre appareil refusés avant tout appel Stripe', async (t) => {
  const f = fixture(t);
  f.db.prepare("UPDATE licenses SET plan='lifetime',expires_at=NULL").run();
  assert.equal((await create(f)).body.error, 'already_active');
  f.db.prepare("UPDATE licenses SET plan='trial10'").run();
  for (const state of ['frozen','banned']) {
    f.db.prepare('UPDATE devices SET block_status=?').run(state);
    assert.equal((await create(f)).body.error, 'checkout_not_allowed');
  }
  f.db.prepare('UPDATE devices SET block_status=NULL').run();
  f.db.prepare('UPDATE apps SET is_active=0 WHERE id=?').run(APP);
  assert.equal((await create(f)).body.error, 'checkout_not_allowed');
  f.db.prepare('UPDATE apps SET is_active=1 WHERE id=?').run(APP);
  f.binding.device_id = 'other_device';
  assert.equal((await create(f)).body.error, 'checkout_not_allowed');
  assert.equal(f.calls.length, 0); assert.equal(count(f, 'payments'), 0);
});

test('signature : corps brut, fenêtre cinq minutes, plusieurs v1 et champs inconnus', async () => {
  const now = 1900000000000, timestamp = Math.floor(now / 1000), body = '{"a": 1}';
  const hash = createHmac('sha256', secret).update(timestamp + '.' + body).digest('hex');
  assert.equal(await verifyNovatubeStripeSignature(body, 't=' + timestamp + ',v1=' + hash, secret, now), true);
  assert.equal(await verifyNovatubeStripeSignature(body, 'unknown=ignored,v1=' + '0'.repeat(64) + ',t=' + timestamp + ',v1=' + hash, secret, now), true);
  assert.equal(await verifyNovatubeStripeSignature('{"a":1}', 't=' + timestamp + ',v1=' + hash, secret, now), false);
  assert.equal(await verifyNovatubeStripeSignature(body, 't=' + timestamp + ',v1=' + hash, secret, now + 300001), false);
  assert.equal(await verifyNovatubeStripeSignature(body, 't=' + timestamp + ',v1=' + hash, secret, now - 300001), false);
  assert.equal(await verifyNovatubeStripeSignature(body, 't=' + timestamp + ',t=' + timestamp + ',v1=' + hash, secret, now), false);
});

test('paiement confirmé relu : active seulement NovaTube, une fois, sans renouvellement automatique', async (t) => {
  const f = fixture(t); await create(f); const session = markPaid(f);
  const before = Date.now();
  const r = await hook(f, eventFor(session));
  assert.equal(r.status, 200); assert.equal(r.body.activated, true);
  assert.equal(license(f).status, 'active'); assert.equal(license(f).plan, 'custom');
  assert.equal(license(f).auto_renew, 0);
  assert.ok(license(f).expires_at >= before + 365 * 86400000);
  assert.equal(count(f, 'payments'), 1); assert.equal(count(f, 'audit_logs'), 1);
  assert.equal(count(f, 'credit_ledger'), 0); assert.equal(count(f, 'novatube4k_purchase_guard'), 0);
  assert.equal(f.wakeups, 1);
  const replay = await hook(f, eventFor(session, { id: 'evt_otherdelivery' }));
  assert.equal(replay.body.duplicate, true);
  assert.equal(count(f, 'payments'), 1); assert.equal(count(f, 'audit_logs'), 1); assert.equal(f.wakeups, 1);
});

test('mode test ne peut pas délivrer un paiement live et signature inconnue ne lit pas Stripe', async (t) => {
  const f = fixture(t); await create(f); const session = markPaid(f), calls = f.calls.length;
  assert.equal((await hook(f, eventFor(session, { livemode: true }))).status, 400);
  assert.equal((await hook(f, eventFor(session), { key: secret + 'wrong' })).status, 400);
  assert.equal(f.calls.length, calls); assert.equal(count(f, 'payments'), 0);
});

test('vérifie somme, devise, produit, appareil, licence, ligne et PaymentIntent', async (t) => {
  const f = fixture(t); await create(f); const paid = structuredClone(markPaid(f));
  const mutations = [
    s => s.amount_total = 998, s => s.currency = 'usd', s => s.livemode = true,
    s => s.mode = 'subscription', s => s.metadata.app_id = 'app_7motion',
    s => s.metadata.device_id = 'other', s => s.metadata.license_id = 'other',
    s => s.metadata.order_id = 'other', s => s.client_reference_id = 'other',
    s => s.line_items.data[0].quantity = 2, s => s.line_items.data[0].price.unit_amount = 1,
    s => s.line_items.has_more = true, s => s.payment_intent.status = 'processing',
    s => s.payment_intent.amount_received = 1, s => s.payment_intent.amount = 1000, s => s.payment_intent.metadata.device_id = 'other',
    s => s.payment_intent.livemode = true,
  ];
  for (const mutate of mutations) {
    const session = structuredClone(paid); mutate(session); f.sessions.set(session.id, session);
    assert.equal((await hook(f, eventFor(session))).status, 409);
    assert.equal(count(f, 'payments'), 0); assert.equal(license(f).plan, 'trial10');
  }
});

test('completed encore impayé : aucune activation ; async paid confirmé déclenche ensuite', async (t) => {
  const f = fixture(t); await create(f); const row = order(f), session = f.sessions.get(row.session_id);
  session.status = 'complete';
  assert.equal((await hook(f, eventFor(session))).body.pending, true);
  assert.equal(count(f, 'payments'), 0); assert.equal(license(f).plan, 'trial10');
  markPaid(f);
  assert.equal((await hook(f, eventFor(session, { type: 'checkout.session.async_payment_succeeded' }))).body.activated, true);
});

test('commande inconnue signée ignorée, aucun faux succès et aucune activation', async (t) => {
  const f = fixture(t);
  const r = await hook(f, eventFor({ id: 'cs_test_unknown' }));
  assert.equal(r.status, 200); assert.equal(r.body.ignored, true);
  assert.equal(f.calls.length, 0); assert.equal(count(f, 'payments'), 0);
});

test('panne transactionnelle annule paiement, licence, audit ; rejeu restaure exactement une fois', async (t) => {
  const f = fixture(t); await create(f); const session = markPaid(f), before = license(f);
  f.faults.add({ match: /INSERT INTO payments/, times: 1 });
  assert.equal((await hook(f, eventFor(session))).status, 503);
  assert.deepEqual(license(f), before); assert.equal(order(f).state, 'pending');
  assert.equal(count(f, 'payments'), 0); assert.equal(count(f, 'audit_logs'), 0);
  assert.equal((await hook(f, eventFor(session))).body.activated, true);
  assert.equal(count(f, 'payments'), 1);
});

test('webhooks concurrents : paiement/licence/audit engagés une seule fois', async (t) => {
  const f = fixture(t, { jitterMs: 4 }); await create(f); const session = markPaid(f);
  const result = await Promise.all([hook(f, eventFor(session)), hook(f, eventFor(session)), hook(f, eventFor(session))]);
  assert.deepEqual(result.map(x => x.status), [200,200,200]);
  assert.equal(result.filter(x => x.body.activated).length, 1);
  assert.equal(count(f, 'payments'), 1); assert.equal(count(f, 'audit_logs'), 1);
});

test('licence modifiée par administration pendant Checkout : vérification manuelle, aucun écrasement', async (t) => {
  const f = fixture(t); await create(f); const session = markPaid(f);
  f.db.prepare("UPDATE licenses SET plan='yearly',expires_at=?,updated_at=?").run(Date.now() + 500 * 86400000, Date.now() + 1);
  const before = license(f), r = await hook(f, eventFor(session));
  assert.equal(r.status, 200); assert.equal(r.body.review, true);
  assert.deepEqual(license(f), before); assert.equal(count(f, 'payments'), 1);
  assert.equal(order(f).state, 'review');
  assert.equal(f.db.prepare('SELECT status FROM payments').get().status, 'succeeded');
  assert.equal((await hook(f, eventFor(session))).body.review, true);
  assert.equal(count(f, 'payments'), 1);
});

test('gel concurrent juste avant transaction : garde SQL annule toute activation', async (t) => {
  const f = fixture(t); await create(f); const session = markPaid(f), batch = f.env.DB.batch;
  f.env.DB.batch = async statements => {
    if (statements.some(s => /UPDATE novatube4k_purchase_orders SET state='paid'/.test(s.sql))) {
      f.db.prepare("UPDATE devices SET block_status='frozen'").run();
    }
    return batch(statements);
  };
  const before = license(f), r = await hook(f, eventFor(session));
  assert.equal(r.status, 200); assert.equal(r.body.review, true);
  assert.deepEqual(license(f), before); assert.equal(count(f, 'payments'), 1);
  assert.equal(count(f, 'novatube4k_purchase_guard'), 0);
});

test('durée figée dans la commande, choix à vie uniquement si explicite', async (t) => {
  const f = fixture(t); f.env.NOVATUBE_PAID_DURATION = 'lifetime';
  const checkout = await create(f); const session = markPaid(f);
  assert.equal(checkout.body.license_duration, 'lifetime'); assert.equal(checkout.body.license_duration, order(f).term);
  f.env.NOVATUBE_PAID_DURATION = '30';
  assert.equal((await hook(f, eventFor(session))).body.activated, true);
  assert.equal(license(f).plan, 'lifetime'); assert.equal(license(f).expires_at, null);
});

test('retour navigateur neutre : aucun état payé ne dépend des paramètres', async (t) => {
  const f = fixture(t), before = license(f);
  const page = handleNovatubePaymentReturn(new Request('https://fixture.test/novatube/payment-return?paid=true&mac=' + MAC));
  assert.equal(page.status, 200);
  assert.match(await page.text(), /après confirmation du paiement/);
  assert.deepEqual(license(f), before); assert.equal(count(f, 'payments'), 0);
  assert.equal(handleNovatubePaymentReturn(new Request('https://fixture.test/unknown')), null);
});
