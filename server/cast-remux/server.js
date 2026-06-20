'use strict';

// ============================================================
//  cast-remux — remux IPTV MPEG-TS LIVE -> HLS-fMP4 pour le Cast
// ============================================================
//
//  Pourquoi : un Chromecast / recepteur Cast par defaut (Shaka,
//  depuis fin 2025) ne sait PAS lire du MPEG-TS brut de façon
//  fiable (pas de transmux TS cote receiver). Le format que TOUS
//  les Chromecast lisent nativement = HLS avec segments fMP4.
//
//  Ce service prend une URL upstream (le flux Xtream .ts), lance
//  ffmpeg en `-c copy` (REMUX conteneur uniquement, AUCUN
//  re-encodage -> ~1-2% CPU par chaine), et sert une playlist HLS
//  fMP4 live + ses segments. Le Cast pointe ici, lit le HLS, joue.
//
//  - Stateless cote URL : l'upstream est encode en base64url dans
//    le chemin -> pas de base de donnees.
//  - Mutualisation : plusieurs spectateurs de la MEME chaine
//    partagent UN seul ffmpeg (cle = base64url de l'upstream).
//  - Reaper : un ffmpeg sans requete depuis IDLE_TIMEOUT_MS est tue
//    et son dossier nettoye.
//
//  HTTPS : ce service ecoute en HTTP simple sur PORT ; c'est Caddy
//  (cf. docker-compose.yml + Caddyfile) qui termine le TLS devant
//  et proxy ici. Le Cast exige du https (mixed content), Caddy le
//  fournit automatiquement (Let's Encrypt).

const http = require('http');
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PORT = parseInt(process.env.PORT || '8080', 10);
// Tue ffmpeg apres ce delai sans aucune requete sur la chaine.
const IDLE_TIMEOUT_MS = parseInt(process.env.IDLE_TIMEOUT_MS || '30000', 10);
// Attente max que ffmpeg produise la 1ere playlist (1er segment ~4s).
const READY_TIMEOUT_MS = parseInt(process.env.READY_TIMEOUT_MS || '15000', 10);
// User-Agent envoye a l'upstream Xtream (passe les filtres anti-bot).
const UPSTREAM_UA =
  process.env.UPSTREAM_UA || 'VLC/3.0.18 LibVLC/3.0.18';

const ROOT = fs.mkdtempSync(path.join(os.tmpdir(), 'castremux-'));

/** @type {Map<string, {dir:string, proc:import('child_process').ChildProcess, lastAccess:number, lastErr:string, exited:boolean}>} */
const sessions = new Map();

function b64urlDecode(s) {
  let t = s.replace(/-/g, '+').replace(/_/g, '/');
  while (t.length % 4) t += '=';
  return Buffer.from(t, 'base64').toString('utf8');
}

function startSession(b64) {
  const upstream = b64urlDecode(b64);
  const u = new URL(upstream); // throw si invalide
  if (u.protocol !== 'http:' && u.protocol !== 'https:') {
    throw new Error('bad protocol');
  }
  const dir = fs.mkdtempSync(path.join(ROOT, 'ch-'));
  const args = [
    '-hide_banner',
    '-loglevel', 'error',
    '-user_agent', UPSTREAM_UA,
    '-reconnect', '1',
    '-reconnect_streamed', '1',
    '-reconnect_delay_max', '5',
    '-i', upstream,
    // REMUX uniquement (pas de re-encodage). aac_adtstoasc : convertit
    // l'AAC ADTS du TS vers le format attendu en fMP4.
    '-c', 'copy',
    '-bsf:a', 'aac_adtstoasc',
    '-f', 'hls',
    '-hls_time', '4',
    '-hls_list_size', '6',
    // live : on supprime les vieux segments et on n'ecrit PAS d'ENDLIST.
    '-hls_flags', 'delete_segments+independent_segments+omit_endlist',
    '-hls_segment_type', 'fmp4',
    '-hls_fmp4_init_filename', 'init.mp4',
    '-hls_segment_filename', path.join(dir, 'seg_%d.m4s'),
    path.join(dir, 'master.m3u8'),
  ];
  const proc = spawn('ffmpeg', args, { stdio: ['ignore', 'ignore', 'pipe'] });
  const sess = { dir, proc, lastAccess: Date.now(), lastErr: '', exited: false };
  proc.stderr.on('data', (d) => {
    sess.lastErr = (sess.lastErr + d.toString()).slice(-2000);
  });
  proc.on('exit', (code) => {
    sess.exited = true;
    sessions.set(b64, sess);
    setTimeout(() => {
      if (sessions.get(b64) === sess) sessions.delete(b64);
      try { fs.rmSync(dir, { recursive: true, force: true }); } catch (_) {}
    }, 1000);
  });
  sessions.set(b64, sess);
  return sess;
}

