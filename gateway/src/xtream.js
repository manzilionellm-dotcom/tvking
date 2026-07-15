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
 * Réécrit une playlist M3U : remplace la base + identifiants du FOURNISSEUR
 * par la base publique de la passerelle + les identifiants de l'utilisateur
 * passerelle. Ainsi le client ne voit jamais la ligne réelle.
 */
export function rewriteM3U(text, gwUser, gwPass) {
  if (!config.publicBase) return text;
  const upBase = config.upstreamBase.replace(/^https?:\/\//i, '');
  const gwUserE = encodeURIComponent(gwUser);
  const gwPassE = encodeURIComponent(gwPass);
  const upUserE = encodeURIComponent(config.upstreamUser);
  const upPassE = encodeURIComponent(config.upstreamPass);
  // 1) base http(s)://fournisseur[:port] → base publique passerelle
  let out = text.replace(
    new RegExp('https?://' + escapeRe(upBase), 'gi'),
    config.publicBase,
  );
  // 2) identifiants dans le chemin /kind/UPUSER/UPPASS/ → /kind/GWUSER/GWPASS/
  out = out.replace(
    new RegExp('/(live|movie|series)/' + escapeRe(upUserE) + '/' + escapeRe(upPassE) + '/', 'gi'),
    (_m, kind) => `/${kind}/${gwUserE}/${gwPassE}/`,
  );
  // 3) identifiants en query (get.php?username=…&password=…)
  out = out
    .replace(new RegExp('username=' + escapeRe(upUserE), 'gi'), 'username=' + gwUserE)
    .replace(new RegExp('password=' + escapeRe(upPassE), 'gi'), 'password=' + gwPassE);
  return out;
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
