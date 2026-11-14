// Paiement unique de l'application NovaTube. Aucune chaîne n'est vendue ici.
// Ce module reste fermé tant que le marchand et la durée ne sont pas configurés.
// Le retour navigateur ne donne jamais une licence : seul un paiement Stripe
// relu côté serveur et rattaché à notre commande peut activer cette application.
const APP = 'app_novatube4k';
const PACKAGE = 'com.manthefew';
const PRICE = 999;
const CURRENCY = 'EUR';
const WEBHOOK = '/api/novatube4k/payments/stripe-webhook';
const STRIPE_API = 'https://api.stripe.com/v1/checkout/sessions';
const STRIPE_VERSION = '2026-10-28.endive';
const MAX_BODY = 256 * 1024;
const WINDOW_MS = 5 * 60_000;
const ORDER_MS = 35 * 60_000;
const encoder = new TextEncoder();
const ready = new WeakSet();

function response(body, status = 200) {
  return Response.json(body, { status, headers: {
    'Cache-Control': 'no-store, private', 'X-Content-Type-Options': 'nosniff',
  } });
}
function failure(error, message, status = 409) { return response({ ok: false, error, message }, status); }

function stripeCredentials(env) {
  const mode = env?.NOVATUBE_STRIPE_MODE;
  const key = env?.NOVATUBE_STRIPE_SECRET_KEY;
  const secret = env?.NOVATUBE_STRIPE_WEBHOOK_SECRET;
  if (!['test', 'live'].includes(mode) || typeof key !== 'string' || typeof secret !== 'string'
    || !new RegExp('^(?:sk|rk)_' + mode + '_[A-Za-z0-9]{16,}$').test(key)
    || !/^whsec_[A-Za-z0-9]{16,}$/.test(secret)) return null;
  return { mode, key, secret, live: mode === 'live' };
}

function commercialConfig(env) {
  const stripe = stripeCredentials(env);
  const value = String(env?.NOVATUBE_PAID_DURATION || '');
  const days = /^\d{1,4}$/.test(value) ? Number(value) : null;
  if (!stripe || env?.NOVATUBE_COMMERCE_ENABLED !== '1'
    || !(value === 'lifetime' || (Number.isInteger(days) && days >= 1 && days <= 3660))) return null;
  let origin;
  try {
    const url = new URL(env.NOVATUBE_CHECKOUT_ORIGIN);
    if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash
      || url.pathname !== '/' || !/^[a-z0-9.-]+\.[a-z]{2,}$/i.test(url.hostname)
      || /(?:^|\.)(?:localhost|local|invalid|test|example)$/.test(url.hostname)) return null;
    origin = url.origin;
  } catch { return null; }
  return { ...stripe, days: value === 'lifetime' ? null : days, term: value === 'lifetime' ? 'lifetime' : days + '_days', origin };
}

export function novatubeCommerceMetadata(env) {
  const config = commercialConfig(env);
  return { price_minor: PRICE, currency: CURRENCY, auto_renew: false,
    license_duration: config?.term || null, checkout_available: !!config, checkout_url: null };
}

export async function ensureNovatubeCommerceSchema(env) {
  if (ready.has(env.DB)) return;
  await env.DB.batch([
    env.DB.prepare(`CREATE TABLE IF NOT EXISTS novatube4k_purchase_orders (
      id TEXT PRIMARY KEY, app_id TEXT NOT NULL, mac TEXT NOT NULL,
      device_id TEXT NOT NULL, customer_id TEXT NOT NULL, license_id TEXT NOT NULL,
      amount_minor INTEGER NOT NULL CHECK(amount_minor = 999), currency TEXT NOT NULL CHECK(currency = 'EUR'),
      duration_days INTEGER, term TEXT NOT NULL, live_mode INTEGER NOT NULL CHECK(live_mode IN (0,1)),
      state TEXT NOT NULL CHECK(state IN ('pending','expired','paid','review')),
      session_id TEXT UNIQUE, checkout_url TEXT, payment_intent TEXT UNIQUE,
      license_status TEXT NOT NULL, license_plan TEXT NOT NULL, license_expires_at INTEGER,
      license_updated_at INTEGER NOT NULL, created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL,
      paid_at INTEGER, review_reason TEXT,
      CHECK((term='lifetime' AND duration_days IS NULL) OR (duration_days BETWEEN 1 AND 3660))
    )`),
    env.DB.prepare(`CREATE UNIQUE INDEX IF NOT EXISTS uq_novatube4k_pending_purchase
      ON novatube4k_purchase_orders(license_id) WHERE state='pending'`),
    env.DB.prepare(`CREATE TABLE IF NOT EXISTS novatube4k_purchase_guard (
      id TEXT PRIMARY KEY, valid INTEGER NOT NULL CHECK(valid=1)
    )`),
  ]);
  ready.add(env.DB);
}

