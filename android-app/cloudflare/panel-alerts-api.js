// API privée des alertes du propriétaire. Chaque appel réutilise la session,
// le rôle courant et les contrôles d'origine du Worker historique.
import { readNovatubePanelActor } from './novatube4k-panel-admin.js';
import { ensurePanelAlertsSchema, panelAlertPayload } from './panel-alerts.js';

const PREFIX = '/api/v1/panel-alerts';
const TYPES = ['new_device', 'activation', 'problem'];
const encoder = new TextEncoder();
const EVENT_ID = /^[A-Za-z0-9_.:-]{8,128}$/;
const SUB_ID = /^pps_[a-f0-9]{32}$/;
const MESSAGES = {
  forbidden: 'Ces alertes sont réservées au propriétaire.',
  session_required: 'Reconnecte-toi pour gérer les notifications de cet appareil.',
  alerts_unavailable: 'Les alertes sont momentanément indisponibles.',
  push_unavailable: 'Les notifications Push ne sont pas encore configurées.',
  invalid_preferences: 'Vérifie les préférences de notification.',
  invalid_subscription: 'La souscription du navigateur est invalide.',
  consent_required: 'Active les notifications du compte et autorise-les sur cet appareil.',
  subscription_conflict: 'Cette souscription appartient déjà à un autre compte.',
  subscription_limit: 'Cinq appareils sont déjà autorisés. Désactive un ancien appareil.',
  not_found: 'Élément introuvable.',
  invalid_request: 'La demande est invalide.',
  body_too_large: 'La demande est trop volumineuse.',
  rate_limited: 'Trop de demandes. Réessaie dans une minute.',
  method_not_allowed: 'Méthode non autorisée.',
};
function json(headers, data, status = 200) { return Response.json(data, { status, headers }); }
function fail(headers, error, status = 400) { return json(headers, { ok: false, error, message: MESSAGES[error] }, status); }
function plain(value) { return !!value && typeof value === 'object' && !Array.isArray(value); }

function base64url(value, bytes) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]+$/.test(value) || value.length > 128) return null;
  try {
    const raw = atob(value.replaceAll('-', '+').replaceAll('_', '/'));
    if (raw.length !== bytes) return null;
    const canonical = btoa(raw).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
    return canonical === value ? Uint8Array.from(raw, (c) => c.charCodeAt(0)) : null;
  } catch { return null; }
}
async function publicPoint(value) {
  const bytes = base64url(value, 65);
  if (!bytes || bytes[0] !== 4) return false;
  try { await crypto.subtle.importKey('raw', bytes, { name: 'ECDH', namedCurve: 'P-256' }, false, []); return true; }
  catch { return false; }
}
export function validatePanelPushEndpoint(value) {
  if (typeof value !== 'string' || value.length > 2048 || /[\s\u0000-\u001f\u007f]/.test(value)) return false;
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:' || url.username || url.password || url.port || url.search || url.hash) return false;
    if (url.hostname === 'fcm.googleapis.com') return /^\/(?:fcm\/send|wp)\/[^/?#]+$/.test(url.pathname);
    if (url.hostname === 'updates.push.services.mozilla.com') return /^\/wpush\/v2\/[^/?#]+$/.test(url.pathname);
    if (url.hostname === 'web.push.apple.com') return /^\/Q[^/?#]+$/.test(url.pathname);
    // Pas de domaine arbitraire ni de WNS non vérifié : le transport répète
    // ce contrôle et refuse les redirections avant tout appel réseau.
    return false;
  } catch { return false; }
}

async function readBody(request) {
  const reader = request.body?.getReader();
  if (!reader) return {};
  const chunks = []; let size = 0;
  try {
    while (true) {
      const next = await reader.read(); if (next.done) break;
      size += next.value.byteLength;
      if (size > 8192) { await reader.cancel(); return { tooLarge: true }; }
      chunks.push(next.value);
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const part of chunks) { bytes.set(part, offset); offset += part.length; }
    const body = JSON.parse(new TextDecoder().decode(bytes));
    return { body: plain(body) ? body : null };
  } catch { return { body: null }; }
  finally { reader.releaseLock(); }
}

function preferences(row) {
  return { enabled: row?.enabled === 1, types: Object.fromEntries(TYPES.map((type) => [type, row ? row[type] === 1 : true])) };
}
async function prefs(env, actor) {
  return env.DB.prepare('SELECT * FROM panel_alert_preferences WHERE actor_id=?').bind(actor).first();
}
async function configuredPublicKey(env) {
  const key = env.PANEL_PUSH_PUBLIC_KEY;
  return typeof key === 'string' && await publicPoint(key) ? key : null;
}
function label(value) {
  return (typeof value === 'string' ? value : '').replace(/[\u0000-\u001f\u007f]/g, ' ')
    .replace(/https?:\/\/\S+/gi, '[lien]').replace(/\b[a-f0-9]{64}\b/gi, '[secret]')
    .replace(/\b[0-9A-HJKMNP-TV-Z]{4}(?:-[0-9A-HJKMNP-TV-Z]{4}){2}\b/g, '[code]')
    .trim().slice(0, 80) || 'Cet appareil';
}
async function digest(text) {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(text))), (n) => n.toString(16).padStart(2, '0')).join('');
}
function audit(env, user, action, target, data, now) {
  return env.DB.prepare(`INSERT INTO audit_logs
    (id,actor_type,actor_id,action,target_type,target_id,before_json,after_json,created_at)
    VALUES(?,'admin',?,?,'panel_push',?,NULL,?,?)`)
    .bind('aud_' + crypto.randomUUID(), user.sub, action, target, JSON.stringify(data), now);
}

