// =========================================================
//  family_multi_mac.js — Ligne M3U unique partagée (multi-MAC)
// =========================================================
//  Module AUTONOME : aucune import depuis api_v1.js / worker.js
//  (évite les imports circulaires). Les chemins existants
//  (handleFamilyAddMember, upsertDeviceSource) lui sont INJECTÉS
//  en deps au moment du branchement.
//
//  Produit (rappel) :
//    • Toggle OFF → le Worker continue de 302 vers get.php / URL M3U
//      (zéro régression, c'est le comportement actuel).
//    • Toggle ON  → /api/m3u/{token} sert UN M3U généré, alimenté
//      par UNE seule session amont (credentials source_json de la
//      famille). N appareils (10–12 MAC) s'authentifient chacun
//      avec leur MAC mais voient le même flux fournisseur.
//    • Les device_sources des MAC pointent vers /api/m3u/{token}
//      (M3U partagé) et NON vers get.php direct.
//
//  Helpers exportés (contrat produit) :
//    parseBulkMacs, ensureFamilyMultiMac, ensureFamilyLinkToken,
//    enableSharedM3uLine, buildMultiMacM3u, refreshUpstreamIfExpired,
//    interceptFamilyProfile, sharedM3uSource.
// =========================================================

/// Plafond produit : l'admin colle 10–12 MAC. Au-delà on refuse.
export const MULTI_MAC_MAX = 12;

/// Durée de vie du cache M3U amont (ms). Assez court pour rattraper
/// un token qui expire, assez long pour ne pas marteler le fournisseur.
export const UPSTREAM_TTL_MS = 4 * 60 * 1000;

/// On rafraîchit UN PEU avant l'échéance d'un token signé (30 s).
const TOKEN_REFRESH_SKEW_MS = 30 * 1000;

/// Format canonique des MAC 7 MOTION : MK:XX:XX:XX:XX:XX.
const MAC_CANON_RX = /^MK(?::[0-9A-F]{2}){5}$/;

/// Cache mémoire par famille (isolate Worker). Un cold start refetch :
/// c'est voulu — ça rafraîchit les tokens. Clé = family_id.
const _upstreamCache = new Map();

/// Vide le cache (smoke tests uniquement).
export function _clearUpstreamCache() {
  _upstreamCache.clear();
}
export function _cacheGet(familyId) {
  return _upstreamCache.get(String(familyId)) || null;
}
export function _cacheSet(familyId, entry) {
  _upstreamCache.set(String(familyId), entry);
}

// ---------------------------------------------------------
//  parseBulkMacs — CSV / espaces / retours ligne → macList[]
// ---------------------------------------------------------

/// Normalise une MAC collée (avec ou sans préfixe MK, avec ou sans
/// deux-points) vers MK:XX:XX:XX:XX:XX. `null` si invalide.
export function normalizeFamilyMac(raw) {
  if (raw == null) return null;
  let s = String(raw).trim().toUpperCase();
  if (!s) return null;
  // On retire tout ce qui n'est pas hex — les séparateurs varient
  // (:, -, espaces). Le préfixe MK optionnel est retiré ensuite.
  if (s.startsWith('MK')) s = s.slice(2);
  const hex = s.replace(/[^0-9A-F]/g, '');
  // Format 7 MOTION = MK + 5 octets (MK:XX:XX:XX:XX:XX), pas une MAC
  // réseau à 6 octets. 10 hex = canonique ; 12 hex = on refuse (ça
  // produirait MK:aa:bb:cc:dd:ee:ff, rejeté par _MAC_RX).
  if (hex.length !== 10) return null;
  const pairs = hex.match(/../g);
  if (!pairs || pairs.length !== 5) return null;
  const mac = 'MK:' + pairs.join(':');
  return MAC_CANON_RX.test(mac) ? mac : null;
}

