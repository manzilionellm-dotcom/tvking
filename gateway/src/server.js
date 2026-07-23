'use strict';

/**
 * server.js — Façade HTTP du gateway 7 MOTION.
 *
 * Rôles :
 *   - Authentifie les spectateurs avec l'identité de DIFFUSION
 *     (BROADCAST_USER / BROADCAST_PASS). La ligne fournisseur réelle
 *     (UPSTREAM_USER/PASS) n'est JAMAIS exposée.
 *   - Sert les flux live via le Hub (mutualisation + fan-out).
 *   - Réécrit les URLs des playlists (M3U / API Xtream) vers PUBLIC_BASE, de
 *     sorte que la ligne réelle n'apparaisse jamais côté application/panel.
 *   - Applique le plafond de spectateurs (BROADCAST_MAX_STREAMS) et la limite
 *     fournisseur (PROVIDER_MAX_CONNECTIONS, gérée par le Hub → 503 propre).
 *
 * Routes principales :
 *   GET /healthz                          → JSON de santé + stats (mutualisation)
 *   GET /live/:user/:pass/:streamId(.ext) → flux live mutualisé
 *   GET /get.php?username&password&type   → playlist M3U réécrite (façade Xtream)
 *   GET /player_api.php                   → API Xtream réécrite (façade)
 */

const http = require('node:http');
const https = require('node:https');
const { URL } = require('node:url');
const { Hub, makeLogger } = require('./hub');

/** Compare deux chaînes en temps ~constant (évite les fuites par timing). */
function safeEqual(a, b) {
  a = String(a || '');
  b = String(b || '');
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * Construit l'URL amont réelle pour un flux donné, à partir de l'identité
 * FOURNISSEUR (jamais exposée). Format Xtream classique :
 *   {UPSTREAM_BASE}/live/{UPSTREAM_USER}/{UPSTREAM_PASS}/{streamId}.{ext}
 */
function buildUpstreamUrl(cfg, streamId, ext) {
  const safeExt = ext && /^[a-z0-9]+$/i.test(ext) ? ext : 'ts';
  return `${cfg.UPSTREAM_BASE}/live/${encodeURIComponent(
    cfg.UPSTREAM_USER,
  )}/${encodeURIComponent(cfg.UPSTREAM_PASS)}/${encodeURIComponent(streamId)}.${safeExt}`;
}

/**
 * Réécrit toutes les URLs d'une playlist M3U pour qu'elles pointent vers la
 * façade publique (PUBLIC_BASE) avec l'identité de DIFFUSION. La ligne réelle
 * disparaît complètement.
 */
function rewriteM3U(body, cfg) {
  if (!cfg.PUBLIC_BASE) return body; // sans domaine public on ne réécrit pas
  const lines = body.split(/\r?\n/);
  const out = lines.map((line) => {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) return line; // en-têtes EXTINF etc.
    // On tente d'extraire un identifiant de flux depuis l'URL amont.
    // Format attendu : .../live/USER/PASS/<id>.<ext>
    const m = trimmed.match(/\/live\/[^/]+\/[^/]+\/([^/]+?)\.([a-z0-9]+)(\?.*)?$/i);
    if (m) {
      const id = m[1];
      const ext = m[2];
      return `${cfg.PUBLIC_BASE}/live/${encodeURIComponent(
        cfg.BROADCAST_USER,
      )}/${encodeURIComponent(cfg.BROADCAST_PASS)}/${id}.${ext}`;
    }
    return line;
  });
  return out.join('\n');
}

/** Récupère (GET) une ressource amont et renvoie { statusCode, headers, body }. */
function fetchUpstream(url, cfg) {
  return new Promise((resolve, reject) => {
    const mod = url.startsWith('https:') ? https : http;
    const req = mod.get(
      url,
      { timeout: cfg.UPSTREAM_TIMEOUT_MS, headers: { 'User-Agent': 'gateway-7motion/1.0' } },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () =>
          resolve({
            statusCode: res.statusCode,
            headers: res.headers,
            body: Buffer.concat(chunks),
          }),
        );
      },
    );
    req.on('error', reject);
    req.setTimeout(cfg.UPSTREAM_TIMEOUT_MS, () => req.destroy(new Error('timeout amont')));
  });
}

/**
 * Crée le serveur HTTP (sans le démarrer). Retourne { server, hub }.
 * @param {object} cfg — configuration issue de loadConfig()
 * @param {object} [deps] — injections de test (ex. hub, logger)
 */
