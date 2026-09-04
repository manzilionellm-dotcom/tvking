// =========================================================
//  server.js — Serveur HTTP + routage de la passerelle
// =========================================================
import http from 'node:http';
import os from 'node:os';
import { config } from './config.js';
import { log } from './logger.js';
import { metrics } from './metrics.js';
import {
  authenticate, listUsers, loadUsers,
  listFamilies, createFamily, deleteFamily, addUser, deleteUser,
} from './users.js';
import { acquireSession, snapshotSessions } from './limits.js';
import { hub } from './hub.js';
import { RateLimiter } from './ratelimit.js';

// Limiteur des endpoints coûteux (get.php / player_api), par utilisateur.
const apiLimiter = new RateLimiter(config.apiRateLimit, config.apiRateWindowMs);
import { parseStreamPath, streamKey, makeM3URewriter, rewritePlayerApi } from './xtream.js';
import {
  callPlayerApi, openGetPhp, proxyRawFailover, upstreamStreamPath,
} from './upstream.js';

const START = Date.now();

// ---- Santé SYSTÈME du serveur (CPU / RAM / charge) ---------------------
//  Vraies mesures process + OS (aucune dépendance). Le % CPU est calculé
//  par DELTA entre deux appels (fraction de temps CPU consommée depuis le
//  dernier /admin/status). Exposé dans /admin/status → le panel affiche une
//  « Santé serveurs » réelle (plus de « non instrumenté »).
let _lastCpu = process.cpuUsage();
let _lastCpuAt = Date.now();
function systemSnapshot() {
  const now = Date.now();
  const delta = process.cpuUsage(_lastCpu); // µs de CPU depuis le dernier appel
  const elapsedMs = Math.max(1, now - _lastCpuAt);
  _lastCpu = process.cpuUsage();
  _lastCpuAt = now;
  // (user+system) µs ramenés au temps écoulé → % d'UN cœur.
  const cpuPct = Math.max(
    0,
    Math.min(100, Math.round(((delta.user + delta.system) / 1000 / elapsedMs) * 100)),
  );
  const mem = process.memoryUsage();
  const totalMem = os.totalmem();
  const freeMem = os.freemem();
  return {
    cpuPct, // % CPU du process (d'un cœur) sur l'intervalle
    cpuCount: os.cpus().length,
    loadavg1: Math.round(os.loadavg()[0] * 100) / 100, // charge système 1 min
    rssMB: Math.round(mem.rss / 1048576), // mémoire résidente du process
    heapUsedMB: Math.round(mem.heapUsed / 1048576),
    sysMemUsedPct: Math.round((1 - freeMem / totalMem) * 100), // RAM système utilisée
    totalMemMB: Math.round(totalMem / 1048576),
    procUptimeSec: Math.floor(process.uptime()),
  };
}

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

// CORS pour que le panel (autre origine) puisse piloter la passerelle.
function cors(res) {
  res.setHeader('access-control-allow-origin', '*');
  res.setHeader('access-control-allow-methods', 'GET,POST,DELETE,OPTIONS');
  res.setHeader('access-control-allow-headers', 'authorization,content-type');
  res.setHeader('access-control-max-age', '600');
}