/// Découpe un CSV (virgules, points-virgules, espaces, newlines),
/// déduplique, plafonne à MULTI_MAC_MAX. N'échoue PAS sur un CSV
/// vide (cas « toggle ON sans nouvelles MAC » = on ne fait que
/// pointer les membres déjà là vers le lien partagé).
export function parseBulkMacs(macCsv) {
  const parts = String(macCsv || '')
    .split(/[,;\s]+/)
    .map((p) => p.trim())
    .filter(Boolean);
  const macs = [];
  const errors = [];
  const seen = new Set();
  for (const p of parts) {
    const n = normalizeFamilyMac(p);
    if (!n) {
      errors.push(p);
      continue;
    }
    if (seen.has(n)) continue;
    seen.add(n);
    macs.push(n);
  }
  if (macs.length > MULTI_MAC_MAX) {
    return {
      ok: false,
      error: 'too_many_macs',
      message: `Maximum ${MULTI_MAC_MAX} adresses MAC (tu en as collé ${macs.length}).`,
      macs: macs.slice(0, MULTI_MAC_MAX),
      errors,
    };
  }
  if (errors.length) {
    return {
      ok: false,
      error: 'bad_mac',
      message: `MAC invalide(s) : ${errors.slice(0, 3).join(', ')}. Format : MK:XX:XX:XX:XX:XX`,
      macs,
      errors,
    };
  }
  return { ok: true, macs, errors: [] };
}

// ---------------------------------------------------------
//  ensureFamilyMultiMac — colonnes additives à la volée
// ---------------------------------------------------------

/// ALTER idempotent (ignore « duplicate column »). À appeler après
/// ensureFamiliesTables, et en tête de handlePublicFamilyM3u pour
/// que le SELECT des nouvelles colonnes ne plante jamais.
export async function ensureFamilyMultiMac(env) {
  if (!env || !env.DB) return false;
  try {
    await env.DB.prepare(
      'ALTER TABLE families ADD COLUMN multi_mac_enabled INTEGER NOT NULL DEFAULT 0',
    ).run();
  } catch (_) { /* déjà là */ }
  try {
    await env.DB.prepare(
      'ALTER TABLE families ADD COLUMN multi_macs TEXT',
    ).run();
  } catch (_) { /* déjà là */ }
  return true;
}

/// Le toggle est-il effectivement ON ? Absent / 0 / NULL = OFF
/// (comportement actuel). On est strict : seule la valeur 1 allume.
export function isMultiMacEnabled(familyRow) {
  if (!familyRow) return false;
  return Number(familyRow.multi_mac_enabled) === 1;
}

// ---------------------------------------------------------
//  interceptFamilyProfile — ON → servir le M3U, OFF → 302
// ---------------------------------------------------------

/// Décide si une requête « profil famille » doit être interceptée
/// pour servir le M3U multi-MAC à la place du M3U / 302 direct.
///
///  - familyRow.multi_mac_enabled !== 1  → { intercept: false }
///    (c'est LE filet anti-régression : le 302 actuel est conservé)
///  - request absente (appel depuis handlePublicFamilyM3u) → on
///    se fie uniquement au toggle (on est déjà sur /api/m3u/:token)
///  - pathname /api/m3u/… ou …/player_api.php → intercept si ON
///    (player_api = hook Gateway, documenté dans
///    docs/INTEGRATION_FAMILY_MULTI_MAC.md ; le Worker ne réécrit
///    pas gateway/src/server.js).
export function interceptFamilyProfile(request, familyRow) {
  if (!isMultiMacEnabled(familyRow)) {
    return { intercept: false, reason: 'toggle_off' };
  }
  if (!request || !request.url) {
    return { intercept: true, familyId: familyRow.id || null, reason: 'toggle_on' };
  }
  let path = '';
  try { path = new URL(request.url).pathname || ''; } catch (_) { path = ''; }
  const isFamilyM3u = /\/api\/m3u\//i.test(path);
  const isPlayerApi = /player_api\.php$/i.test(path);
  if (!isFamilyM3u && !isPlayerApi) {
    return { intercept: false, reason: 'not_profile_route', path };
  }
  return {
    intercept: true,
    familyId: familyRow.id || null,
    path,
    reason: isFamilyM3u ? 'family_m3u' : 'player_api',
  };
}

// ---------------------------------------------------------
//  Source M3U partagée (ce qu'on pousse à chaque MAC)
// ---------------------------------------------------------

