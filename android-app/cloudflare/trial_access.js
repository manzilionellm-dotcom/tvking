// =========================================================
//  trial_access.js — Essai 7 jours décidé par le SERVEUR
// =========================================================
//  Lionel : une app téléchargée (Zuno TV sur box, 7 Motion si elle
//  parle au même Worker) peut fonctionner 7 jours MAXIMUM sans
//  activation payée. Au 8e jour (début = première apparition +
//  exactement 7 × 24 h), sans licence payée, l'accès est « expiré ».
//
//  INTERRUPTEUR : variable d'environnement TRIAL_ENFORCEMENT.
//  Coupé par défaut (absent, « 0 », « off », « false »). Tant qu'il
//  est coupé, les réponses /api/status et /api/heartbeat restent
//  celles d'aujourd'hui : on n'impose PAS le verrou de 7 jours, on
//  ne change PAS le débit des crédits. Les ancres (première
//  apparition) sont quand même notées, pour que le jour où on
//  allume l'interrupteur l'essai ne reparte pas de zéro.
//
//  Allumé (« 1 », « true », « on », « yes ») :
//    - la fin d'essai = ancre + 7 jours, horloge DU SERVEUR ;
//    - réinstallation, effacement, ou nouvelle MAC avec le même
//      ANDROID_ID ne relance pas l'ancre ;
//    - un client déjà activé (licence en cours ou à vie) n'est
//      jamais basculé « expiré » par cet essai ;
//    - une licence à durée échue bloque vraiment ;
//    - « à vie » activé une seconde fois ne redébite pas
//      (voir handleActivate).
// =========================================================

export const DAY_MS = 24 * 60 * 60 * 1000;
export const TRIAL_DAYS = 7;

/// true seulement si l'opérateur a ALLUMÉ l'interrupteur.
export function trialEnforcementOn(env) {
  const v = String((env && env.TRIAL_ENFORCEMENT) || '').trim().toLowerCase();
  return v === '1' || v === 'true' || v === 'on' || v === 'yes';
}

/// Fenêtre d'essai. `expired` dès que l'horloge serveur atteint
/// début + durée (7 jours pile = début du 8e jour = bloqué).
export function trialWindow(startedAt, now, days = TRIAL_DAYS) {
  const start = Number(startedAt) > 0 ? Number(startedAt) : now;
  const trialUntil = start + days * DAY_MS;
  const expired = now >= trialUntil;
  const daysLeft = expired
    ? 0
    : Math.max(0, Math.ceil((trialUntil - now) / DAY_MS));
  return { start, trialUntil, expired, daysLeft };
}

let _anchorReady = false;

export async function ensureTrialAnchorTable(env) {
  if (_anchorReady || !env || !env.DB) return;
  await env.DB.prepare(
    'CREATE TABLE IF NOT EXISTS trial_anchors ('
    + 'mac TEXT PRIMARY KEY, android_id TEXT, started_at INTEGER NOT NULL)',
  ).run();
  try {
    await env.DB.prepare(
      'CREATE INDEX IF NOT EXISTS idx_trial_anchors_android ON trial_anchors(android_id)',
    ).run();
  } catch (_) { /* index déjà là */ }
  _anchorReady = true;
}

/// Mémorise le début d'essai et ne le recule JAMAIS vers le futur.
/// Si le même ANDROID_ID a déjà une ancre plus ancienne (autre MAC),
/// c'est cette date qui gagne : changer d'identifiant affiché ne
/// redonne pas 7 jours.
/// Renvoie l'ancre (ms epoch). Best-effort : en cas d'erreur, on
/// renvoie le candidat sans inventer une date.
export async function rememberTrialStart(env, mac, androidId, candidateStart) {
  const candidate = Number(candidateStart) > 0 ? Number(candidateStart) : Date.now();
  if (!env || !env.DB || !mac) return candidate;
  try {
    await ensureTrialAnchorTable(env);
    const aid = String(androidId || '').trim().slice(0, 64);
    const macRow = await env.DB
      .prepare('SELECT started_at, android_id FROM trial_anchors WHERE mac = ?')
      .bind(mac)
      .first();
    let started = candidate;
    if (macRow && Number(macRow.started_at) > 0 && Number(macRow.started_at) < started) {
      started = Number(macRow.started_at);
    }
    if (aid) {
      const idRow = await env.DB
        .prepare('SELECT MIN(started_at) AS started_at FROM trial_anchors WHERE android_id = ?')
        .bind(aid)
        .first();
      if (idRow && Number(idRow.started_at) > 0 && Number(idRow.started_at) < started) {
        started = Number(idRow.started_at);
      }
    }
    const storedAid = macRow && macRow.android_id ? String(macRow.android_id) : '';
    const unchanged = macRow
      && Number(macRow.started_at) === started
      && (aid === '' || storedAid === aid);
    if (unchanged) return started;
    if (macRow) {
      await env.DB.prepare(
        'UPDATE trial_anchors SET started_at = ?, '
        + "android_id = CASE WHEN ? != '' THEN ? ELSE android_id END WHERE mac = ?",
      ).bind(started, aid, aid, mac).run();
    } else {
      try {
        await env.DB.prepare(
          'INSERT INTO trial_anchors (mac, android_id, started_at) VALUES (?, ?, ?)',
        ).bind(mac, aid || null, started).run();
      } catch (_) {
        const again = await env.DB
          .prepare('SELECT started_at FROM trial_anchors WHERE mac = ?')
          .bind(mac)
          .first();
        if (again && Number(again.started_at) > 0) {
          return Math.min(started, Number(again.started_at));
        }
      }
    }
    return started;
  } catch (_) {
    return candidate;
  }
}