function getOrStart(b64) {
  let sess = sessions.get(b64);
  if (!sess || sess.exited) {
    sess = startSession(b64);
  }
  sess.lastAccess = Date.now();
  return sess;
}

function waitForFile(file, timeoutMs) {
  return new Promise((resolve) => {
    const t0 = Date.now();
    const tick = () => {
      if (fs.existsSync(file)) return resolve(true);
      if (Date.now() - t0 > timeoutMs) return resolve(false);
      setTimeout(tick, 200);
    };
    tick();
  });
}

const CT = {
  '.m3u8': 'application/vnd.apple.mpegurl',
  '.m4s': 'video/iso.segment',
  '.mp4': 'video/mp4',
};

function send(res, status, headers, body) {
  res.writeHead(status, {
    'Access-Control-Allow-Origin': '*',
    'Cache-Control': 'no-store, no-cache',
    ...headers,
  });
  if (body && body.pipe) body.pipe(res);
  else res.end(body);
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    const parts = url.pathname.split('/').filter(Boolean);

    if (parts[0] === 'health') return send(res, 200, { 'Content-Type': 'text/plain' }, 'ok');

    // /live/<b64>/<file>
    if (parts[0] === 'live' && parts.length === 3) {
      const b64 = parts[1];
      const file = parts[2];
      if (file.includes('..') || path.isAbsolute(file)) {
        return send(res, 400, { 'Content-Type': 'text/plain' }, 'bad file');
      }

      let sess;
      try {
        sess = getOrStart(b64);
      } catch (e) {
        return send(res, 400, { 'Content-Type': 'text/plain' }, 'bad token');
      }

      const target = path.join(sess.dir, file);
      const ext = path.extname(file);

      // La playlist peut ne pas exister encore (ffmpeg demarre) : on attend.
      if (ext === '.m3u8') {
        const ok = await waitForFile(target, READY_TIMEOUT_MS);
        if (!ok) {
          const reason = sess.exited
            ? `ffmpeg a quitte: ${sess.lastErr || 'flux upstream injoignable'}`
            : 'timeout demarrage ffmpeg';
          return send(res, 502, { 'Content-Type': 'text/plain' }, reason);
        }
      }

      if (!fs.existsSync(target)) {
        return send(res, 404, { 'Content-Type': 'text/plain' }, 'not found');
      }
      sess.lastAccess = Date.now();
      return send(
        res,
        200,
        { 'Content-Type': CT[ext] || 'application/octet-stream' },
        fs.createReadStream(target),
      );
    }

    return send(res, 404, { 'Content-Type': 'text/plain' }, 'not found');
  } catch (e) {
    return send(res, 500, { 'Content-Type': 'text/plain' }, 'server error');
  }
});

// Reaper : tue les ffmpeg inactifs.
setInterval(() => {
  const now = Date.now();
  for (const [b64, sess] of sessions) {
    if (sess.exited) continue;
    if (now - sess.lastAccess > IDLE_TIMEOUT_MS) {
      try { sess.proc.kill('SIGKILL'); } catch (_) {}
    }
  }
}, 5000);

server.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`cast-remux on :${PORT} (tmp ${ROOT})`);
});