export async function handlePanelAlertsApi(request, env, ctx, original, deps = {}) {
  const url = new URL(request.url), path = '/' + url.pathname.split('/').filter(Boolean).join('/');
  if (!(path === PREFIX || path.startsWith(PREFIX + '/')) || request.method === 'OPTIONS') return null;
  const gate = await readNovatubePanelActor(request, env, ctx, original);
  if (gate.error) return gate.error;
  const { user, headers } = gate;
  headers.set('Cache-Control', 'no-store, private'); headers.set('X-Content-Type-Options', 'nosniff');
  if (user?.role !== 'super_admin') return fail(headers, 'forbidden', 403);
  if (typeof user.sid !== 'string' || !user.sid) return fail(headers, 'session_required', 401);
  try {
    if (typeof deps.rateLimitOk !== 'function') return fail(headers, 'alerts_unavailable', 503);
    if (!await deps.rateLimitOk(env, request, request.method === 'GET' ? 'panel-alerts-read' : 'panel-alerts-write',
      request.method === 'GET' ? 240 : 60, 60_000)) return fail(headers, 'rate_limited', 429);
    await ensurePanelAlertsSchema(env);
    const now = Date.now(), tail = path.slice(PREFIX.length);
    if (tail === '/preferences' && request.method === 'GET') {
      const key = await configuredPublicKey(env);
      return json(headers, { ok: true, ...preferences(await prefs(env, user.sub)), push_available: !!key, public_key: key });
    }
    if (tail === '/preferences' && request.method === 'PUT') {
      const parsed = await readBody(request);
      if (parsed.tooLarge) return fail(headers, 'body_too_large', 413);
      const body = parsed.body;
      if (!body || typeof body.enabled !== 'boolean' || !plain(body.types)
        || Object.keys(body.types).length !== TYPES.length
        || TYPES.some((type) => typeof body.types[type] !== 'boolean')) return fail(headers, 'invalid_preferences');
      // Le seuil est calculé DANS SQLite : deux PUT concurrents ne peuvent
      // remettre un ancien enabled_at et réexpédier tout l'historique.
      await env.DB.batch([
        env.DB.prepare(`INSERT INTO panel_alert_preferences(actor_id,enabled,new_device,activation,problem,enabled_at,updated_at)
          VALUES(?,?,?,?,?,?,?) ON CONFLICT(actor_id) DO UPDATE SET
            enabled=excluded.enabled,new_device=excluded.new_device,activation=excluded.activation,problem=excluded.problem,
            enabled_at=CASE WHEN excluded.enabled=1 AND (panel_alert_preferences.enabled=0
              OR (panel_alert_preferences.new_device=0 AND excluded.new_device=1)
              OR (panel_alert_preferences.activation=0 AND excluded.activation=1)
              OR (panel_alert_preferences.problem=0 AND excluded.problem=1))
              THEN MAX(panel_alert_preferences.enabled_at,excluded.updated_at) ELSE panel_alert_preferences.enabled_at END,
            updated_at=MAX(panel_alert_preferences.updated_at,excluded.updated_at)`).bind(user.sub, body.enabled ? 1 : 0,
          ...TYPES.map((type) => body.types[type] ? 1 : 0), body.enabled ? now : 0, now),
        audit(env, user, 'panel.push.preferences', user.sub, { enabled: body.enabled, types: body.types }, now),
      ]);
      const key = await configuredPublicKey(env);
      return json(headers, { ok: true, ...preferences(await prefs(env, user.sub)), push_available: !!key, public_key: key });
    }
    if (tail === '/events' && request.method === 'GET') {
      const rawAfter = url.searchParams.get('after'), rawLimit = url.searchParams.get('limit');
      const after = rawAfter == null ? null : Number(rawAfter), limit = rawLimit == null ? 50 : Number(rawLimit);
      if ((after !== null && (!Number.isSafeInteger(after) || after < 0 || !/^\d+$/.test(rawAfter)))
        || !Number.isSafeInteger(limit) || limit < 1 || limit > 100) return fail(headers, 'invalid_request');
      const query = `SELECT e.*,r.read_at FROM panel_alert_events e
        LEFT JOIN panel_alert_reads r ON r.event_id=e.event_id AND r.actor_id=?
        ${after === null ? '' : 'WHERE e.seq > ?'} ORDER BY e.seq ${after === null ? 'DESC' : 'ASC'} LIMIT ?`;
      const rows = await env.DB.prepare(query).bind(user.sub, ...(after === null ? [] : [after]), limit).all();
      const items = (rows.results || []).map((row) => {
        const payload = panelAlertPayload(row);
        return payload ? { ...payload, seq: row.seq, created_at: row.created_at, read_at: row.read_at ?? null } : null;
      }).filter(Boolean);
      const unread = await env.DB.prepare(`SELECT COUNT(*) n FROM panel_alert_events e
        WHERE NOT EXISTS(SELECT 1 FROM panel_alert_reads r WHERE r.event_id=e.event_id AND r.actor_id=?)`).bind(user.sub).first();
      return json(headers, { ok: true, items,
        next_cursor: Math.max(after || 0, ...(rows.results || []).map((row) => row.seq)), unread_count: Number(unread?.n || 0) });
    }
    if (tail === '/read' && request.method === 'POST') {
      const parsed = await readBody(request);
      if (parsed.tooLarge) return fail(headers, 'body_too_large', 413);
      const ids = parsed.body?.event_ids;
      if (!Array.isArray(ids) || !ids.length || ids.length > 100 || ids.some((id) => typeof id !== 'string' || !EVENT_ID.test(id))) {
        return fail(headers, 'invalid_request');
      }
      const results = await env.DB.batch([...new Set(ids)].map((id) => env.DB.prepare(`INSERT INTO panel_alert_reads(actor_id,event_id,read_at)
        SELECT ?,event_id,? FROM panel_alert_events WHERE event_id=? ON CONFLICT(actor_id,event_id) DO NOTHING`).bind(user.sub, now, id)));
      return json(headers, { ok: true, updated: results.reduce((n, r) => n + Number(r.meta?.changes || 0), 0) });
    }
    if (tail === '/subscriptions' && request.method === 'GET') {
      const rows = await env.DB.prepare(`SELECT id,label,enabled,session_id,created_at,consented_at,expires_at,
        last_success_at,revoked_at,revoked_reason FROM panel_push_subscriptions WHERE actor_id=? ORDER BY created_at DESC LIMIT 100`)
        .bind(user.sub).all();
      return json(headers, { ok: true, items: (rows.results || []).map(({ session_id, enabled, ...row }) =>
        ({ ...row, enabled: enabled === 1, current_session: session_id === user.sid })) });
    }
    if (tail === '/subscriptions' && request.method === 'POST') {
      const parsed = await readBody(request);
      if (parsed.tooLarge) return fail(headers, 'body_too_large', 413);
      const body = parsed.body;
      if (body?.consent !== true || body?.permission !== 'granted' || !(await prefs(env, user.sub))?.enabled) {
        return fail(headers, 'consent_required', 409);
      }
      if (!await configuredPublicKey(env)) return fail(headers, 'push_unavailable', 503);
      if (!validatePanelPushEndpoint(body.endpoint) || !plain(body.keys)
        || !base64url(body.keys.auth, 16) || !await publicPoint(body.keys.p256dh)
        || (body.expirationTime != null && (!Number.isSafeInteger(body.expirationTime) || body.expirationTime <= now))) {
        return fail(headers, 'invalid_subscription');
      }
      const session = await env.DB.prepare('SELECT actor,expires_at FROM auth_sessions WHERE id=?').bind(user.sid).first();
      if (!session || session.actor !== 'admin:' + user.sub || session.expires_at <= now) return fail(headers, 'session_required', 401);
      const endpoint = new URL(body.endpoint).href;
      const endpointHash = await digest(endpoint), expires = Math.min(session.expires_at, body.expirationTime ?? session.expires_at);
      const old = await env.DB.prepare('SELECT id,actor_id FROM panel_push_subscriptions WHERE endpoint_hash=?').bind(endpointHash).first();
      if (old && old.actor_id !== user.sub) return fail(headers, 'subscription_conflict', 409);
      const id = old?.id || 'pps_' + crypto.randomUUID().replaceAll('-', '');
      const statement = env.DB.prepare(`INSERT INTO panel_push_subscriptions
        (id,actor_id,session_id,endpoint_hash,endpoint,p256dh,auth,label,enabled,created_at,consented_at,updated_at,expires_at)
        SELECT ?,?,?,?,?,?,?,?,1,?,?,?,? WHERE (
          SELECT COUNT(*) FROM panel_push_subscriptions WHERE actor_id=? AND enabled=1
            AND (expires_at IS NULL OR expires_at>?) AND endpoint_hash<>?
        ) < 5 ON CONFLICT(endpoint_hash) DO UPDATE SET session_id=excluded.session_id,
          endpoint=excluded.endpoint,p256dh=excluded.p256dh,auth=excluded.auth,label=excluded.label,
          enabled=1,consented_at=excluded.consented_at,updated_at=excluded.updated_at,expires_at=excluded.expires_at,
          revoked_at=NULL,revoked_reason=NULL WHERE panel_push_subscriptions.actor_id=excluded.actor_id`)
        .bind(id, user.sub, user.sid, endpointHash, endpoint, body.keys.p256dh, body.keys.auth, label(body.label),
          now, now, now, expires, user.sub, now, endpointHash);
      const result = await env.DB.batch([statement,
        env.DB.prepare(`INSERT INTO audit_logs
          (id,actor_type,actor_id,action,target_type,target_id,before_json,after_json,created_at)
          SELECT ?,'admin',?,'panel.push.subscribe','panel_push',id,NULL,?,?
          FROM panel_push_subscriptions WHERE actor_id=? AND endpoint_hash=? AND changes()=1`)
          .bind('aud_' + crypto.randomUUID(), user.sub, JSON.stringify({ enabled: true, expires_at: expires }), now, user.sub, endpointHash),
      ]);
      if (!Number(result[0]?.meta?.changes || 0)) return fail(headers, 'subscription_limit', 409);
      // Une requête jumelle peut avoir créé la même souscription entre nos
      // lectures. Retourner l'identifiant réellement conservé par l'UPSERT.
      const stored = await env.DB.prepare('SELECT id,expires_at,consented_at FROM panel_push_subscriptions WHERE actor_id=? AND endpoint_hash=?')
        .bind(user.sub, endpointHash).first();
      if (!stored) return fail(headers, 'alerts_unavailable', 503);
      return json(headers, { ok: true, ...stored, enabled: true, delivery_confirmed: false }, old ? 200 : 201);
    }
    if (tail.startsWith('/subscriptions/') && request.method === 'DELETE') {
      const id = tail.slice('/subscriptions/'.length);
      if (!SUB_ID.test(id)) return fail(headers, 'invalid_request');
      const row = await env.DB.prepare('SELECT id FROM panel_push_subscriptions WHERE id=? AND actor_id=?').bind(id, user.sub).first();
      if (!row) return fail(headers, 'not_found', 404);
      await env.DB.batch([
        env.DB.prepare("UPDATE panel_push_subscriptions SET enabled=0,revoked_at=?,revoked_reason='user_disabled',updated_at=? WHERE id=? AND actor_id=?")
          .bind(now, now, id, user.sub),
        env.DB.prepare("UPDATE panel_push_deliveries SET state='cancelled',lease_token=NULL,lease_until=NULL,updated_at=? WHERE subscription_id=? AND state IN('pending','leased','retry')")
          .bind(now, id),
        audit(env, user, 'panel.push.unsubscribe', id, { enabled: false }, now),
      ]);
      return json(headers, { ok: true, id, enabled: false });
    }
    if (['/preferences', '/events', '/read', '/subscriptions'].includes(tail) || tail.startsWith('/subscriptions/')) {
      return fail(headers, 'method_not_allowed', 405);
    }
    return fail(headers, 'not_found', 404);
  } catch {
    // Le corps, les endpoints Push, auth, clés ou erreurs SQL ne sont jamais
    // recopiés dans une réponse ni un journal.
    return fail(headers, 'alerts_unavailable', 503);
  }
}