// Lit un corps JSON borné (protège la mémoire).
function readJson(req, limit = 64 * 1024) {
  return new Promise((resolve) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > limit) { try { req.destroy(); } catch { /* */ } resolve(null); return; }
      chunks.push(c);
    });
    req.on('end', () => {
      if (!chunks.length) { resolve({}); return; }
      try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8'))); }
      catch { resolve(null); }
    });
    req.on('error', () => resolve(null));
  });
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
  // Multi-MAC panel : user.panelFamily a maxStreams élevé, mais le hub
  // (ci-dessous) n'ouvre qu'UNE connexion fournisseur par streamId —
  // N télés sur la même chaîne = 1 live/user/pass amont (max_connections=1).
  const sess = acquireSession(user);
  if (!sess.ok) {
    metrics.inc('gw_rejected_session_total', 1, { reason: sess.code });
    return sendText(res, 429, mapErr(sess.code));
  }
  res.on('close', () => sess.release());
  const key = streamKey('live', streamId, ext);
  const streamPath = upstreamStreamPath('live', streamId, ext);
  metrics.inc('gw_live_requests_total');
  const r = await hub.subscribe(key, streamPath, res);
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
    const up = await proxyRawFailover(
      upstreamStreamPath(kind, streamId, ext), ac.signal, extra);
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
  if (!apiLimiter.allow(user.username)) {
    metrics.inc('gw_rate_limited_total', 1, { endpoint: 'player_api' });
    return sendJson(res, 429, { user_info: { auth: 1, status: 'Rate limited' } });
  }
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
        // Famille panel multi-MAC : la ligne fournisseur a max_connections=1
        // mais N clients partagent UN flux via hub.subscribe. On annonce
        // un plafond client honnête (écrans), pas la limite amont.
        if (user.panelFamily) {
          json.user_info.max_connections = String(user.maxStreams || 12);
        }
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
  if (!apiLimiter.allow(user.username)) {
    metrics.inc('gw_rate_limited_total', 1, { endpoint: 'get_php' });
    return sendText(res, 429, '#EXTM3U\n# rate limited\n', 'application/x-mpegurl');
  }
  const params = { ...q };
  delete params.username; delete params.password;
  const ac = new AbortController();
  res.on('close', () => { try { ac.abort(); } catch { /* */ } });
  let up;
  try {
    up = await openGetPhp(params, ac.signal);
  } catch (e) {
    if (!res.headersSent) sendText(res, 502, '#EXTM3U\n# upstream error\n', 'application/x-mpegurl');
    return;
  }
  if (up.statusCode >= 400) {
    try { up.body.destroy(); } catch { /* */ }
    return sendText(res, 502, '#EXTM3U\n# upstream error\n', 'application/x-mpegurl');
  }
  res.writeHead(200, {
    'content-type': 'application/x-mpegurl',
    'cache-control': 'no-cache',
  });
  const rewrite = makeM3URewriter(user.username, user.password);
  // panelFamily : username=password=token 32 hex → les URLs deviennent
  // /live/{token}/{token}/{id}.ts (même contrat que le Worker en mode gateway).
  // Pas de réécriture requise (pas de PUBLIC_BASE) → passthrough direct.
  if (!rewrite) { up.body.pipe(res); return; }
  // Réécriture ligne par ligne EN STREAMING : mémoire bornée (une ligne
  // partielle + un chunk), l'event-loop respire entre les chunks, et
  // backpressure vers l'upstream si le client est lent.
  let buf = '';
  up.body.setEncoding('utf8');
  up.body.on('data', (chunk) => {
    if (res.writableEnded) return;
    buf += chunk;
    let nl;
    let out = '';
    while ((nl = buf.indexOf('\n')) !== -1) {
      out += rewrite(buf.slice(0, nl + 1));
      buf = buf.slice(nl + 1);
    }
    if (out) {
      if (!res.write(out)) {
        up.body.pause();
        res.once('drain', () => { try { up.body.resume(); } catch { /* */ } });
      }
    }
  });
  up.body.on('end', () => {
    if (buf && !res.writableEnded) { try { res.write(rewrite(buf)); } catch { /* */ } }
    try { res.end(); } catch { /* */ }
  });
  up.body.on('error', () => { try { res.destroy(); } catch { /* */ } });
}

// ---- Routeur -----------------------------------------------------------

