// =========================================================
//  server.js — Serveur HTTP + routage de la passerelle
// =========================================================
import http from 'node:http';
import { config } from './config.js';
import { log } from './logger.js';
import { metrics } from './metrics.js';
import { authenticate, listUsers, loadUsers } from './users.js';
import { acquireSession, snapshotSessions } from './limits.js';
import { hub } from './hub.js';
import { parseStreamPath, streamKey, rewriteM3U, rewritePlayerApi } from './xtream.js';
import {
  callPlayerApi, callGetPhp, proxyRaw, upstreamStreamUrl,
} from './upstream.js';

const START = Date.now();

function sendJson(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' });
  res.end(body);
}
function sendText(res, status, text, ctype = 'text/plain; charset=utf-8') {
  res.writeHead(status, { 'content-type': ctype });
  res.end(text);
}

function adminOk(url, req) {
  if (!config.adminToken) return false; // désactivé si pas de jeton
  const bearer = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  const token = bearer || url.searchParams.get('token') || '';
  return token && token === config.adminToken;
}

function mapErr(code) {
  switch (code) {
    case 'provider_limit':
      return 'Ligne saturée : nombre maximum de connexions fournisseur atteint.';
    case 'user_limit':
      return 'Trop d\'écrans ouverts pour cet utilisateur.';
    case 'family_limit':
      return 'Limite de la famille atteinte (écrans simultanés).';
    case 'upstream_error':
      return 'Le fournisseur a refusé ce flux.';
    default:
      return 'Flux indisponible pour le moment.';
  }
}

// ---- Handlers ----------------------------------------------------------

async function handleLive(streamId, ext, req, res, user) {
  const sess = acquireSession(user);
  if (!sess.ok) {
    metrics.inc('gw_rejected_session_total', 1, { reason: sess.code });
    return sendText(res, 429, mapErr(sess.code));
  }
  res.on('close', () => sess.release());
  const key = streamKey('live', streamId, ext);
  const url = upstreamStreamUrl('live', streamId, ext);
  metrics.inc('gw_live_requests_total');
  const r = await hub.subscribe(key, url, res);
  if (!r.ok) {
    sess.release();
    if (!res.headersSent && !res.writableEnded) {
      sendText(res, r.status || 502, mapErr(r.code));
    } else {
      try { res.end(); } catch { /* */ }
    }
  }
}

async function handleVod(kind, streamId, ext, req, res, user) {
  // VOD/série : jamais mutualisé (chacun sa position), mais compté dans la
  // limite fournisseur comme une vraie connexion.
  const release = hub.reserveRaw();
  if (!release) return sendText(res, 503, mapErr('provider_limit'));
  const sess = acquireSession(user);
  if (!sess.ok) { release(); return sendText(res, 429, mapErr(sess.code)); }
  const ac = new AbortController();
  let cleaned = false;
  const cleanup = () => {
    if (cleaned) return; cleaned = true;
    try { ac.abort(); } catch { /* */ }
    sess.release(); release();
  };
  res.on('close', cleanup);
  metrics.inc('gw_vod_requests_total');
  try {
    const extra = {};
    if (req.headers.range) extra.range = req.headers.range;
    const up = await proxyRaw(upstreamStreamUrl(kind, streamId, ext), ac.signal, extra);
    const headers = {
      'content-type': up.headers['content-type'] || 'application/octet-stream',
    };
    for (const h of ['content-length', 'content-range', 'accept-ranges']) {
      if (up.headers[h]) headers[h] = up.headers[h];
    }
    res.writeHead(up.statusCode, headers);
    up.body.on('data', (c) => metrics.inc('gw_bytes_clients_total', c.length));
    up.body.on('error', () => { try { res.destroy(); } catch { /* */ } });
    up.body.pipe(res);
  } catch (e) {
    if (!res.headersSent) sendText(res, 502, mapErr('upstream_unavailable'));
    cleanup();
  }
}

