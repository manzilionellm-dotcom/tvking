// Ce Worker ne possède aucune route d'envoi publique. Son cron traite uniquement
// les événements persistés et les abonnements explicitement acceptés par le
// propriétaire du panneau. Il ne modifie jamais les licences ou les appareils.
import { verifyVapidConfig, sendWebPush } from './web-push.js';
import { collectConfirmedOrderFailures, panelAlertPayload } from '../panel-alerts.js';

const HOUR = 3600000;
const MAX_ATTEMPTS = 6;
const BATCH_SIZE = 20;
const LEASE_MS = 120000;

// Le timestamp initial reste injectable pour les fixtures. En production,
// l'horloge avance pendant les attentes D1, le chiffrement et les lots réseau.
// Un recul de l'horloge ne prolonge jamais une session déjà expirée.
function dispatchClock(initial, suppliedClock) {
  if (!Number.isSafeInteger(initial) || initial <= 0
      || (suppliedClock != null && typeof suppliedClock !== 'function')) {
    throw new Error('dispatch_clock_invalid');
  }
  const started = performance.now();
  let last = initial;
  return () => {
    const value = suppliedClock ? suppliedClock() : initial + Math.max(0, Math.floor(performance.now() - started));
    if (!Number.isSafeInteger(value) || value <= 0) throw new Error('dispatch_clock_invalid');
    last = Math.max(last, value);
    return last;
  };
}

// Le contrôle du compte ET de la session est répété juste avant chaque envoi.
// Les mots de passe historiques peuvent avoir un timestamp en secondes.
const ELIGIBLE = `
  s.enabled = 1 AND s.revoked_at IS NULL
  AND (s.expires_at IS NULL OR s.expires_at > ?)
  AND p.enabled = 1
  AND a.role = 'super_admin' AND a.is_active = 1
  AND z.actor = 'admin:' || s.actor_id AND z.expires_at > ?
  AND z.created_at >= CASE
    WHEN COALESCE(a.password_changed_at, 0) > 1000000000000 THEN a.password_changed_at
    ELSE COALESCE(a.password_changed_at, 0) * 1000 END
  AND e.created_at >= MAX(p.enabled_at, s.consented_at)
  AND e.created_at >= ? AND e.created_at <= ?
  AND ((e.type = 'new_device' AND p.new_device = 1)
    OR (e.type = 'activation' AND p.activation = 1)
    OR (e.type = 'problem' AND p.problem = 1))`;

function payloadFor(row) {
  return panelAlertPayload(row);
}

async function enqueue(env, now) {
  // NOT EXISTS évite qu'un historique déjà traité monopolise la limite. L'index
  // unique reste l'arbitre lorsque deux invocations de cron se chevauchent.
  const result = await env.DB.prepare(`
    INSERT OR IGNORE INTO panel_push_deliveries
      (event_id, subscription_id, state, attempts, next_attempt_at, created_at, updated_at)
    SELECT e.event_id, s.id, 'pending', 0, ?, ?, ?
    FROM panel_alert_events e
    JOIN panel_push_subscriptions s ON 1 = 1
    JOIN panel_alert_preferences p ON p.actor_id = s.actor_id
    JOIN admin_users a ON a.id = s.actor_id
    JOIN auth_sessions z ON z.id = s.session_id
    WHERE ${ELIGIBLE}
      AND NOT EXISTS (SELECT 1 FROM panel_push_deliveries d
        WHERE d.event_id = e.event_id AND d.subscription_id = s.id)
    ORDER BY e.seq ASC LIMIT 500
  `).bind(now, now, now, now, now, now - 24 * HOUR, now).run();
  return result.meta?.changes || 0;
}

async function finish(env, delivery, lease, now, state, detail = {}) {
  return env.DB.prepare(`
    UPDATE panel_push_deliveries SET state = ?, next_attempt_at = ?,
      lease_token = NULL, lease_until = NULL, last_status = ?, last_error = ?,
      sent_at = CASE WHEN ? = 'sent' THEN ? ELSE sent_at END, updated_at = ?
    WHERE event_id = ? AND subscription_id = ? AND lease_token = ?
  `).bind(state, detail.next || now, detail.status ?? null, detail.error || null,
    state, now, now, delivery.event_id, delivery.subscription_id, lease).run();
}

function timeEligible(row, now) {
  return row && (row.expires_at == null || row.expires_at > now)
    && row.session_expires_at > now
    && row.event_created_at >= now - 24 * HOUR && row.event_created_at <= now;
}

