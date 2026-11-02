// Routes administrateur additives ; aucun accès aux secrets du fournisseur.
import { normalizeTrialMac, trialSettings } from './gold_trial_policy.js';

const json = (data, status = 200) => Response.json(data, { status, headers: { 'Cache-Control': 'no-store' } });

export async function goldTrialAdmin(request, env, user) {
  // Contrôle serveur, y compris pour quelqu'un qui saisit l'URL directement.
  if (!['super_admin', 'admin'].includes(user?.role)) {
    return json({ error: 'forbidden', message: 'Accès administrateur requis.' }, 403);
  }
  const url = new URL(request.url);
  if (request.method === 'GET' && url.pathname.endsWith('/history')) {
    const mac = normalizeTrialMac(url.searchParams.get('mac'));
    if (!mac) return json({ error: 'invalid_mac', message: 'Adresse MAC invalide.' }, 400);
    const before = url.searchParams.get('before');
    if (before && !/^[1-9][0-9]{0,14}$/.test(before)) return json({ error: 'invalid_cursor' }, 400);
    const rows = await env.DB.prepare(`SELECT id,mac,event,reason,created_at,expire,line_id,ip,app_version
      FROM gold_trial_events_v2 WHERE mac=? AND id<? ORDER BY id DESC LIMIT 101`)
      .bind(mac, before ? Number(before) : Number.MAX_SAFE_INTEGER).all();
    const history = rows.results.slice(0, 100);
    return json({ history, next_before: rows.results.length > 100 ? history.at(-1).id : null });
  }
  if (url.pathname !== '/api/v1/gold/trial-control') return json({ error: 'not_found' }, 404);
  if (request.method === 'GET') {
    const [settings, recent] = await Promise.all([
      trialSettings(env.DB),
      env.DB.prepare(`SELECT mac,state,created_at,expire,line_id,ip,app_version
        FROM gold_trial_claims_v2 WHERE state IN ('created','delivered','used') ORDER BY created_at DESC LIMIT 50`).all(),
    ]);
    return json({ ...settings, integration_ready: env.GOLD_TRIAL_POLICY_READY === 'true', recent: recent.results });
  }
  if (request.method !== 'PUT') return json({ error: 'method_not_allowed' }, 405);
  let body;
  try { body = await request.json(); } catch { return json({ error: 'invalid_json' }, 400); }
  if (typeof body?.gold_trial_enabled !== 'boolean' || !Number.isInteger(body.daily_cap) ||
      body.daily_cap < 0 || body.daily_cap > 10000 || !Number.isSafeInteger(body.revision) || body.revision < 0) {
    return json({ error: 'invalid_settings', message: 'Plafond entier attendu, de 0 à 10 000.' }, 400);
  }
  // Ne pas ouvrir l'offre tant que gold.js et son historique n'ont pas été
  // raccordés et vérifiés sur staging. Couper l'offre reste toujours possible.
  if (body.gold_trial_enabled && env.GOLD_TRIAL_POLICY_READY !== 'true') {
    return json({ error: 'integration_unverified', message: 'Activation indisponible : la connexion au service d’essai doit être vérifiée.' }, 409);
  }
  const result = await env.DB.prepare(`UPDATE gold_trial_settings_v2 SET
    gold_trial_enabled=?,daily_cap=?,updated_at=?,revision=revision+1 WHERE id=1 AND revision=?`)
    .bind(body.gold_trial_enabled ? 1 : 0, body.daily_cap, Date.now(), body.revision).run();
  if (!result.meta.changes) return json({ error: 'settings_changed', message: 'Les réglages ont changé. Rechargez-les avant de réessayer.' }, 409);
  return json({ ok: true, ...await trialSettings(env.DB) });
}