async function handlePlayerApi(url, res) {
  const q = Object.fromEntries(url.searchParams);
  const user = authenticate(q.username, q.password);
  if (!user) return sendJson(res, 200, { user_info: { auth: 0 } });
  const params = { ...q };
  delete params.username; delete params.password;
  try {
    const { status, json, text } = await callPlayerApi(params);
    if (json) {
      rewritePlayerApi(json);
      // On masque la ligne réelle : le client voit SES identifiants.
      if (json.user_info) {
        json.user_info.username = user.username;
        json.user_info.password = user.password;
      }
      return sendJson(res, 200, json);
    }
    return sendText(res, status, text, 'application/json');
  } catch (e) {
    return sendJson(res, 200, { user_info: { auth: 0 } });
  }
}

async function handleGetPhp(url, res) {
  const q = Object.fromEntries(url.searchParams);
  const user = authenticate(q.username, q.password);
  if (!user) return sendText(res, 403, '#EXTM3U\n# auth failed\n', 'application/x-mpegurl');
  const params = { ...q };
  delete params.username; delete params.password;
  try {
    const { status, text } = await callGetPhp(params);
    const rewritten = rewriteM3U(text, user.username, user.password);
    return sendText(res, status, rewritten, 'application/x-mpegurl');
  } catch (e) {
    return sendText(res, 502, '#EXTM3U\n# upstream error\n', 'application/x-mpegurl');
  }
}

// ---- Routeur -----------------------------------------------------------

async function route(req, res) {
  const url = new URL(req.url, 'http://localhost');
  const path = url.pathname;

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return sendText(res, 405, 'Method Not Allowed');
  }

  // Santé / supervision
  if (path === '/health') {
    return sendJson(res, 200, {
      ok: true,
      upstreamActive: hub.totalUpstream(),
      providerMax: config.providerMaxConnections,
      uptimeSec: Math.floor((Date.now() - START) / 1000),
    });
  }
  if (path === '/metrics') {
    if (!adminOk(url, req)) return sendText(res, 404, 'Not Found');
    return sendText(res, 200, metrics.render(), 'text/plain; version=0.0.4');
  }
  if (path === '/admin/status') {
    if (!adminOk(url, req)) return sendText(res, 404, 'Not Found');
    return sendJson(res, 200, {
      hub: hub.status(),
      sessions: snapshotSessions(),
      users: listUsers(),
      metrics: metrics.snapshot(),
      uptimeSec: Math.floor((Date.now() - START) / 1000),
    });
  }
  if (path === '/admin/reload-users') {
    if (!adminOk(url, req)) return sendText(res, 404, 'Not Found');
    const r = await loadUsers();
    return sendJson(res, 200, { ok: true, ...r });
  }

  // Façade Xtream : API
  if (path === '/player_api.php') return handlePlayerApi(url, res);
  if (path === '/get.php' || path === '/playlist.m3u' || path === '/get.php/') {
    return handleGetPhp(url, res);
  }

  // Flux (live mutualisé, VOD direct)
  const s = parseStreamPath(path);
  if (s) {
    const user = authenticate(s.user, s.pass);
    if (!user) return sendText(res, 403, 'Forbidden');
    if (s.kind === 'live') return handleLive(s.streamId, s.ext, req, res, user);
    return handleVod(s.kind, s.streamId, s.ext, req, res, user);
  }

  return sendText(res, 404, 'Not Found');
}

export function createServer() {
  const server = http.createServer((req, res) => {
    metrics.inc('gw_http_requests_total');
    Promise.resolve(route(req, res)).catch((e) => {
      log.error('route.crash', { path: req.url, error: String(e && e.message || e) });
      if (!res.headersSent) {
        try { sendText(res, 500, 'Internal error'); } catch { /* */ }
      } else {
        try { res.end(); } catch { /* */ }
      }
    });
  });
  // Un flux live n'a pas de fin naturelle : on désactive les timeouts serveur.
  server.requestTimeout = 0;
  server.headersTimeout = 0;
  server.timeout = 0;
  return server;
}
