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
// =========================================================

/// Rang d'une ligne licence : 0 = jouable maintenant, 1 = sinon.
/// Jouable = status 'active' ET (à vie OU expires_at > now).
export function licensePlayableRank(row, now) {
  const status = String((row && (row.lstatus || row.status)) || '');
  const exp = row && row.expires_at;
  const lifetime = exp === null || exp === undefined;
  const notExpired = lifetime || Number(exp) > now;
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
/// [nowExpr] = placeholder `?` (à binder) OU un entier ms déjà sûr
/// (sous-requêtes en rafale : on évite 4 binds identiques à compter).
export function bestLicenseOrderSql(alias = '', nowExpr = '?') {
  const p = alias ? `${alias}.` : '';
  // `?` = bind ; sinon on n'accepte qu'un entier (jamais une string
  // libre — ce fragment est interpolé dans du SQL).
  const now = nowExpr === '?' ? '?' : String(Math.trunc(Number(nowExpr)) || 0);
  return `CASE WHEN ${p}status = 'active' AND (${p}expires_at IS NULL OR ${p}expires_at > ${now}) THEN 0 ELSE 1 END, `
    + `(${p}expires_at IS NULL) DESC, ${p}expires_at DESC`;
}