async function licenseFor(env, binding) {
  return env.DB.prepare(`SELECT l.*, d.mac, d.block_status, a.is_active AS app_active
    FROM licenses l JOIN devices d ON d.id=l.device_id AND d.mac=?
    JOIN apps a ON a.id=l.app_id AND a.package_name=?
    JOIN novatube4k_devices n ON n.device_id=d.id AND n.mac=d.mac
    WHERE l.app_id=? AND l.device_id=? LIMIT 1`)
    .bind(binding.mac, PACKAGE, APP, binding.device_id).first();
}

function eligible(row, now) {
  if (!row || row.app_active !== 1 || ['banned','frozen'].includes(row.block_status)
    || ['banned','frozen'].includes(row.status)) return 'checkout_not_allowed';
  if (row.status === 'active' && !/^trial(?:\d+)?$/.test(row.plan)
    && (row.expires_at === null || Number(row.expires_at) > now)) return 'already_active';
  if (!['inactive','active','expired','pending'].includes(row.status)) return 'checkout_not_allowed';
  return null;
}

async function stripeCall(config, path, options = {}, deps = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10000);
  try {
    const headers = { Authorization: 'Bearer ' + config.key, 'Stripe-Version': STRIPE_VERSION, ...options.headers };
    // Workers accepte « manual », pas « error ». Un 3xx est refusé ci-dessous;
    // la clé marchande n'est donc jamais transmise à une URL de redirection.
    const result = await (deps.fetch || fetch)(path, { ...options, headers, signal: controller.signal, redirect: 'manual' });
    if (!result.ok) throw new Error('stripe_unavailable');
    const text = await result.text();
    if (text.length > MAX_BODY) throw new Error('stripe_unavailable');
    return JSON.parse(text);
  } finally { clearTimeout(timeout); }
}

function safeCheckoutUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && url.hostname === 'checkout.stripe.com' && !url.username
      && !url.password && (!url.port || url.port === '443') && url.pathname.startsWith('/c/pay/') ? url.href : null;
  } catch { return null; }
}

function checkoutReply(order) {
  return response({ ok: true, order_id: order.id, checkout_url: order.checkout_url,
    expires_at: order.expires_at, price_minor: PRICE, currency: CURRENCY, license_duration: order.term });
}

