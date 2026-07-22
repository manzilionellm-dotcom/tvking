// =========================================================
//  upstream.js — Client de la ligne fournisseur (undici)
// =========================================================
//  Un SEUL point de sortie vers le fournisseur. Gère :
//   • l'User-Agent d'un vrai lecteur ;
//   • les certificats TLS invalides (fréquents en IPTV) si autorisé ;
//   • le suivi des redirections ;
//   • l'ouverture d'un flux (corps = Readable Node, pipeable).
// =========================================================
import { Agent, request } from 'undici';
import { config } from './config.js';

// Agent réutilisé (pool de connexions). rejectUnauthorized selon config.
const agent = new Agent({
  connect: { rejectUnauthorized: !config.allowInsecureTls },
  // Un flux live est long : pas de timeout de corps agressif.
  bodyTimeout: 0,
  headersTimeout: 60_000,
  keepAliveTimeout: 30_000,
});

function base() { return config.upstreamBase; }

/** Liste ordonnée des bases fournisseur (principale puis secours). */
export function upstreamBases() {
  return config.upstreamBases && config.upstreamBases.length
    ? config.upstreamBases
    : [config.upstreamBase];
}

/** Suffixe d'URL d'un flux (SANS base) : /kind/user/pass/id.ext. */
export function upstreamStreamPath(kind, streamId, ext) {
  const u = encodeURIComponent(config.upstreamUser);
  const p = encodeURIComponent(config.upstreamPass);
  return `/${kind}/${u}/${p}/${streamId}.${ext}`;
}

/** Construit l'URL upstream d'un flux (base principale + suffixe). */
export function upstreamStreamUrl(kind, streamId, ext) {
  return `${base()}${upstreamStreamPath(kind, streamId, ext)}`;
}

/** Appel player_api.php avec les identifiants de la LIGNE (upstream). */
export async function callPlayerApi(params) {
  const usp = new URLSearchParams({
    username: config.upstreamUser,
    password: config.upstreamPass,
    ...params,
  });
  const url = `${base()}/player_api.php?${usp.toString()}`;
  const res = await request(url, {
    method: 'GET',
    dispatcher: agent,
    maxRedirections: config.maxRedirects,
    headers: { 'user-agent': config.userAgent, accept: 'application/json' },
  });
  const text = await res.body.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* renvoyé brut si non-JSON */ }
  return { status: res.statusCode, json, text };
}

/** Récupère un M3U (get.php) avec les identifiants de la ligne — bufferisé.
 *  Conservé pour compatibilité ; le chemin chaud utilise openGetPhp (stream). */
export async function callGetPhp(params) {
  const res = await openGetPhp(params);
  const text = await res.body.text();
  return { status: res.statusCode, text };
}

/**
 * Ouvre get.php en STREAMING (corps = Readable, non bufferisé). Permet de
 * réécrire la playlist ligne par ligne sans charger des dizaines de Mo en
 * mémoire ni bloquer l'event-loop mono-thread avec un regex géant.
 * Renvoie { statusCode, headers, body }.
 */
export async function openGetPhp(params, signal) {
  const usp = new URLSearchParams({
    username: config.upstreamUser,
    password: config.upstreamPass,
    ...params,
  });
  const url = `${base()}/get.php?${usp.toString()}`;
  return request(url, {
    method: 'GET',
    dispatcher: agent,
    maxRedirections: config.maxRedirects,
    headers: { 'user-agent': config.userAgent },
    signal,
  });
}

/**
 * Ouvre un flux upstream. Renvoie { statusCode, headers, body (Readable) }.
 * Le body doit être consommé/détruit par l'appelant. `signal` permet
 * d'annuler (fermeture de session).
 */
export async function openStream(url, signal) {
  const res = await request(url, {
    method: 'GET',
    dispatcher: agent,
    maxRedirections: config.maxRedirects,
    headers: { 'user-agent': config.userAgent },
    signal,
  });
  return res; // { statusCode, headers, body }
}

/** Proxy direct (VOD, EPG…) : non mutualisé, renvoie la réponse telle quelle. */
export async function proxyRaw(url, signal, extraHeaders) {
  return request(url, {
    method: 'GET',
    dispatcher: agent,
    maxRedirections: config.maxRedirects,
    headers: { 'user-agent': config.userAgent, ...(extraHeaders || {}) },
    signal,
  });
}

/**
 * Proxy direct AVEC failover de ligne : essaie chaque base (principale puis
 * secours) pour [streamPath] et renvoie la 1re réponse exploitable. On bascule
 * uniquement sur une panne de LIGNE (erreur réseau ou 5xx) — un 4xx (film
 * absent) est renvoyé tel quel (les lignes de secours sont des miroirs, pas des
 * catalogues différents). Avec une seule base : identique à proxyRaw.
 */
export async function proxyRawFailover(streamPath, signal, extraHeaders) {
  const bases = upstreamBases();
  let lastErr = null;
  for (let i = 0; i < bases.length; i++) {
    try {
      const up = await proxyRaw(bases[i] + streamPath, signal, extraHeaders);
      if (up.statusCode >= 500 && i < bases.length - 1) {
        // Corps jeté : absorbe ses erreurs (AbortError sur signal partagé).
        try { up.body.on('error', () => {}); up.body.destroy(); } catch { /* ignore */ }
        continue; // ligne en panne (5xx) → suivante
      }
      return up;
    } catch (e) {
      lastErr = e;
      if (i < bases.length - 1) continue; // erreur réseau → ligne suivante
      throw e;
    }
  }
  throw lastErr || new Error('aucune base fournisseur');
}
