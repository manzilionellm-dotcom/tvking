// Essai commercial NovaTube : dix jours au premier enrôlement uniquement.
// Cette table n'a volontairement aucune clé étrangère vers devices : supprimer
// puis réinscrire une fiche ne doit jamais fabriquer un nouvel essai gratuit.
// Les installations déjà connues sont mémorisées comme exclues, sans modifier
// leur licence, leur abonnement, leurs sources ni les règles des autres apps.
export const NOVATUBE_TRIAL_DAYS = 10;
export const NOVATUBE_TRIAL_MS = NOVATUBE_TRIAL_DAYS * 86_400_000;
const APP = 'app_novatube4k';
const PACKAGE = 'com.manthefew';
const ready = new WeakSet();

export async function ensureNovatubeTrialEntitlements(env) {
  if (ready.has(env.DB)) return;
  await env.DB.batch([
    env.DB.prepare(`CREATE TABLE IF NOT EXISTS novatube4k_trial_entitlements (
      raw_mac TEXT PRIMARY KEY,
      mac TEXT NOT NULL UNIQUE,
      first_device_id TEXT NOT NULL,
      registered_at INTEGER NOT NULL,
      disposition TEXT NOT NULL CHECK (disposition IN ('trial', 'existing', 'disabled')),
      started_at INTEGER,
      expires_at INTEGER,
      CHECK ((disposition = 'trial' AND started_at IS NOT NULL AND started_at > 0 AND expires_at IS NOT NULL
        AND expires_at = started_at + ${NOVATUBE_TRIAL_MS})
        OR (disposition <> 'trial' AND started_at IS NULL AND expires_at IS NULL))
    )`),
    // Migration additive : aucun ancien client, payé ou non, ne reçoit un essai
    // à la mise en ligne. Une ancre créée par le nouvel enrôlement reste intacte.
    env.DB.prepare(`INSERT INTO novatube4k_trial_entitlements
      (raw_mac, mac, first_device_id, registered_at, disposition, started_at, expires_at)
      SELECT n.raw_mac, n.mac, n.device_id, n.created_at, 'existing', NULL, NULL
      FROM novatube4k_devices n WHERE 1
      ON CONFLICT(raw_mac) DO NOTHING`),
  ]);
  ready.add(env.DB);
}

// Ces deux instructions appartiennent AU MÊME lot D1 que la création de la
// fiche. Une panne ou deux inscriptions concurrentes annulent le lot entier.
// Le premier device_id reste ancré : une fiche recréée n'adopte pas cet essai.
export function novatubeTrialEnrollmentStatements(env, identity) {
  const { raw, mac, deviceId, customerId, licenseId, now } = identity;
  return [
    env.DB.prepare(`INSERT INTO novatube4k_trial_entitlements
      (raw_mac, mac, first_device_id, registered_at, disposition, started_at, expires_at)
      SELECT ?, ?, ?, ?, CASE WHEN a.is_active = 1 THEN 'trial' ELSE 'disabled' END,
        CASE WHEN a.is_active = 1 THEN ? ELSE NULL END,
        CASE WHEN a.is_active = 1 THEN ? ELSE NULL END
      FROM apps a WHERE a.id = ? AND a.package_name = ?
      ON CONFLICT(raw_mac) DO NOTHING`)
      .bind(raw, mac, deviceId, now, now, now + NOVATUBE_TRIAL_MS, APP, PACKAGE),
    env.DB.prepare(`INSERT INTO licenses
      (id, customer_id, device_id, app_id, status, plan, started_at,
       expires_at, auto_renew, created_at, updated_at)
      SELECT ?, ?, ?, ?,
        CASE WHEN e.first_device_id = ? AND e.disposition = 'trial' THEN 'active' ELSE 'inactive' END,
        CASE WHEN e.first_device_id = ? AND e.disposition = 'trial' THEN 'trial10' ELSE 'custom' END,
        CASE WHEN e.first_device_id = ? AND e.disposition = 'trial' THEN e.started_at ELSE ? END,
        CASE WHEN e.first_device_id = ? AND e.disposition = 'trial' THEN e.expires_at ELSE 0 END,
        0, ?, ?
      FROM novatube4k_trial_entitlements e WHERE e.raw_mac = ? AND e.mac = ?`)
      .bind(licenseId, customerId, deviceId, APP, deviceId, deviceId, deviceId, now,
        deviceId, now, now, raw, mac),
  ];
}

export async function novatubeTrialMetadata(env, binding, access, now) {
  const row = access.row;
  const trialPlan = /^trial(?:\d+)?$/.test(row.plan || '');
  const anchor = await env.DB.prepare(`SELECT first_device_id, disposition, started_at, expires_at
    FROM novatube4k_trial_entitlements WHERE raw_mac = ? AND mac = ?`)
    .bind(binding.raw_mac, binding.mac).first();
  const automatic = anchor?.disposition === 'trial' && anchor.first_device_id === binding.device_id;
  let status = 'not_offered', startedAt = null, expiresAt = null;
  if (trialPlan) {
    // L'échéance de la licence est l'autorité courante : une prolongation
    // manuelle par l'administrateur reste possible et ne recrée pas l'ancre.
    startedAt = automatic ? anchor.started_at : Number(row.started_at);
    expiresAt = Number(row.expires_at);
    const valid = Number.isSafeInteger(startedAt) && startedAt > 0
      && Number.isSafeInteger(expiresAt) && expiresAt > startedAt;
    if (!valid) { startedAt = null; expiresAt = null; status = 'unavailable'; }
    else if (['banned', 'frozen', 'disabled'].includes(access.status)) status = 'unavailable';
    else if (access.status === 'expired' || expiresAt <= now) status = 'expired';
    else if (access.status === 'active') status = 'active';
    else status = 'unavailable';
  } else if (anchor?.disposition === 'trial' && !automatic) {
    // Une fiche supprimée puis recréée sait que l'essai est déjà utilisé,
    // mais cette information n'accorde aucun droit de lecture.
    status = 'unavailable';
  }
  return {
    duration_days: NOVATUBE_TRIAL_DAYS,
    status,
    started_at: startedAt,
    expires_at: expiresAt,
  };
}