/** Appelé uniquement après le garde raw_mac + X-Device-Key du dispatcher. */
export async function createNovatubeCheckout(env, binding, input, deps = {}) {
  const config = commercialConfig(env);
  if (!config) return failure('checkout_unavailable', 'Le paiement en ligne est momentanément indisponible. Contactez votre assistance.', 503);
  if (!binding || !/^MK(?::[0-9A-F]{2}){5}$/.test(binding.mac || '') || !binding.device_id) {
    return failure('checkout_not_allowed', 'Cette installation doit être vérifiée.', 403);
  }
  const now = Date.now();
  const license = await licenseFor(env, binding);
  const rejected = eligible(license, now);
  if (rejected) return failure(rejected, rejected === 'already_active'
    ? 'Cette application est déjà activée.' : 'L’activation de cet appareil nécessite votre assistance.');
  await ensureNovatubeCommerceSchema(env);
  const review = await env.DB.prepare("SELECT id FROM novatube4k_purchase_orders WHERE license_id=? AND state='review' LIMIT 1")
    .bind(license.id).first();
  if (review) return failure('checkout_review_required', 'Un paiement est en cours de vérification. Contactez votre assistance.');
  const pending = await env.DB.prepare("SELECT * FROM novatube4k_purchase_orders WHERE license_id=? AND state='pending' LIMIT 1")
    .bind(license.id).first();
  if (pending && pending.expires_at <= now) {
    // Une notification de paiement peut être en retard. Avant d'ouvrir une
    // autre commande, vérifier que Stripe considère vraiment l'ancienne
    // session expirée et impayée. Une panne/ambiguïté ne crée pas un second débit.
    if (!pending.session_id || pending.live_mode !== Number(config.live)) {
      return failure('checkout_conflict', 'Une ancienne demande nécessite une vérification. Contactez votre assistance.');
    }
    let prior;
    try {
      prior = await stripeCall(config, STRIPE_API + '/' + encodeURIComponent(pending.session_id)
        + '?expand[]=line_items&expand[]=payment_intent', { method: 'GET' }, deps);
    } catch { return failure('checkout_unavailable', 'La précédente demande est encore en cours de vérification.', 503); }
    if (sessionMatchesOrder(prior, pending, true)) {
      const confirmed = await fulfill(env, pending, prior, { id: null }, deps);
      return failure(confirmed.review ? 'checkout_review_required' : 'already_active', confirmed.review
        ? 'Le paiement a été reçu et nécessite une vérification par votre assistance.'
        : 'Le paiement a été confirmé. Relisez l’état de votre application.');
    }
    if (!sessionMatchesOrder(prior, pending, false) || prior.status !== 'expired') {
      return failure('checkout_conflict', 'La précédente demande est encore en cours de vérification.');
    }
    await env.DB.prepare("UPDATE novatube4k_purchase_orders SET state='expired' WHERE id=? AND state='pending' AND paid_at IS NULL")
      .bind(pending.id).run();
  }
  // Une contrainte unique interdit deux commandes ouvertes pour la même licence.
  // Le même identifiant Stripe est réutilisé après une réponse réseau perdue.
  const id = 'nova_' + crypto.randomUUID().replace(/-/g, '');
  await env.DB.prepare(`INSERT OR IGNORE INTO novatube4k_purchase_orders
    (id,app_id,mac,device_id,customer_id,license_id,amount_minor,currency,duration_days,term,live_mode,
     state,license_status,license_plan,license_expires_at,license_updated_at,created_at,expires_at)
    VALUES (?,?,?,?,?,?,999,'EUR',?,?,?,'pending',?,?,?,?,?,?)`)
    .bind(id, APP, binding.mac, binding.device_id, license.customer_id, license.id, config.days, config.term,
      config.live ? 1 : 0, license.status, license.plan, license.expires_at, license.updated_at, now, now + ORDER_MS).run();
  let order = await env.DB.prepare("SELECT * FROM novatube4k_purchase_orders WHERE license_id=? AND state='pending' LIMIT 1")
    .bind(license.id).first();
  if (!order || order.app_id !== APP || order.device_id !== binding.device_id || order.mac !== binding.mac
    || order.live_mode !== Number(config.live) || order.term !== config.term) {
    return failure('checkout_conflict', 'Une demande existe déjà. Réessayez après son expiration.');
  }
  if (order.session_id && safeCheckoutUrl(order.checkout_url)) return checkoutReply(order);
  const form = new URLSearchParams({
    mode: 'payment', ui_mode: 'hosted_page', locale: 'fr',
    'adaptive_pricing[enabled]': 'false',
    client_reference_id: order.id,
    success_url: config.origin + '/novatube/payment-return',
    cancel_url: config.origin + '/novatube/payment-cancel',
    expires_at: String(Math.floor(order.expires_at / 1000)),
    'payment_method_types[0]': 'card',
    'line_items[0][quantity]': '1',
    'line_items[0][price_data][currency]': 'eur',
    'line_items[0][price_data][unit_amount]': String(PRICE),
    'line_items[0][price_data][product_data][name]': 'NovaTube — activation ' + (order.duration_days === null ? 'à vie' : order.duration_days + ' jours'),
    'line_items[0][price_data][product_data][description]': 'Application de lecture. Aucun contenu ni abonnement TV inclus. Paiement unique.',
  });
  for (const [key,value] of Object.entries({ order_id: order.id, app_id: APP, device_id: order.device_id, license_id: order.license_id })) {
    form.set('metadata[' + key + ']', value);
    form.set('payment_intent_data[metadata][' + key + ']', value);
  }
  let session;
  try {
    session = await stripeCall(config, STRIPE_API, { method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Idempotency-Key': order.id }, body: form.toString() }, deps);
  } catch { return failure('checkout_unavailable', 'Le paiement n’a pas pu être ouvert. Aucun accès payant n’a été confirmé.', 503); }
  const checkoutUrl = safeCheckoutUrl(session.url);
  if (!sessionMatchesOrder(session, order, false) || !checkoutUrl || session.status !== 'open'
    || session.expires_at * 1000 <= Date.now() || session.expires_at * 1000 > order.expires_at + 1000) {
    return failure('checkout_unavailable', 'Le paiement n’a pas pu être ouvert. Contactez votre assistance.', 503);
  }
  await env.DB.prepare(`UPDATE novatube4k_purchase_orders SET session_id=?,checkout_url=?,expires_at=?
    WHERE id=? AND state='pending' AND (session_id IS NULL OR session_id=?)`)
    .bind(session.id, checkoutUrl, session.expires_at * 1000, order.id, session.id).run();
  order = await env.DB.prepare('SELECT * FROM novatube4k_purchase_orders WHERE id=?').bind(order.id).first();
  if (order.state !== 'pending' || order.session_id !== session.id || !safeCheckoutUrl(order.checkout_url)) {
    return failure('checkout_conflict', 'La demande de paiement a changé. Relisez l’état de votre application.');
  }
  return checkoutReply(order);
}

function sessionMatchesOrder(session, order, paid) {
  if (!session || !new RegExp('^cs_' + (order.live_mode ? 'live' : 'test') + '_[A-Za-z0-9]+$').test(session.id || '')
    || (order.session_id && session.id !== order.session_id) || session.object !== 'checkout.session'
    || session.mode !== 'payment' || session.livemode !== !!order.live_mode
    || session.currency !== 'eur' || session.amount_total !== PRICE
    || session.client_reference_id !== order.id || session.metadata?.order_id !== order.id
    || session.metadata?.app_id !== APP || session.metadata?.device_id !== order.device_id
    || session.metadata?.license_id !== order.license_id) return false;
  if (!paid) return session.payment_status === 'unpaid';
  const lines = session.line_items?.data;
  const item = lines?.[0];
  const intent = session.payment_intent;
  return session.status === 'complete' && session.payment_status === 'paid'
    && Array.isArray(lines) && lines.length === 1 && session.line_items.has_more === false
    && item.quantity === 1 && item.amount_total === PRICE && item.currency === 'eur'
    && item.price?.unit_amount === PRICE && item.price?.currency === 'eur' && item.price?.type === 'one_time'
    && intent?.object === 'payment_intent' && /^pi_[A-Za-z0-9]+$/.test(intent.id || '')
    && intent.status === 'succeeded' && intent.currency === 'eur' && intent.amount === PRICE && intent.amount_received === PRICE
    && intent.livemode === !!order.live_mode && intent.metadata?.order_id === order.id
    && intent.metadata?.app_id === APP && intent.metadata?.device_id === order.device_id
    && intent.metadata?.license_id === order.license_id;
}

async function boundedBody(request) {
  const reader = request.body?.getReader();
  if (!reader) return null;
  const chunks = []; let size = 0;
  try {
    while (true) {
      const { done,value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_BODY) { await reader.cancel(); return null; }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
}

export async function verifyNovatubeStripeSignature(body, signature, secret, now = Date.now()) {
  if (typeof body !== 'string' || typeof signature !== 'string' || signature.length > 4096) return false;
  const entries = signature.split(',').map(part => part.trim().split('='));
  const timestamps = entries.filter(([key]) => key === 't').map(([,value]) => value);
  if (timestamps.length !== 1 || !/^\d{1,12}$/.test(timestamps[0])) return false;
  const timestamp = Number(timestamps[0]) * 1000;
  if (!Number.isSafeInteger(timestamp) || Math.abs(now - timestamp) > WINDOW_MS) return false;
  const candidates = entries.filter(([key,value]) => key === 'v1' && /^[a-f0-9]{64}$/i.test(value || ''));
  if (!candidates.length || candidates.length > 8) return false;
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
  const signed = encoder.encode(timestamps[0] + '.' + body);
  for (const [,value] of candidates) {
    const bytes = Uint8Array.from(value.match(/../g), hex => parseInt(hex, 16));
    if (await crypto.subtle.verify('HMAC', key, bytes, signed)) return true;
  }
  return false;
}

async function markReview(env, order, reason, session, event) {
  // L'encaissement existe même si une action administrative empêche de donner
  // l'accès. Le journal conserve donc le paiement réel, sans activer la licence.
  const now = Date.now(), guard = crypto.randomUUID(), payment = 'pay_' + order.id;
  try {
    await env.DB.batch([
      env.DB.prepare(`UPDATE novatube4k_purchase_orders SET state='review',review_reason=?,paid_at=?,payment_intent=?
        WHERE id=? AND state IN ('pending','expired') AND session_id=? AND paid_at IS NULL`)
        .bind(reason, now, session.payment_intent.id, order.id, session.id),
      env.DB.prepare('INSERT INTO novatube4k_purchase_guard(id,valid) SELECT ?,CASE WHEN changes()=1 THEN 1 ELSE 0 END').bind(guard),
      env.DB.prepare(`INSERT INTO payments(id,customer_id,amount_cents,currency,gateway,gateway_payment_id,status,license_id,metadata_json,created_at,paid_at)
        VALUES (?,(SELECT id FROM customers WHERE id=?),999,'EUR','stripe',?,'succeeded',(SELECT id FROM licenses WHERE id=?),?,?,?)`)
        .bind(payment, order.customer_id, session.payment_intent.id, order.license_id,
          JSON.stringify({ app_id: APP, order_id: order.id, session_id: session.id, event_id: event.id,
            fulfillment: 'review', reason }), now, now),
      env.DB.prepare(`INSERT INTO audit_logs(id,actor_type,actor_id,action,target_type,target_id,after_json,created_at)
        VALUES (?,'system','novatube_stripe','novatube.payment.review','payment',?,?,?)`)
        .bind('aud_' + crypto.randomUUID().replace(/-/g, ''), payment,
          JSON.stringify({ app_id: APP, order_id: order.id, reason, amount_minor: PRICE, currency: CURRENCY }), now),
      env.DB.prepare('DELETE FROM novatube4k_purchase_guard WHERE id=?').bind(guard),
    ]);
    return 'review';
  } catch (error) {
    const row = await env.DB.prepare('SELECT state FROM novatube4k_purchase_orders WHERE id=?').bind(order.id).first();
    if (['paid','review'].includes(row?.state)) return row.state;
    throw error;
  }
}

async function fulfill(env, order, session, event, deps) {
  if (order.state === 'paid') return { duplicate: true };
  if (order.state === 'review') return { review: true };
  const now = Date.now();
  const license = await licenseFor(env, order);
  const conflict = !license || eligible(license, now) || license.id !== order.license_id
    || license.customer_id !== order.customer_id || license.status !== order.license_status
    || license.plan !== order.license_plan || license.expires_at !== order.license_expires_at
    || license.updated_at !== order.license_updated_at;
  if (conflict) {
    const state = await markReview(env, order, 'license_changed', session, event);
    return state === 'paid' ? { duplicate: true } : { review: true };
  }
  // La durée de la commande est figée avant le paiement. Une modification de
  // configuration ultérieure ne raccourcit pas ce que le client a acheté.
  const expires = order.duration_days === null ? null : now + order.duration_days * 86400000;
  const plan = order.duration_days === null ? 'lifetime' : 'custom';
  const payment = 'pay_' + order.id;
  const guard = crypto.randomUUID();
  const before = JSON.stringify({ status: license.status, plan: license.plan, expires_at: license.expires_at });
  const after = JSON.stringify({ status: 'active', plan, expires_at: expires, app_id: APP,
    payment_id: payment, order_id: order.id, amount_minor: PRICE, currency: CURRENCY });
  try {
    await env.DB.batch([
      env.DB.prepare(`UPDATE novatube4k_purchase_orders SET state='paid',paid_at=?,payment_intent=?
        WHERE id=? AND state IN ('pending','expired') AND session_id=? AND paid_at IS NULL`)
        .bind(now, session.payment_intent.id, order.id, session.id),
      env.DB.prepare('INSERT INTO novatube4k_purchase_guard(id,valid) SELECT ?,CASE WHEN changes()=1 THEN 1 ELSE 0 END').bind(guard + 'o'),
      env.DB.prepare(`UPDATE licenses SET status='active',plan=?,started_at=?,expires_at=?,auto_renew=0,payment_id=?,updated_at=?
        WHERE id=? AND app_id=? AND device_id=? AND customer_id=? AND status=? AND plan=? AND expires_at IS ? AND updated_at=?
        AND EXISTS (SELECT 1 FROM devices d JOIN apps a ON a.id=? AND a.package_name=?
          JOIN novatube4k_devices n ON n.device_id=d.id AND n.mac=d.mac
          WHERE d.id=? AND d.mac=? AND COALESCE(d.block_status,'') NOT IN ('banned','frozen') AND a.is_active=1)`)
        .bind(plan, now, expires, payment, now, order.license_id, APP, order.device_id, order.customer_id,
          order.license_status, order.license_plan, order.license_expires_at, order.license_updated_at,
          APP, PACKAGE, order.device_id, order.mac),
      env.DB.prepare('INSERT INTO novatube4k_purchase_guard(id,valid) SELECT ?,CASE WHEN changes()=1 THEN 1 ELSE 0 END').bind(guard + 'l'),
      env.DB.prepare(`INSERT INTO payments(id,customer_id,amount_cents,currency,gateway,gateway_payment_id,status,license_id,metadata_json,created_at,paid_at)
        VALUES (?,?,999,'EUR','stripe',?,'succeeded',?,?,?,?)`)
        .bind(payment, order.customer_id, session.payment_intent.id, order.license_id,
          JSON.stringify({ app_id: APP, order_id: order.id, session_id: session.id, event_id: event.id }), now, now),
      env.DB.prepare(`INSERT INTO audit_logs(id,actor_type,actor_id,action,target_type,target_id,before_json,after_json,created_at)
        VALUES (?,'system','novatube_stripe','novatube.payment.activate','license',?,?,?,?)`)
        .bind('aud_' + crypto.randomUUID().replace(/-/g, ''), order.license_id, before, after, now),
      env.DB.prepare('DELETE FROM novatube4k_purchase_guard WHERE id IN (?,?)').bind(guard + 'o', guard + 'l'),
    ]);
  } catch (error) {
    const current = await env.DB.prepare('SELECT state FROM novatube4k_purchase_orders WHERE id=?').bind(order.id).first();
    if (current?.state === 'paid') return { duplicate: true };
    if (/CHECK constraint failed/i.test(String(error?.message || ''))) {
      const state = await markReview(env, order, 'license_changed', session, event);
      return state === 'paid' ? { duplicate: true } : { review: true };
    }
    throw new Error('payment_storage_unavailable');
  }
  if (typeof deps.notifyBox === 'function') {
    // Le paiement est déjà engagé. Un réveil perdu n'annule pas la transaction;
    // la lecture régulière de state retrouvera l'activation.
    try { await deps.notifyBox(env, order.mac, 'license', {}); } catch { /* lecture régulière */ }
  }
  return { activated: true };
}

/** Raccorder avant le dispatcher d'identité, uniquement à ce chemin exact. */
export async function handleNovatubeStripeWebhook(request, env, deps = {}) {
  if (new URL(request.url).pathname !== WEBHOOK) return null;
  if (request.method !== 'POST') return failure('method_not_allowed', 'Méthode non autorisée.', 405);
  const config = stripeCredentials(env);
  if (!config) return failure('payment_unavailable', 'Service de paiement indisponible.', 503);
  let raw;
  try { raw = await boundedBody(request); } catch { raw = null; }
  if (raw === null || !await verifyNovatubeStripeSignature(raw, request.headers.get('Stripe-Signature'), config.secret)) {
    return failure('invalid_signature', 'Signature invalide.', 400);
  }
  let event;
  try { event = JSON.parse(raw); } catch { return failure('invalid_event', 'Événement invalide.', 400); }
  if (!/^evt_[A-Za-z0-9]+$/.test(event?.id || '') || event.object !== 'event' || event.livemode !== config.live) {
    return failure('invalid_event', 'Événement invalide.', 400);
  }
  if (!['checkout.session.completed','checkout.session.async_payment_succeeded'].includes(event.type)) {
    return response({ received: true, ignored: true });
  }
  const candidate = event.data?.object;
  if (candidate?.object !== 'checkout.session' || !/^cs_(?:test|live)_[A-Za-z0-9]+$/.test(candidate.id || '')) {
    return failure('invalid_event', 'Événement invalide.', 400);
  }
  try {
    await ensureNovatubeCommerceSchema(env);
    const order = await env.DB.prepare('SELECT * FROM novatube4k_purchase_orders WHERE session_id=? LIMIT 1').bind(candidate.id).first();
    if (!order) return response({ received: true, ignored: true });
    if (order.app_id !== APP || order.live_mode !== Number(config.live)) return failure('invalid_event', 'Événement invalide.', 400);
    const session = await stripeCall(config, STRIPE_API + '/' + encodeURIComponent(candidate.id)
      + '?expand[]=line_items&expand[]=payment_intent', { method: 'GET' }, deps);
    if (session.payment_status === 'unpaid' && sessionMatchesOrder(session, order, false)) {
      return response({ received: true, pending: true });
    }
    if (!sessionMatchesOrder(session, order, true)) return failure('payment_mismatch', 'Le paiement ne correspond pas à la commande.', 409);
    const result = await fulfill(env, order, session, event, deps);
    return response({ received: true, ...result });
  } catch { return failure('payment_unavailable', 'Le paiement sera vérifié de nouveau.', 503); }
}

/** Pages neutres : aucun paramètre du navigateur ne peut activer une licence. */
export function handleNovatubePaymentReturn(request) {
  const path = new URL(request.url).pathname;
  if (!['/novatube/payment-return','/novatube/payment-cancel'].includes(path)) return null;
  if (request.method !== 'GET') return failure('method_not_allowed', 'Méthode non autorisée.', 405);
  const canceled = path.endsWith('-cancel');
  const title = canceled ? 'Paiement interrompu' : 'Vérification du paiement';
  const text = canceled ? 'Le paiement n’a pas été confirmé. Vous pouvez revenir dans NovaTube.'
    : 'NovaTube vérifie le paiement. Retournez dans l’application : l’activation apparaît après confirmation du paiement.';
  return new Response('<!doctype html><html lang="fr"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
    + '<title>NovaTube — ' + title + '</title><style>body{margin:0;background:#080d19;color:#e9eef9;font:18px system-ui;display:grid;min-height:100vh;place-items:center}'
    + 'main{max-width:40rem;padding:2rem}h1{font-size:2rem}p{line-height:1.7;color:#c1cbe0}</style><main><strong>NovaTube</strong><h1>'
    + title + '</h1><p>' + text + '</p></main></html>', { headers: {
      'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store',
      'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
      'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff',
    } });
}
