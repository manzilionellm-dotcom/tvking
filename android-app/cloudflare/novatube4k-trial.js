// Ajout MANUEL de jours à un essai NOVATUBE déjà accordé. L'enrôlement
// inactive/custom/0 n'est jamais un essai ; un abonnement payé n'est jamais
// converti. Les anciennes MAC gardent intégralement le handler historique.
import { readNovatubePanelActor } from './novatube4k-panel-admin.js';

const ready = new WeakSet();
function response(headers, body, status = 200) { return Response.json(body, { headers, status }); }
function fail(headers, error, message, status = 409) { return response(headers, { error, message }, status); }

export async function handleNovatube4kTrialExtend(request, env, ctx, original, deps, body) {
  const mac = typeof body?.mac === 'string' ? body.mac.trim().toUpperCase() : '';
  if (!/^MK(?::[0-9A-F]{2}){5}$/.test(mac)) return null;
  let binding;
  try { binding = await env.DB.prepare('SELECT device_id FROM novatube4k_devices WHERE mac = ?').bind(mac).first(); }
  catch (error) {
    if (/no such table:\s*novatube4k_devices\b/i.test(String(error?.message || ''))) return null;
    throw error;
  }
  if (!binding) return null;
  let gate = await readNovatubePanelActor(request, env, ctx, original);
  // Cette route historique accepte aussi X-Admin-Secret. /auth/me contrôle
  // d'abord l'origine ; seul son refus 401 peut être remplacé par ce secret.
  if (gate.error?.status === 401 && typeof deps.adminSecretMatches === 'function'
    && deps.adminSecretMatches(request, env)) {
    const headers = new Headers(gate.error.headers);
    headers.delete('Content-Length'); headers.set('Cache-Control', 'no-store, private');
    gate = { headers, user: { role: 'super_admin', sub: 'admin_secret' } };
  }
  if (gate.error) return gate.error;
  const { user, headers } = gate;
  if (user?.role !== 'super_admin') return fail(headers, 'forbidden', 'Seul l’administrateur peut ajouter des jours d’essai.', 403);
  if (![deps.parseExtendDays, deps.nextTrialEnd, deps.ensureTrialAnchorTable, deps.notifyBox]
    .every((fn) => typeof fn === 'function')) return fail(headers, 'trial_unavailable', 'Ajout de jours indisponible.', 503);
  const parsed = deps.parseExtendDays(body.days);
  if (parsed.error) return fail(headers, 'bad_days', parsed.error, 400);
  const license = await env.DB.prepare(`SELECT id, status, plan, expires_at, updated_at FROM licenses
    WHERE device_id = ? AND app_id = 'app_novatube4k'`).bind(binding.device_id).first();
  if (!license || !['active', 'expired'].includes(license.status) || !/^trial(?:\d+)?$/.test(license.plan || '')
    || !Number.isSafeInteger(license.expires_at) || license.expires_at <= 0) {
    return fail(headers, 'novatube4k_trial_required', 'Cette action exige un essai NOVATUBE déjà accordé. La licence actuelle reste inchangée.');
  }
  if (!ready.has(env.DB)) {
    await deps.ensureTrialAnchorTable(env);
    await env.DB.prepare('CREATE TABLE IF NOT EXISTS novatube4k_trial_guard (id TEXT PRIMARY KEY, valid INTEGER NOT NULL CHECK (valid = 1))').run();
    try { await env.DB.prepare('ALTER TABLE audit_logs ADD COLUMN correlation_id TEXT').run(); }
    catch (error) {
      if (!/duplicate column name:\s*correlation_id\b/i.test(String(error?.message || ''))) throw error;
    }
    ready.add(env.DB);
  }
  const now = Date.now(), previous = license.expires_at;
  const until = deps.nextTrialEnd(previous, now, parsed.days);
  const trace = /^[A-Za-z0-9_.:-]{8,64}$/.test(request.headers.get('X-Request-Id') || '')
    ? request.headers.get('X-Request-Id') : crypto.randomUUID();
  headers.set('X-Request-Id', trace);
  const id = crypto.randomUUID();
  try {
    await env.DB.batch([
      env.DB.prepare(`UPDATE licenses SET expires_at = ?, status = 'active', updated_at = ?
        WHERE id = ? AND device_id = ? AND app_id = 'app_novatube4k'
        AND status = ? AND plan = ? AND expires_at = ? AND updated_at = ?`)
        .bind(until, now, license.id, binding.device_id, license.status, license.plan, previous, license.updated_at),
      env.DB.prepare('INSERT INTO novatube4k_trial_guard (id, valid) SELECT ?, CASE WHEN changes() = 1 THEN 1 ELSE 0 END').bind(id),
      env.DB.prepare(`INSERT INTO trial_extensions
        (id, mac, days, previous_until, new_until, actor_type, actor_id, created_at)
        VALUES (?, ?, ?, ?, ?, 'admin', ?, ?)`)
        .bind('tx_' + id, mac, parsed.days, previous, until, user.sub, now),
      env.DB.prepare(`INSERT INTO audit_logs
        (id, actor_type, actor_id, action, target_type, target_id, before_json, after_json,
         ip, user_agent, created_at, correlation_id)
        VALUES (?, 'admin', ?, 'trial.extend', 'device', ?, ?, ?, ?, ?, ?, ?)`)
        .bind('aud_' + id, user.sub, binding.device_id, JSON.stringify({ previous_until: previous }),
          JSON.stringify({ mac, app_id: 'app_novatube4k', days: parsed.days, trial_until: until }),
          request.headers.get('CF-Connecting-IP'), request.headers.get('User-Agent'), now, trace),
      env.DB.prepare('DELETE FROM novatube4k_trial_guard WHERE id = ?').bind(id),
    ]);
  } catch (error) {
    if (/CHECK constraint failed/i.test(String(error?.message || ''))) return fail(headers, 'trial_conflict', 'La licence a changé. Relis la fiche.');
    return fail(headers, 'trial_unavailable', 'Ajout de jours non confirmé. Relis la fiche avant de réessayer.', 503);
  }
  const sent = await Promise.allSettled([deps.notifyBox(env, mac, 'license', { traceId: trace, t1: now, t2: now })]);
  return response(headers, { ok: true, mac, days: parsed.days, previous_until: previous, trial_until: until,
    notifications_ok: sent[0].status === 'fulfilled' && !!sent[0].value });
}
