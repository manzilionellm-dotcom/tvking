// =========================================================
//  license_pick.js — Quelle licence déverrouille l'appareil ?
// =========================================================
//  MODÈLE MÉTIER (13/09/2026) : UNE MAC = UN DROIT DE LECTURE.
//
//  Téléphone, tablette et box TV partagent le MÊME backend. On pose
//  la licence sur `app_7motion` (produit principal). Le verdict
//  « peut-il regarder ? » ignore `app_id` : on prend la meilleure
//  licence JOUABLE du device. Activer une tablette ou une Firestick
//  déverrouille CET appareil, pas « l'app TV » vs « l'app phone ».
//
//  POURQUOI CE MODULE. L'ancien tri
//    ORDER BY (expires_at IS NULL) DESC, expires_at DESC
//  préférait une licence À VIE inactive/révoquée à une licence
//  annuelle tout juste activée. Symptôme Lionel : le panel dit
//  « activé », l'appareil reste verrouillé — d1StatusForMac lisait
//  la vieille ligne, paid=false.
//
//  Une seule implémentation, importée par worker.js (heartbeat /
//  device-source) ET api_v1.js (fiche + références). Recopier le
//  ORDER BY à deux endroits, c'est le jour où le panel affiche
//  « à jour » pendant que la tablette reste bloquée.
//
//  DERNIER JOUR INCLUS (16/09/2026, abo 7 MOTION) : expires_at
//  posé à minuit le 16 = le 16 EST payé, entier. `expires_at <= now`
//  coupait dès 00:00. On ne meurt qu'après la fin du jour UTC.
// =========================================================

const DAY_MS = 24 * 60 * 60 * 1000;

/// Instant exclusif de mort : lendemain 00:00 UTC du jour de expires_at.
/// expires_at = 16/09 00:00 UTC → jouable tant que now < 17/09 00:00 UTC.
function expiryDayEndMs(expiresAt) {
  const d = new Date(expiresAt);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1, 0, 0, 0, 0);
}

/// Début du jour calendaire UTC de [now] — seuil SQL équivalent
/// (`expires_at >= utcDayStart` ⇔ `now < expiryDayEndMs(expires_at)`).
export function utcDayStartMs(now) {
  const d = new Date(now);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 0, 0, 0, 0);
}

/// Licence payante expirée seulement APRÈS la fin du jour UTC de expires_at.
/// Lifetime (null/undefined) → jamais expirée.
export function paidLicenseExpired(expiresAt, now) {
  if (expiresAt === null || expiresAt === undefined) return false;
  return now >= expiryDayEndMs(expiresAt);
}

/// Jours restants, dernier jour INCLUS (ceil jusqu'à expiryDayEndMs).
/// Lifetime → null. Le 16/09 à 23:59 avec expires_at=16/09 00:00 → 1.
export function paidLicenseDaysLeft(expiresAt, now, dayMs = DAY_MS) {
  if (expiresAt === null || expiresAt === undefined) return null;
  return Math.max(0, Math.ceil((expiryDayEndMs(expiresAt) - now) / dayMs));
}

export { expiryDayEndMs };

/// Rang d'une ligne licence : 0 = jouable maintenant, 1 = sinon.
/// Jouable = status 'active' ET (à vie OU encore le jour de fin UTC).
export function licensePlayableRank(row, now) {
  const status = String((row && (row.lstatus || row.status)) || '');
  const exp = row && row.expires_at;
  const lifetime = exp === null || exp === undefined;
  const notExpired = lifetime || !paidLicenseExpired(exp, now);
  return status === 'active' && notExpired ? 0 : 1;
}

/// Choisit la meilleure licence parmi [rows] (déjà lues en D1).
/// Ordre : jouable d'abord, puis à vie, puis échéance la plus lointaine.
/// `null` si la liste est vide — l'appelant retombe sur l'essai.
export function pickBestLicense(rows, now = Date.now()) {
  if (!Array.isArray(rows) || rows.length === 0) return null;
  const scored = rows.map((row) => {
    const exp = row && row.expires_at;
    const lifetime = exp === null || exp === undefined;
    return {
      row,
      play: licensePlayableRank(row, now),
      life: lifetime ? 0 : 1,
      exp: lifetime ? Number.POSITIVE_INFINITY : Number(exp) || 0,
    };
  });
  scored.sort((a, b) => {
    if (a.play !== b.play) return a.play - b.play;
    if (a.life !== b.life) return a.life - b.life;
    return b.exp - a.exp;
  });
  return scored[0].row;
}

/// Fragment ORDER BY SQL (même règle que pickBestLicense).
/// [alias] = préfixe colonne (`l` → `l.status`) ; vide = colonnes nues.
/// [nowExpr] = placeholder `?` (à binder avec utcDayStartMs(now))
/// OU un entier ms déjà sûr — alors on interpolle le début de jour UTC.
export function bestLicenseOrderSql(alias = '', nowExpr = '?') {
  const p = alias ? `${alias}.` : '';
  // `?` = bind (l'appelant passe utcDayStartMs) ; sinon on n'accepte
  // qu'un entier (jamais une string libre — interpolé dans du SQL).
  const threshold = nowExpr === '?'
    ? '?'
    : String(utcDayStartMs(Math.trunc(Number(nowExpr)) || 0));
  return `CASE WHEN ${p}status = 'active' AND (${p}expires_at IS NULL OR ${p}expires_at >= ${threshold}) THEN 0 ELSE 1 END, `
    + `(${p}expires_at IS NULL) DESC, ${p}expires_at DESC`;
}
