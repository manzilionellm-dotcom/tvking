// =========================================================
//  source_hidden.js — Drapeau « hidden » par liste (masquer / réafficher)
// =========================================================
//  Le panel (PR #98, bouton « masquer / réafficher une liste ») envoie,
//  dans PUT /api/v1/sources/:mac, un booléen `hidden` sur CHAQUE entrée
//  du tableau `sources`. La box le lit dans GET /api/device-source/<mac>
//  et masque la liste SANS la retélécharger (elle reste importée).
//
//  INTERRUPTEUR DE REPLI : variable Worker SOURCE_HIDDEN (coupée par
//  défaut). Coupé :
//    - PUT ignore le champ `hidden` (rien n'est stocké, comme avant) ;
//    - les lectures (box et panel) retirent tout `hidden` déjà stocké
//      (si l'interrupteur a été allumé puis coupé) → réponse identique
//      à avant.
//  Allumé : seul `hidden: true` est stocké ; `false` ou absent = visible
//  (le champ n'est pas écrit, la ligne reste identique à avant).
//
//  Fichier pur (aucun accès réseau) sauf readHiddenSignature (lecture D1).
// =========================================================

/// true seulement si l'opérateur a ALLUMÉ l'interrupteur.
export function sourceHiddenOn(env) {
  const v = String((env && env.SOURCE_HIDDEN) || '').trim().toLowerCase();
  return v === '1' || v === 'true' || v === 'on' || v === 'yes';
}

/// Applique le drapeau reçu sur une source déjà normalisée.
/// Renvoie { source } ou { error }. Coupé : source inchangée.
export function withHidden(env, source, raw) {
  if (!sourceHiddenOn(env) || !raw || typeof raw !== 'object' || !('hidden' in raw)) {
    return { source };
  }
  const h = raw.hidden;
  if (h === undefined || h === null || h === false) return { source };
  if (h === true) return { source: { ...source, hidden: true } };
  return { error: 'hidden doit être true ou false' };
}

/// Politique de LECTURE : coupé → on retire `hidden` ; allumé → on ne
/// garde que `hidden: true` (toute autre valeur est retirée).
export function applyHiddenPolicy(env, list) {
  if (!Array.isArray(list)) return list;
  const on = sourceHiddenOn(env);
  return list.map((s) => {
    if (!s || typeof s !== 'object' || !('hidden' in s)) return s;
    const { hidden, ...rest } = s;
    return on && hidden === true ? { ...rest, hidden: true } : rest;
  });
}

/// Signature des listes masquées (positions des listes du panel), pour
/// savoir si un envoi a changé l'état masqué. Ex. "0,2" ; "" = aucune.
export function hiddenSignature(list) {
  if (!Array.isArray(list)) return '';
  const panel = list.filter((s) => s && (s.origin === undefined || s.origin === 'panel'));
  return panel
    .map((s, i) => (s && s.hidden === true ? String(i) : null))
    .filter((x) => x !== null)
    .join(',');
}

/// Lit la signature actuellement stockée pour une MAC ('' si rien).
export async function readHiddenSignature(env, mac) {
  try {
    const row = await env.DB
      .prepare('SELECT sources_json FROM device_sources WHERE mac = ?')
      .bind(mac).first();
    if (!row || !row.sources_json) return '';
    let arr = [];
    try { arr = JSON.parse(row.sources_json) || []; } catch (_) { arr = []; }
    return hiddenSignature(arr);
  } catch (_) {
    return '';
  }
}
