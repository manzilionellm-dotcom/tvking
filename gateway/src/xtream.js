// =========================================================
//  xtream.js — Façade compatible Xtream Codes
// =========================================================
//  Les apps (7 MOTION, IBO, Smarters…) pointent sur la passerelle comme
//  sur un panel Xtream normal. On :
//   • valide l'utilisateur passerelle (papa/clones) ;
//   • réécrit les URLs des playlists / server_info pour qu'elles tapent le
//     VPS (et non le fournisseur) ;
//   • laisse le hub mutualiser les flux live identiques.
// =========================================================
import { config } from './config.js';

// /live|/movie|/series/:user/:pass/:id.:ext  → { kind, streamId, ext }
const STREAM_RE = /^\/(live|movie|series)\/([^/]+)\/([^/]+)\/([^/]+?)\.([a-z0-9]+)$/i;
// Live « court » sans segment /live/ : /:user/:pass/:id[.ext]
const SHORT_RE = /^\/([^/]+)\/([^/]+)\/(\d+)(?:\.([a-z0-9]+))?$/i;

export function parseStreamPath(pathname) {
  let m = STREAM_RE.exec(pathname);
  if (m) {
    return { kind: m[1].toLowerCase(), user: decodeURIComponent(m[2]), pass: decodeURIComponent(m[3]), streamId: m[4], ext: m[5].toLowerCase() };
  }
  m = SHORT_RE.exec(pathname);
  if (m) {
    return { kind: 'live', user: decodeURIComponent(m[1]), pass: decodeURIComponent(m[2]), streamId: m[3], ext: (m[4] || 'ts').toLowerCase() };
  }
  return null;
}

/** Clé de mutualisation : indépendante de l'utilisateur, propre à la chaîne. */
export function streamKey(kind, streamId, ext) {
  return `${kind}:${streamId}.${ext}`;
}

/**
 * Fabrique un réécrivain de playlist M3U réutilisable : compile les 4 motifs
 * UNE seule fois, puis les applique à une chaîne (ligne ou texte entier).
 * Aucun motif ne franchit un saut de ligne (base+identifiants tiennent sur la
 * MÊME ligne d'URL), donc appliquer ligne par ligne est STRICTEMENT équivalent
 * à l'appliquer au texte entier — ce qui permet le streaming (voir server.js).
 * @returns {((s: string) => string) | null} null si aucune réécriture requise.
 */
export function makeM3URewriter(gwUser, gwPass) {
  if (!config.publicBase) return null;
  const upBase = config.upstreamBase.replace(/^https?:\/\//i, '');
  const gwUserE = encodeURIComponent(gwUser);
  const gwPassE = encodeURIComponent(gwPass);
  const upUserE = encodeURIComponent(config.upstreamUser);
  const upPassE = encodeURIComponent(config.upstreamPass);
  const reBase = new RegExp('https?://' + escapeRe(upBase), 'gi');
  const rePath = new RegExp('/(live|movie|series)/' + escapeRe(upUserE) + '/' + escapeRe(upPassE) + '/', 'gi');
  const reUser = new RegExp('username=' + escapeRe(upUserE), 'gi');
  const rePass = new RegExp('password=' + escapeRe(upPassE), 'gi');
  // String.prototype.replace réinitialise lastIndex : réutiliser ces regex
  // globales d'un appel à l'autre est sûr.
  return (s) => s
    .replace(reBase, config.publicBase)
    .replace(rePath, (_m, kind) => `/${kind}/${gwUserE}/${gwPassE}/`)
    .replace(reUser, 'username=' + gwUserE)
    .replace(rePass, 'password=' + gwPassE);
}

/**
 * Réécrit une playlist M3U entière (remplace la base + identifiants du
 * FOURNISSEUR par la base publique de la passerelle + les identifiants de
 * l'utilisateur passerelle). Conservé pour les appels non-streaming/tests.
 */
export function rewriteM3U(text, gwUser, gwPass) {
  const fn = makeM3URewriter(gwUser, gwPass);
  return fn ? fn(text) : text;
}

/** Ajuste server_info d'un player_api pour pointer sur la passerelle. */
export function rewritePlayerApi(json) {
  if (!json || typeof json !== 'object' || !config.publicBase) return json;
  try {
    const u = new URL(config.publicBase);
    if (json.server_info) {
      json.server_info.url = u.hostname;
      json.server_info.server_url = u.hostname;
      json.server_info.port = u.port || (u.protocol === 'https:' ? '443' : '80');
      json.server_info.https_port = u.protocol === 'https:' ? (u.port || '443') : json.server_info.https_port;
    }
  } catch { /* URL publique invalide : on laisse tel quel */ }
  return json;
}

function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