/// Source normalisée « type m3u » pointant vers le lien public de
/// la famille — PAS vers get.php direct. C'est ça qui fait que le
/// fournisseur ne voit qu'UNE session (celle du Worker).
export function sharedM3uSource(origin, token, label) {
  const base = String(origin || '').replace(/\/+$/, '');
  const tok = String(token || '').trim();
  return {
    type: 'm3u',
    label: label || 'Famille (ligne partagée)',
    server_url: null,
    username: null,
    password: null,
    m3u_url: `${base}/api/m3u/${tok}`,
    epg_url: null,
  };
}

/// Garantit qu'un jeton family_links existe pour cette famille.
/// Réutilise le plus ancien (inchangé pour les liens déjà distribués)
/// ; n'en crée un que s'il n'y en a aucun.
export async function ensureFamilyLinkToken(env, familyId, genIdFn) {
  const existing = await env.DB.prepare(
    'SELECT token FROM family_links WHERE family_id = ? ORDER BY created_at ASC LIMIT 1',
  ).bind(familyId).first();
  if (existing && existing.token) return String(existing.token);
  const token = (globalThis.crypto && crypto.randomUUID)
    ? crypto.randomUUID().replace(/-/g, '')
    : (`t${Date.now().toString(16)}${Math.random().toString(16).slice(2)}`).slice(0, 32);
  const id = typeof genIdFn === 'function'
    ? genIdFn('lnk')
    : `lnk_${Date.now().toString(36)}`;
  await env.DB.prepare(
    `INSERT INTO family_links (id, family_id, token, label, created_at)
     VALUES (?, ?, ?, ?, ?)`,
  ).bind(id, familyId, token, 'multi-mac', Date.now()).run();
  return token;
}

// ---------------------------------------------------------
//  Amont : URL get.php / M3U + rafraîchissement des tokens
// ---------------------------------------------------------

/// Parse source_json (objet ou chaîne). `null` si illisible.
export function parseFamilySource(sourceJson) {
  if (!sourceJson) return null;
  if (typeof sourceJson === 'object') return sourceJson;
  try { return JSON.parse(sourceJson); } catch (_) { return null; }
}

/// Construit l'URL amont UNIQUE à partir des credentials famille.
/// Xtream → get.php (une ligne) ; M3U → l'URL telle quelle.
export function upstreamM3uUrlFromSource(src) {
  if (!src) return null;
  if (src.type === 'xtream' && src.server_url && src.username && src.password) {
    const base = String(src.server_url).replace(/\/+$/, '');
    const u = encodeURIComponent(src.username);
    const p = encodeURIComponent(src.password);
    return `${base}/get.php?username=${u}&password=${p}&type=m3u_plus&output=ts`;
  }
  if ((src.type === 'm3u' || !src.type) && src.m3u_url) return src.m3u_url;
  return null;
}

/// Cherche dans un M3U la plus proche échéance d'un token signé
/// (`expires=`, `exp=`, `expire=`, `validuntil=` — secondes ou ms).
/// `null` si aucun timestamp trouvé (playlist Xtream classique
/// /live/user/pass/id.ts → pas de token à rafraîchir).
export function earliestTokenExpiryMs(m3u) {
  if (!m3u) return null;
  const re = /[?&](?:expires|exp|expire|validuntil)=(\d+)/gi;
  let min = Infinity;
  let m;
  while ((m = re.exec(String(m3u)))) {
    let ts = Number(m[1]);
    if (!Number.isFinite(ts) || ts <= 0) continue;
    // Heuristique : < 10^12 = secondes Unix, sinon millisecondes.
    if (ts < 1e12) ts *= 1000;
    if (ts < min) min = ts;
  }
  return min === Infinity ? null : min;
}

/// Un cache est-il encore utilisable à `now` ?
export function isUpstreamCacheFresh(entry, now) {
  if (!entry || !entry.m3u) return false;
  const t = Number(now) || Date.now();
  const fetched = Number(entry.fetchedAt) || 0;
  if (fetched && (t - fetched) > UPSTREAM_TTL_MS) return false;
  if (entry.expiresAt && (Number(entry.expiresAt) - TOKEN_REFRESH_SKEW_MS) <= t) {
    return false;
  }
  return true;
}