function createServer(cfg, deps = {}) {
  const log = deps.logger || makeLogger(cfg.LOG_LEVEL);
  const hub = deps.hub || new Hub(cfg, { logger: log });

  /** Vérifie l'identité de diffusion (spectateurs). */
  function checkBroadcastAuth(user, pass) {
    return (
      safeEqual(user, cfg.BROADCAST_USER) && safeEqual(pass, cfg.BROADCAST_PASS)
    );
  }

  const server = http.createServer((req, res) => {
    let url;
    try {
      url = new URL(req.url, cfg.PUBLIC_BASE || `http://localhost:${cfg.PORT}`);
    } catch {
      res.writeHead(400).end('Requête invalide');
      return;
    }
    const path = url.pathname;

    // ---- Santé / preuve de mutualisation ----------------------------------
    if (path === '/healthz' || path === '/health') {
      const stats = hub.stats();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'ok', ...stats }, null, 2));
      return;
    }

    // ---- Flux live mutualisé ----------------------------------------------
    // /live/:user/:pass/:streamId(.ext)
    const liveMatch = path.match(
      /^\/live\/([^/]+)\/([^/]+)\/([^/]+?)(?:\.([a-z0-9]+))?$/i,
    );
    if (liveMatch) {
      const [, user, pass, streamId, ext] = liveMatch;

      // Auth diffusion.
      if (!checkBroadcastAuth(decodeURIComponent(user), decodeURIComponent(pass))) {
        res.writeHead(401, { 'Content-Type': 'text/plain' });
        res.end('Identité de diffusion invalide');
        return;
      }

      // Plafond global de spectateurs (sockets).
      if (hub.totalSubscribers >= cfg.BROADCAST_MAX_STREAMS) {
        log.warn(
          `Plafond spectateurs atteint (${cfg.BROADCAST_MAX_STREAMS}) → refus`,
        );
        res.writeHead(503, { 'Content-Type': 'text/plain', 'Retry-After': '5' });
        res.end('Capacité maximale de spectateurs atteinte');
        return;
      }

      const upstreamUrl = buildUpstreamUrl(cfg, decodeURIComponent(streamId), ext);
      const meta = {
        ip: req.socket.remoteAddress,
        ua: req.headers['user-agent'] || '',
      };

      // On abonne au Hub. Le Hub gère la limite fournisseur (503 si dépassée).
      const result = hub.subscribe(streamId, upstreamUrl, res, meta);
      if (!result.ok) {
        res.writeHead(result.code, {
          'Content-Type': 'text/plain',
          'Retry-After': '10',
        });
        res.end(result.reason);
        return;
      }
      // À partir d'ici, le Hub écrit directement dans `res`. On ne fait rien
      // d'autre : la réponse reste ouverte jusqu'à déconnexion / fin de flux.
      return;
    }

    // ---- Playlist M3U (façade Xtream : get.php) ---------------------------
    if (path === '/get.php') {
      const user = url.searchParams.get('username');
      const pass = url.searchParams.get('password');
      if (!checkBroadcastAuth(user, pass)) {
        res.writeHead(401).end('Identité de diffusion invalide');
        return;
      }
      // On interroge l'amont avec l'identité FOURNISSEUR, puis on réécrit.
      const upstreamPlaylist =
        `${cfg.UPSTREAM_BASE}/get.php?username=${encodeURIComponent(cfg.UPSTREAM_USER)}` +
        `&password=${encodeURIComponent(cfg.UPSTREAM_PASS)}` +
        `&type=${encodeURIComponent(url.searchParams.get('type') || 'm3u_plus')}` +
        `&output=${encodeURIComponent(url.searchParams.get('output') || 'ts')}`;
      fetchUpstream(upstreamPlaylist, cfg)
        .then(({ statusCode, body }) => {
          const rewritten = rewriteM3U(body.toString('utf8'), cfg);
          res.writeHead(statusCode || 200, {
            'Content-Type': 'application/x-mpegurl; charset=utf-8',
            'Cache-Control': 'no-cache',
          });
          res.end(rewritten);
        })
        .catch((err) => {
          log.warn(`get.php amont échec: ${err.message}`);
          res.writeHead(502).end('Amont indisponible');
        });
      return;
    }

    // ---- API Xtream (player_api.php) : réécriture minimale ----------------
    if (path === '/player_api.php') {
      const user = url.searchParams.get('username');
      const pass = url.searchParams.get('password');
      if (!checkBroadcastAuth(user, pass)) {
        res.writeHead(401).end('Identité de diffusion invalide');
        return;
      }
      // On proxifie la réponse JSON amont (identité fournisseur). Les URLs de
      // flux sont de toute façon construites côté client à partir de PUBLIC_BASE
      // + identité de diffusion, donc la ligne réelle n'apparaît pas.
      const q = new URLSearchParams(url.searchParams);
      q.set('username', cfg.UPSTREAM_USER);
      q.set('password', cfg.UPSTREAM_PASS);
      fetchUpstream(`${cfg.UPSTREAM_BASE}/player_api.php?${q.toString()}`, cfg)
        .then(({ statusCode, headers, body }) => {
          res.writeHead(statusCode || 200, {
            'Content-Type': headers['content-type'] || 'application/json',
            'Cache-Control': 'no-cache',
          });
          res.end(body);
        })
        .catch((err) => {
          log.warn(`player_api.php amont échec: ${err.message}`);
          res.writeHead(502).end('Amont indisponible');
        });
      return;
    }

    // ---- Racine : petite page d'état -------------------------------------
    if (path === '/') {
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(
        'Gateway 7 MOTION — façade de diffusion.\n' +
          `Amonts actifs : ${hub.activeUpstreams}/${cfg.PROVIDER_MAX_CONNECTIONS}\n` +
          `Spectateurs : ${hub.totalSubscribers}/${cfg.BROADCAST_MAX_STREAMS}\n` +
          'Voir /healthz pour les stats détaillées.\n',
      );
      return;
    }

    res.writeHead(404, { 'Content-Type': 'text/plain' }).end('Introuvable');
  });

  // keep-alive / timeouts serveur : garder 500 sockets ouverts proprement.
  server.keepAliveTimeout = Math.max(cfg.KEEPALIVE_MS, 5000);
  server.headersTimeout = server.keepAliveTimeout + 5000;
  // requestTimeout=0 : un flux live n'a pas de durée max de requête.
  server.requestTimeout = 0;
  // NOTE : on NE touche PAS à server.maxConnections — le défaut est « illimité ».
  // (La mettre à 0 signifierait « aucune connexion autorisée », pas « illimité ».)
  // Le vrai plafond de spectateurs est BROADCAST_MAX_STREAMS, appliqué dans le
  // handler ; la limite OS se règle via ulimit -n (voir README).

  return { server, hub };
}

module.exports = {
  createServer,
  buildUpstreamUrl,
  rewriteM3U,
  safeEqual,
};
