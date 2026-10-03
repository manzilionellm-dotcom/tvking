// =========================================================
//  page_query.js — pagination, dates et statut de licence
// =========================================================
//  Fonctions pures, sans D1, partagées par api_v1.js et les tests.
//  Le panel affiche des milliers de box : on ne renvoie jamais
//  toute la table d'un coup, et on ne ment pas sur le total.
//
//  Les dates métier sont des millisecondes (Date.now()). D'anciennes
//  lignes peuvent être en secondes : on les ramène en ms avant de
//  comparer, sinon tout paraît expiré (1,7e9 < 1,7e12).
// =========================================================

/// Borne une page demandée par l'URL. `limit` trop grand (ou absent)
/// retombe sur le défaut, jamais au-delà de `maxLimit` : une requête
/// ne peut pas demander 100 000 lignes et saturer le Worker.
export function parsePageQuery(url, opts = {}) {
  const defaultLimit = opts.defaultLimit ?? 200;
  const maxLimit = opts.maxLimit ?? 200;
  const params = url && url.searchParams ? url.searchParams : url;
  const rawLimit = Number(params && params.get ? params.get('limit') : NaN);
  const rawOffset = Number(params && params.get ? params.get('offset') : NaN);
  let limit = defaultLimit;
  if (Number.isFinite(rawLimit) && rawLimit > 0) {
    limit = Math.min(Math.floor(rawLimit), maxLimit);
  }
  let offset = 0;
  if (Number.isFinite(rawOffset) && rawOffset > 0) {
    // Plafond : un offset absurde ne doit pas faire un scan infini.
    offset = Math.min(Math.floor(rawOffset), 1_000_000);
  }
  return { limit, offset };
}

/// Enveloppe JSON d'une liste. `truncated` est vrai quand la page
/// ne contient pas la fin : le panel doit proposer « suivant ».
export function pageEnvelope(items, total, limit, offset) {
  const list = Array.isArray(items) ? items : [];
  const t = Number(total);
  const totalN = Number.isFinite(t) ? t : list.length;
  const lim = Number(limit);
  const off = Number(offset);
  const limitN = Number.isFinite(lim) ? lim : list.length;
  const offsetN = Number.isFinite(off) && off > 0 ? off : 0;
  return {
    items: list,
    total: totalN,
    limit: limitN,
    offset: offsetN,
    truncated: offsetN + list.length < totalN,
  };
}

/// Millisecondes, ou null si la valeur est vide / 0 / illisible.
/// Un nombre < 1e11 est traité comme des secondes Unix.
export function epochMs(value) {
  if (value == null || value === '') return null;
  const n = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(n) || n <= 0) return null;
  if (n < 1e11) return Math.round(n * 1000);
  return n;
}

/// Expression SQL qui normalise une colonne INTEGER (secondes ou ms).
/// `column` doit être un nom de colonne écrit dans le code, jamais
/// une saisie utilisateur (on l'interpole, on ne la lie pas).
export function epochSql(column) {
  if (!/^[a-zA-Z_][a-zA-Z0-9_.]*$/.test(column)) {
    throw new Error('epochSql: nom de colonne refuse');
  }
  return `(CASE WHEN ${column} > 0 AND ${column} < 100000000000 THEN ${column} * 1000 ELSE ${column} END)`;
}

/// Statut affiché d'une licence, recalculé à la lecture.
/// Le champ `status` en base reste souvent « active » après la date :
/// le tableau et le compteur « expirés » se contredisaient.
/// Gelé / banni restent gelé / banni, même si la date est passée.
/// expires_at null ou 0 = à vie (pas expiré).
export function liveLicenseStatus(status, expiresAt, now) {
  if (status === 'banned' || status === 'frozen') return status;
  const exp = epochMs(expiresAt);
  if (exp == null) {
    if (!status || status === 'active' || status === 'expired') return 'active';
    return status;
  }
  if (status && status !== 'active' && status !== 'expired') return status;
  return exp > now ? 'active' : 'expired';
}

/// Lit un COUNT(*) sans planter si D1 renvoie null.
export function num(row, key) {
  const v = Number(row && row[key]);
  return Number.isFinite(v) ? v : 0;
}

/// Journal Worker : on garde la cause pour l'opérateur, on retire
/// tout ce qui ressemble à un secret ou à un lien de flux.
export function redact(value) {
  return String(value == null ? '' : value)
    .replace(/Bearer\s+\S+/gi, 'Bearer [redacted]')
    .replace(
      /(password|passwd|token|secret|authorization|m3u_url|m3u)\s*[=:]\s*\S+/gi,
      '$1=[redacted]',
    )
    .slice(0, 500);
}

export function safeRoute(request) {
  try {
    return new URL(request.url).pathname.slice(0, 120);
  } catch (_) {
    return 'unknown';
  }
}