/// Récupère (ou raffraîchit) le M3U amont. `sourceJson` = objet ou
/// chaîne. `cacheEntry` = { m3u, fetchedAt, expiresAt } ou null.
/// `fetchFn` injectable (smoke tests) — défaut = fetch global.
///
/// Si le fetch échoue MAIS qu'on a un cache (même périmé), on le
/// sert : mieux vaut une playlist un peu vieille qu'un 502.
export async function refreshUpstreamIfExpired(
  sourceJson,
  cacheEntry = null,
  now = Date.now(),
  fetchFn = fetch,
) {
  const src = parseFamilySource(sourceJson);
  const url = upstreamM3uUrlFromSource(src);
  if (!url) {
    return { error: 'source incomplète', m3u: null, refreshed: false };
  }
  if (isUpstreamCacheFresh(cacheEntry, now)) {
    return {
      m3u: cacheEntry.m3u,
      fetchedAt: cacheEntry.fetchedAt,
      expiresAt: cacheEntry.expiresAt || null,
      refreshed: false,
      url,
    };
  }
  try {
    const ctrl = (typeof AbortController !== 'undefined') ? new AbortController() : null;
    const timer = ctrl ? setTimeout(() => { try { ctrl.abort(); } catch (_) {} }, 15000) : null;
    const resp = await fetchFn(url, ctrl ? { signal: ctrl.signal } : {});
    if (timer) clearTimeout(timer);
    if (!resp || (typeof resp.ok === 'boolean' && !resp.ok) || (resp.status && resp.status >= 400)) {
      const status = resp && resp.status ? resp.status : 0;
      if (cacheEntry && cacheEntry.m3u) {
        return {
          m3u: cacheEntry.m3u,
          fetchedAt: cacheEntry.fetchedAt,
          expiresAt: cacheEntry.expiresAt || null,
          refreshed: false,
          stale: true,
          url,
        };
      }
      return { error: `amont HTTP ${status || 'erreur'}`, m3u: null, refreshed: false, url };
    }
    const m3u = await resp.text();
    if (!m3u || !String(m3u).trim()) {
      if (cacheEntry && cacheEntry.m3u) {
        return { ...cacheEntry, refreshed: false, stale: true, url };
      }
      return { error: 'playlist amont vide', m3u: null, refreshed: false, url };
    }
    const tokenExp = earliestTokenExpiryMs(m3u);
    const fetchedAt = now;
    // expiresAt = min(token, TTL). Si pas de token, le TTL seul compte.
    const ttlExp = fetchedAt + UPSTREAM_TTL_MS;
    const expiresAt = tokenExp ? Math.min(tokenExp, ttlExp) : ttlExp;
    return { m3u, fetchedAt, expiresAt, refreshed: true, url };
  } catch (e) {
    if (cacheEntry && cacheEntry.m3u) {
      return {
        m3u: cacheEntry.m3u,
        fetchedAt: cacheEntry.fetchedAt,
        expiresAt: cacheEntry.expiresAt || null,
        refreshed: false,
        stale: true,
        url,
      };
    }
    return {
      error: 'amont injoignable',
      m3u: null,
      refreshed: false,
      url,
    };
  }
}

/// Construit le M3U servi aux N MAC. UNE session amont (cache
/// partagé par family_id). N'est appelé que si le toggle est ON.
export async function buildMultiMacM3u(env, fam, opts = {}) {
  const now = opts.now || Date.now();
  const fetchFn = opts.fetchFn || fetch;
  if (!fam || !fam.source_json) {
    return { error: 'source absente', status: 404 };
  }
  const familyId = fam.id || 'unknown';
  const cached = _cacheGet(familyId);
  const refreshed = await refreshUpstreamIfExpired(fam.source_json, cached, now, fetchFn);
  if (refreshed.error && !refreshed.m3u) {
    return { error: refreshed.error, status: 502 };
  }
  _cacheSet(familyId, {
    m3u: refreshed.m3u,
    fetchedAt: refreshed.fetchedAt,
    expiresAt: refreshed.expiresAt,
  });
  return {
    m3u: refreshed.m3u,
    refreshed: !!refreshed.refreshed,
    stale: !!refreshed.stale,
    url: refreshed.url || null,
  };
}

// ---------------------------------------------------------
//  enableSharedM3uLine — sauve le toggle + active les MAC
// ---------------------------------------------------------