async function deliverOne(env, delivery, clock, fetcher) {
  const claimedAt = clock();
  const lease = crypto.randomUUID();
  const claimed = await env.DB.prepare(`
    UPDATE panel_push_deliveries SET state = 'leased', lease_token = ?,
      lease_until = ?, attempts = attempts + 1, updated_at = ?
    WHERE event_id = ? AND subscription_id = ? AND attempts < ?
      AND ((state IN ('pending', 'retry') AND next_attempt_at <= ?)
        OR (state = 'leased' AND lease_until <= ?))
  `).bind(lease, claimedAt + LEASE_MS, claimedAt, delivery.event_id, delivery.subscription_id,
    MAX_ATTEMPTS, claimedAt, claimedAt).run();
  if (!claimed.meta?.changes) return 'not_claimed';

  const checkedAt = clock();
  const row = await env.DB.prepare(`
    SELECT e.event_id, e.type, e.title, e.message, e.url,
      e.created_at AS event_created_at, z.expires_at AS session_expires_at,
      s.id, s.endpoint, s.p256dh, s.auth, s.expires_at
    FROM panel_alert_events e
    JOIN panel_push_subscriptions s ON s.id = ?
    JOIN panel_alert_preferences p ON p.actor_id = s.actor_id
    JOIN admin_users a ON a.id = s.actor_id
    JOIN auth_sessions z ON z.id = s.session_id
    WHERE e.event_id = ? AND ${ELIGIBLE}
  `).bind(delivery.subscription_id, delivery.event_id, checkedAt, checkedAt, checkedAt - 24 * HOUR, checkedAt).first();
  if (!timeEligible(row, clock())) {
    await finish(env, delivery, lease, clock(), 'cancelled', { error: 'consent_or_session_inactive' });
    return 'cancelled';
  }

  let result;
  let expiredBeforeSend = false;
  try {
    result = await sendWebPush({ endpoint: row.endpoint,
      expirationTime: row.expires_at, keys: { p256dh: row.p256dh, auth: row.auth } },
    payloadFor(row), env, (url, init) => {
      // Le chiffrement est asynchrone : revérifier les échéances au moment où
      // le transport allait réellement partir, sans appeler le service tiers.
      if (!timeEligible(row, clock())) {
        expiredBeforeSend = true;
        throw new Error('dispatch_expired_before_send');
      }
      return fetcher(url, init);
    });
  } catch {
    // Un événement invalide reste dans l'historique, mais aucune donnée libre
    // n'est envoyée au navigateur. Pas de détails privés dans les logs.
    await finish(env, delivery, lease, clock(), 'failed', { error: 'dispatch_validation_failed' });
    return 'failed';
  }
  const finishedAt = clock();
  if (expiredBeforeSend) {
    await finish(env, delivery, lease, finishedAt, 'cancelled', { error: 'consent_or_session_inactive' });
    return 'cancelled';
  }
  const attempts = Number(delivery.attempts) + 1;
  let state = result.state;
  if (state === 'gone' || state === 'invalid') {
    const reason = state === 'gone' ? 'push_service_expired' : 'invalid_subscription';
    await env.DB.prepare(`
      UPDATE panel_push_subscriptions SET enabled = 0, revoked_at = ?,
        revoked_reason = ?, updated_at = ? WHERE id = ?
    `).bind(finishedAt, reason, finishedAt, row.id).run();
    state = 'failed';
  }
  if (state === 'retry' && attempts >= MAX_ATTEMPTS) state = 'failed';
  const delaySeconds = Math.max(result.retryAfter || 0, Math.min(3600, 60 * (2 ** (attempts - 1))));
  await finish(env, delivery, lease, finishedAt, state,
    { status: result.status, error: result.error, next: finishedAt + delaySeconds * 1000 });
  if (state === 'sent') {
    await env.DB.prepare('UPDATE panel_push_subscriptions SET last_success_at = ? WHERE id = ?')
      .bind(finishedAt, row.id).run();
  }
  return state;
}

export async function dispatchAlerts(env, fetcher = fetch, now = Date.now(), suppliedClock) {
  if (env.PANEL_PUSH_ENABLED !== 'true') return { enabled: false, queued: 0, processed: 0 };
  const clock = dispatchClock(now, suppliedClock);
  await verifyVapidConfig(env);
  await collectConfirmedOrderFailures(env, clock());
  const queued = await enqueue(env, clock());
  // Une invocation interrompue lors de son dernier essai ne doit pas laisser
  // une réservation permanente. La réception n'est jamais déduite de ce cas.
  const cleanedAt = clock();
  await env.DB.prepare(`
    UPDATE panel_push_deliveries SET state = 'failed', lease_token = NULL,
      lease_until = NULL, last_error = 'attempts_exhausted', updated_at = ?
    WHERE state = 'leased' AND lease_until <= ? AND attempts >= ?
  `).bind(cleanedAt, cleanedAt, MAX_ATTEMPTS).run();
  const selectedAt = clock();
  const candidates = await env.DB.prepare(`
    SELECT event_id, subscription_id, attempts FROM panel_push_deliveries
    WHERE attempts < ? AND ((state IN ('pending','retry') AND next_attempt_at <= ?)
      OR (state = 'leased' AND lease_until <= ?))
    ORDER BY created_at ASC, event_id ASC, subscription_id ASC LIMIT ?
  `).bind(MAX_ATTEMPTS, selectedAt, selectedAt, BATCH_SIZE).all();
  const counts = { enabled: true, queued, processed: 0, sent: 0, retry: 0,
    failed: 0, cancelled: 0, not_claimed: 0 };
  // Quatre requêtes simultanées, 8 secondes chacune, au maximum vingt éléments.
  // Les promesses sont toutes attendues par le handler scheduled.
  for (let offset = 0; offset < (candidates.results || []).length; offset += 4) {
    const group = candidates.results.slice(offset, offset + 4);
    const outcomes = await Promise.all(group.map((delivery) => deliverOne(env, delivery, clock, fetcher)));
    for (const outcome of outcomes) { counts.processed++; counts[outcome]++; }
  }
  return counts;
}

export default {
  fetch() { return new Response('Not found', { status: 404, headers: { 'Cache-Control': 'no-store' } }); },
  async scheduled(_controller, env) {
    try {
      const counts = await dispatchAlerts(env);
      console.info(JSON.stringify({ event: 'panel_alert_dispatch', ...counts }));
    } catch {
      console.error('panel_alert_dispatch_failed');
      throw new Error('panel_alert_dispatch_failed');
    }
  },
};