/// Durée d'essai du panel (app_config.trial_days). Utilisée SEULEMENT
/// quand l'interrupteur est coupé, pour ne pas changer le comportement
/// actuel. Repli : 7.
export async function configuredTrialDays(env) {
  if (!env || !env.DB) return TRIAL_DAYS;
  try {
    const r = await env.DB
      .prepare("SELECT value FROM app_config WHERE key = 'trial_days'")
      .first();
    const td = parseInt(r && r.value, 10);
    return Number.isFinite(td) && td >= 0 ? td : TRIAL_DAYS;
  } catch (_) {
    return TRIAL_DAYS;
  }
}

function cfg(value) {
  return value == null ? '' : String(value);
}

/// Textes de l'écran de blocage + lien de paiement. Vides par défaut :
/// l'app affiche alors son texte intégré (français / anglais) et le
/// moyen de contact DÉJÀ présent dans le projet.
export async function loadBlockCopy(env) {
  const empty = {
    title_fr: '', body_fr: '', title_en: '', body_en: '', pay_url: '',
  };
  if (!env || !env.DB) return empty;
  try {
    const rs = await env.DB.prepare(
      'SELECT key, value FROM app_config WHERE key IN '
      + "('trial_block_title_fr','trial_block_body_fr',"
      + "'trial_block_title_en','trial_block_body_en','trial_pay_url')",
    ).all();
    const map = {};
    for (const row of (rs && rs.results) || []) map[row.key] = cfg(row.value);
    return {
      title_fr: map.trial_block_title_fr || '',
      body_fr: map.trial_block_body_fr || '',
      title_en: map.trial_block_title_en || '',
      body_en: map.trial_block_body_en || '',
      pay_url: map.trial_pay_url || '',
    };
  } catch (_) {
    return empty;
  }
}

/// Complète une réponse de statut QUAND l'interrupteur est allumé.
/// Un accès déjà payé n'est pas touché. Un accès fini (essai ou
/// abonnement à durée) devient status « expired » et trial_until = 0
/// pour qu'un client qui compare trial_until à l'horloge du téléviseur
/// ne puisse pas se redonner du temps en reculant la date.
export function shapeEnforcedStatus(base, now, copy) {
  const block = !!(base && base.expired && !base.paid && !base.frozen && !base.banned);
  const c = copy || {};
  return {
    ...base,
    status: block ? 'expired' : base.status,
    trial_until: block ? 0 : base.trial_until,
    trial_enforced: true,
    server_now: now,
    block_title_fr: c.title_fr || '',
    block_body_fr: c.body_fr || '',
    block_title_en: c.title_en || '',
    block_body_en: c.body_en || '',
    pay_url: c.pay_url || '',
  };
}

function dateLabel(ms) {
  try {
    return new Date(ms).toISOString().slice(0, 10);
  } catch (_) {
    return '';
  }
}

/// Pastille du panel pour UN appareil. Même règle que l'app :
/// interrupteur allumé → 7 jours depuis l'ancre ; coupé → durée du
/// panel depuis first_seen (comportement actuel).
export function describeAccess({ now, startedAt, trialDays, license, blockStatus }) {
  if (blockStatus === 'banned') {
    return { access: 'banned', label: 'Banni', days_left: 0, ends_at: null };
  }
  if (blockStatus === 'frozen') {
    return { access: 'frozen', label: 'Gelé', days_left: 0, ends_at: null };
  }
  const st = license && license.status;
  const ignored = !st || st === 'inactive' || st === 'pending';
  if (!ignored) {
    const lifetime = license.expires_at === null || license.expires_at === undefined;
    if (lifetime && st === 'active') {
      return { access: 'lifetime', label: 'Activé à vie', days_left: null, ends_at: null };
    }
    if (st === 'active' && !lifetime && Number(license.expires_at) > now) {
      const ends = Number(license.expires_at);
      const left = Math.max(0, Math.ceil((ends - now) / DAY_MS));
      return {
        access: 'activated',
        label: `Activé · fin le ${dateLabel(ends)}`,
        days_left: left,
        ends_at: ends,
      };
    }
    if (!lifetime && license.expires_at != null && Number(license.expires_at) <= now) {
      const ends = Number(license.expires_at);
      return {
        access: 'expired',
        label: `Expiré · le ${dateLabel(ends)}`,
        days_left: 0,
        ends_at: ends,
      };
    }
  }
  const days = Number.isFinite(Number(trialDays)) ? Number(trialDays) : TRIAL_DAYS;
  const win = trialWindow(startedAt, now, days);
  if (win.expired) {
    return { access: 'expired', label: 'Essai expiré', days_left: 0, ends_at: win.trialUntil };
  }
  const left = win.daysLeft;
  const j = left > 1 ? 'jours restants' : 'jour restant';
  return {
    access: 'trial',
    label: `Essai en cours · ${left} ${j}`,
    days_left: left,
    ends_at: win.trialUntil,
  };
}