/// Persiste toggle + CSV, et SI enabled :
///   1. assure un jeton family_links (ensureFamilyLinkToken)
///   2. pour chaque MAC du CSV : active via le chemin existant
///      (`deps.activateMember` = handleFamilyAddMember) puis
///      ÉCRASE la source Xtream par le M3U /api/m3u/{token}
///   3. re-pointe AUSSI les membres déjà là vers ce même lien
///
/// SI disabled : on sauve juste le flag (handlePublicFamilyM3u
/// retombe sur le 302 actuel). On ne touche pas aux sources.
export async function enableSharedM3uLine(env, opts) {
  const familyId = opts && opts.familyId;
  const macCsv = (opts && opts.macCsv) || '';
  const multiMacEnabled = !!(opts && opts.multiMacEnabled);
  const origin = (opts && opts.origin) || '';
  const now = (opts && opts.now) || Date.now();
  const deps = (opts && opts.deps) || {};
  const upsertDeviceSource = deps.upsertDeviceSource;
  const activateMember = deps.activateMember;
  const genIdFn = deps.genId;

  if (!familyId) return { ok: false, error: 'missing_family', message: 'familyId required' };

  const parsed = parseBulkMacs(macCsv);
  if (!parsed.ok) {
    return { ok: false, error: parsed.error, message: parsed.message, macs: parsed.macs };
  }

  await ensureFamilyMultiMac(env);

  const fam = await env.DB.prepare('SELECT * FROM families WHERE id = ?')
    .bind(familyId).first();
  if (!fam) return { ok: false, error: 'not_found', message: 'Family not found' };

  await env.DB.prepare(
    `UPDATE families
        SET multi_mac_enabled = ?, multi_macs = ?, updated_at = ?
      WHERE id = ?`,
  ).bind(multiMacEnabled ? 1 : 0, macCsv, now, familyId).run();

  // OFF : on s'arrête là. /api/m3u/:token redevient un 302.
  if (!multiMacEnabled) {
    return {
      ok: true,
      family_id: familyId,
      multi_mac_enabled: false,
      macs: parsed.macs,
      token: null,
      activated: [],
      errors: [],
    };
  }

  const token = await ensureFamilyLinkToken(env, familyId, genIdFn);
  const source = sharedM3uSource(origin, token, fam.name);
  const activated = [];
  const errors = [];

  // 1) MAC collées : chemin existant (activate + membre) puis overwrite M3U.
  for (const mac of parsed.macs) {
    try {
      if (typeof activateMember === 'function') {
        const act = await activateMember(mac);
        if (act && typeof act.status === 'number' && act.status >= 400) {
          let msg = 'activate_failed';
          try {
            const body = await act.clone().json();
            msg = (body && (body.message || body.error)) || msg;
          } catch (_) { /* ignore */ }
          errors.push({ mac, error: msg });
          continue;
        }
      }
      if (typeof upsertDeviceSource === 'function') {
        await upsertDeviceSource(env, mac, [source]);
      }
      activated.push(mac);
    } catch (e) {
      errors.push({ mac, error: String(e && e.message ? e.message : e) });
    }
  }

  // 2) Membres déjà dans la famille (ajoutés un par un avant le toggle) :
  //    on les re-pointe aussi vers le lien partagé, sinon ILS continueraient
  //    à frapper get.php en direct.
  try {
    const members = await env.DB.prepare(
      'SELECT mac FROM family_members WHERE family_id = ?',
    ).bind(familyId).all();
    const already = new Set(activated);
    for (const r of (members && members.results) || []) {
      const mac = String(r.mac || '').toUpperCase();
      if (!mac || already.has(mac)) continue;
      try {
        if (typeof upsertDeviceSource === 'function') {
          await upsertDeviceSource(env, mac, [source]);
        }
        activated.push(mac);
      } catch (e) {
        errors.push({ mac, error: String(e && e.message ? e.message : e) });
      }
    }
  } catch (_) { /* table vide / absente : on ignore */ }

  return {
    ok: errors.length === 0,
    family_id: familyId,
    multi_mac_enabled: true,
    macs: parsed.macs,
    token,
    m3u_url: source.m3u_url,
    activated,
    errors,
  };
}