// Routes admin (déjà authentifiées + CORS posé par l'appelant).
async function adminRoute(req, res, url, path) {
  if (path === '/metrics') {
    return sendText(res, 200, metrics.render(), 'text/plain; version=0.0.4');
  }
  if (path === '/admin/status') {
    return sendJson(res, 200, {
      hub: hub.status(),
      sessions: snapshotSessions(),
      users: listUsers(),
      metrics: metrics.snapshot(),
      uptimeSec: Math.floor((Date.now() - START) / 1000),
      system: systemSnapshot(),
    });
  }
  if (path === '/admin/reload-users') {
    const r = await loadUsers();
    return sendJson(res, 200, { ok: true, ...r });
  }

  // Gestion des familles / clones
  if (path === '/admin/families') {
    if (req.method === 'GET') {
      return sendJson(res, 200, { families: listFamilies() });
    }
    if (req.method === 'POST') {
      const body = await readJson(req);
      if (!body) return sendJson(res, 400, { ok: false, code: 'bad_json' });
      const r = await createFamily({ id: body.id, maxStreams: body.maxStreams });
      return sendJson(res, r.ok ? 201 : 409, r);
    }
    return sendText(res, 405, 'Method Not Allowed');
  }
  // /admin/families/:id  et  /admin/families/:id/users[/:username]
  const fam = /^\/admin\/families\/([^/]+)(?:\/users(?:\/([^/]+))?)?$/.exec(path);
  if (fam) {
    const familyId = decodeURIComponent(fam[1]);
    const username = fam[2] ? decodeURIComponent(fam[2]) : null;
    const isUsers = /\/users/.test(path);
    if (!isUsers && req.method === 'DELETE') {
      const r = await deleteFamily(familyId);
      return sendJson(res, r.ok ? 200 : 404, r);
    }
    if (isUsers && !username && req.method === 'POST') {
      const body = await readJson(req);
      if (!body) return sendJson(res, 400, { ok: false, code: 'bad_json' });
      const r = await addUser(familyId, {
        username: body.username, password: body.password, maxStreams: body.maxStreams,
      });
      return sendJson(res, r.ok ? 201 : 409, r);
    }
    if (isUsers && username && req.method === 'DELETE') {
      const r = await deleteUser(familyId, username);
      return sendJson(res, r.ok ? 200 : 404, r);
    }
    return sendText(res, 405, 'Method Not Allowed');
  }

  return sendText(res, 404, 'Not Found');
}

async function route(req, res) {
  const url = new URL(req.url, 'http://localhost');
  const path = url.pathname;

  // ---- Zone ADMIN (CORS + jeton) : supervision + gestion des familles ----
  if (path === '/metrics' || path.startsWith('/admin/')) {
    cors(res);
    if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }
    if (!adminOk(url, req)) return sendText(res, 404, 'Not Found');
    return adminRoute(req, res, url, path);
  }

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
  // Un flux live/VOD n'a pas de fin naturelle : le timeout d'INACTIVITÉ de la
  // socket reste désactivé (sinon on couperait une lecture légitime). MAIS on
  // borne la seule PHASE REQUÊTE entrante (anti-slow-loris) — inoffensif car
  // nos requêtes sont des GET sans corps.
  server.timeout = 0;
  server.headersTimeout = config.headersTimeoutMs || 0;
  server.requestTimeout = config.requestTimeoutMs || 0;
  // Détection des pairs MORTS : keepalive TCP sur chaque connexion. Une box qui
  // disparaît sans FIN/RST est sondée par le noyau ; la socket morte finit par
  // être coupée → 'close' se déclenche → le slot de la ligne fournisseur est
  // libéré (sinon il resterait fantôme et saturerait la ligne → 503 en cascade).
  if (config.socketKeepAliveMs > 0) {
    server.on('connection', (socket) => {
      try { socket.setKeepAlive(true, config.socketKeepAliveMs); } catch { /* */ }
    });
  }
  // Ronde anti-backpressure : plafond mémoire GLOBAL des files clients.
  hub.startBackpressureSweep();
  server.on('close', () => hub.stopBackpressureSweep());
  return server;
}
