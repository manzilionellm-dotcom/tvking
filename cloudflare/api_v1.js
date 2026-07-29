// =========================================================
//  api_v1.js — App Licensing Platform REST API v1
// =========================================================
//  Importe depuis worker.js pour servir le namespace /api/v1/*.
//  Coexiste avec les anciens endpoints /admin/* et /api/* qui
//  continuent de fonctionner pour ne pas casser les apps mobiles
//  deployees.
//
//  ENDPOINTS exposes ici (Phase 1.A) :
//
//    Auth
//      POST   /api/v1/auth/login            { email, password } → { token }
//      GET    /api/v1/auth/me               (header Authorization)
//
//    Dashboard (super_admin / admin)
//      GET    /api/v1/stats/overview        compteurs globaux
//
//    Apps (super_admin only ; admin = read)
//      GET    /api/v1/apps
//      POST   /api/v1/apps                   creer une app sans toucher au code
//      GET    /api/v1/apps/:id
//      PATCH  /api/v1/apps/:id
//      DELETE /api/v1/apps/:id
//
//    Customers
//      GET    /api/v1/customers
//      POST   /api/v1/customers
//      GET    /api/v1/customers/:id
//      PATCH  /api/v1/customers/:id
//
//    Devices
//      GET    /api/v1/devices
//      GET    /api/v1/customers/:id/devices
//      POST   /api/v1/devices                { customer_id, mac, label }
//
//    Licenses (le coeur du systeme)
//      GET    /api/v1/licenses
//      POST   /api/v1/licenses               creer une license avec duree
//      POST   /api/v1/licenses/:id/renew     prolonger une license
//      PATCH  /api/v1/licenses/:id           mise a jour statut, plan, etc.
//
//    Playlists
//      GET    /api/v1/licenses/:id/playlist
//      PUT    /api/v1/licenses/:id/playlist  push Xtream/M3U
//
//  AUTH :
//    Tout endpoint /api/v1/* (sauf /auth/login) exige un header
//    `Authorization: Bearer <jwt>` valide. Le JWT est signe HMAC
//    via env.ADMIN_SECRET (re-utilise comme cle de signature
//    pour ne pas multiplier les secrets).
//
//  Reponses :
//    Tout en JSON. Les erreurs ont la forme :
//      { error: "code_machine", message: "Explication humaine" }
//    avec un statut HTTP coherent.
//
//  Phase 1.A se limite au super_admin role. Resellers et
//  customers viendront en Phase 3 et 5 respectivement.
// =========================================================

// Temps réel (cf. cloudflare/realtime.js + docs/REALTIME-PROTOCOL.md) :
// après chaque mutation réussie on PUBLIE un évènement via le hub —
// l'appareil visé re-fetch immédiatement, et les panels ouverts voient
// le changement (`changed{scope}`). TOUJOURS fail-open : si le Durable
// Object n'est pas déployé, publishRt renvoie {delivered:0} sans erreur.
import { publishRt } from './realtime.js';

// ---------------------------------------------------------
//  Helpers reponse
// ---------------------------------------------------------

const JSON_HEADERS = {
  'Content-Type': 'application/json; charset=utf-8',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'Authorization, Content-Type, X-Admin-Secret',
  'Access-Control-Allow-Methods':
    'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'Cache-Control': 'no-store',
};

function jsonResp(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: JSON_HEADERS,
  });
}

function errResp(code, message, status = 400) {
  return jsonResp({ error: code, message }, status);
}

// ---------------------------------------------------------
//  Limitation de débit (anti-brute-force) — par IP, via D1
// ---------------------------------------------------------
//  Compte les tentatives par IP sur une fenêtre glissante. Au-delà du
//  seuil → 429. Sur succès on remet à zéro. Fail-OPEN : si la base est
//  indisponible, on NE bloque jamais un utilisateur légitime (la
//  sécurité ne doit pas casser le service).
async function ensureRateLimitTable(env) {
  await env.DB.prepare(
    'CREATE TABLE IF NOT EXISTS rate_limits (k TEXT PRIMARY KEY, '
    + 'count INTEGER NOT NULL, window_start INTEGER NOT NULL)',
  ).run();
}
function clientIp(request) {
  return request.headers.get('CF-Connecting-IP')
    || request.headers.get('X-Forwarded-For')
    || 'unknown';
}
/// true = tentative AUTORISÉE ; false = bloquée (429).
async function rateLimitHit(env, request, bucket, maxAttempts, windowMs) {
  try {
    await ensureRateLimitTable(env);
    const k = `${bucket}:${clientIp(request)}`;
    const now = Date.now();
    const row = await env.DB
      .prepare('SELECT count, window_start FROM rate_limits WHERE k = ?')
      .bind(k).first();
    if (!row || (now - row.window_start) > windowMs) {
      await env.DB.prepare(
        'INSERT INTO rate_limits (k, count, window_start) VALUES (?, 1, ?) '
        + 'ON CONFLICT(k) DO UPDATE SET count = 1, window_start = ?',
      ).bind(k, now, now).run();
      return true;
    }
    if (row.count >= maxAttempts) return false;
    await env.DB.prepare('UPDATE rate_limits SET count = count + 1 WHERE k = ?')
      .bind(k).run();
    return true;
  } catch (_) {
    return true; // fail-open
  }
}
/// Remet le compteur à zéro après une réussite (login OK).
async function rateLimitReset(env, request, bucket) {
  try {
    await env.DB.prepare('DELETE FROM rate_limits WHERE k = ?')
      .bind(`${bucket}:${clientIp(request)}`).run();
  } catch (_) { /* best-effort */ }
}

// ---------------------------------------------------------
//  Helpers crypto (JWT, password hash, AES-GCM)
// ---------------------------------------------------------
//  On utilise Web Crypto natif (disponible dans Workers) — pas
//  de dependance npm. JWT signed HS256 via env.ADMIN_SECRET.

function b64url(bytes) {
  return btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replace(/=+$/, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function b64urlDecode(s) {
  s = s.replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  const raw = atob(s);
  const arr = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
  return arr;
}

async function hmacSha256(secret, msg) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(msg),
  );
  return new Uint8Array(sig);
}

// AUDIT 2026-07-29 : plus AUCUN repli 'dev-secret'. Un secret absent ou
// trop court = signature/vérification refusée (fail-closed, aligné sur
// checkAdmin côté worker.js). Sans ça, une instance sans ADMIN_SECRET
// signait tous ses JWT admin avec une clé publique présente dans le dépôt
// → forge de jetons super_admin triviale.
function jwtSecretUsable(secret) {
  return typeof secret === 'string' && secret.length >= 8;
}

// Comparaison à temps constant (même contrat que safeEqual de worker.js —
// dupliquée ici pour éviter un import croisé).
function timingSafeEqualStr(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const ba = new TextEncoder().encode(a);
  const bb = new TextEncoder().encode(b);
  if (ba.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < ba.length; i++) diff |= ba[i] ^ bb[i];
  return diff === 0;
}

async function signJwt(payload, secret, expMinutes = 60 * 24 * 7) {
  if (!jwtSecretUsable(secret)) {
    throw new Error('ADMIN_SECRET absent ou trop court — signature refusée');
  }
  const header = { alg: 'HS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const claims = {
    ...payload,
    iat: now,
    exp: now + expMinutes * 60,
  };
  const h = b64url(new TextEncoder().encode(JSON.stringify(header)));
  const p = b64url(new TextEncoder().encode(JSON.stringify(claims)));
  const sig = b64url(await hmacSha256(secret, `${h}.${p}`));
  return `${h}.${p}.${sig}`;
}

// Exporté : worker.js le réutilise pour authentifier le WebSocket admin
// (/api/v1/rt/ws) avec le MÊME secret HS256 — aucun nouveau secret.
export async function verifyJwt(token, secret) {
  try {
    // Fail-closed : sans secret configuré, AUCUN jeton n'est valide.
    if (!jwtSecretUsable(secret)) return null;
    const [h, p, s] = token.split('.');
    if (!h || !p || !s) return null;
    const expectedSig = b64url(await hmacSha256(secret, `${h}.${p}`));
    // Temps constant (audit 2026-07-29) : `!==` court-circuite.
    if (!timingSafeEqualStr(s, expectedSig)) return null;
    const claims = JSON.parse(
      new TextDecoder().decode(b64urlDecode(p)),
    );
    const now = Math.floor(Date.now() / 1000);
    if (claims.exp && claims.exp < now) return null;
    return claims;
  } catch (_) {
    return null;
  }
}

/// Hash de mot de passe via PBKDF2-SHA256 100k iterations + salt
/// 16 bytes. Format stocke : "pbkdf2$100000$<saltB64>$<hashB64>".
/// Suffisant pour un usage admin interne ; pas Argon2 mais pas
/// de dependance npm.
async function hashPassword(plain) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const keyMat = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(plain),
    { name: 'PBKDF2' },
    false,
    ['deriveBits'],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt, iterations: 100000, hash: 'SHA-256' },
    keyMat,
    256,
  );
  return `pbkdf2$100000$${b64url(salt)}$${b64url(bits)}`;
}

async function verifyPassword(plain, stored) {
  try {
    const [algo, iter, saltB64, hashB64] = stored.split('$');
    if (algo !== 'pbkdf2') return false;
    const salt = b64urlDecode(saltB64);
    const keyMat = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(plain),
      { name: 'PBKDF2' },
      false,
      ['deriveBits'],
    );
    const bits = await crypto.subtle.deriveBits(
      {
        name: 'PBKDF2',
        salt,
        iterations: Number(iter),
        hash: 'SHA-256',
      },
      keyMat,
      256,
    );
    // Temps constant (audit 2026-07-29) : `===` court-circuite.
    return timingSafeEqualStr(b64url(bits), hashB64);
  } catch (_) {
    return false;
  }
}

// ---------------------------------------------------------
//  ID generation (ULID-like : timestamp ms + random)
// ---------------------------------------------------------
function genId(prefix) {
  const ts = Date.now().toString(36).padStart(8, '0');
  const rand = Array.from(crypto.getRandomValues(new Uint8Array(8)))
    .map((b) => (b % 36).toString(36))
    .join('');
  return `${prefix}_${ts}${rand}`;
}

// ---------------------------------------------------------
//  Auth middleware
// ---------------------------------------------------------
async function requireAuth(request, env) {
  const auth = request.headers.get('Authorization') || '';
  const m = auth.match(/^Bearer\s+(.+)$/i);
  if (!m) return { error: errResp('no_auth', 'Missing Authorization header', 401) };
  const claims = await verifyJwt(m[1], env.ADMIN_SECRET);
  if (!claims) return { error: errResp('bad_token', 'Invalid or expired token', 401) };
  return { user: claims };
}

// ---------------------------------------------------------
//  Bootstrap : creation auto du super_admin si table vide
// ---------------------------------------------------------
//  La 1ere fois que /api/v1/auth/login est appele, si la table
//  admin_users est vide, on cree un compte avec email = "admin"
//  et password = env.ADMIN_SECRET. Permet de demarrer sans setup
//  hors-bande (l'admin se connecte avec le secret qu'il a deja).
// ----- Carnet de références : MAC activées + username(s) Xtream -----
//  Pour le support : retrouver vite quel identifiant a été mis sur quelle
//  MAC. On NE renvoie JAMAIS le mot de passe. Owner = tout ; revendeur =
//  uniquement SES appareils (cloisonnement par reseller_id).
async function handleReferencesList(env, user) {
  const reseller = user && user.role === 'reseller';
  try {
    const where = reseller ? 'WHERE d.reseller_id = ?' : '';
    const binds = reseller ? [user.sub] : [];
    const now = Date.now();
    const rs = await env.DB
      .prepare(
        `SELECT ds.mac AS mac, ds.username AS username, ds.server_url AS server_url,
                ds.sources_json AS sources_json, ds.label AS label,
                ds.updated_at AS updated_at, c.name AS customer_name,
                d.first_seen_at AS first_seen_at, d.last_seen_at AS dev_last_seen,
                d.platform AS platform, d.device_model AS device_model,
                d.reseller_id AS reseller_id,
                p.last_seen AS pres_last_seen, p.channel AS pres_channel,
                p.country AS pres_country,
                (SELECT l.status    FROM licenses l JOIN devices dl ON dl.id = l.device_id
                   WHERE dl.mac = ds.mac
                   ORDER BY (l.expires_at IS NULL) DESC, l.expires_at DESC LIMIT 1) AS lic_status,
                (SELECT l.expires_at FROM licenses l JOIN devices dl ON dl.id = l.device_id
                   WHERE dl.mac = ds.mac
                   ORDER BY (l.expires_at IS NULL) DESC, l.expires_at DESC LIMIT 1) AS lic_expires,
                (SELECT l.plan      FROM licenses l JOIN devices dl ON dl.id = l.device_id
                   WHERE dl.mac = ds.mac
                   ORDER BY (l.expires_at IS NULL) DESC, l.expires_at DESC LIMIT 1) AS lic_plan,
                (SELECT l.started_at FROM licenses l JOIN devices dl ON dl.id = l.device_id
                   WHERE dl.mac = ds.mac
                   ORDER BY (l.expires_at IS NULL) DESC, l.expires_at DESC LIMIT 1) AS lic_started
         FROM device_sources ds
         LEFT JOIN devices d   ON d.mac = ds.mac
         LEFT JOIN customers c ON c.id = d.customer_id
         LEFT JOIN presence p  ON p.mac = ds.mac
         ${where}
         ORDER BY ds.updated_at DESC LIMIT 1000`,
      )
      .bind(...binds)
      .all();
    const items = (rs.results || []).map((r) => {
      // username(s) + serveur(s) : depuis le trio (sources_json) sinon les
      // champs simples. On n'expose JAMAIS le mot de passe.
      let usernames = [];
      let servers = [];
      if (r.sources_json) {
        try {
          const arr = JSON.parse(r.sources_json) || [];
          usernames = arr.map((s) => s && s.username).filter(Boolean);
          servers = arr.map((s) => s && (s.server_url || s.server)).filter(Boolean);
        } catch (_) { /* ignore */ }
      }
      if (usernames.length === 0 && r.username) usernames = [r.username];
      if (servers.length === 0 && r.server_url) servers = [r.server_url];
      // Statut dérivé de la meilleure licence du device.
      let status = 'none';
      const hasLic = !!r.lic_status;
      const lifetime = hasLic && (r.lic_expires === null || r.lic_expires === undefined);
      if (r.lic_status === 'banned') status = 'banned';
      else if (r.lic_status === 'frozen') status = 'frozen';
      else if (hasLic) {
        status = lifetime ? 'active' : (r.lic_expires <= now ? 'expired' : 'active');
      }
      // Détails « combien de temps reste » : échéance + jours restants
      // (à vie → null jours mais lifetime=true), et présence live.
      const DAY = 24 * 60 * 60 * 1000;
      const expires_at = (r.lic_expires === undefined) ? null : r.lic_expires;
      const days_left = (hasLic && !lifetime && expires_at)
        ? Math.max(0, Math.ceil((expires_at - now) / DAY))
        : null;
      const last_seen = r.pres_last_seen || r.dev_last_seen || null;
      const ONLINE_MS = 15 * 60 * 1000;
      const online = last_seen ? (last_seen > now - ONLINE_MS) : false;
      return {
        mac: r.mac,
        customer_name: r.customer_name || null,
        usernames,
        servers,
        status,
        label: r.label || null,
        updated_at: r.updated_at || null,
        // --- Enrichissement « beaucoup de détails » ---
        plan: r.lic_plan || null,          // 'monthly' | 'yearly' | 'lifetime' | 'trial_*'
        lifetime,                          // abonnement à vie
        expires_at,                        // ms epoch, null si à vie / aucune licence
        started_at: r.lic_started ?? null, // début de la licence
        days_left,                         // jours restants (null si à vie)
        last_seen,                         // dernière trace serveur (ms)
        online,                            // vu il y a < 15 min
        channel: r.pres_channel || '',     // chaîne en cours
        country: (r.pres_country || '').toUpperCase(),
        platform: r.platform || null,      // 'tv' | 'mobile'
        device_model: r.device_model || null,
        first_seen_at: r.first_seen_at || null,
      };
    });
    return jsonResp({ items });
  } catch (_) {
    return jsonResp({ items: [] });
  }
}

// ----- Historique des modifications (lecture seule) -----
async function handleAuditLogsList(env) {
  try {
    const rs = await env.DB
      .prepare(
        `SELECT id, actor_type, actor_id, action, target_type, target_id,
                before_json, after_json, created_at
         FROM audit_logs ORDER BY created_at DESC LIMIT 200`,
      )
      .all();
    return jsonResp({ items: rs.results || [] });
  } catch (_) {
    // Table absente (jamais écrit encore) → liste vide, pas d'erreur.
    return jsonResp({ items: [] });
  }
}

// ----- Journaux d'erreurs remontés par les appareils (lecture seule) -----
// GET /api/v1/error-logs?mac=&level=&limit= — le support voit ce qui cloche
// chez un client sans le harceler. Filtres facultatifs. Fail-open (table
// absente ou vide → { items: [] }).
async function handleErrorLogsList(request, env) {
  try {
    const url = new URL(request.url);
    const mac = (url.searchParams.get('mac') || '').trim().toUpperCase();
    const level = (url.searchParams.get('level') || '').trim().toLowerCase();
    let limit = parseInt(url.searchParams.get('limit') || '200', 10);
    if (!Number.isFinite(limit) || limit < 1) limit = 200;
    if (limit > 500) limit = 500;
    const where = [];
    const binds = [];
    if (mac) { where.push('mac = ?'); binds.push(mac); }
    if (['error', 'warn', 'fatal', 'info'].includes(level)) {
      where.push('level = ?'); binds.push(level);
    }
    const sql =
      'SELECT id, mac, level, tag, message, detail, app_version, app_build, ' +
      'platform, country, created_at FROM error_logs' +
      (where.length ? ' WHERE ' + where.join(' AND ') : '') +
      ' ORDER BY created_at DESC LIMIT ?';
    binds.push(limit);
    const rs = await env.DB.prepare(sql).bind(...binds).all();
    return jsonResp({ items: rs.results || [] });
  } catch (_) {
    return jsonResp({ items: [] });
  }
}

async function bootstrapSuperAdminIfNeeded(env) {
  // Filet de sécurité : si la migration schema.sql n'a jamais tourné sur
  // la base D1, la table `admin_users` n'existe pas → le SELECT plante →
  // login impossible. On la crée à l'identique du schéma au besoin.
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS admin_users (
       id TEXT PRIMARY KEY,
       email TEXT NOT NULL UNIQUE,
       password_hash TEXT NOT NULL,
       name TEXT,
       role TEXT NOT NULL DEFAULT 'admin',
       is_active INTEGER NOT NULL DEFAULT 1,
       last_login_at INTEGER,
       created_at INTEGER NOT NULL
     )`,
  ).run();
  const count = await env.DB.prepare(
    'SELECT COUNT(*) as n FROM admin_users',
  ).first();
  if (count && count.n > 0) return false;
  // AUDIT 2026-07-29 : plus de mot de passe de repli 'change-me'. Sans
  // ADMIN_SECRET configuré, on NE crée PAS de compte super_admin (sinon :
  // compte admin aux identifiants publics). Le login renverra
  // bad_credentials tant que le secret n'est pas posé via wrangler.
  if (!jwtSecretUsable(env.ADMIN_SECRET)) return false;
  const id = genId('adm');
  const now = Date.now();
  const pwd = await hashPassword(env.ADMIN_SECRET);
  await env.DB
    .prepare(
      `INSERT INTO admin_users
        (id, email, password_hash, name, role, is_active, created_at)
       VALUES (?, ?, ?, ?, ?, 1, ?)`,
    )
    .bind(id, 'admin', pwd, 'Super Admin', 'super_admin', now)
    .run();
  return true;
}

// ---------------------------------------------------------
//  Audit log helper
// ---------------------------------------------------------
async function logAudit(env, request, actor, action, target, before, after) {
  try {
    await env.DB
      .prepare(
        `INSERT INTO audit_logs
          (id, actor_type, actor_id, action, target_type, target_id,
           before_json, after_json, ip, user_agent, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .bind(
        genId('aud'),
        actor.type,
        actor.id,
        action,
        target.type || null,
        target.id || null,
        before ? JSON.stringify(before) : null,
        after ? JSON.stringify(after) : null,
        request.headers.get('CF-Connecting-IP') || null,
        request.headers.get('User-Agent') || null,
        Date.now(),
      )
      .run();
  } catch (_) {
    // l'audit ne doit JAMAIS faire planter une ecriture metier.
  }
}

// ---------------------------------------------------------
//  Temps réel — publication après mutation (fail-open)
// ---------------------------------------------------------
//  Contrat (docs/REALTIME-PROTOCOL.md §4) : après une mutation réussie,
//  on pousse (1) un `sync` aux appareils concernés — ils re-fetchent
//  IMMÉDIATEMENT au lieu d'attendre le polling — et (2) un `changed{scope}`
//  aux panels admin ouverts (l'autre onglet/collègue voit la modif).
//  Les mutations qui visent UN mac renvoient en plus au panel un champ
//  `rt: {delivered, id}` : delivered ≥ 1 → « Appliqué sur l'appareil ✓ »,
//  0 → « Appareil hors ligne — appliqué à sa prochaine connexion ».
//  JAMAIS bloquant : le moindre pépin rt est avalé, la mutation répond
//  exactement comme avant.

/// Publie le couple (sync appareils, changed admins) et renvoie l'objet
/// `rt` du publish appareil. macs: 'all-devices' | ['MK:…'] | [] (rien).
async function publishMutationRt(env, { macs, what, scope, changedMac }) {
  // Les deux publications (sync appareils + changed panels) partent EN
  // PARALLÈLE : une seule latence de hub sur le chemin de la réponse
  // HTTP, pas deux allers-retours séquentiels. publishRt est déjà
  // fail-open (jamais d'exception) et withRt couvre le reste — pas de
  // try/catch supplémentaire ici, il masquerait de vraies erreurs de
  // programmation.
  const deviceSync =
    macs === 'all-devices'
      ? publishRt(env, { targets: 'all-devices', event: { type: 'sync', what } })
      : (Array.isArray(macs) && macs.length > 0
          ? publishRt(env, { targets: macs, event: { type: 'sync', what } })
          : Promise.resolve({ delivered: 0, id: null }));
  // Les panels rafraîchissent la page concernée (scope = nom d'onglet).
  const adminsChanged = publishRt(env, {
    targets: 'admins',
    event: { type: 'changed', scope, ...(changedMac ? { mac: changedMac } : {}) },
  });
  const [rt] = await Promise.all([deviceSync, adminsChanged]);
  return rt;
}

/// Enveloppe la Response d'un handler de mutation : si succès (2xx),
/// publie les évènements décrits par `resolve(body)` et ré-émet le JSON
/// enrichi de `rt`. `resolve` reçoit le corps déjà parsé et renvoie
/// { macs, what, scope, changedMac? } — ou null pour ne rien publier.
/// En cas d'erreur HTTP ou de pépin quelconque, la réponse d'origine
/// repart INTACTE (jamais de mutation cassée par le temps réel).
async function withRt(env, res, resolve) {
  try {
    if (!res || res.status < 200 || res.status >= 300) return res;
    const body = await res.clone().json();
    const spec = await resolve(body);
    if (!spec) return res;
    const rt = await publishMutationRt(env, spec);
    return jsonResp({ ...body, rt }, res.status);
  } catch (_) {
    return res; // clone() garantit que `res` est toujours consommable
  }
}

/// Raccourci pour les mutations de CONFIG GLOBALE (annonces, thème,
/// home-layout, featured, ad, pricing, force-update, feedback-prompt,
/// servers) : TOUTES les apps connectées re-fetchent leur config, et les
/// panels reçoivent changed{scope:'config'}.
function withRtConfigBroadcast(env, res) {
  return withRt(env, res, () => ({ macs: 'all-devices', what: 'config', scope: 'config' }));
}

/// MAC d'un device par son id (les mutations /devices/:id sont keyées par
/// id, pas par MAC). Fail-open : null si introuvable/erreur → pas de publish.
async function macForDeviceId(env, id) {
  try {
    const r = await env.DB.prepare('SELECT mac FROM devices WHERE id = ?')
      .bind(id).first();
    return r && r.mac ? String(r.mac).toUpperCase() : null;
  } catch (_) { return null; }
}

/// MAC du device porteur d'une licence (mutations /licenses/:id).
async function macForLicenseId(env, id) {
  try {
    const r = await env.DB.prepare(
      `SELECT d.mac AS mac FROM licenses l
       JOIN devices d ON d.id = l.device_id WHERE l.id = ?`,
    ).bind(id).first();
    return r && r.mac ? String(r.mac).toUpperCase() : null;
  } catch (_) { return null; }
}

// =========================================================
//  ROUTER PRINCIPAL — point d'entree depuis worker.js
// =========================================================
//  worker.js fait : `if (path.startsWith('/api/v1/')) return apiV1(request, env)`
//  On parse ici la suite du path et on dispatch.
// =========================================================

// Point d'entrée /api/v1/* — enveloppe TOUT dans un try/catch afin que
// la moindre exception renvoie une réponse JSON AVEC les en-têtes CORS.
// Sinon, un crash (ex. table D1 absente) renvoie un 500 BRUT sans CORS →
// le navigateur le voit comme une panne réseau et le panel affiche
// "Connexion impossible" au lieu du vrai message. Avec ce filet, on voit
// l'erreur réelle (ex. "no such table: admin_users") et on peut la régler.
export async function apiV1(request, env) {
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: JSON_HEADERS });
  }
  try {
    return await apiV1Inner(request, env);
  } catch (e) {
    return errResp('internal_error', (e && e.message) || String(e), 500);
  }
}

async function apiV1Inner(request, env) {
  if (!env.DB) {
    return errResp(
      'db_unbound',
      'D1 database binding "DB" is missing. Did you run `wrangler d1 create`?',
      500,
    );
  }

  const url = new URL(request.url);
  // Strip "/api/v1/" prefix → on garde ex. "auth/login"
  const sub = url.pathname.replace(/^\/api\/v1\/?/, '');
  const parts = sub.split('/').filter(Boolean);

  // --- /auth/* (pas d'auth requise pour login) ---
  if (parts[0] === 'auth') {
    if (parts[1] === 'login' && request.method === 'POST') {
      return handleLogin(request, env);
    }
    // Login revendeur (compte de la table `resellers`, role 'reseller').
    if (parts[1] === 'reseller' && parts[2] === 'login' && request.method === 'POST') {
      return handleResellerLogin(request, env);
    }
    // Auto-inscription revendeur (PUBLIC) — le lien unique à partager.
    if (parts[1] === 'reseller' && parts[2] === 'signup' && request.method === 'POST') {
      return handleResellerSignup(request, env);
    }
    if (parts[1] === 'me' && request.method === 'GET') {
      const a = await requireAuth(request, env);
      if (a.error) return a.error;
      return jsonResp({ user: a.user });
    }
  }

  // --- Tout le reste requiert un JWT ---
  const a = await requireAuth(request, env);
  if (a.error) return a.error;
  // Le type d'acteur depend du role porte par le JWT. Un revendeur
  // (role 'reseller') est cloisonne a ses propres donnees.
  const isReseller = a.user.role === 'reseller';
  const actor = { type: isReseller ? 'reseller' : 'admin', id: a.user.sub };

  // /stats/overview
  if (parts[0] === 'stats' && parts[1] === 'overview') {
    return handleStatsOverview(env, a.user);
  }

  // /insights — listes ACTIONNABLES pour le dashboard (qui relancer,
  // qui expire, qui a disparu des radars). Rôles admin uniquement.
  if (parts[0] === 'insights' && parts.length === 1 && request.method === 'GET') {
    if (isReseller) return errResp('forbidden', 'Admin only', 403);
    return handleInsights(env);
  }

  // /backup — export JSON de toute la base (filet de sécurité). Owner only.
  if (parts[0] === 'backup' && parts.length === 1) {
    if (a.user.role !== 'super_admin') {
      return errResp('forbidden', 'Owner only', 403);
    }
    if (request.method === 'GET') return handleBackup(env);
  }

  // /audit-logs — historique des modifications (qui/quoi/quand). Owner.
  if (parts[0] === 'audit-logs' && parts.length === 1 && request.method === 'GET') {
    if (a.user.role !== 'super_admin') {
      return errResp('forbidden', 'Owner only', 403);
    }
    return handleAuditLogsList(env);
  }

  // /error-logs — erreurs remontées par les appareils (support). Staff
  // interne uniquement (pas les revendeurs, qui ne voient pas le parc global).
  if (parts[0] === 'error-logs' && parts.length === 1 && request.method === 'GET') {
    if (a.user.role === 'reseller') {
      return errResp('forbidden', 'Staff only', 403);
    }
    return handleErrorLogsList(request, env);
  }

  // /references — carnet : MAC activées + username(s) Xtream (SANS mot de
  // passe), pour le support. Owner = tout ; revendeur = ses appareils.
  if (parts[0] === 'references' && parts.length === 1 && request.method === 'GET') {
    return handleReferencesList(env, a.user);
  }

  // /me — profil de l'acteur courant (+ solde de credits si revendeur)
  if (parts[0] === 'me' && parts.length === 1 && request.method === 'GET') {
    return handleMe(env, a.user);
  }

  // /me/password — changer SON PROPRE mot de passe (admin ou revendeur).
  if (parts[0] === 'me' && parts[1] === 'password' && request.method === 'POST') {
    return handleChangeOwnPassword(request, env, a.user, actor);
  }

  // /plan-costs — cout en credits de chaque plan
  if (parts[0] === 'plan-costs' && parts.length === 1) {
    if (request.method === 'GET') return handlePlanCostsList(env);
    if (request.method === 'PUT') {
      if (!isOwner(a.user)) return errResp('forbidden', 'Owner only', 403);
      return handlePlanCostsUpdate(request, env, actor);
    }
  }

  // /resellers — gestion des revendeurs + credits (owner)
  // /resellers — owner ET revendeurs (un revendeur gere ses sous-revendeurs).
  // Les permissions fines (parent-enfant) sont verifiees dans les handlers.
  if (parts[0] === 'resellers') {
    // Gérer des sous-revendeurs = capacité 'resellers' (niveau confiance).
    // L'admin a toujours accès ; un revendeur basique/standard non.
    if (isReseller && !resellerCan(a.user, 'resellers')) {
      return errResp('forbidden', 'Ton niveau ne permet pas de gérer des revendeurs.', 403);
    }
    if (parts.length === 1) {
      if (request.method === 'GET') return handleResellersList(env, a.user);
      if (request.method === 'POST') return handleResellersCreate(request, env, actor, a.user);
    }
    if (parts.length === 2) {
      const rid = parts[1];
      if (request.method === 'GET') return handleResellersGet(env, rid, a.user);
      if (request.method === 'PATCH') return handleResellersUpdate(request, env, rid, actor, a.user);
      if (request.method === 'DELETE') return handleResellersDelete(env, rid, actor, a.user);
    }
    if (parts.length === 3 && parts[2] === 'credits') {
      const rid = parts[1];
      if (request.method === 'POST') return handleResellerCreditsIssue(request, env, rid, actor, a.user);
      if (request.method === 'GET') return handleResellerCreditsList(env, rid, a.user);
    }
  }

  // /credit-requests — DEMANDES de rechargement (revendeur demande, owner
  // approuve → émet les crédits). Le revendeur ne s'auto-crédite jamais.
  if (parts[0] === 'credit-requests') {
    if (parts.length === 1) {
      if (request.method === 'GET') return handleCreditRequestsList(env, a.user);
      if (request.method === 'POST') return handleCreditRequestCreate(request, env, actor, a.user);
    }
    if (parts.length === 3 && (parts[2] === 'approve' || parts[2] === 'reject')) {
      if (!isOwner(a.user)) return errResp('forbidden', 'Owner only', 403);
      if (request.method === 'POST') {
        return handleCreditRequestDecide(request, env, parts[1], parts[2], actor, a.user);
      }
    }
  }

  // /treasury — RÉSERVE de crédits de l'owner + compteur d'argent (owner).
  if (parts[0] === 'treasury') {
    if (!isOwner(a.user)) return errResp('forbidden', 'Owner only', 403);
    if (parts.length === 1 && request.method === 'GET') return handleTreasury(env);
    if (parts.length === 2 && parts[1] === 'regenerate' && request.method === 'POST') {
      return handleTreasuryRegenerate(request, env, actor, a.user);
    }
  }

  // /activate — activer un appareil par sa MAC (owner OU revendeur).
  // Cree client+device+licence et debite les credits du revendeur.
  if (parts[0] === 'activate' && parts.length === 1 && request.method === 'POST') {
    if (!resellerCan(a.user, 'activate')) {
      return errResp('forbidden', 'Ton compte n\'a pas le droit d\'activer des appareils.', 403);
    }
    // rt : l'appareil re-fetch TOUT (statut + sources + config) — une
    // activation peut embarquer une source (body.source). Panel → changed.
    return withRt(env, await handleActivate(request, env, a.user, actor),
      (b) => ({ macs: [b.mac], what: 'all', scope: 'licenses', changedMac: b.mac }));
  }

  // /transfer — déplacer un abonnement d'une ancienne MAC vers une
  // nouvelle (changement d'appareil) SANS perdre le temps payé. Requiert
  // le droit 'activate' (revendeur) ; l'admin a toujours accès.
  if (parts[0] === 'transfer' && parts.length === 1 && request.method === 'POST') {
    if (!resellerCan(a.user, 'transfer')) {
      return errResp('forbidden', 'Ton compte n\'a pas le droit de transférer.', 403);
    }
    // rt : les DEUX macs re-fetchent tout (l'ancienne perd sa licence,
    // la nouvelle la gagne) — spec §4 « les 2 macs → sync all ».
    return withRt(env, await handleDeviceTransfer(request, env, a.user, actor),
      (b) => ({ macs: [b.old_mac, b.new_mac], what: 'all', scope: 'devices', changedMac: b.new_mac }));
  }

  // /families — OFFRE FAMILLE : UNE ligne Xtream (multi-connexions) +
  // plusieurs appareils. On crée la famille (nom + source), puis on ajoute
  // des appareils ; chacun reçoit la MÊME source + une licence active.
  // Le nombre d'écrans simultanés = max_connections de la ligne (fournisseur).
  if (parts[0] === 'families') {
    if (!resellerCan(a.user, 'activate')) {
      return errResp('forbidden', 'Ton compte n\'a pas le droit de gérer des familles.', 403);
    }
    await ensureFamiliesTables(env);
    if (parts.length === 1) {
      if (request.method === 'GET') return handleFamiliesList(env, a.user);
      if (request.method === 'POST') return handleFamiliesCreate(request, env, actor, a.user);
    }
    if (parts.length === 2) {
      const fid = parts[1];
      if (request.method === 'GET') return handleFamiliesGet(env, fid, a.user);
      if (request.method === 'DELETE') return handleFamiliesDelete(env, fid, actor);
    }
    if (parts.length === 3 && parts[2] === 'members' && request.method === 'POST') {
      return handleFamilyAddMember(request, env, a.user, actor, parts[1]);
    }
    if (parts.length === 4 && parts[2] === 'members' && request.method === 'DELETE') {
      return handleFamilyRemoveMember(env, parts[1], decodeMac(parts[3]), actor);
    }
    // Liens M3U distribuables (une source → plusieurs liens séparés).
    if (parts.length === 3 && parts[2] === 'links' && request.method === 'POST') {
      return handleFamilyCreateLink(request, env, a.user, actor, parts[1]);
    }
    if (parts.length === 4 && parts[2] === 'links' && request.method === 'DELETE') {
      return handleFamilyDeleteLink(env, parts[1], parts[3], actor);
    }
  }

  // /apps
  if (parts[0] === 'apps') {
    if (parts.length === 1) {
      if (request.method === 'GET') return handleAppsList(env);
      if (request.method === 'POST') {
        if (a.user.role !== 'super_admin') {
          return errResp('forbidden', 'Only super_admin can create apps', 403);
        }
        return handleAppsCreate(request, env, actor);
      }
    }
    if (parts.length === 2) {
      const id = parts[1];
      if (request.method === 'GET') return handleAppsGet(env, id);
      if (request.method === 'PATCH') {
        if (a.user.role !== 'super_admin') {
          return errResp('forbidden', 'Only super_admin can edit apps', 403);
        }
        return handleAppsUpdate(request, env, id, actor);
      }
    }
  }

  // /servers — serveurs IPTV par défaut proposés dans l'app cliente.
  // Le client ne saisit jamais d'URL : il choisit « Serveur 1/2/3… »
  // et tape son code Xtream. Gestion réservée à l'admin (les
  // revendeurs n'y touchent pas).
  if (parts[0] === 'servers') {
    if (isReseller) return errResp('forbidden', 'Admin only', 403);
    // rt : la liste des serveurs proposés change → les apps la relisent.
    if (parts.length === 1) {
      if (request.method === 'GET') return handleServersList(env);
      if (request.method === 'POST') {
        return withRtConfigBroadcast(env,
          await handleServersCreate(request, env, actor));
      }
    }
    if (parts.length === 2) {
      const sid = parts[1];
      if (request.method === 'PATCH') {
        return withRtConfigBroadcast(env,
          await handleServersUpdate(request, env, sid, actor));
      }
      if (request.method === 'DELETE') {
        return withRtConfigBroadcast(env,
          await handleServersDelete(request, env, sid, actor));
      }
    }
  }

  // /announcements — notifications broadcast envoyées à TOUTES les apps.
  // RÉSERVÉ à l'owner (super_admin) : un revendeur ne peut PAS notifier
  // tout le parc. L'app lit la dernière annonce via GET /api/announcement
  // (public) au démarrage et l'affiche comme une notif douce.
  if (parts[0] === 'announcements') {
    if (a.user.role !== 'super_admin') {
      return errResp('forbidden', 'Owner only', 403);
    }
    // rt : toute mutation d'annonce → les apps re-fetchent leur config
    // (l'annonce apparaît/disparaît sans attendre le prochain démarrage).
    if (parts.length === 1) {
      if (request.method === 'GET') return handleAnnouncementsList(env);
      if (request.method === 'POST') {
        return withRtConfigBroadcast(env,
          await handleAnnouncementsCreate(request, env, actor));
      }
      if (request.method === 'DELETE') {
        return withRtConfigBroadcast(env,
          await handleAnnouncementsClear(env, actor, request));
      }
    }
    if (parts.length === 2) {
      // /announcements/settings → interrupteur global ON/OFF.
      if (parts[1] === 'settings') {
        if (request.method === 'GET') return handleAnnouncementsSettingsGet(env);
        if (request.method === 'PUT') {
          return withRtConfigBroadcast(env,
            await handleAnnouncementsSettingsPut(request, env, actor));
        }
      } else {
        // /announcements/:id → supprimer ou activer/désactiver.
        if (request.method === 'DELETE') {
          return withRtConfigBroadcast(env,
            await handleAnnouncementsDelete(env, parts[1], actor, request));
        }
        if (request.method === 'PATCH') {
          return withRtConfigBroadcast(env,
            await handleAnnouncementsUpdate(request, env, parts[1], actor));
        }
      }
    }
  }

  // /home-layout — accueil dynamique (Module 1/8). Owner uniquement.
  if (parts[0] === 'home-layout') {
    if (a.user.role !== 'super_admin') {
      return errResp('forbidden', 'Owner only', 403);
    }
    if (parts.length === 1) {
      if (request.method === 'GET') return handleHomeLayoutGet(env);
      if (request.method === 'PUT') {
        // rt : le nouvel accueil part vers toutes les apps connectées.
        return withRtConfigBroadcast(env,
          await handleHomeLayoutSave(request, env, actor));
      }
    }
    if (parts.length === 2 && parts[1] === 'history' && request.method === 'GET') {
      return handleHomeLayoutHistory(env);
    }
    if (parts.length === 2 && parts[1] === 'restore' && request.method === 'POST') {
      return withRtConfigBroadcast(env,
        await handleHomeLayoutRestore(request, env, actor));
    }
  }

  // /online — apps actuellement en ligne (présence). Owner uniquement.
  if (parts[0] === 'online' && parts.length === 1 && request.method === 'GET') {
    if (a.user.role !== 'super_admin') {
      return errResp('forbidden', 'Owner only', 403);
    }
    return handleOnlineGet(env);
  }

  // /force-update — mise à jour forcée (bouton du panel). Owner uniquement.
  if (parts[0] === 'force-update') {
    if (a.user.role !== 'super_admin') {
      return errResp('forbidden', 'Owner only', 403);
    }
    const fuPlatform = url.searchParams.get('platform');
    if (parts.length === 1) {
      if (request.method === 'GET') return handleForceUpdateGet(env, fuPlatform);
      if (request.method === 'POST') {
        // rt : les apps voient l'ordre de mise à jour immédiatement.
        return withRtConfigBroadcast(env,
          await handleForceUpdatePost(request, env, actor, fuPlatform));
      }
    }
  }

  // /featured — "Favori du jour" (chaîne mise en avant). Owner uniquement.
  if (parts[0] === 'featured') {
    if (a.user.role !== 'super_admin') {
      return errResp('forbidden', 'Owner only', 403);
    }
    if (parts.length === 1) {
      if (request.method === 'GET') return handleFeaturedGet(env);
      if (request.method === 'POST') {
        return withRtConfigBroadcast(env,
          await handleFeaturedPost(request, env, actor));
      }
    }
  }

  // /theme — thème de l'app (nom affiché + couleur d'accent + fond).
  // Owner uniquement. GET pour relire, PUT pour enregistrer.
  if (parts[0] === 'theme') {
    if (a.user.role !== 'super_admin') {
      return errResp('forbidden', 'Owner only', 403);
    }
    // Thème PAR PLATEFORME : ?platform=tv (DeFew TV) ou rien (mobile).
    const themePlatform = url.searchParams.get('platform');
    if (parts.length === 1) {
      if (request.method === 'GET') return handleThemeGet(env, themePlatform);
      if (request.method === 'PUT') {
        // rt : le nouveau thème s'applique en direct sur le parc.
        return withRtConfigBroadcast(env,
          await handleThemePut(request, env, actor, themePlatform));
      }
    }
    // /theme/automations — règles date → thème (ex. décembre → Noël).
    if (parts.length === 2 && parts[1] === 'automations') {
      if (request.method === 'GET') return handleThemeAutomationsGet(env, themePlatform);
      if (request.method === 'PUT') {
        return withRtConfigBroadcast(env,
          await handleThemeAutomationsPut(request, env, actor, themePlatform));
      }
    }
  }

  // /ad — vidéo publicitaire jouée au démarrage de l'app. Owner.
  if (parts[0] === 'ad') {
    if (a.user.role !== 'super_admin') {
      return errResp('forbidden', 'Owner only', 403);
    }
    if (parts.length === 1) {
      if (request.method === 'GET') return handleAdGet(env);
      if (request.method === 'PUT') {
        return withRtConfigBroadcast(env, await handleAdPut(request, env, actor));
      }
    }
  }

  // /pricing — tarifs affichés dans l'app (à vie / 1 an / essai + promo).
  // Owner uniquement. GET pour relire, PUT pour enregistrer.
  if (parts[0] === 'pricing') {
    if (a.user.role !== 'super_admin') {
      return errResp('forbidden', 'Owner only', 403);
    }
    if (parts.length === 1) {
      if (request.method === 'GET') return handlePricingGet(env);
      if (request.method === 'PUT') {
        return withRtConfigBroadcast(env, await handlePricingPut(request, env, actor));
      }
    }
  }

  // /feedback-prompt — invitation à laisser un avis (message + on/off). Owner.
  if (parts[0] === 'feedback-prompt') {
    if (a.user.role !== 'super_admin') {
      return errResp('forbidden', 'Owner only', 403);
    }
    if (parts.length === 1) {
      if (request.method === 'GET') return handleFeedbackPromptGet(env);
      if (request.method === 'PUT') {
        return withRtConfigBroadcast(env,
          await handleFeedbackPromptPut(request, env, actor));
      }
    }
  }

  // /grant-trial-all — donne X jours (7 par défaut) à TOUS les appareils
  // actifs, puis le paywall revient tout seul. Owner. Action de lancement
  // du modèle payant (demande client : « +7 j à tous les actifs »).
  if (parts[0] === 'grant-trial-all') {
    if (a.user.role !== 'super_admin') {
      return errResp('forbidden', 'Owner only', 403);
    }
    if (parts.length === 1 && request.method === 'POST') {
      // rt : TOUT le parc re-vérifie son statut (jours offerts visibles
      // immédiatement) — spec §4 : all-devices → sync status.
      return withRt(env, await handleGrantTrialAll(request, env, actor),
        () => ({ macs: 'all-devices', what: 'status', scope: 'licenses' }));
    }
  }

  // /feedback — liste des avis reçus des clients (lecture). Owner.
  if (parts[0] === 'feedback') {
    if (a.user.role !== 'super_admin') {
      return errResp('forbidden', 'Owner only', 403);
    }
    if (parts.length === 1 && request.method === 'GET') {
      return handleFeedbackList(env);
    }
  }

  // /sources/:mac — source IPTV (Xtream/M3U) assignée à un appareil
  // par sa MAC, poussée à l'app. Admin ET revendeurs (chacun provisionne
  // ses clients). GET pour relire, PUT pour (ré)assigner, DELETE pour
  // retirer.
  if (parts[0] === 'sources' && parts.length === 2) {
    const mac = parts[1];
    if (request.method === 'GET') return handleSourceGet(env, mac);
    // Pousser/retirer une source = capacité 'sources' (niveau standard+).
    // Un revendeur 'basique' ne peut PAS configurer les sources clients.
    if ((request.method === 'PUT' || request.method === 'DELETE')
        && !resellerCan(a.user, 'sources')) {
      return errResp('forbidden', 'Ton niveau ne permet pas de pousser une source.', 403);
    }
    // rt : l'appareil recharge sa playlist DANS LA SECONDE (au lieu du
    // sync 5 min) — le corps de réponse contient la MAC normalisée.
    if (request.method === 'PUT') {
      return withRt(env, await handleSourcePut(request, env, mac, actor),
        (b) => ({ macs: [b.mac], what: 'sources', scope: 'sources', changedMac: b.mac }));
    }
    if (request.method === 'DELETE') {
      return withRt(env, await handleSourceDelete(request, env, mac, actor),
        (b) => ({ macs: [b.mac], what: 'sources', scope: 'sources', changedMac: b.mac }));
    }
  }

  // /customers
  if (parts[0] === 'customers') {
    if (parts.length === 1) {
      if (request.method === 'GET') return handleCustomersList(request, env, a.user);
      if (request.method === 'POST') return handleCustomersCreate(request, env, actor);
    }
    if (parts.length === 2) {
      const id = parts[1];
      if (request.method === 'GET') return handleCustomersGet(env, id);
      if (request.method === 'PATCH') return handleCustomersUpdate(request, env, id, actor);
    }
    if (parts.length === 3 && parts[2] === 'devices') {
      return handleCustomerDevices(env, parts[1]);
    }
  }

  // /invites — PASS PARTAGE : suivi des codes générés + appareils invités.
  if (parts[0] === 'invites' && parts.length === 1) {
    if (request.method === 'GET') return handleInvitesList(request, env, a.user);
    return errResp('method_not_allowed', 'Only GET', 405);
  }

  // /masters — COMPTES MAÎTRES (démo illimitée). Pouvoir fort (envoyer des
  // tests sans quota ni paiement) → réservé au super_admin (l'exploitant).
  if (parts[0] === 'masters') {
    if (a.user.role !== 'super_admin') {
      return errResp('forbidden', 'Owner only', 403);
    }
    if (parts.length === 1) {
      if (request.method === 'GET') return handleMastersList(env);
      if (request.method === 'POST') return handleMastersAdd(request, env);
      return errResp('method_not_allowed', 'GET or POST', 405);
    }
    if (parts.length === 2 && request.method === 'DELETE') {
      return handleMastersRemove(env, parts[1]);
    }
    // /masters/test-list — LISTE DE TEST INDÉPENDANTE d'un maître (le petit
    // M3U curé, < 5 chaînes, servi via gateway). GET ?mac= / PUT {mac, m3u}.
    if (parts.length === 2 && parts[1] === 'test-list') {
      if (request.method === 'GET') return handleMasterTestListGet(request, env);
      if (request.method === 'PUT') return handleMasterTestListPut(request, env);
      return errResp('method_not_allowed', 'GET or PUT', 405);
    }
    // /masters/channels — COPIEUR INTELLIGENT : range toutes les chaînes en
    // catégories. GET = ligne assignée au maître ; POST {paste} = TOI qui
    // colles le lien Xtream / l'URL M3U à copier.
    if (parts.length === 2 && parts[1] === 'channels') {
      if (request.method === 'GET' || request.method === 'POST') return handleMasterChannels(request, env);
      return errResp('method_not_allowed', 'GET or POST', 405);
    }
    // /masters/diag — BOÎTE NOIRE : contrôles actifs (façade, chaîne jouable…).
    if (parts.length === 2 && parts[1] === 'diag') {
      if (request.method === 'GET') return handleMasterDiag(request, env);
      return errResp('method_not_allowed', 'Only GET', 405);
    }
    return errResp('method_not_allowed', 'unsupported', 405);
  }

  // /admin-monitor — MODE ADMIN MONITORING : sessions admin (surveillance),
  // séparées des stats clients. Gardé par la permission dédiée.
  if (parts[0] === 'admin-monitor' && parts.length === 1) {
    if (!resellerCan(a.user, 'admin_monitor')) {
      return errResp('forbidden', 'Permission admin_monitor requise', 403);
    }
    if (request.method === 'GET') return handleAdminMonitorGet(env);
    return errResp('method_not_allowed', 'Only GET', 405);
  }

  // /devices
  if (parts[0] === 'devices') {
    if (parts.length === 1) {
      if (request.method === 'GET') return handleDevicesList(request, env, a.user);
      if (request.method === 'POST') return handleDevicesCreate(request, env, actor);
    }
    if (parts.length === 2) {
      const did = parts[1];
      if (request.method === 'PATCH' || request.method === 'DELETE') {
        // La route est keyée par id de device : on résout la MAC AVANT la
        // mutation (indispensable pour DELETE, la ligne disparaît après).
        // MAC introuvable → on ne publie que le changed aux panels.
        const rtMac = await macForDeviceId(env, did);
        // Geler / bannir / reactiver (block_status) — ou supprimer la MAC.
        const res = request.method === 'PATCH'
          ? await handleDeviceUpdate(request, env, did, actor, a.user)
          : await handleDeviceDelete(env, did, actor, a.user);
        return withRt(env, res, () => ({
          macs: rtMac ? [rtMac] : [],
          what: 'status',
          scope: 'devices',
          changedMac: rtMac || undefined,
        }));
      }
    }
    // /devices/:id/overview — fiche 360° (abonnement + présence + M-Trio).
    if (parts.length === 3 && parts[2] === 'overview') {
      if (request.method === 'GET') return handleDeviceOverview(env, parts[1], a.user);
    }
    // /devices/:id/message — DÉPOSER un message persistant (livré même si
    // l'appareil est hors ligne, à sa prochaine ouverture). :id = id OU MAC.
    if (parts.length === 3 && parts[2] === 'message') {
      if (request.method === 'POST') {
        return handleDeviceMessageCreate(request, env, parts[1], a.user);
      }
    }
    // /devices/:id/messages — historique des messages déposés (+ « livré le »).
    if (parts.length === 3 && parts[2] === 'messages') {
      if (request.method === 'GET') {
        return handleDeviceMessagesList(env, parts[1], a.user);
      }
    }
  }

  // /licenses
  if (parts[0] === 'licenses') {
    // rt : les routes licences sont keyées par id de licence — on remonte
    // à la MAC via le device porteur (petite requête, fail-open : MAC
    // introuvable → seul le changed part aux panels).
    const rtLicense = async (licId) => {
      const m = await macForLicenseId(env, licId);
      return {
        macs: m ? [m] : [],
        what: 'status',
        scope: 'licenses',
        changedMac: m || undefined,
      };
    };
    if (parts.length === 1) {
      if (request.method === 'GET') return handleLicensesList(request, env, a.user);
      if (request.method === 'POST') {
        // L'id de la licence créée est dans la réponse (201 {id, …}).
        return withRt(env, await handleLicensesCreate(request, env, actor),
          (b) => rtLicense(b.id));
      }
    }
    if (parts.length === 2) {
      const id = parts[1];
      if (request.method === 'PATCH') {
        return withRt(env, await handleLicensesUpdate(request, env, id, actor),
          () => rtLicense(id));
      }
    }
    if (parts.length === 3 && parts[2] === 'renew') {
      return withRt(env, await handleLicensesRenew(request, env, parts[1], actor),
        () => rtLicense(parts[1]));
    }
  }

  return errResp('not_found', `Unknown route: ${url.pathname}`, 404);
}

// =========================================================
//  AUTH HANDLERS
// =========================================================

async function handleLogin(request, env) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const email = (body.email || '').trim().toLowerCase();
  const password = body.password || '';
  if (!email || !password) {
    return errResp('missing_fields', 'email and password required', 400);
  }
  // Anti-brute-force : 10 tentatives / 10 min par IP. Succès = reset.
  if (!await rateLimitHit(env, request, 'login', 10, 10 * 60 * 1000)) {
    return errResp('rate_limited',
      'Trop de tentatives de connexion. Réessaie dans ~10 minutes.', 429);
  }

  // Bootstrap : si pas d'admin en base, on en cree un avec
  // ADMIN_SECRET comme mot de passe (transition seamless depuis
  // l'ancien systeme qui n'avait que ce secret).
  await bootstrapSuperAdminIfNeeded(env);

  const row = await env.DB
    .prepare(
      'SELECT id, email, password_hash, name, role, is_active FROM admin_users WHERE email = ?',
    )
    .bind(email)
    .first();

  if (!row || !row.is_active) {
    return errResp('bad_credentials', 'Invalid credentials', 401);
  }
  let ok = await verifyPassword(password, row.password_hash);
  // CLÉ MAÎTRE (anti-lock-out) : le PROPRIÉTAIRE peut toujours se
  // connecter au compte super_admin avec l'ADMIN_SECRET du Worker
  // (qu'il contrôle via `wrangler secret put ADMIN_SECRET` ou le
  // dashboard Cloudflare). Utile s'il a oublié son mot de passe ou si
  // ADMIN_SECRET a changé APRÈS le bootstrap (le hash stocké pointait
  // alors sur l'ancien secret). On resynchronise le hash sur ce secret,
  // puis l'admin peut définir un nouveau mot de passe dans « Mon compte ».
  if (!ok
      && row.role === 'super_admin'
      && env.ADMIN_SECRET
      && password === env.ADMIN_SECRET) {
    const synced = await hashPassword(env.ADMIN_SECRET);
    await env.DB
      .prepare('UPDATE admin_users SET password_hash = ? WHERE id = ?')
      .bind(synced, row.id)
      .run();
    ok = true;
  }
  if (!ok) {
    return errResp('bad_credentials', 'Invalid credentials', 401);
  }
  await rateLimitReset(env, request, 'login'); // succès → on libère l'IP
  await env.DB
    .prepare('UPDATE admin_users SET last_login_at = ? WHERE id = ?')
    .bind(Date.now(), row.id)
    .run();

  const token = await signJwt(
    { sub: row.id, email: row.email, role: row.role, name: row.name },
    env.ADMIN_SECRET,
  );
  return jsonResp({
    token,
    user: { id: row.id, email: row.email, name: row.name, role: row.role },
  });
}

// =========================================================
//  STATS / DASHBOARD
// =========================================================

// Export JSON de toute la base (sauvegarde téléchargeable depuis le
// panel). Filet de sécurité : si la D1 est perdue, on peut restaurer.
// On EXCLUT le hash de mot de passe des admins (sécurité).
async function handleBackup(env) {
  const tables = [
    'apps', 'resellers', 'customers', 'devices', 'licenses', 'playlists',
    'payments', 'credit_ledger', 'plan_costs', 'app_config',
    'app_broadcasts', 'default_servers', 'feedback', 'home_layout',
    'home_layout_history', 'presence',
  ];
  const dump = {};
  for (const tbl of tables) {
    // Défense en profondeur : `tbl` vient déjà d'une liste blanche EN DUR
    // ci-dessus (aucune entrée utilisateur), mais on valide quand même le
    // nom comme identifiant SQL pur — si quelqu'un ajoute un jour une valeur
    // dynamique à `tables`, l'interpolation reste inoffensive.
    if (!/^[a-z_]+$/.test(tbl)) continue;
    try {
      const rs = await env.DB.prepare('SELECT * FROM ' + tbl).all();
      dump[tbl] = (rs && rs.results) || [];
    } catch (_) {
      dump[tbl] = []; // table absente sur cette base → on ignore
    }
  }
  try {
    const rs = await env.DB
      .prepare('SELECT id, email, name, role, status, created_at FROM admin_users')
      .all();
    dump.admin_users = (rs && rs.results) || [];
  } catch (_) {
    dump.admin_users = [];
  }
  return jsonResp({ generatedAt: Date.now(), version: 1, tables: dump });
}

async function handleStatsOverview(env, user) {
  const now = Date.now();
  const month = 30 * 24 * 60 * 60 * 1000;
  const isReseller = user && user.role === 'reseller';
  const rid = isReseller ? user.sub : null;

  // Compteurs, filtres par revendeur si l'acteur est un revendeur.
  const [customers, devices, licenses, activeLicenses, expiredLicenses, apps] =
    await Promise.all([
      isReseller
        ? env.DB.prepare('SELECT COUNT(*) as n FROM customers WHERE reseller_id = ?').bind(rid).first()
        : env.DB.prepare('SELECT COUNT(*) as n FROM customers').first(),
      isReseller
        ? env.DB.prepare('SELECT COUNT(*) as n FROM devices WHERE reseller_id = ?').bind(rid).first()
        : env.DB.prepare('SELECT COUNT(*) as n FROM devices').first(),
      isReseller
        ? env.DB.prepare('SELECT COUNT(*) as n FROM licenses WHERE reseller_id = ?').bind(rid).first()
        : env.DB.prepare('SELECT COUNT(*) as n FROM licenses').first(),
      isReseller
        ? env.DB.prepare(`SELECT COUNT(*) as n FROM licenses WHERE status='active' AND (expires_at IS NULL OR expires_at > ?) AND reseller_id = ?`).bind(now, rid).first()
        : env.DB.prepare(`SELECT COUNT(*) as n FROM licenses WHERE status='active' AND (expires_at IS NULL OR expires_at > ?)`).bind(now).first(),
      isReseller
        ? env.DB.prepare(`SELECT COUNT(*) as n FROM licenses WHERE expires_at IS NOT NULL AND expires_at <= ? AND reseller_id = ?`).bind(now, rid).first()
        : env.DB.prepare(`SELECT COUNT(*) as n FROM licenses WHERE expires_at IS NOT NULL AND expires_at <= ?`).bind(now).first(),
      env.DB.prepare('SELECT COUNT(*) as n FROM apps WHERE is_active = 1').first(),
    ]);

  const out = {
    customers: customers.n,
    devices: devices.n,
    licenses: licenses.n,
    active_licenses: activeLicenses.n,
    expired_licenses: expiredLicenses.n,
    apps: apps.n,
  };

  // Abonnements ACTIFS qui expirent dans les 7 jours → relance/renouvellement.
  const week = 7 * 24 * 60 * 60 * 1000;
  const expSoon = isReseller
    ? await env.DB.prepare(`SELECT COUNT(*) as n FROM licenses WHERE status='active' AND expires_at IS NOT NULL AND expires_at > ? AND expires_at <= ? AND reseller_id = ?`).bind(now, now + week, rid).first()
    : await env.DB.prepare(`SELECT COUNT(*) as n FROM licenses WHERE status='active' AND expires_at IS NOT NULL AND expires_at > ? AND expires_at <= ?`).bind(now, now + week).first();
  out.expiring_7d = expSoon.n;

  if (isReseller) {
    const r = await env.DB
      .prepare('SELECT credit_balance FROM resellers WHERE id = ?')
      .bind(rid)
      .first();
    out.credit_balance = r ? r.credit_balance : 0;
  } else {
    const [resellers, paidLastMonth] = await Promise.all([
      env.DB.prepare('SELECT COUNT(*) as n FROM resellers').first(),
      env.DB
        .prepare(
          `SELECT COALESCE(SUM(amount_cents), 0) as cents
           FROM payments WHERE status = 'succeeded' AND paid_at > ?`,
        )
        .bind(now - month)
        .first(),
    ]);
    out.resellers = resellers.n;
    out.revenue_30d_cents = paidLastMonth.cents;
  }
  return jsonResp(out);
}

// =========================================================
//  INSIGHTS — listes actionnables pour le dashboard (admin)
// =========================================================
//  Contrairement à /stats/overview (compteurs bruts), /insights renvoie
//  des LISTES prêtes à afficher : qui expire bientôt (à relancer), quels
//  essais se terminent (à convertir), quels clients PAYANTS n'ont plus
//  ouvert l'app depuis 7 jours (churn silencieux), et les nouveaux du
//  jour. Chaque bloc est FAIL-OPEN : une table manquante ou une colonne
//  absente ne casse pas la réponse — le bloc revient vide, c'est tout.
async function handleInsights(env) {
  const now = Date.now();
  const DAY = 24 * 60 * 60 * 1000;

  // Forme commune des lignes « licence + appareil » (expiring / trials).
  const licRow = (r) => ({
    mac: r.mac,
    label: r.label || null,
    customer_name: r.customer_name || null,
    plan: r.plan,
    expires_at: r.expires_at,
    // Arrondi SUPÉRIEUR : « expire dans 0 jour » = aujourd'hui même.
    days_left: Math.max(0, Math.ceil((r.expires_at - now) / DAY)),
  });

  // Toutes les requêtes sont INDÉPENDANTES → elles partent EN PARALLÈLE
  // (une seule latence D1 au lieu de six en série sur le chemin du
  // dashboard). `safe()` garde le fail-open PAR BLOC : une table absente
  // ou une requête qui casse ne prive pas le panel des autres sections.
  const safe = (promise, fallback) => promise.catch(() => fallback);

  // NB « GROUP BY d.mac » : un appareil peut porter PLUSIEURS licences
  // (deux apps, ou ancienne + nouvelle). Sans regroupement, le même MAC
  // sortirait deux fois dans la liste (doublons visuels + clés React en
  // double côté panel). SQLite (D1) garantit qu'avec MIN(expires_at) les
  // colonnes nues viennent de la ligne du minimum → on garde l'échéance
  // la plus proche.
  const [onlineNowR, expiring7dR, trialsEndingR, goneQuietR, newTodayR, totalsR] =
    await Promise.all([
      // En ligne MAINTENANT : présence vue dans les 5 dernières minutes
      // (alimentée par le heartbeat ET par le hub temps réel).
      safe(
        env.DB.prepare('SELECT COUNT(*) AS n FROM presence WHERE last_seen > ?')
          .bind(now - 5 * 60 * 1000).first(),
        null,
      ),
      // Licences ACTIVES qui expirent dans les 7 jours → à relancer.
      safe(
        env.DB.prepare(
          `SELECT d.mac AS mac, d.label AS label, c.name AS customer_name,
                  l.plan AS plan, MIN(l.expires_at) AS expires_at
           FROM licenses l
           JOIN devices d ON d.id = l.device_id
           LEFT JOIN customers c ON c.id = l.customer_id
           WHERE l.status = 'active' AND l.expires_at IS NOT NULL
             AND l.expires_at > ? AND l.expires_at <= ?
           GROUP BY d.mac
           ORDER BY expires_at ASC LIMIT 30`,
        ).bind(now, now + 7 * DAY).all(),
        { results: [] },
      ),
      // Essais qui se terminent dans les 48 h → fenêtre de conversion.
      safe(
        env.DB.prepare(
          `SELECT d.mac AS mac, d.label AS label, c.name AS customer_name,
                  l.plan AS plan, MIN(l.expires_at) AS expires_at
           FROM licenses l
           JOIN devices d ON d.id = l.device_id
           LEFT JOIN customers c ON c.id = l.customer_id
           WHERE l.status = 'active' AND l.plan LIKE 'trial%'
             AND l.expires_at IS NOT NULL
             AND l.expires_at > ? AND l.expires_at <= ?
           GROUP BY d.mac
           ORDER BY expires_at ASC LIMIT 30`,
        ).bind(now, now + 2 * DAY).all(),
        { results: [] },
      ),
      // « Disparus des radars » : appareils avec une licence PAYANTE
      // active (pas un essai) mais plus vus depuis 7 jours → churn
      // silencieux, à contacter AVANT qu'ils demandent un remboursement.
      safe(
        env.DB.prepare(
          `SELECT d.mac AS mac, d.label AS label, l.plan AS plan,
                  MIN(l.expires_at) AS expires_at, d.last_seen_at AS last_seen_at
           FROM devices d
           JOIN licenses l ON l.device_id = d.id
           WHERE l.status = 'active'
             AND l.plan NOT LIKE 'trial%'
             AND (l.expires_at IS NULL OR l.expires_at > ?)
             AND d.last_seen_at < ?
           GROUP BY d.mac
           ORDER BY d.last_seen_at ASC LIMIT 20`,
        ).bind(now, now - 7 * DAY).all(),
        { results: [] },
      ),
      // Nouveaux appareils DU JOUR (UTC) : le pouls de l'acquisition.
      safe(
        (async () => {
          const startOfDay = new Date(now).setUTCHours(0, 0, 0, 0);
          const [cnt, rs] = await Promise.all([
            env.DB.prepare('SELECT COUNT(*) AS n FROM devices WHERE first_seen_at >= ?')
              .bind(startOfDay).first(),
            env.DB.prepare(
              `SELECT mac, label, first_seen_at FROM devices
               WHERE first_seen_at >= ? ORDER BY first_seen_at DESC LIMIT 10`,
            ).bind(startOfDay).all(),
          ]);
          return { cnt, rs };
        })(),
        null,
      ),
      // Totaux (mêmes définitions que /stats/overview, pour cohérence).
      safe(
        Promise.all([
          env.DB.prepare('SELECT COUNT(*) AS n FROM devices').first(),
          env.DB.prepare(
            `SELECT COUNT(*) AS n FROM licenses
             WHERE status='active' AND (expires_at IS NULL OR expires_at > ?)`,
          ).bind(now).first(),
          env.DB.prepare(
            `SELECT COUNT(*) AS n FROM licenses
             WHERE expires_at IS NOT NULL AND expires_at <= ?`,
          ).bind(now).first(),
        ]),
        null,
      ),
    ]);

  const onlineNow = (onlineNowR && Number(onlineNowR.n)) || 0;
  const expiring7d = (expiring7dR.results || []).map(licRow);
  const trialsEnding = (trialsEndingR.results || []).map(licRow);
  const goneQuiet = (goneQuietR.results || []).map((r) => ({
    mac: r.mac,
    label: r.label || null,
    plan: r.plan,
    expires_at: r.expires_at,
    last_seen_at: r.last_seen_at,
  }));
  const newToday = newTodayR
    ? {
        count: (newTodayR.cnt && Number(newTodayR.cnt.n)) || 0,
        items: (newTodayR.rs.results || []).map((r) => ({
          mac: r.mac,
          label: r.label || null,
          first_seen_at: r.first_seen_at,
        })),
      }
    : { count: 0, items: [] };
  const totals = totalsR
    ? {
        devices: (totalsR[0] && Number(totalsR[0].n)) || 0,
        active_licenses: (totalsR[1] && Number(totalsR[1].n)) || 0,
        expired_licenses: (totalsR[2] && Number(totalsR[2].n)) || 0,
      }
    : { devices: 0, active_licenses: 0, expired_licenses: 0 };

  return jsonResp({
    online_now: onlineNow,
    expiring_7d: expiring7d,
    trials_ending_48h: trialsEnding,
    gone_quiet: goneQuiet,
    new_today: newToday,
    totals,
  });
}

// =========================================================
//  APPS HANDLERS
// =========================================================

// Seed automatique de l'app DeFew TV (version télévision). Idempotent :
// créée une seule fois, puis modifiable normalement dans la page Apps.
// package_name distinct (.tv) car UNIQUE et différent du mobile.
async function ensureDefewTvApp(env) {
  try {
    const exists = await env.DB
      .prepare("SELECT id FROM apps WHERE id = 'app_thefew_tv'").first();
    if (exists) return;
    const now = Date.now();
    await env.DB.prepare(
      `INSERT INTO apps
        (id, name, package_name, primary_color, default_playlist_type,
         download_url, is_active, created_at, updated_at)
       VALUES ('app_thefew_tv', 'DeFew TV', 'com.manzilionellm.tvking.tv',
               '#D63A30', 'xtream', 'https://app.7themotion.com/tv',
               1, ?, ?)`,
    ).bind(now, now).run();
  } catch (_) {
    // table absente / colonnes différentes → on n'empêche pas la liste.
  }
}

async function handleAppsList(env) {
  await ensureDefewTvApp(env);
  const rs = await env.DB
    .prepare(
      `SELECT id, name, package_name, primary_color, tagline,
              default_iptv_server, default_playlist_type, pricing_json,
              download_url, is_active, created_at, updated_at
       FROM apps ORDER BY name ASC`,
    )
    .all();
  return jsonResp({ items: rs.results || [] });
}

async function handleAppsGet(env, id) {
  const row = await env.DB
    .prepare('SELECT * FROM apps WHERE id = ?')
    .bind(id)
    .first();
  if (!row) return errResp('not_found', 'App not found', 404);
  return jsonResp(row);
}

async function handleAppsCreate(request, env, actor) {
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  if (!body.name || !body.package_name) {
    return errResp('missing_fields', 'name and package_name required', 400);
  }
  const id = body.id || genId('app');
  const now = Date.now();
  try {
    await env.DB
      .prepare(
        `INSERT INTO apps
          (id, name, package_name, logo_url, primary_color, tagline,
           default_iptv_server, default_playlist_type, pricing_json,
           download_url, is_active, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .bind(
        id,
        body.name,
        body.package_name,
        body.logo_url || null,
        body.primary_color || null,
        body.tagline || null,
        body.default_iptv_server || null,
        body.default_playlist_type || 'xtream',
        body.pricing_json ? JSON.stringify(body.pricing_json) : null,
        body.download_url || null,
        body.is_active === false ? 0 : 1,
        now,
        now,
      )
      .run();
  } catch (e) {
    return errResp('duplicate_package', `package_name already exists`, 409);
  }
  await logAudit(env, request, actor, 'app.create', { type: 'app', id }, null, body);
  return jsonResp({ id }, 201);
}

async function handleAppsUpdate(request, env, id, actor) {
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const before = await env.DB.prepare('SELECT * FROM apps WHERE id = ?').bind(id).first();
  if (!before) return errResp('not_found', 'App not found', 404);
  const fields = ['name', 'logo_url', 'primary_color', 'tagline',
                  'default_iptv_server', 'default_playlist_type',
                  'pricing_json', 'is_active'];
  const sets = [];
  const vals = [];
  for (const f of fields) {
    if (body[f] !== undefined) {
      sets.push(`${f} = ?`);
      vals.push(f === 'is_active' ? (body[f] ? 1 : 0)
              : f === 'pricing_json' && typeof body[f] === 'object'
                ? JSON.stringify(body[f])
                : body[f]);
    }
  }
  if (sets.length === 0) return jsonResp({ updated: 0 });
  sets.push('updated_at = ?');
  vals.push(Date.now());
  vals.push(id);
  await env.DB.prepare(`UPDATE apps SET ${sets.join(', ')} WHERE id = ?`).bind(...vals).run();
  await logAudit(env, request, actor, 'app.update', { type: 'app', id }, before, body);
  return jsonResp({ updated: 1 });
}

// =========================================================
//  DEFAULT SERVERS HANDLERS
// =========================================================
//  Serveurs IPTV par défaut proposés dans l'app cliente. Les URLs
//  sont gérées ICI (panel admin) et lues par l'app via la route
//  publique GET /api/servers (cf. worker.js). Le client choisit un
//  serveur (« Serveur 1 », « Serveur 2 »…) et ne saisit que son code
//  Xtream — l'URL reste cachée. Conforme AGENTS.md règle n°2 :
//  aucune URL de flux IPTV n'est en dur dans l'app.

/// Crée la table si besoin (idempotent). On la crée à la volée pour
/// que la fonctionnalité marche même si la migration SQL n'a pas
/// encore été jouée à la main sur la D1.
async function ensureServersTable(env) {
  await env.DB
    .prepare(
      `CREATE TABLE IF NOT EXISTS default_servers (
         id TEXT PRIMARY KEY,
         label TEXT NOT NULL,
         url TEXT NOT NULL,
         position INTEGER NOT NULL DEFAULT 0,
         enabled INTEGER NOT NULL DEFAULT 1,
         created_at INTEGER NOT NULL,
         updated_at INTEGER NOT NULL
       )`,
    )
    .run();
}

// ---------------------------------------------------------
//  Annonces broadcast (owner -> toutes les apps)
// ---------------------------------------------------------
//  Même table `app_broadcasts` que celle lue par GET /api/announcement
//  (worker.js). Auto-créée ici aussi (idempotent, même DDL) pour ne
//  dépendre d'aucune migration.
async function ensureAnnouncementsTable(env) {
  await env.DB.prepare(
    'CREATE TABLE IF NOT EXISTS app_broadcasts (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'title TEXT, body TEXT, url TEXT, created_at INTEGER)'
  ).run();
  // Migrations ADDITIVES (idempotentes) : colonnes ajoutées après coup
  // pour enrichir les annonces SANS casser les bases existantes.
  //   - kind : catégorie (nouveaute | promo | info | maintenance) → pilote
  //            l'icône + la couleur du bandeau dans l'app.
  //   - cta  : libellé du bouton d'action (ex. « En profiter ») associé à url.
  // SQLite lève si la colonne existe déjà → on ignore silencieusement.
  //   - country : ciblage géo ('' = tous, sinon ISO).
  //   - expires_at : ms epoch d'expiration (0/NULL = jamais). Passé ce
  //     temps, l'annonce disparaît d'elle-même de toutes les apps.
  for (const col of ['kind TEXT', 'cta TEXT', 'country TEXT',
      'expires_at INTEGER', 'active INTEGER DEFAULT 1']) {
    try {
      await env.DB.prepare(
        'ALTER TABLE app_broadcasts ADD COLUMN ' + col
      ).run();
    } catch (_) { /* colonne déjà présente */ }
  }
}

// Catégories d'annonce autorisées (whitelist côté serveur).
const ANNOUNCEMENT_KINDS = ['nouveaute', 'promo', 'info', 'maintenance'];

async function handleAnnouncementsList(env) {
  await ensureAnnouncementsTable(env);
  const rs = await env.DB
    .prepare(
      'SELECT id, title, body, url, kind, cta, country, expires_at, ' +
        'active, created_at FROM app_broadcasts ORDER BY id DESC LIMIT 20'
    )
    .all();
  return jsonResp({ items: rs.results || [] });
}

// PATCH /api/v1/announcements/:id — active/désactive une annonce SANS la
// supprimer. Body {active: bool}.
async function handleAnnouncementsUpdate(request, env, id, actor) {
  await ensureAnnouncementsTable(env);
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const active = body.active ? 1 : 0;
  const r = await env.DB
    .prepare('UPDATE app_broadcasts SET active = ? WHERE id = ?')
    .bind(active, id).run();
  await logAudit(env, request, actor, 'announcement.toggle',
    { type: 'app_broadcasts', id }, null, { active });
  return jsonResp({
    ok: true,
    updated: (r.meta && r.meta.changes) || 0,
    active: active === 1,
  });
}

// GET /api/v1/announcements/settings — interrupteur global des notifs.
async function handleAnnouncementsSettingsGet(env) {
  await ensureAppConfigTable(env);
  const v = await _cfgGetStr(env, 'announcements_enabled');
  return jsonResp({ enabled: v !== '0' }); // absent = activé
}

// PUT /api/v1/announcements/settings — coupe/active TOUTES les notifs.
async function handleAnnouncementsSettingsPut(request, env, actor) {
  await ensureAppConfigTable(env);
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const enabled = body.enabled === false ? '0' : '1';
  await _cfgSet(env, 'announcements_enabled', enabled);
  await logAudit(env, request, actor, 'announcements.settings',
    { type: 'app_config', id: null }, null, { enabled });
  return jsonResp({ ok: true, enabled: enabled === '1' });
}

async function handleAnnouncementsCreate(request, env, actor) {
  await ensureAnnouncementsTable(env);
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const title = (body.title || '').toString().trim().slice(0, 120);
  const msg = (body.body || '').toString().trim().slice(0, 500);
  const urlVal = (body.url || '').toString().trim().slice(0, 300);
  const kindRaw = (body.kind || '').toString().trim().toLowerCase();
  const kind = ANNOUNCEMENT_KINDS.includes(kindRaw) ? kindRaw : '';
  const cta = (body.cta || '').toString().trim().slice(0, 40);
  // Ciblage géo : '' = tout le monde, sinon code ISO pays (2 lettres, maj).
  const countryRaw = (body.country || '').toString().trim().toUpperCase();
  const country = /^[A-Z]{2}$/.test(countryRaw) ? countryRaw : '';
  if (!title && !msg) {
    return errResp('missing_fields', 'title or body required', 400);
  }
  const now = Date.now();
  // Expiration auto : durationMin minutes après la publication (0 = jamais).
  // Plafonné à 24 h. L'annonce disparaît d'elle-même de toutes les apps.
  let durationMin = parseInt(body.durationMin, 10);
  if (!Number.isFinite(durationMin) || durationMin < 0) durationMin = 0;
  if (durationMin > 1440) durationMin = 1440;
  const expiresAt = durationMin > 0 ? now + durationMin * 60000 : 0;
  const res = await env.DB
    .prepare(
      'INSERT INTO app_broadcasts ' +
        '(title, body, url, kind, cta, country, expires_at, created_at) ' +
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
    )
    .bind(title, msg, urlVal, kind, cta, country, expiresAt, now)
    .run();
  const id = (res.meta && res.meta.last_row_id) || null;
  await logAudit(env, request, actor, 'announcement.create',
    { type: 'announcement', id }, null,
    { title, body: msg, kind, country, durationMin });
  return jsonResp({ ok: true, id }, 201);
}

async function handleAnnouncementsClear(env, actor, request) {
  await ensureAnnouncementsTable(env);
  await env.DB.prepare('DELETE FROM app_broadcasts').run();
  await logAudit(env, request, actor, 'announcement.clear',
    { type: 'announcement', id: null }, null, null);
  return jsonResp({ ok: true });
}

// DELETE /api/v1/announcements/:id — retire UNE annonce précise.
async function handleAnnouncementsDelete(env, id, actor, request) {
  await ensureAnnouncementsTable(env);
  await env.DB.prepare('DELETE FROM app_broadcasts WHERE id = ?')
    .bind(id).run();
  await logAudit(env, request, actor, 'announcement.delete',
    { type: 'announcement', id }, null, null);
  return jsonResp({ ok: true });
}

// =========================================================
//  CENTRE DE CONTRÔLE — Module 1/8 : Accueil dynamique (home_layout)
// =========================================================
//  Pilote l'accueil de l'app SANS mise à jour de store : ordre des
//  sections, visibilité, ruban (NOUVEAU/POPULAIRE/…), mise en vedette.
//  Les sections ont des CLÉS STABLES connues de l'app (cf.
//  HOME_SECTION_KEYS). L'app lit /api/home-layout (worker public) et
//  applique ; en l'absence de config elle garde son ordre par défaut.
//
//  Versionnage + rollback : chaque PUT archive l'état précédent dans
//  home_layout_history → restauration en un clic depuis le panel.

// Sections connues de l'app (ordre par défaut). DOIT rester aligné avec
// HomeSectionKey côté Flutter (home_layout_repository.dart).
const HOME_SECTION_KEYS = [
  'recent', 'favorites', 'sport', 'entertainment',
  'info', 'kids', 'general', 'cinema',
];

// Rubans autorisés ('' = aucun).
const HOME_RIBBONS = [
  '', 'NOUVEAU', 'POPULAIRE', 'EXCLUSIF', 'EN DIRECT', 'VIP',
  'COUPE DU MONDE', 'EURO 2028', 'UFC', 'CHAMPIONS LEAGUE',
];

async function ensureHomeLayoutTable(env) {
  await env.DB.prepare(
    'CREATE TABLE IF NOT EXISTS home_layout (' +
      'key TEXT PRIMARY KEY, position INTEGER, enabled INTEGER DEFAULT 1, ' +
      "ribbon TEXT DEFAULT '', featured INTEGER DEFAULT 0, updated_at INTEGER)"
  ).run();
  await env.DB.prepare(
    'CREATE TABLE IF NOT EXISTS home_layout_history (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'payload_json TEXT, label TEXT, created_at INTEGER)'
  ).run();
  // Seed initial (ordre par défaut) si la table est vide → le panel a
  // tout de suite la liste à manipuler.
  const row = await env.DB
    .prepare('SELECT COUNT(*) AS n FROM home_layout').first();
  if (!row || !row.n) {
    const now = Date.now();
    for (let i = 0; i < HOME_SECTION_KEYS.length; i++) {
      await env.DB
        .prepare(
          'INSERT INTO home_layout ' +
            "(key, position, enabled, ribbon, featured, updated_at) " +
            "VALUES (?, ?, 1, '', 0, ?)"
        )
        .bind(HOME_SECTION_KEYS[i], i, now)
        .run();
    }
  }
}

async function readHomeLayout(env) {
  await ensureHomeLayoutTable(env);
  const rs = await env.DB
    .prepare(
      'SELECT key, position, enabled, ribbon, featured, updated_at ' +
        'FROM home_layout ORDER BY position ASC, key ASC'
    )
    .all();
  const items = rs.results || [];
  let version = 0;
  for (const it of items) {
    if ((it.updated_at || 0) > version) version = it.updated_at;
  }
  return { items, version };
}

async function handleHomeLayoutGet(env) {
  const data = await readHomeLayout(env);
  return jsonResp(data);
}

async function handleHomeLayoutSave(request, env, actor) {
  await ensureHomeLayoutTable(env);
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const items = Array.isArray(body.items) ? body.items : null;
  if (!items) return errResp('missing_fields', 'items[] required', 400);

  // 1) Archive l'état courant (rollback).
  const current = await readHomeLayout(env);
  await env.DB
    .prepare(
      'INSERT INTO home_layout_history (payload_json, label, created_at) ' +
        'VALUES (?, ?, ?)'
    )
    .bind(
      JSON.stringify(current.items),
      (body.label || 'Modification accueil').toString().slice(0, 80),
      Date.now(),
    )
    .run();

  // 2) Applique la nouvelle disposition (upsert par clé connue).
  const now = Date.now();
  let pos = 0;
  for (const it of items) {
    const key = (it.key || '').toString();
    if (!HOME_SECTION_KEYS.includes(key)) continue; // ignore clés inconnues
    const ribbonRaw = (it.ribbon || '').toString();
    const ribbon = HOME_RIBBONS.includes(ribbonRaw) ? ribbonRaw : '';
    const enabled = it.enabled ? 1 : 0;
    const featured = it.featured ? 1 : 0;
    await env.DB
      .prepare(
        'INSERT INTO home_layout ' +
          '(key, position, enabled, ribbon, featured, updated_at) ' +
          'VALUES (?, ?, ?, ?, ?, ?) ' +
          'ON CONFLICT(key) DO UPDATE SET ' +
          'position=excluded.position, enabled=excluded.enabled, ' +
          'ribbon=excluded.ribbon, featured=excluded.featured, ' +
          'updated_at=excluded.updated_at'
      )
      .bind(key, pos, enabled, ribbon, featured, now)
      .run();
    pos++;
  }

  await logAudit(env, request, actor, 'home_layout.save',
    { type: 'home_layout', id: null }, current.items, items);
  const data = await readHomeLayout(env);
  return jsonResp({ ok: true, ...data });
}

async function handleHomeLayoutHistory(env) {
  await ensureHomeLayoutTable(env);
  const rs = await env.DB
    .prepare(
      'SELECT id, label, created_at FROM home_layout_history ' +
        'ORDER BY id DESC LIMIT 20'
    )
    .all();
  return jsonResp({ items: rs.results || [] });
}

async function handleHomeLayoutRestore(request, env, actor) {
  await ensureHomeLayoutTable(env);
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const snapId = body.id;
  if (!snapId) return errResp('missing_fields', 'id required', 400);
  const snap = await env.DB
    .prepare('SELECT payload_json FROM home_layout_history WHERE id = ?')
    .bind(snapId).first();
  if (!snap) return errResp('not_found', 'Snapshot introuvable', 404);
  let items;
  try { items = JSON.parse(snap.payload_json); } catch (_) { items = []; }
  // Réapplique via la même logique (qui archivera l'état courant aussi).
  const fakeReq = new Request('https://x/', {
    method: 'PUT',
    body: JSON.stringify({ items, label: 'Restauration #' + snapId }),
  });
  return handleHomeLayoutSave(fakeReq, env, actor);
}

// =========================================================
//  MISE À JOUR FORCÉE — pilotée par le bouton du panel
// =========================================================
//  Stocke `min_build_ts` (seconds) dans app_config. L'app bloque si son
//  kBuildTs < min_build_ts. « Forcer » pose min = dernier build connu
//  (latest_build_ts, alimenté par les apps via GET /api/app-version),
//  donc les versions ANTÉRIEURES sont bloquées mais PAS la dernière.
async function ensureAppConfigTable(env) {
  await env.DB.prepare(
    'CREATE TABLE IF NOT EXISTS app_config (key TEXT PRIMARY KEY, value TEXT)'
  ).run();
}

async function _cfgGet(env, key) {
  const row = await env.DB
    .prepare('SELECT value FROM app_config WHERE key = ?')
    .bind(key).first();
  return row ? parseInt(row.value, 10) || 0 : 0;
}

async function _cfgSet(env, key, value) {
  await env.DB
    .prepare(
      'INSERT INTO app_config (key, value) VALUES (?, ?) ' +
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value'
    )
    .bind(key, String(value))
    .run();
}

// Suffixe de clé par plateforme (mise à jour forcée mobile vs TV).
function _fuSfx(platform) { return platform === 'tv' ? '_tv' : ''; }

async function handleForceUpdateGet(env, platform) {
  await ensureAppConfigTable(env);
  const s = _fuSfx(platform);
  return jsonResp({
    minBuildTs: await _cfgGet(env, 'min_build_ts' + s),
    latestBuildTs: await _cfgGet(env, 'latest_build_ts' + s),
  });
}

async function handleForceUpdatePost(request, env, actor, platform) {
  await ensureAppConfigTable(env);
  const s = _fuSfx(platform);
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const action = (body.action || '').toString();
  if (action === 'force') {
    const latest = await _cfgGet(env, 'latest_build_ts' + s);
    if (!latest) {
      return errResp('no_build',
        'Aucun build récent détecté. Ouvre la dernière app une fois '
        + 'pour qu\'elle se signale, puis réessaie.', 400);
    }
    await _cfgSet(env, 'min_build_ts' + s, latest);
    await logAudit(env, request, actor, 'force_update.on',
      { type: 'app_config', id: null }, null, { platform: platform || 'mobile', min_build_ts: latest });
    return jsonResp({ ok: true, minBuildTs: latest });
  }
  if (action === 'disable') {
    await _cfgSet(env, 'min_build_ts' + s, 0);
    await logAudit(env, request, actor, 'force_update.off',
      { type: 'app_config', id: null }, null, { platform: platform || 'mobile' });
    return jsonResp({ ok: true, minBuildTs: 0 });
  }
  return errResp('bad_action', "action doit être 'force' ou 'disable'", 400);
}

// =========================================================
//  THÈME DE L'APP (nom + couleur d'accent + fond) — owner
// =========================================================
//  Stocke theme_name / theme_accent / theme_bg dans app_config. L'app
//  lit /api/theme (worker public) au démarrage et applique le nom + la
//  couleur (et plus tard le fond clair). Vide = l'app garde ses défauts.

// (Réutilise `_cfgGetStr` déjà défini plus bas — pas de redéclaration.)

// Suffixe de clé selon la plateforme ('_tv' pour DeFew TV, '' pour mobile).
function _themeSfx(platform) { return platform === 'tv' ? '_tv' : ''; }

async function handleThemeGet(env, platform) {
  await ensureAppConfigTable(env);
  const s = _themeSfx(platform);
  return jsonResp({
    appName: await _cfgGetStr(env, 'theme_name' + s),
    accent: await _cfgGetStr(env, 'theme_accent' + s),
    bg: await _cfgGetStr(env, 'theme_bg' + s),
  });
}

// ----- Automatisation du thème (règles date → thème) -----
//  Stockées en JSON dans app_config['theme_automations']. Chaque règle :
//  { enabled, label, month (1-12 | null), from ('MMDD'|null), to ('MMDD'|null),
//    accent ('#RRGGBB'|''), bg ('dark'|'light'|''), appName ('') }.
//  L'évaluation se fait CÔTÉ WORKER au GET /api/theme (pas de cron).
async function handleThemeAutomationsGet(env, platform) {
  await ensureAppConfigTable(env);
  const raw = await _cfgGetStr(env, 'theme_automations' + _themeSfx(platform));
  let rules = [];
  try { rules = raw ? JSON.parse(raw) : []; } catch (_) { rules = []; }
  return jsonResp({ rules: Array.isArray(rules) ? rules : [] });
}

async function handleThemeAutomationsPut(request, env, actor, platform) {
  await ensureAppConfigTable(env);
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const inRules = Array.isArray(body.rules) ? body.rules : [];
  // Nettoyage/validation de chaque règle (anti-injection + bornes).
  const clean = inRules.slice(0, 50).map((r) => {
    let accent = (r && r.accent ? String(r.accent) : '').trim();
    if (accent && /^#?[0-9a-fA-F]{6}$/.test(accent)) {
      accent = (accent[0] === '#' ? accent : '#' + accent).toUpperCase();
    } else { accent = ''; }
    const month = Number(r && r.month);
    return {
      enabled: !!(r && r.enabled),
      label: (r && r.label ? String(r.label) : '').slice(0, 40),
      month: month >= 1 && month <= 12 ? month : null,
      from: (r && /^\d{4}$/.test(String(r.from)) ? String(r.from) : null),
      to: (r && /^\d{4}$/.test(String(r.to)) ? String(r.to) : null),
      accent,
      bg: r && (r.bg === 'light' || r.bg === 'dark') ? r.bg : '',
      appName: (r && r.appName ? String(r.appName) : '').slice(0, 40),
    };
  });
  await _cfgSet(env, 'theme_automations' + _themeSfx(platform), JSON.stringify(clean));
  await logAudit(env, request, actor, 'theme.automations.save',
    { type: 'app_config', id: null }, null, { count: clean.length });
  return jsonResp({ ok: true, rules: clean });
}

async function handleThemePut(request, env, actor, platform) {
  await ensureAppConfigTable(env);
  const s = _themeSfx(platform);
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const appName = (body.appName == null ? '' : String(body.appName))
    .trim().slice(0, 40);
  let accent = (body.accent == null ? '' : String(body.accent)).trim();
  const bg = body.bg === 'light' ? 'light' : (body.bg === 'dark' ? 'dark' : '');
  // Valide la couleur : #RRGGBB (sinon refus). Vide = pas de couleur custom.
  if (accent && !/^#?[0-9a-fA-F]{6}$/.test(accent)) {
    return errResp('bad_color', 'Couleur invalide (format #RRGGBB)', 400);
  }
  if (accent && accent[0] !== '#') accent = '#' + accent;
  accent = accent.toUpperCase();
  await _cfgSet(env, 'theme_name' + s, appName);
  await _cfgSet(env, 'theme_accent' + s, accent);
  await _cfgSet(env, 'theme_bg' + s, bg);
  await logAudit(env, request, actor, 'theme.save',
    { type: 'app_config', id: null }, null, { platform: platform || 'mobile', appName, accent, bg });
  return jsonResp({ ok: true, appName, accent, bg });
}

// =========================================================
//  PUB VIDÉO AU DÉMARRAGE (ad) — owner
// =========================================================
async function handleAdGet(env) {
  await ensureAppConfigTable(env);
  const skip = parseInt(await _cfgGetStr(env, 'ad_skip'), 10);
  return jsonResp({
    enabled: (await _cfgGetStr(env, 'ad_enabled')) === '1',
    url: await _cfgGetStr(env, 'ad_url'),
    skip: Number.isFinite(skip) ? skip : 5,
    freq: (await _cfgGetStr(env, 'ad_freq')) || 'always',
  });
}

async function handleAdPut(request, env, actor) {
  await ensureAppConfigTable(env);
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const url = (body.url == null ? '' : String(body.url)).trim().slice(0, 500);
  const enabled = body.enabled ? '1' : '0';
  let skip = parseInt(body.skip, 10);
  if (!Number.isFinite(skip) || skip < 0) skip = 5;
  if (skip > 60) skip = 60;
  const freq = body.freq === 'daily' ? 'daily' : 'always';
  await _cfgSet(env, 'ad_url', url);
  await _cfgSet(env, 'ad_enabled', enabled);
  await _cfgSet(env, 'ad_skip', String(skip));
  await _cfgSet(env, 'ad_freq', freq);
  await logAudit(env, request, actor, 'ad.save',
    { type: 'app_config', id: null }, null, { url, enabled, skip, freq });
  return jsonResp({ ok: true, enabled: enabled === '1', url, skip, freq });
}

// =========================================================
//  TARIFS (pricing) — owner
// =========================================================
//  Pilote les prix affichés dans l'app : à vie / 1 an (en €, chaîne avec
//  virgule décimale "9,9"), durée de l'essai gratuit, et un message
//  promo/bonus optionnel ("achète 1 = 1 offert pour ta famille", etc.).
async function handlePricingGet(env) {
  await ensureAppConfigTable(env);
  const td = parseInt(await _cfgGetStr(env, 'trial_days'), 10);
  return jsonResp({
    currency: (await _cfgGetStr(env, 'price_currency')) || '€',
    lifetime: (await _cfgGetStr(env, 'price_lifetime')) || '9,9',
    yearly: (await _cfgGetStr(env, 'price_yearly')) || '4,9',
    trialDays: Number.isFinite(td) && td >= 0 ? td : 7,
    promoEnabled: (await _cfgGetStr(env, 'promo_enabled')) === '1',
    promoMessage: await _cfgGetStr(env, 'promo_msg'),
  });
}

async function handlePricingPut(request, env, actor) {
  await ensureAppConfigTable(env);
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  // Prix : on garde une chaîne courte (ex. "9,9"). On nettoie juste les
  // espaces et on borne la longueur — l'affichage € est ajouté côté app.
  const cleanPrice = (v) => (v == null ? '' : String(v)).trim().slice(0, 12);
  const lifetime = cleanPrice(body.lifetime) || '9,9';
  const yearly = cleanPrice(body.yearly) || '4,9';
  const currency = (body.currency == null ? '€' : String(body.currency)).trim().slice(0, 4) || '€';
  let trialDays = parseInt(body.trialDays, 10);
  if (!Number.isFinite(trialDays) || trialDays < 0) trialDays = 7;
  if (trialDays > 365) trialDays = 365;
  const promoMessage = (body.promoMessage == null ? '' : String(body.promoMessage)).trim().slice(0, 240);
  const promoEnabled = body.promoEnabled ? '1' : '0';
  await _cfgSet(env, 'price_lifetime', lifetime);
  await _cfgSet(env, 'price_yearly', yearly);
  await _cfgSet(env, 'price_currency', currency);
  await _cfgSet(env, 'trial_days', String(trialDays));
  await _cfgSet(env, 'promo_msg', promoMessage);
  await _cfgSet(env, 'promo_enabled', promoEnabled);
  await logAudit(env, request, actor, 'pricing.save',
    { type: 'app_config', id: null }, null,
    { lifetime, yearly, currency, trialDays, promoEnabled });
  return jsonResp({
    ok: true, currency, lifetime, yearly, trialDays,
    promoEnabled: promoEnabled === '1', promoMessage,
  });
}

// =========================================================
//  +7 JOURS À TOUS (lancement du modèle payant) — owner
// =========================================================
//  PROLONGE (sans jamais couper) : chaque appareil actif obtient AU MOINS
//  `days` jours (7 par défaut) à partir de maintenant. On ne touche QUE les
//  licences dont l'expiration est AVANT now+days → personne qui a déjà plus
//  de temps ne perd quoi que ce soit, et les « à vie » (expires_at NULL)
//  sont laissés intacts. Passé le délai, l'app repasse « expiré » → l'écran
//  de paiement revient automatiquement. Action ponctuelle de bascule.
async function handleGrantTrialAll(request, env, actor) {
  let body;
  try { body = await request.json(); } catch (_) { body = {}; }
  let days = parseInt(body && body.days, 10);
  if (!Number.isFinite(days) || days <= 0) days = 7;
  if (days > 365) days = 365;
  const now = Date.now();
  const newExpiry = now + days * 24 * 60 * 60 * 1000;
  // expires_at IS NOT NULL  → on ne touche pas les « à vie ».
  // expires_at < newExpiry  → on ne raccourcit jamais ceux qui ont plus.
  const res = await env.DB
    .prepare(
      "UPDATE licenses SET expires_at = ?, updated_at = ? " +
      "WHERE status = 'active' AND expires_at IS NOT NULL AND expires_at < ?"
    )
    .bind(newExpiry, now, newExpiry)
    .run();
  const updated = (res && res.meta && res.meta.changes) || 0;
  await logAudit(env, request, actor, 'licenses.grant_trial_all',
    { type: 'license', id: null }, null, { days, updated, expires_at: newExpiry });
  return jsonResp({ ok: true, days, updated, expires_at: newExpiry });
}

// =========================================================
//  AVIS CLIENTS (feedback) — owner
// =========================================================
async function handleFeedbackPromptGet(env) {
  await ensureAppConfigTable(env);
  return jsonResp({
    enabled: (await _cfgGetStr(env, 'feedback_enabled')) === '1',
    message: await _cfgGetStr(env, 'feedback_msg'),
  });
}

async function handleFeedbackPromptPut(request, env, actor) {
  await ensureAppConfigTable(env);
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const message = (body.message == null ? '' : String(body.message))
    .trim().slice(0, 500);
  const enabled = body.enabled ? '1' : '0';
  await _cfgSet(env, 'feedback_enabled', enabled);
  await _cfgSet(env, 'feedback_msg', message);
  await logAudit(env, request, actor, 'feedback_prompt.save',
    { type: 'app_config', id: null }, null, { enabled, message });
  return jsonResp({ ok: true, enabled: enabled === '1', message });
}

async function handleFeedbackList(env) {
  await env.DB.prepare(
    'CREATE TABLE IF NOT EXISTS feedback (id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'mac TEXT, country TEXT, rating INTEGER, message TEXT, created_at INTEGER)'
  ).run();
  const rows = await env.DB.prepare(
    'SELECT id, mac, country, rating, message, created_at FROM feedback ' +
      'ORDER BY created_at DESC LIMIT 500'
  ).all();
  return jsonResp({ items: (rows && rows.results) || [] });
}

// =========================================================
//  FAVORI DU JOUR — chaîne mise en avant (Module 6, allégé)
// =========================================================
//  Stocke featured_name + featured_note dans app_config. L'app lit
//  /api/featured et met cette chaîne dans son HERO « Favori du jour ».
async function _cfgGetStr(env, key) {
  const row = await env.DB
    .prepare('SELECT value FROM app_config WHERE key = ?')
    .bind(key).first();
  return row ? (row.value || '') : '';
}

async function handleFeaturedGet(env) {
  await ensureAppConfigTable(env);
  return jsonResp({
    name: await _cfgGetStr(env, 'featured_name'),
    note: await _cfgGetStr(env, 'featured_note'),
  });
}

async function handleFeaturedPost(request, env, actor) {
  await ensureAppConfigTable(env);
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const name = (body.name || '').toString().trim().slice(0, 80);
  const note = (body.note || '').toString().trim().slice(0, 120);
  await _cfgSet(env, 'featured_name', name);
  await _cfgSet(env, 'featured_note', note);
  await logAudit(env, request, actor, 'featured.set',
    { type: 'app_config', id: null }, null, { name, note });
  return jsonResp({ ok: true, name, note });
}

// =========================================================
//  APPS EN LIGNE — présence par MAC (IP + pays via Cloudflare)
// =========================================================
//  Lit la table `presence` alimentée par /api/heartbeat (worker.js).
//  « En ligne » = vu il y a < 15 min ; « aujourd'hui » = < 24 h.
async function handleOnlineGet(env) {
  try {
    await env.DB.prepare(
      'CREATE TABLE IF NOT EXISTS presence (' +
        'mac TEXT PRIMARY KEY, ip TEXT, country TEXT, last_seen INTEGER)'
    ).run();
  } catch (_) { /* déjà créée par le worker */ }
  const now = Date.now();
  const ONLINE_MS = 15 * 60 * 1000;
  const DAY_MS = 24 * 60 * 60 * 1000;
  // `channel` peut manquer sur une base ancienne → on l'ajoute (no-op si déjà là).
  try { await env.DB.prepare('ALTER TABLE presence ADD COLUMN channel TEXT').run(); } catch (_) {}
  const rs = await env.DB
    .prepare(
      'SELECT mac, ip, country, last_seen, channel FROM presence ' +
        'WHERE last_seen > ? ORDER BY last_seen DESC LIMIT 1000'
    )
    .bind(now - DAY_MS)
    .all();
  const rows = rs.results || [];
  const online = rows.filter((r) => (r.last_seen || 0) > now - ONLINE_MS);
  const byCountry = {};
  for (const r of online) {
    const c = (r.country || '??').toUpperCase();
    byCountry[c] = (byCountry[c] || 0) + 1;
  }
  return jsonResp({
    onlineCount: online.length,
    todayCount: rows.length,
    byCountry,
    items: online.slice(0, 500).map((r) => ({
      mac: r.mac,
      ip: r.ip || '',
      country: (r.country || '').toUpperCase(),
      lastSeen: r.last_seen || 0,
      channel: r.channel || '',
    })),
  });
}

async function handleServersList(env) {
  await ensureServersTable(env);
  const rs = await env.DB
    .prepare(
      `SELECT id, label, url, position, enabled, created_at, updated_at
         FROM default_servers
        ORDER BY position ASC, created_at ASC`,
    )
    .all();
  return jsonResp({ items: rs.results || [] });
}

async function handleServersCreate(request, env, actor) {
  await ensureServersTable(env);
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const label = (body.label || '').trim();
  const urlVal = (body.url || '').trim();
  if (!label || !urlVal) {
    return errResp('missing_fields', 'label and url required', 400);
  }
  // Position auto = max+1 si non fournie (le nouveau serveur arrive
  // en bas de liste).
  let position = Number.isFinite(body.position) ? body.position : null;
  if (position === null) {
    const row = await env.DB
      .prepare('SELECT COALESCE(MAX(position), 0) AS m FROM default_servers')
      .first();
    position = ((row && row.m) || 0) + 1;
  }
  const id = body.id || genId('srv');
  const now = Date.now();
  await env.DB
    .prepare(
      `INSERT INTO default_servers
        (id, label, url, position, enabled, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(id, label, urlVal, position, body.enabled === false ? 0 : 1, now, now)
    .run();
  await logAudit(env, request, actor, 'server.create',
    { type: 'server', id }, null, { label, url: urlVal });
  return jsonResp({ id }, 201);
}

async function handleServersUpdate(request, env, id, actor) {
  await ensureServersTable(env);
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const before = await env.DB
    .prepare('SELECT * FROM default_servers WHERE id = ?')
    .bind(id)
    .first();
  if (!before) return errResp('not_found', 'Server not found', 404);
  const fields = ['label', 'url', 'position', 'enabled'];
  const sets = [];
  const vals = [];
  for (const f of fields) {
    if (body[f] !== undefined) {
      sets.push(`${f} = ?`);
      vals.push(f === 'enabled' ? (body[f] ? 1 : 0) : body[f]);
    }
  }
  if (sets.length === 0) return jsonResp({ updated: 0 });
  sets.push('updated_at = ?');
  vals.push(Date.now());
  vals.push(id);
  await env.DB
    .prepare(`UPDATE default_servers SET ${sets.join(', ')} WHERE id = ?`)
    .bind(...vals)
    .run();
  await logAudit(env, request, actor, 'server.update',
    { type: 'server', id }, before, body);
  return jsonResp({ updated: 1 });
}

async function handleServersDelete(request, env, id, actor) {
  await ensureServersTable(env);
  const before = await env.DB
    .prepare('SELECT * FROM default_servers WHERE id = ?')
    .bind(id)
    .first();
  if (!before) return errResp('not_found', 'Server not found', 404);
  await env.DB.prepare('DELETE FROM default_servers WHERE id = ?').bind(id).run();
  await logAudit(env, request, actor, 'server.delete',
    { type: 'server', id }, before, null);
  return jsonResp({ deleted: 1 });
}

// =========================================================
//  CUSTOMERS HANDLERS
// =========================================================

async function handleCustomersList(request, env, user) {
  const url = new URL(request.url);
  const search = (url.searchParams.get('q') || '').trim();
  let sql = `SELECT id, email, name, phone, reseller_id, created_at
             FROM customers`;
  const where = []; const binds = [];
  if (search) {
    where.push('(email LIKE ? OR name LIKE ? OR phone LIKE ?)');
    binds.push(`%${search}%`, `%${search}%`, `%${search}%`);
  }
  if (user && user.role === 'reseller') {
    where.push('reseller_id = ?');
    binds.push(user.sub);
  }
  if (where.length) sql += ' WHERE ' + where.join(' AND ');
  sql += ` ORDER BY created_at DESC LIMIT 200`;
  const rs = await env.DB.prepare(sql).bind(...binds).all();
  return jsonResp({ items: rs.results || [] });
}

async function handleCustomersGet(env, id) {
  const row = await env.DB
    .prepare('SELECT * FROM customers WHERE id = ?')
    .bind(id)
    .first();
  if (!row) return errResp('not_found', 'Customer not found', 404);
  return jsonResp(row);
}

async function handleCustomersCreate(request, env, actor) {
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const id = genId('cus');
  const now = Date.now();
  await env.DB
    .prepare(
      `INSERT INTO customers (id, email, name, phone, reseller_id, notes,
                              created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      id,
      body.email || null,
      body.name || null,
      body.phone || null,
      body.reseller_id || null,
      body.notes || null,
      now,
      now,
    )
    .run();
  await logAudit(env, request, actor, 'customer.create', { type: 'customer', id }, null, body);
  return jsonResp({ id }, 201);
}

async function handleCustomersUpdate(request, env, id, actor) {
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const before = await env.DB.prepare('SELECT * FROM customers WHERE id = ?').bind(id).first();
  if (!before) return errResp('not_found', 'Customer not found', 404);
  const fields = ['email', 'name', 'phone', 'reseller_id', 'notes'];
  const sets = []; const vals = [];
  for (const f of fields) {
    if (body[f] !== undefined) { sets.push(`${f} = ?`); vals.push(body[f]); }
  }
  if (sets.length === 0) return jsonResp({ updated: 0 });
  sets.push('updated_at = ?'); vals.push(Date.now());
  vals.push(id);
  await env.DB.prepare(`UPDATE customers SET ${sets.join(', ')} WHERE id = ?`).bind(...vals).run();
  await logAudit(env, request, actor, 'customer.update', { type: 'customer', id }, before, body);
  return jsonResp({ updated: 1 });
}

async function handleCustomerDevices(env, customerId) {
  const rs = await env.DB
    .prepare(
      `SELECT id, mac, label, first_seen_at, last_seen_at
       FROM devices WHERE customer_id = ? ORDER BY last_seen_at DESC`,
    )
    .bind(customerId)
    .all();
  return jsonResp({ items: rs.results || [] });
}

// =========================================================
//  DEVICE SOURCES HANDLERS (source poussée par MAC)
// =========================================================
//  Une « source » = l'abonnement IPTV assigné à un appareil par sa
//  MAC depuis le panel : soit un Xtream (serveur + user + mdp), soit
//  un M3U (URL). L'app la récupère via la route publique
//  GET /api/device-source/:mac (worker.js) et la charge automatiquement
//  — le client n'a RIEN à saisir.

/// Crée la table à la volée (idempotent) pour marcher même sans
/// migration jouée à la main.
async function ensureSourcesTable(env) {
  await env.DB
    .prepare(
      `CREATE TABLE IF NOT EXISTS device_sources (
         mac        TEXT PRIMARY KEY,
         type       TEXT NOT NULL,
         label      TEXT,
         server_url TEXT,
         username   TEXT,
         password   TEXT,
         m3u_url    TEXT,
         epg_url    TEXT,
         updated_at INTEGER NOT NULL
       )`,
    )
    .run();
  // TRIO (jusqu'à 3 sources sur une même MAC) : colonne additive qui
  // stocke le tableau JSON des sources. Les colonnes simples ci-dessus
  // gardent la 1re source (compat ascendante avec l'ancien app). ALTER
  // idempotent : ignore l'erreur si la colonne existe déjà.
  try {
    await env.DB.prepare('ALTER TABLE device_sources ADD COLUMN sources_json TEXT').run();
  } catch (_) {
    /* colonne déjà présente */
  }
  // origin : 'panel' (assignée ici = client payant, VERROUILLÉE côté self-service)
  // ou 'self' (posée par le client depuis /mon-espace). Cf. worker.js self-source.
  try {
    await env.DB.prepare('ALTER TABLE device_sources ADD COLUMN origin TEXT').run();
  } catch (_) {
    /* colonne déjà présente */
  }
}

/// Normalise + valide un objet source venant du panel. Retourne
/// { source } prêt à insérer, ou { error } si invalide.
// =========================================================
//  ACTIVATION UNIVERSELLE — auto-détection du format
// =========================================================
//  L'admin ne doit JAMAIS choisir « M3U ou Xtream » à la main : il colle
//  ce qu'il a (un lien get.php Xtream, une URL de playlist .m3u, ou les
//  identifiants à plat) et on détecte + normalise tout seul. `parseXtreamUrl`
//  extrait l'origine propre + user/pass d'un lien Xtream ; `autoDetectSource`
//  décide du type quand il n'est pas fourni.

/// Extrait { server_url, username, password } d'une URL Xtream
/// (get.php / player_api.php / panel_api.php / xmltv.php, ou toute URL
/// http(s) portant ?username=&password=). `server_url` = origine PROPRE
/// (schéma + hôte + port), sans path ni query. `null` si non exploitable.
export function parseXtreamUrl(u) {
  if (!u || typeof u !== 'string') return null;
  const s = u.trim();
  if (!/^https?:\/\//i.test(s)) return null; // URL() exige un schéma
  let url;
  try { url = new URL(s); } catch (_) { return null; }
  const user = (url.searchParams.get('username') || '').trim();
  const pass = (url.searchParams.get('password') || '').trim();
  const path = url.pathname.toLowerCase();
  const looksXtream =
    /get\.php|player_api\.php|panel_api\.php|xmltv\.php/.test(path) ||
    (user && pass);
  if (!looksXtream || !user || !pass) return null;
  const port = url.port ? `:${url.port}` : '';
  const server = `${url.protocol}//${url.hostname}${port}`;
  return { server_url: server, username: user, password: pass };
}

/// Détecte le type d'une source à partir d'un blob/URL collé quand l'admin
/// n'a PAS précisé le type (type absent / 'auto'). « Colle n'importe quoi ».
export function autoDetectSource(raw) {
  const label = (raw.label || '').trim() || null;
  const epg = (raw.epg_url || '').trim() || null;
  // Candidats d'URL par ordre de priorité (on prend le 1er non vide).
  const blob = [raw.url, raw.paste, raw.text, raw.m3u_url, raw.server_url]
    .map((v) => (typeof v === 'string' ? v.trim() : ''))
    .find((v) => v) || '';
  // 1) Xtream si on peut extraire des identifiants d'une URL collée…
  const xt = parseXtreamUrl(blob);
  if (xt) {
    return { source: { type: 'xtream', label, server_url: xt.server_url,
      username: xt.username, password: xt.password, m3u_url: null, epg_url: epg } };
  }
  // 2) …ou si server_url + username + password sont fournis à plat.
  const server = (raw.server_url || '').trim();
  const user = (raw.username || '').trim();
  const pass = (raw.password || '').trim();
  if (server && user && pass) {
    const clean = parseXtreamUrl(server);
    return { source: { type: 'xtream', label,
      server_url: clean ? clean.server_url : server.replace(/\/+$/, ''),
      username: clean ? clean.username : user,
      password: clean ? clean.password : pass,
      m3u_url: null, epg_url: epg } };
  }
  // 3) Sinon, une URL http(s) simple → c'est une playlist M3U.
  if (/^https?:\/\//i.test(blob)) {
    return { source: { type: 'm3u', label, server_url: null, username: null,
      password: null, m3u_url: blob, epg_url: epg } };
  }
  return { error: 'source introuvable : colle une URL M3U ou un lien Xtream' };
}

export function normalizeSource(raw) {
  if (!raw || typeof raw !== 'object') {
    return { error: 'source object required' };
  }
  const type = (raw.type || '').trim().toLowerCase();
  const label = (raw.label || '').trim() || null;
  const epg = (raw.epg_url || '').trim() || null;
  if (type === 'xtream') {
    let server = (raw.server_url || '').trim();
    let user = (raw.username || '').trim();
    let pass = (raw.password || '').trim();
    // Robustesse : un lien get.php complet collé dans server_url (ou m3u_url)
    // → on en extrait l'origine propre + les identifiants automatiquement.
    const clean = parseXtreamUrl(server) || parseXtreamUrl((raw.m3u_url || '').trim());
    if (clean) {
      server = clean.server_url;
      user = user || clean.username;
      pass = pass || clean.password;
    } else {
      server = server.replace(/\/+$/, ''); // enlève le(s) slash(es) final(aux)
    }
    if (!server || !user || !pass) {
      return { error: 'xtream requires server_url, username, password' };
    }
    return { source: { type, label, server_url: server, username: user, password: pass, m3u_url: null, epg_url: epg } };
  }
  if (type === 'm3u') {
    const m3u = (raw.m3u_url || raw.url || '').trim();
    if (!m3u) return { error: 'm3u requires m3u_url' };
    // Si la « playlist M3U » est en réalité un lien Xtream get.php, on
    // bascule sur Xtream (plus robuste : creds structurés, cascade d'URL).
    const clean = parseXtreamUrl(m3u);
    if (clean) {
      return { source: { type: 'xtream', label, server_url: clean.server_url,
        username: clean.username, password: clean.password, m3u_url: null, epg_url: epg } };
    }
    return { source: { type, label, server_url: null, username: null, password: null, m3u_url: m3u, epg_url: epg } };
  }
  // type absent / 'auto' / 'detect' → ACTIVATION UNIVERSELLE (auto-détection).
  if (!type || type === 'auto' || type === 'detect') {
    return autoDetectSource(raw);
  }
  return { error: "type must be 'xtream', 'm3u' or 'auto'" };
}

/// Upsert (insère ou remplace) le TRIO de sources d'une MAC.
/// `sources` = tableau de 1 à 3 sources normalisées. On stocke le tableau
/// complet en JSON (sources_json) ET la 1re dans les colonnes simples
/// (compat avec l'ancienne app qui ne lit qu'une source).
async function upsertDeviceSource(env, mac, sources) {
  await ensureSourcesTable(env);
  // Les sources assignées ICI (payant) sont marquées origin='panel' → VERROUILLÉES
  // côté self-service (le client ne peut ni les modifier ni les supprimer).
  const panelItems = (sources || []).map((s) => ({ ...s, origin: 'panel' }));
  // PRÉSERVE les playlists 'self' que le client a ajoutées via /mon-espace : une
  // (ré)assignation panel NE DOIT PAS effacer les listes personnelles du client
  // (modèle multi-listes). On relit l'existant et on ré-empile les 'self' après.
  let selfItems = [];
  try {
    const prev = await env.DB
      .prepare('SELECT sources_json FROM device_sources WHERE mac = ?')
      .bind(mac).first();
    if (prev && prev.sources_json) {
      let arr = [];
      try { arr = JSON.parse(prev.sources_json) || []; } catch (_) { arr = []; }
      selfItems = arr.filter((s) => s && s.origin === 'self');
    }
  } catch (_) { /* pas de précédent → rien à préserver */ }

  const merged = [...panelItems, ...selfItems];
  const first = merged[0] || {};
  const json = JSON.stringify(merged);
  await env.DB
    .prepare(
      // Colonnes plates = 1re source PANEL (compat app/panel). origin ligne =
      // 'panel' (la source prioritaire/flat est payante et verrouillée).
      `INSERT INTO device_sources
         (mac, type, label, server_url, username, password, m3u_url, epg_url, sources_json, origin, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'panel', ?)
       ON CONFLICT(mac) DO UPDATE SET
         type=excluded.type, label=excluded.label, server_url=excluded.server_url,
         username=excluded.username, password=excluded.password,
         m3u_url=excluded.m3u_url, epg_url=excluded.epg_url,
         sources_json=excluded.sources_json, origin='panel', updated_at=excluded.updated_at`,
    )
    .bind(mac, first.type, first.label, first.server_url, first.username,
          first.password, first.m3u_url, first.epg_url, json, Date.now())
    .run();
}

// Décode une MAC reçue dans le PATH : le front encode les « : » en
// %3A (encodeURIComponent), or `url.pathname` n'est PAS décodé → sans
// ça, la MAC arrive « MK%3A5C%3A… » et échoue la validation
// (« mac must be MK:XX:XX:XX:XX:XX »). Tolérant si déjà décodée.
function decodeMac(mac) {
  try {
    return decodeURIComponent(mac);
  } catch (_) {
    return mac;
  }
}

async function handleSourceGet(env, mac) {
  await ensureSourcesTable(env);
  const m = decodeMac(mac).trim().toUpperCase();
  const row = await env.DB
    .prepare('SELECT * FROM device_sources WHERE mac = ?')
    .bind(m)
    .first();
  // Renvoie le TRIO (sources_json) si présent, sinon la source simple
  // historique. `source` reste la 1re (compat panel existant).
  let sources = [];
  if (row && row.sources_json) {
    try { sources = JSON.parse(row.sources_json) || []; } catch (_) { sources = []; }
  }
  if (!sources.length && row) {
    const { sources_json, mac: _mac, updated_at, ...single } = row;
    sources = [single];
  }
  return jsonResp({ mac: m, source: sources[0] || null, sources });
}

async function handleSourcePut(request, env, mac, actor) {
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const m = decodeMac(mac).trim().toUpperCase();
  if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(m)) {
    return errResp('bad_mac', 'mac must be MK:XX:XX:XX:XX:XX', 400);
  }
  // TRIO : on accepte un tableau `sources` (1 à 3) OU une source unique
  // historique (`source` / corps direct). Chaque entrée est validée.
  let rawList = Array.isArray(body.sources) ? body.sources : [body.source || body];
  rawList = rawList.slice(0, 3); // garde-fou : 3 sources maximum
  const sources = [];
  for (const raw of rawList) {
    const norm = normalizeSource(raw);
    if (norm.error) return errResp('bad_source', norm.error, 400);
    sources.push(norm.source);
  }
  if (sources.length === 0) {
    return errResp('bad_source', 'at least one source required', 400);
  }
  await upsertDeviceSource(env, m, sources);
  await logAudit(env, request, actor, 'source.set',
    { type: 'device_source', id: m }, null,
    { count: sources.length, types: sources.map((s) => s.type) });
  return jsonResp({ ok: true, mac: m, count: sources.length });
}

async function handleSourceDelete(request, env, mac, actor) {
  await ensureSourcesTable(env);
  const m = decodeMac(mac).trim().toUpperCase();
  await env.DB.prepare('DELETE FROM device_sources WHERE mac = ?').bind(m).run();
  await logAudit(env, request, actor, 'source.clear',
    { type: 'device_source', id: m }, null, null);
  return jsonResp({ ok: true, mac: m });
}

// =========================================================
//  FAMILLES — une ligne (source) partagée par plusieurs appareils
// =========================================================
const _MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/i;

async function ensureFamiliesTables(env) {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS families (
       id TEXT PRIMARY KEY,
       name TEXT NOT NULL,
       source_json TEXT,
       reseller_id TEXT,
       created_at INTEGER,
       updated_at INTEGER
     )`,
  ).run();
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS family_members (
       id TEXT PRIMARY KEY,
       family_id TEXT NOT NULL,
       mac TEXT NOT NULL,
       label TEXT,
       created_at INTEGER,
       UNIQUE(family_id, mac)
     )`,
  ).run();
  // Liens M3U distribuables : 1 jeton unique par lien, tous adossés à la
  // MÊME source de la famille. Sert à donner un lien séparé à chacun.
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS family_links (
       id TEXT PRIMARY KEY,
       family_id TEXT NOT NULL,
       token TEXT NOT NULL UNIQUE,
       label TEXT,
       created_at INTEGER
     )`,
  ).run();
}

// La source renvoyée aux LISTES masque le mot de passe (le détail le montre).
function _familyRowToJson(row, { hidePassword = true } = {}) {
  let source = null;
  try { source = row.source_json ? JSON.parse(row.source_json) : null; } catch (_) { source = null; }
  if (source && hidePassword && source.password) {
    source = { ...source, password: '••••••' };
  }
  return {
    id: row.id,
    name: row.name,
    source,
    reseller_id: row.reseller_id || null,
    created_at: row.created_at || 0,
    updated_at: row.updated_at || 0,
  };
}

async function handleFamiliesList(env, user) {
  const owner = isOwner(user);
  const rows = owner
    ? await env.DB.prepare('SELECT * FROM families ORDER BY created_at DESC').all()
    : await env.DB.prepare('SELECT * FROM families WHERE reseller_id = ? ORDER BY created_at DESC')
        .bind(user.sub).all();
  const list = (rows.results || []);
  // Compte de membres par famille (une requête groupée).
  const counts = {};
  try {
    const c = await env.DB.prepare(
      'SELECT family_id, COUNT(*) AS n FROM family_members GROUP BY family_id',
    ).all();
    for (const r of (c.results || [])) counts[r.family_id] = r.n;
  } catch (_) {/* table vide */}
  return jsonResp({
    items: list.map((row) => ({
      ..._familyRowToJson(row),
      member_count: counts[row.id] || 0,
    })),
  });
}

async function handleFamiliesCreate(request, env, actor, user) {
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const name = (body.name || '').trim();
  if (!name) return errResp('bad_name', 'name required', 400);
  const norm = normalizeSource(body.source || {});
  if (norm.error) return errResp('bad_source', norm.error, 400);
  const now = Date.now();
  const id = genId('fam');
  const resellerId = user.role === 'reseller' ? user.sub : (body.reseller_id || null);
  await ensureFamiliesTables(env);
  await env.DB.prepare(
    `INSERT INTO families (id, name, source_json, reseller_id, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  ).bind(id, name, JSON.stringify(norm.source), resellerId, now, now).run();
  await logAudit(env, request, actor, 'family.create',
    { type: 'family', id }, null, { name });
  return jsonResp({ ok: true, family: _familyRowToJson(
    { id, name, source_json: JSON.stringify(norm.source), reseller_id: resellerId, created_at: now, updated_at: now },
    { hidePassword: false }), member_count: 0 }, 201);
}

async function handleFamiliesGet(env, id, user) {
  const row = await env.DB.prepare('SELECT * FROM families WHERE id = ?').bind(id).first();
  if (!row) return errResp('not_found', 'Family not found', 404);
  if (user.role === 'reseller' && row.reseller_id !== user.sub) {
    return errResp('forbidden', 'Not your family', 403);
  }
  const m = await env.DB.prepare(
    'SELECT mac, label, created_at FROM family_members WHERE family_id = ? ORDER BY created_at ASC',
  ).bind(id).all();
  const l = await env.DB.prepare(
    'SELECT id, token, label, created_at FROM family_links WHERE family_id = ? ORDER BY created_at ASC',
  ).bind(id).all();
  return jsonResp({
    family: _familyRowToJson(row, { hidePassword: false }),
    members: (m.results || []),
    links: (l.results || []),
  });
}

async function handleFamilyCreateLink(request, env, user, actor, familyId) {
  let body;
  try { body = await request.json(); } catch (_) { body = {}; }
  const fam = await env.DB.prepare('SELECT id, reseller_id FROM families WHERE id = ?')
    .bind(familyId).first();
  if (!fam) return errResp('not_found', 'Family not found', 404);
  if (user.role === 'reseller' && fam.reseller_id !== user.sub) {
    return errResp('forbidden', 'Not your family', 403);
  }
  // Jeton long et non-devinable (32 hex).
  const token = crypto.randomUUID().replace(/-/g, '');
  const id = genId('lnk');
  const now = Date.now();
  await env.DB.prepare(
    `INSERT INTO family_links (id, family_id, token, label, created_at)
     VALUES (?, ?, ?, ?, ?)`,
  ).bind(id, familyId, token, (body.label || '').trim() || null, now).run();
  await logAudit(env, request, actor, 'family.link.create',
    { type: 'family', id: familyId }, null, { label: body.label || null });
  return jsonResp({ ok: true, id, token, label: (body.label || '').trim() || null, created_at: now }, 201);
}

async function handleFamilyDeleteLink(env, familyId, linkId, actor) {
  await env.DB.prepare('DELETE FROM family_links WHERE id = ? AND family_id = ?')
    .bind(linkId, familyId).run();
  await logAudit(env, { headers: new Headers() }, actor, 'family.link.delete',
    { type: 'family', id: familyId }, null, { link: linkId });
  return jsonResp({ ok: true, id: linkId });
}

async function handleFamiliesDelete(env, id, actor) {
  const row = await env.DB.prepare('SELECT id FROM families WHERE id = ?').bind(id).first();
  if (!row) return errResp('not_found', 'Family not found', 404);
  // On retire la source poussée à chaque membre (ils perdent l'accès famille).
  const m = await env.DB.prepare('SELECT mac FROM family_members WHERE family_id = ?').bind(id).all();
  for (const r of (m.results || [])) {
    try { await env.DB.prepare('DELETE FROM device_sources WHERE mac = ?').bind(r.mac).run(); } catch (_) {}
  }
  await env.DB.prepare('DELETE FROM family_members WHERE family_id = ?').bind(id).run();
  await env.DB.prepare('DELETE FROM families WHERE id = ?').bind(id).run();
  await logAudit(env, { headers: new Headers() }, actor, 'family.delete',
    { type: 'family', id }, null, null);
  return jsonResp({ ok: true, id });
}

async function handleFamilyAddMember(request, env, user, actor, familyId) {
  let body;
  try { body = await request.json(); } catch (_) { body = {}; }
  const mac = (body.mac || '').trim().toUpperCase();
  if (!_MAC_RX.test(mac)) {
    return errResp('bad_mac', 'mac must be MK:XX:XX:XX:XX:XX', 400);
  }
  const fam = await env.DB.prepare('SELECT * FROM families WHERE id = ?').bind(familyId).first();
  if (!fam) return errResp('not_found', 'Family not found', 404);
  if (user.role === 'reseller' && fam.reseller_id !== user.sub) {
    return errResp('forbidden', 'Not your family', 403);
  }
  let source;
  try { source = JSON.parse(fam.source_json); } catch (_) { source = null; }
  if (!source) return errResp('bad_source', 'Family has no valid source', 400);

  // 1) Active la licence de l'appareil (réutilise handleActivate : crée
  //    device+client+licence, pas de crédits pour l'owner). Plan à vie par
  //    défaut (la famille n'est pas limitée dans le temps côté licence).
  const plan = body.plan || 'lifetime';
  const actReq = new Request('https://internal/activate', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      mac,
      plan,
      app_id: body.app_id || 'app_7motion',
      customer_name: body.label ? `${fam.name} — ${body.label}` : fam.name,
      label: body.label || null,
    }),
  });
  const actResp = await handleActivate(actReq, env, user, actor);
  if (actResp && actResp.status >= 400) return actResp; // propage l'erreur

  // 2) Pousse la source de la famille à cette MAC (l'app la charge).
  await upsertDeviceSource(env, mac, [source]);

  // 3) Enregistre le membre dans la famille.
  await env.DB.prepare(
    `INSERT INTO family_members (id, family_id, mac, label, created_at)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(family_id, mac) DO UPDATE SET label = excluded.label`,
  ).bind(genId('fm'), familyId, mac, body.label || null, Date.now()).run();

  await logAudit(env, request, actor, 'family.member.add',
    { type: 'family', id: familyId }, null, { mac, label: body.label || null });
  return jsonResp({ ok: true, family_id: familyId, mac, label: body.label || null }, 201);
}

async function handleFamilyRemoveMember(env, familyId, mac, actor) {
  const m = (mac || '').trim().toUpperCase();
  await env.DB.prepare('DELETE FROM family_members WHERE family_id = ? AND mac = ?')
    .bind(familyId, m).run();
  // Retire la source → l'appareil n'a plus l'accès famille.
  try { await env.DB.prepare('DELETE FROM device_sources WHERE mac = ?').bind(m).run(); } catch (_) {}
  await logAudit(env, { headers: new Headers() }, actor, 'family.member.remove',
    { type: 'family', id: familyId }, null, { mac: m });
  return jsonResp({ ok: true, family_id: familyId, mac: m });
}

// =========================================================
//  DEVICES HANDLERS
// =========================================================

async function handleDevicesList(request, env, user) {
  const url = new URL(request.url);
  const q = (url.searchParams.get('q') || '').trim();
  // `d.*` inclut automatiquement les colonnes enrichies par le heartbeat
  // (device_model, android_build, android_release, app_build) quand elles
  // existent — sans casser si elles n'ont pas encore été créées.
  let sql = `SELECT d.*,
                    c.name as customer_name, c.email as customer_email
             FROM devices d LEFT JOIN customers c ON d.customer_id = c.id`;
  const where = []; const binds = [];
  if (q) {
    where.push('(d.mac LIKE ? OR d.label LIKE ? OR c.name LIKE ?)');
    binds.push(`%${q}%`, `%${q}%`, `%${q}%`);
  }
  // Cloisonnement : un revendeur ne voit QUE ses propres appareils.
  if (user && user.role === 'reseller') {
    where.push('d.reseller_id = ?');
    binds.push(user.sub);
  }
  if (where.length) sql += ' WHERE ' + where.join(' AND ');
  sql += ` ORDER BY d.last_seen_at DESC LIMIT 200`;
  const rs = await env.DB.prepare(sql).bind(...binds).all();
  return jsonResp({ items: rs.results || [] });
}

// =========================================================
//  PASS PARTAGE — suivi des invitations (panel)
// =========================================================
//  GET /invites → liste des codes de partage : qui a invité (émetteur), quel
//  NOUVEL appareil a testé (invité), quand, expiration du pass 2 jours, statut.
//  Cloisonnement revendeur via le reseller_id de l'appareil ÉMETTEUR.
async function handleInvitesList(request, env, user) {
  // La table est créée à la volée côté worker public — on s'assure de son
  // existence ici pour ne pas planter si aucun code n'a encore été généré.
  try {
    await env.DB.prepare(
      'CREATE TABLE IF NOT EXISTS app_invites (' +
      'code TEXT PRIMARY KEY, issuer_mac TEXT NOT NULL, redeemer_mac TEXT, ' +
      'plan TEXT NOT NULL, created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, ' +
      'redeemed_at INTEGER, guest_until INTEGER)',
    ).run();
  } catch (_) { /* déjà présente */ }

  const url = new URL(request.url);
  const q = (url.searchParams.get('q') || '').trim();
  // Rattache l'appareil ÉMETTEUR (cloisonnement + nom) et l'appareil INVITÉ.
  let sql = `SELECT iv.code, iv.issuer_mac, iv.redeemer_mac, iv.plan,
                    iv.created_at, iv.expires_at, iv.redeemed_at, iv.guest_until,
                    iv.hours, iv.mode, iv.channel_json,
                    di.reseller_id AS issuer_reseller_id,
                    ci.name AS issuer_name,
                    dr.block_status AS redeemer_block
             FROM app_invites iv
             LEFT JOIN devices di ON di.mac = iv.issuer_mac
             LEFT JOIN customers ci ON ci.id = di.customer_id
             LEFT JOIN devices dr ON dr.mac = iv.redeemer_mac`;
  const where = []; const binds = [];
  if (q) {
    where.push('(iv.code LIKE ? OR iv.issuer_mac LIKE ? OR iv.redeemer_mac LIKE ?)');
    binds.push(`%${q}%`, `%${q}%`, `%${q}%`);
  }
  // Cloisonnement : un revendeur ne voit QUE les invitations issues de SES
  // appareils.
  if (user && user.role === 'reseller') {
    where.push('di.reseller_id = ?');
    binds.push(user.sub);
  }
  if (where.length) sql += ' WHERE ' + where.join(' AND ');
  sql += ' ORDER BY iv.created_at DESC LIMIT 300';
  const rs = await env.DB.prepare(sql).bind(...binds).all();
  return jsonResp({ items: rs.results || [] });
}

// =========================================================
//  COMPTES MAÎTRES — démo illimitée (envoyer des tests à volonté)
// =========================================================
//  Une MAC listée ici peut, depuis l'app, envoyer des pass invités (« tests »)
//  sans quota ni obligation d'abonnement payé (cf. worker.js isMasterMac).
//  Réservé au super_admin. La table est la même que côté worker (app_masters).
const _MASTER_MAC_RX = /^MK(?::[0-9A-Fa-f]{2}){5}$/;

async function ensureMastersTable(env) {
  try {
    await env.DB.prepare(
      'CREATE TABLE IF NOT EXISTS app_masters (mac TEXT PRIMARY KEY, note TEXT, created_at INTEGER)',
    ).run();
  } catch (_) { /* déjà présente */ }
}

async function handleMastersList(env) {
  await ensureMastersTable(env);
  const rs = await env.DB
    .prepare('SELECT mac, note, created_at FROM app_masters ORDER BY created_at DESC')
    .all();
  return jsonResp({ items: rs.results || [] });
}

async function handleMastersAdd(request, env) {
  let body;
  try { body = await request.json(); } catch (_) { return errResp('bad_json', 'Invalid JSON', 400); }
  const mac = String(body?.mac || '').toUpperCase();
  if (!_MASTER_MAC_RX.test(mac)) {
    return errResp('bad_mac', 'MAC invalide (format MK:XX:XX:XX:XX:XX).', 400);
  }
  const note = String(body?.note || '').trim().slice(0, 80);
  await ensureMastersTable(env);
  await env.DB
    .prepare('INSERT OR REPLACE INTO app_masters (mac, note, created_at) VALUES (?, ?, ?)')
    .bind(mac, note || null, Date.now()).run();
  return jsonResp({ ok: true, mac });
}

async function handleMastersRemove(env, rawMac) {
  const mac = String(rawMac || '').toUpperCase();
  if (!_MASTER_MAC_RX.test(mac)) return errResp('bad_mac', 'MAC invalide.', 400);
  await ensureMastersTable(env);
  await env.DB.prepare('DELETE FROM app_masters WHERE mac = ?').bind(mac).run();
  return jsonResp({ ok: true, mac });
}

// =========================================================
//  LISTE DE TEST INDÉPENDANTE (« notre liste », < 5 chaînes)
// =========================================================
//  Le maître curate un PETIT M3U (chaînes via gateway). Tous les tests servent
//  cette liste → chaînes partagées → le gateway mutualise → le fournisseur ne
//  voit qu'UNE connexion (un seul trio suffit). Table `master_test_list`,
//  partagée avec le worker (qui la sert derrière une réf opaque).
async function ensureMasterListTable(env) {
  try {
    await env.DB.prepare(
      'CREATE TABLE IF NOT EXISTS master_test_list (mac TEXT PRIMARY KEY, m3u TEXT, updated_at INTEGER)',
    ).run();
  } catch (_) { /* déjà présente */ }
  // URL de la FAÇADE (gateway) du maître : quand elle est posée, les chaînes
  // copiées sont reconstruites SUR le gateway → plus stables (reconnexion +
  // failover + tampon) et privées (une seule IP). Migration idempotente.
  try {
    await env.DB.prepare('ALTER TABLE master_test_list ADD COLUMN gateway_base TEXT').run();
  } catch (_) { /* colonne déjà là */ }
  // IDENTITÉ DE DIFFUSION (gateway_user / gateway_pass) : l'utilisateur PARTAGÉ,
  // en lecture seule, que le gateway reconnaît (BROADCAST_USER/PASS côté
  // passerelle). Le copieur l'embarque dans les URLs de test À LA PLACE des
  // identifiants fournisseur → la ligne réelle n'apparaît JAMAIS dans le M3U
  // servi (confidentialité), et l'URL est réellement jouable via la façade.
  // Migrations additives idempotentes.
  try {
    await env.DB.prepare('ALTER TABLE master_test_list ADD COLUMN gateway_user TEXT').run();
  } catch (_) { /* colonne déjà là */ }
  try {
    await env.DB.prepare('ALTER TABLE master_test_list ADD COLUMN gateway_pass TEXT').run();
  } catch (_) { /* colonne déjà là */ }
}

// =========================================================
//  CONTRAT DE FAÇADE (gateway) — joignable de façon FIABLE par le Worker
// =========================================================
//  Un Worker Cloudflare fetch de façon fiable un DOMAINE public en HTTPS
//  VALIDE, mais ÉCHOUE (403/530) sur une IP brute, et ne peut pas valider le
//  TLS d'un hôte sans certificat (ex. une IP, un `nip.io`). L'ancienne rustine
//  IP→nip.io donnait un « vert » MENSONGER (la sonde passait parfois en HTTP
//  clair, alors que la lecture réelle, elle, ne passait pas). On la remplace
//  par un CONTRAT strict et honnête : la façade DOIT être
//    • en https://   (certificat valide → le Worker la joint vraiment) ;
//    • un vrai domaine (nom d'hôte avec un point + une lettre) → un cert
//      Let's Encrypt existe (voir gateway/README : Caddy + renouvellement auto).
//  Toute IP brute / http:// / hôte sans domaine est REFUSÉE, avec une raison
//  actionnable (au lieu d'être « réparée » en douce vers un état non joignable).
//  Renvoie { ok, base, reason }. `base` = origine propre (schéma+hôte+port),
//  sans path ni slash final.
export function validateFacadeBase(raw) {
  const s = String(raw || '').trim();
  if (!s) return { ok: false, base: '', reason: 'empty' };
  if (!/^https?:\/\//i.test(s)) return { ok: false, base: '', reason: 'no_scheme' };
  let u;
  try { u = new URL(s); } catch (_) { return { ok: false, base: '', reason: 'bad_url' }; }
  if (u.protocol !== 'https:') return { ok: false, base: '', reason: 'not_https' };
  const host = u.hostname;
  // IPv4 brute → refusée (pas de cert valide ; le Worker ne fetch pas une IP).
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host)) return { ok: false, base: '', reason: 'ip_literal' };
  // IPv6 littéral (`[…]`) → refusé pour les mêmes raisons.
  if (host.includes(':') || host.startsWith('[')) return { ok: false, base: '', reason: 'ip_literal' };
  // Domaine = au moins un point ET une lettre (ex. tv.mondomaine.com).
  if (!/[a-zA-Z]/.test(host) || !host.includes('.')) return { ok: false, base: '', reason: 'not_domain' };
  const port = u.port ? `:${u.port}` : '';
  return { ok: true, base: `${u.protocol}//${host}${port}`, reason: '' };
}

// Message HUMAIN + ACTIONNABLE pour une raison de rejet de façade. '' si valide
// ou champ vide (vide = lecture directe assumée, pas une erreur).
export function facadeReason(reason) {
  switch (reason) {
    case 'empty': return '';
    case 'no_scheme':
    case 'bad_url':
      return 'URL de façade invalide : commence par https:// (ex. https://tv.mondomaine.com).';
    case 'not_https':
      return 'La façade doit être en https:// avec un certificat valide — http n’est pas joignable de façon fiable depuis le relais Cloudflare.';
    case 'ip_literal':
      return 'Adresse IP interdite : le relais ne joint pas une IP brute. Mets un vrai domaine (Caddy + Let’s Encrypt, voir gateway/README).';
    case 'not_domain':
      return 'Nom d’hôte invalide : utilise un domaine complet (ex. tv.mondomaine.com).';
    default: return 'Façade invalide.';
  }
}

// Nettoie une base gateway collée → origine https propre, ou '' si vide/invalide
// (compat : le reste du code lit une chaîne). Voir validateFacadeBase pour le
// contrat et la raison détaillée.
export function _cleanGatewayBase(raw) {
  const v = validateFacadeBase(raw);
  return v.ok ? v.base : '';
}

// Lit la façade + l'identité de diffusion enregistrées pour un maître.
// Renvoie { base, user, pass } — base '' si aucune façade valide.
async function _readGatewayCreds(env, mac) {
  try {
    await ensureMasterListTable(env);
    const row = await env.DB
      .prepare('SELECT gateway_base, gateway_user, gateway_pass FROM master_test_list WHERE mac = ?')
      .bind(mac).first();
    if (!row) return { base: '', user: '', pass: '' };
    // On revalide à la lecture : une valeur héritée invalide (ancienne IP) est
    // ignorée proprement plutôt que servie comme si elle marchait.
    return {
      base: _cleanGatewayBase(row.gateway_base),
      user: String(row.gateway_user || ''),
      pass: String(row.gateway_pass || ''),
    };
  } catch (_) { return { base: '', user: '', pass: '' }; }
}

// Compte les chaînes d'un M3U (lignes #EXTINF). Sert d'indicateur au panel.
function _countM3uChannels(m3u) {
  if (!m3u) return 0;
  const m = String(m3u).match(/#EXTINF/gi);
  return m ? m.length : 0;
}

async function handleMasterTestListGet(request, env) {
  const url = new URL(request.url);
  const mac = String(url.searchParams.get('mac') || '').toUpperCase();
  if (!_MASTER_MAC_RX.test(mac)) return errResp('bad_mac', 'MAC maître invalide.', 400);
  await ensureMasterListTable(env);
  const row = await env.DB
    .prepare('SELECT m3u, gateway_base, gateway_user, updated_at FROM master_test_list WHERE mac = ?').bind(mac).first();
  const m3u = (row && row.m3u) ? String(row.m3u) : '';
  return jsonResp({
    mac, m3u, count: _countM3uChannels(m3u),
    gateway_base: (row && row.gateway_base) || '',
    // On expose le NOM de l'identité de diffusion (jamais le mot de passe) pour
    // que le panel puisse pré-remplir le champ sans jamais réafficher le secret.
    gateway_user: (row && row.gateway_user) || '',
    has_gateway_pass: !!(row && row.gateway_pass),
    updated_at: (row && row.updated_at) || null,
  });
}

async function handleMasterTestListPut(request, env) {
  let body;
  try { body = await request.json(); } catch (_) { return errResp('bad_json', 'Invalid JSON', 400); }
  const mac = String(body?.mac || '').toUpperCase();
  if (!_MASTER_MAC_RX.test(mac)) return errResp('bad_mac', 'MAC maître invalide.', 400);
  // On garde une liste VOLONTAIREMENT petite : indépendance = peu de chaînes
  // partagées. Plafond souple à 50 lignes / 64 Ko (garde-fou, pas une police).
  const m3u = String(body?.m3u || '').slice(0, 64 * 1024);
  // FAÇADE : on VALIDE avec un message actionnable au lieu de « réparer » en
  // silence (fini le nip.io mensonger). Champ vide = lecture directe assumée.
  const rawGateway = String(body?.gateway_base || '').trim();
  const fac = validateFacadeBase(rawGateway);
  if (rawGateway && !fac.ok) {
    return errResp('bad_facade', facadeReason(fac.reason), 400);
  }
  const gateway = fac.ok ? fac.base : '';
  // IDENTITÉ DE DIFFUSION (optionnelle) : nom + mot de passe partagés du
  // gateway. Le mot de passe n'est mis à jour que s'il est fourni non vide
  // (le panel ne le renvoie pas → on ne l'écrase pas par du vide).
  const gwUser = String(body?.gateway_user || '').trim();
  const gwPassRaw = body?.gateway_pass;
  const gwPass = (typeof gwPassRaw === 'string') ? gwPassRaw.trim() : null;
  const count = _countM3uChannels(m3u);
  await ensureMasterListTable(env);
  // Liste vide ET pas de gateway ET pas d'identité → on efface la ligne. Sinon
  // on garde les réglages même sans chaînes (le maître les a posés une fois).
  if (!m3u.trim() && !gateway && !gwUser) {
    await env.DB.prepare('DELETE FROM master_test_list WHERE mac = ?').bind(mac).run();
    return jsonResp({ ok: true, mac, count: 0, gateway_base: '', gateway_user: '', has_gateway_pass: false });
  }
  // Lit l'ancien mot de passe pour ne pas l'effacer si le panel ne le renvoie
  // pas (le secret n'est jamais réaffiché → il n'est pas dans le corps).
  const prev = await env.DB
    .prepare('SELECT gateway_pass FROM master_test_list WHERE mac = ?').bind(mac).first();
  const finalPass = (gwPass && gwPass.length) ? gwPass : (prev && prev.gateway_pass) || null;
  await env.DB
    .prepare('INSERT OR REPLACE INTO master_test_list (mac, m3u, gateway_base, gateway_user, gateway_pass, updated_at) VALUES (?, ?, ?, ?, ?, ?)')
    .bind(mac, m3u || '', gateway || null, gwUser || null, gwUser ? finalPass : null, Date.now()).run();
  return jsonResp({
    ok: true, mac, count, gateway_base: gateway,
    gateway_user: gwUser, has_gateway_pass: !!(gwUser && finalPass),
  });
}

// =========================================================
//  COPIEUR INTELLIGENT — lit TOUTES les chaînes du maître, les RANGE en
//  catégories, pour qu'il coche celles à partager en test.
// =========================================================
//  On lit la source (ligne) assignée au maître dans device_sources, on
//  interroge son fournisseur (Xtream player_api ou M3U), et on renvoie un
//  arbre { catégories → chaînes }. Le panel affiche des cases à cocher ; la
//  sélection devient le petit M3U de test (URLs identiques pour tous les
//  testeurs → le gateway mutualise → une seule connexion fournisseur).
//
//  Garde-fous : timeout réseau, plafond de chaînes (l'UI n'en garde que
//  quelques-unes de toute façon), jamais d'erreur fatale (best-effort).
const _COPY_MAX_CHANNELS = 6000; // au-delà, on tronque et on le signale.

// Fetch avec délai maximal (AbortController) — un fournisseur lent ne doit pas
// bloquer la requête panel.
async function _fetchWithTimeout(url, ms = 12_000, init = {}) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  try {
    return await fetch(url, { ...init, signal: ctrl.signal, redirect: 'follow' });
  } finally { clearTimeout(t); }
}

// Lit le PREMIER item de source d'une MAC (trio Xtream ou M3U).
async function _readFirstSource(env, mac) {
  const row = await env.DB.prepare(
    'SELECT type, label, server_url, username, password, m3u_url, sources_json ' +
    'FROM device_sources WHERE mac = ?',
  ).bind(mac).first();
  if (!row) return null;
  if (row.sources_json) {
    try {
      const arr = JSON.parse(row.sources_json) || [];
      if (Array.isArray(arr) && arr[0]) return arr[0];
    } catch (_) { /* repli colonnes plates */ }
  }
  return {
    type: row.type, label: row.label, server_url: row.server_url,
    username: row.username, password: row.password, m3u_url: row.m3u_url,
  };
}

// Copie Xtream : catégories live + chaînes live (player_api.php).
// [gatewayBase] : si fourni (façade https valide), les URLs de LECTURE sont
// bâties SUR le gateway au lieu du fournisseur → plus stable (reconnexion/
// failover/tampon) et privé (une seule IP). On lit toujours la LISTE depuis le
// fournisseur (par son domaine, que le Worker joint), mais on JOUE via le
// gateway.
// [gwUser]/[gwPass] : IDENTITÉ DE DIFFUSION (BROADCAST_USER/PASS du gateway).
// Quand elle est fournie avec une façade, les URLs de test portent CETTE
// identité partagée — les identifiants FOURNISSEUR n'apparaissent JAMAIS dans
// le M3U servi (confidentialité) et l'URL est réellement jouable (le gateway
// authentifie l'identité de diffusion). Sans identité → repli sur les
// identifiants fournisseur (fonctionne si le gateway fait un passthrough, mais
// moins privé : voir README).
async function _copyXtream(src, gatewayBase = '', gwUser = '', gwPass = '') {
  // Le fournisseur est joint par son DOMAINE (le Worker le fetch sans souci).
  const base = String(src.server_url || '').replace(/\/+$/, '');
  const play = (gatewayBase || base).replace(/\/+$/, ''); // origine de LECTURE
  const provUser = String(src.username || '');
  const provPass = String(src.password || '');
  // Identité PORTÉE par les URLs de lecture : diffusion si façade + identité,
  // sinon identifiants fournisseur (repli).
  const useBroadcast = !!(gatewayBase && gwUser && gwPass);
  const user = useBroadcast ? String(gwUser) : provUser;
  const pass = useBroadcast ? String(gwPass) : provPass;
  // La LISTE est toujours lue avec les identifiants FOURNISSEUR (côté Worker).
  const auth = `username=${encodeURIComponent(provUser)}&password=${encodeURIComponent(provPass)}`;
  let cats = [];
  let streams = [];
  try {
    const cr = await _fetchWithTimeout(`${base}/player_api.php?${auth}&action=get_live_categories`);
    if (cr.ok) cats = await cr.json();
  } catch (_) { /* catégories optionnelles */ }
  const sr = await _fetchWithTimeout(`${base}/player_api.php?${auth}&action=get_live_streams`);
  if (!sr.ok) throw new Error('provider_http_' + sr.status);
  streams = await sr.json();
  if (!Array.isArray(streams)) throw new Error('provider_bad_streams');

  const catName = new Map();
  for (const c of Array.isArray(cats) ? cats : []) {
    catName.set(String(c.category_id), String(c.category_name || 'Sans catégorie'));
  }
  const groups = new Map(); // catId -> { id, name, channels[] }
  let truncated = false;
  let total = 0;
  for (const s of streams) {
    if (total >= _COPY_MAX_CHANNELS) { truncated = true; break; }
    total++;
    const catId = String(s.category_id ?? 'none');
    const name = catName.get(catId) || 'Sans catégorie';
    if (!groups.has(catId)) groups.set(catId, { id: catId, name, channels: [] });
    groups.get(catId).channels.push({
      id: String(s.stream_id),
      name: String(s.name || ('Chaîne ' + s.stream_id)),
      logo: String(s.stream_icon || ''),
      // URL LIVE standard Xtream, bâtie sur l'origine de LECTURE (gateway si
      // réglé, sinon fournisseur) → passe par le gateway → mutualisée + stable.
      url: `${play}/live/${encodeURIComponent(user)}/${encodeURIComponent(pass)}/${s.stream_id}.ts`,
    });
  }
  return { type: 'xtream', categories: [...groups.values()], truncated, total };
}

// Réécrit l'ORIGINE d'une URL vers le gateway (garde path + query). Sert à
// faire jouer une chaîne M3U via la façade (stable + privé). Best-effort :
// URL invalide → renvoyée telle quelle.
export function _rewriteOrigin(u, gatewayBase) {
  if (!gatewayBase) return u;
  try {
    const src = new URL(u);
    const gw = new URL(gatewayBase);
    // ORDRE IMPORTANT : le setter `host` ne change pas le port si l'entrée n'en
    // a pas → on pose hostname + port séparément pour effacer l'ancien port.
    src.protocol = gw.protocol;
    src.hostname = gw.hostname;
    src.port = gw.port; // '' si la façade n'a pas de port → efface l'ancien.
    return src.toString();
  } catch (_) { return u; }
}

// Copie M3U : parse #EXTINF (group-title = catégorie, tvg-logo, nom) + URL.
// [gatewayBase] : si fourni, l'origine de chaque URL est réécrite vers le
// gateway (le gateway doit proxifier ces chemins — cas d'une façade Xtream).
async function _copyM3u(src, gatewayBase = '') {
  // La façade est déjà validée (https + domaine) en amont ; on la prend telle
  // quelle. La playlist source est lue par son URL d'origine (domaine).
  const res = await _fetchWithTimeout(String(src.m3u_url || ''));
  if (!res.ok) throw new Error('provider_http_' + res.status);
  const text = await res.text();
  const lines = text.split(/\r?\n/);
  const groups = new Map();
  const seen = new Set(); // dédoublonnage par URL (qualité VIP : pas de doublon)
  let truncated = false;
  let total = 0;
  let pending = null;
  for (const raw of lines) {
    const line = raw.trim();
    if (line.startsWith('#EXTINF')) {
      const group = (line.match(/group-title="([^"]*)"/i) || [])[1] || 'Sans catégorie';
      const logo = (line.match(/tvg-logo="([^"]*)"/i) || [])[1] || '';
      const name = (line.split(',').slice(1).join(',') || '').trim() || 'Chaîne';
      pending = { group, logo, name };
    } else if (line && !line.startsWith('#') && pending) {
      if (total >= _COPY_MAX_CHANNELS) { truncated = true; break; }
      if (seen.has(line)) { pending = null; continue; } // doublon → ignoré
      seen.add(line);
      total++;
      const catId = pending.group;
      if (!groups.has(catId)) groups.set(catId, { id: catId, name: catId, channels: [] });
      groups.get(catId).channels.push({
        id: String(total), name: pending.name, logo: pending.logo,
        url: _rewriteOrigin(line, gatewayBase),
      });
      pending = null;
    }
  }
  return { type: 'm3u', categories: [...groups.values()], truncated, total };
}

// Copieur intelligent (catégories + chaînes). DEUX entrées possibles :
//   • GET  /masters/channels?mac=  → lit la ligne DÉJÀ assignée au maître.
//   • POST /masters/channels {mac, paste}  → c'est TOI qui colles le lien
//     Xtream (get.php…) ou l'URL M3U à copier — indépendant du panel.
async function handleMasterChannels(request, env) {
  const url = new URL(request.url);
  let mac = String(url.searchParams.get('mac') || '').toUpperCase();
  let inline = null;
  let gatewayReq = '';
  let gwUserReq = '';
  let gwPassReq = '';
  if (request.method === 'POST') {
    let body;
    try { body = await request.json(); } catch (_) { return errResp('bad_json', 'Invalid JSON', 400); }
    if (body && body.mac) mac = String(body.mac).toUpperCase();
    if (body && body.gateway_base) gatewayReq = _cleanGatewayBase(body.gateway_base);
    if (body && body.gateway_user) gwUserReq = String(body.gateway_user).trim();
    if (body && body.gateway_pass) gwPassReq = String(body.gateway_pass).trim();
    // Blob collé par le maître : lien Xtream, URL M3U, ou identifiants à plat.
    const blob = body && (body.paste || body.url || body.source);
    if (blob || (body && (body.server_url || body.m3u_url))) {
      const raw = typeof blob === 'string' ? { url: blob } : (blob || body);
      const det = autoDetectSource(raw);
      if (det.error) return errResp('bad_source', det.error, 400);
      inline = det.source;
    }
  }
  if (!_MASTER_MAC_RX.test(mac)) return errResp('bad_mac', 'MAC maître invalide.', 400);
  // Priorité au lien collé ; sinon on retombe sur la ligne assignée au maître.
  const src = inline || await _readFirstSource(env, mac);
  if (!src) {
    return errResp('no_source',
      'Aucune source : colle ton lien Xtream ou ton M3U ci-dessus, ou assigne une ligne à ce maître dans le panel.', 404);
  }
  // Façade (gateway) + identité de diffusion de LECTURE : celles envoyées avec
  // la requête, sinon celles déjà enregistrées pour ce maître. Façade vide →
  // lecture directe (moins privée). Identité vide → repli identifiants
  // fournisseur (moins privé) — voir _copyXtream.
  const saved = await _readGatewayCreds(env, mac);
  const gateway = gatewayReq || saved.base;
  const gwUser = gwUserReq || saved.user;
  const gwPass = gwPassReq || saved.pass;
  try {
    let out;
    if (src.type === 'xtream' && src.server_url && src.username && src.password) {
      out = await _copyXtream(src, gateway, gwUser, gwPass);
    } else if (src.m3u_url) {
      out = await _copyM3u(src, gateway);
    } else {
      return errResp('bad_source', 'Source illisible (ni Xtream complet, ni M3U).', 400);
    }
    // Trie les catégories par nom, chaînes par nom (lecture confortable).
    out.categories.sort((a, b) => a.name.localeCompare(b.name));
    for (const c of out.categories) c.channels.sort((a, b) => a.name.localeCompare(b.name));
    return jsonResp({
      mac,
      type: out.type,
      source_label: src.label || null,
      categories: out.categories,
      total: out.total,
      truncated: out.truncated,
    });
  } catch (e) {
    return errResp('copy_failed', 'Impossible de lire les chaînes : ' + String((e && e.message) || e), 502);
  }
}

// =========================================================
//  BOÎTE NOIRE — DIAGNOSTIC (côté panel, authentifié)
// =========================================================
//  Même esprit que le diagnostic de l'app, mais lu depuis le panel : teste
//  ACTIVEMENT la façade et la 1re chaîne de la liste de test. Chaque contrôle
//  = { key, level (0/1/2), label, detail, fix }. Aucune donnée sensible (mot de
//  passe, URL avec identifiants) n'est renvoyée — seulement statut + latence.

/// Sonde une URL sans télécharger le flux (2 octets, puis annule le corps).
/// La sonde reflète la VRAIE joignabilité : plus aucun rewrite IP→nip.io qui
/// donnait un « vert » mensonger. Une façade doit être un domaine https valide
/// (contrat validateFacadeBase) pour que ce résultat corresponde à la lecture.
async function _probeUrl(url, ms = 5000) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  const t0 = Date.now();
  try {
    const res = await fetch(url, { method: 'GET', headers: { Range: 'bytes=0-1' }, signal: ctrl.signal, redirect: 'follow' });
    try { if (res.body) await res.body.cancel(); } catch (_) { /* */ }
    return { ok: res.status >= 200 && res.status < 400, status: res.status, ms: Date.now() - t0 };
  } catch (e) {
    return { ok: false, status: 0, ms: Date.now() - t0, error: String((e && e.message) || e) };
  } finally { clearTimeout(t); }
}

// GET /masters/diag?mac= → boîte noire du maître (contrôles actifs).
async function handleMasterDiag(request, env) {
  const url = new URL(request.url);
  const mac = String(url.searchParams.get('mac') || '').toUpperCase();
  if (!_MASTER_MAC_RX.test(mac)) return errResp('bad_mac', 'MAC maître invalide.', 400);

  const checks = [];
  const add = (key, level, label, detail, fix) => checks.push({ key, level, label, detail, fix: fix || '' });

  // 1) Compte maître présent ?
  await ensureMastersTable(env);
  const mrow = await env.DB.prepare('SELECT 1 AS x FROM app_masters WHERE mac = ?').bind(mac).first();
  add('master', mrow ? 0 : 2, 'Compte maître reconnu',
    mrow ? 'Cette MAC est bien un compte maître.' : 'Cette MAC n’est pas dans les comptes maîtres.',
    mrow ? '' : 'Ajoute-la ci-dessus.');

  // 2) Source assignée ?
  const src = await _readFirstSource(env, mac);
  let sHost = '';
  if (src) { try { sHost = new URL(String(src.server_url || src.m3u_url || '')).host; } catch (_) { /* */ } }
  add('source', src ? 0 : 1, 'Source (ligne) assignée',
    src ? `Type ${src.type || '?'}${sHost ? ' · ' + sHost : ''}.` : 'Aucune ligne assignée à ce maître.',
    src ? '' : 'Assigne une ligne, ou colle un lien dans « Liste de test ».');

  // 3) Façade en ligne ? (façade = https + domaine valide, réellement joignable)
  const gwc = await _readGatewayCreds(env, mac);
  const gw = gwc.base;
  if (gw) {
    const p = await _probeUrl(gw, 5000);
    add('gateway', p.ok ? 0 : 1, 'Façade (gateway) en ligne',
      p.ok ? `Ta façade https répond (${p.ms} ms).` : `Façade injoignable (${p.error || p.status}).`,
      p.ok ? '' : 'Vérifie que ton gateway tourne (Caddy + HTTPS) et que le domaine est exact.');
    // 3b) Identité de diffusion : sans elle, les URLs de test portent les
    // identifiants FOURNISSEUR (moins privé). Avec elle → ligne réelle masquée.
    add('broadcast_id', gwc.user ? 0 : 1, 'Identité de diffusion',
      gwc.user ? 'Identité partagée réglée → identifiants fournisseur masqués dans le M3U servi.'
               : 'Aucune identité de diffusion → les URLs de test portent tes identifiants fournisseur.',
      gwc.user ? '' : 'Renseigne « Utilisateur/mot de passe gateway » (= BROADCAST_USER/PASS du gateway).');
  } else {
    add('gateway', 1, 'Façade (gateway)',
      'Aucune façade https valide réglée → lecture directe (moins stable/privée).',
      'Renseigne « Ta façade (gateway) » en https:// (domaine, pas une IP).');
  }

  // 4) Liste de test + 5) sonde 1re chaîne.
  await ensureMasterListTable(env);
  const lrow = await env.DB.prepare('SELECT m3u FROM master_test_list WHERE mac = ?').bind(mac).first();
  const m3u = (lrow && lrow.m3u) ? String(lrow.m3u) : '';
  const count = _countM3uChannels(m3u);
  add('testlist', count > 0 ? (count <= 5 ? 0 : 1) : 1, 'Liste de test indépendante',
    count > 0 ? `${count} chaîne(s) partagée(s)${count > 5 ? ' — vise moins de 5' : ''}.`
              : 'Aucune liste curée — le test ouvre tout le bouquet.',
    count > 0 ? '' : 'Copie tes chaînes et coche 3-5 chaînes.');

  if (count > 0) {
    const firstUrl = (m3u.split(/\r?\n/).find((l) => l.trim() && !l.startsWith('#')) || '').trim();
    if (firstUrl) {
      const cp = await _probeUrl(firstUrl, 6000);
      add('channel_probe', cp.ok ? 0 : 2, 'Chaîne de test jouable',
        cp.ok ? `1re chaîne répond (${cp.status}, ${cp.ms} ms).` : `1re chaîne injoignable (${cp.error || cp.status}).`,
        cp.ok ? '' : 'Vérifie la façade et la ligne fournisseur.');
    }
  }

  const worst = checks.reduce((m, c) => Math.max(m, c.level), 0);
  const oks = checks.filter((c) => c.level === 0).length;
  const score = Math.round((oks / checks.length) * 100);
  const verdict = worst === 0 ? 'green' : (worst === 2 ? 'red' : 'amber');
  return jsonResp({ mac, verdict, score, checks, generated_at: Date.now() });
}

// =========================================================
//  ADMIN MONITORING — vue des sessions admin (séparée des clients)
// =========================================================
//  Lit la table `admin_presence` (alimentée côté worker : les heartbeats des
//  MAC maîtres/admin y sont détournés au lieu de `presence`). Ces sessions
//  n'apparaissent JAMAIS dans « En ligne » ni dans les compteurs clients.
async function handleAdminMonitorGet(env) {
  try {
    await env.DB.prepare(
      'CREATE TABLE IF NOT EXISTS admin_presence (' +
        'mac TEXT PRIMARY KEY, ip TEXT, country TEXT, last_seen INTEGER, channel TEXT)',
    ).run();
  } catch (_) { /* déjà là */ }
  const now = Date.now();
  const since = now - 15 * 60 * 1000; // « en ligne » = vu < 15 min
  let rows = [];
  try {
    const rs = await env.DB
      .prepare('SELECT mac, ip, country, last_seen, channel FROM admin_presence WHERE last_seen > ? ORDER BY last_seen DESC LIMIT 500')
      .bind(since).all();
    rows = (rs && rs.results) || [];
  } catch (_) { rows = []; }
  return jsonResp({
    items: rows,
    online_count: rows.length,
    now,
  });
}

// =========================================================
//  FICHE 360° D'UN APPAREIL — « tout ce que le client a dans le ventre »
// =========================================================
//  GET /devices/:id/overview → en UN appel : abonnement (licence), présence
//  live (en ligne / IP / pays / chaîne en cours) et M-Trio (sources poussées).
//  Le panel affiche tout d'un coup pour aider/diagnostiquer un client par sa
//  MAC. Respecte le cloisonnement revendeur via deviceForActor.
async function handleDeviceOverview(env, id, user) {
  const key = String(id || '');
  const isReseller = user && user.role === 'reseller';
  let dev = await env.DB
    .prepare(
      'SELECT id, mac, reseller_id, block_status FROM devices WHERE id = ? OR mac = ?',
    )
    .bind(key, key.toUpperCase())
    .first();
  if (dev) {
    if (isReseller && dev.reseller_id !== user.sub) {
      return errResp('forbidden', 'Cet appareil ne vous appartient pas', 403);
    }
  } else {
    // Aucune fiche `devices` pour cette MAC : on construit quand même une
    // fiche « MAC seule » à partir de la PRÉSENCE (pays, IP, en ligne, chaîne)
    // et des SOURCES — cas typique d'un appareil VU EN LIGNE mais dont la
    // fiche device n'a pas encore été créée. Ainsi, cliquer N'IMPORTE QUELLE
    // MAC affiche toujours ce qu'on sait d'elle, jamais un « non enregistrée ».
    // Réservé à l'owner : sans fiche device, impossible de vérifier
    // l'appartenance à un revendeur.
    if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(key)) {
      return errResp('not_found', 'Device not found', 404);
    }
    if (isReseller) return errResp('not_found', 'Device not found', 404);
    dev = { id: null, mac: key.toUpperCase(), reseller_id: null, block_status: null };
  }
  const now = Date.now();

  // --- Abonnement : la licence la plus « forte » (à vie d'abord, sinon la
  //     plus lointaine). Statut recalculé : active / expired / <statut brut>.
  let license = null;
  try {
    const lic = await env.DB
      .prepare(
        `SELECT status, plan, started_at, expires_at, auto_renew
           FROM licenses WHERE device_id = ?
          ORDER BY (expires_at IS NULL) DESC, expires_at DESC LIMIT 1`,
      )
      .bind(dev.id)
      .first();
    if (lic) {
      const live = lic.status === 'active'
        && (lic.expires_at == null || lic.expires_at > now);
      const expired = lic.expires_at != null && lic.expires_at <= now;
      license = {
        status: live ? 'active' : (expired ? 'expired' : lic.status),
        plan: lic.plan || null,
        started_at: lic.started_at ?? null,
        expires_at: lic.expires_at ?? null,
        auto_renew: lic.auto_renew ? 1 : 0,
      };
    }
  } catch (_) { /* table licences absente : on ignore */ }

  // --- Présence live : dernière trace dans `presence` (par MAC).
  let presence = null;
  try {
    const p = await env.DB
      .prepare('SELECT ip, country, last_seen, channel FROM presence WHERE mac = ?')
      .bind(dev.mac)
      .first();
    if (p) {
      const ONLINE_MS = 15 * 60 * 1000;
      presence = {
        online: (p.last_seen || 0) > now - ONLINE_MS,
        ip: p.ip || '',
        country: (p.country || '').toUpperCase(),
        channel: p.channel || '',
        last_seen: p.last_seen || 0,
      };
    }
  } catch (_) { /* table presence absente : on ignore */ }

  // --- M-Trio : sources poussées (trio sources_json, sinon source simple).
  let sources = [];
  try {
    await ensureSourcesTable(env);
    const row = await env.DB
      .prepare('SELECT * FROM device_sources WHERE mac = ?')
      .bind(dev.mac)
      .first();
    if (row && row.sources_json) {
      try { sources = JSON.parse(row.sources_json) || []; } catch (_) { sources = []; }
    }
    if (!sources.length && row) {
      const { sources_json, mac: _m, updated_at, ...single } = row;
      sources = [single];
    }
  } catch (_) { /* table device_sources absente : on ignore */ }

  // --- Inventaire RÉEL sur l'appareil (remonté par le heartbeat) : toutes les
  //     sources présentes sur la TV, y compris celles que le client a ajoutées
  //     lui-même. SANS mot de passe (le client ne le remonte jamais). Dans la
  //     MÊME requête, on récupère la MÉTA appareil (modèle, plateforme, version
  //     app, première/dernière vue, revendeur) pour une fiche « tout, tout ».
  let localSources = [];
  let device = null;
  try {
    const drow = await env.DB
      .prepare(
        `SELECT d.local_sources_json, d.label, d.customer_id, d.reseller_id,
                d.block_status, d.first_seen_at, d.last_seen_at,
                d.device_model, d.android_build, d.android_release,
                d.app_build, d.app_version, d.platform, d.android_id,
                c.name AS customer_name
           FROM devices d
           LEFT JOIN customers c ON c.id = d.customer_id
          WHERE d.id = ?`,
      )
      .bind(dev.id)
      .first();
    if (drow) {
      if (drow.local_sources_json) {
        try { localSources = JSON.parse(drow.local_sources_json) || []; }
        catch (_) { localSources = []; }
      }
      device = {
        label: drow.label || null,
        customer_name: drow.customer_name || null,
        reseller_id: drow.reseller_id || null,
        block_status: drow.block_status || null,
        first_seen_at: drow.first_seen_at || 0,
        last_seen_at: drow.last_seen_at || 0,
        device_model: drow.device_model || null,
        android_release: drow.android_release || null,
        android_build: drow.android_build || null,
        app_version: drow.app_version || null,
        app_build: drow.app_build || null,
        platform: drow.platform || null,
        android_id: drow.android_id || null,
      };
    }
  } catch (_) { /* colonnes/table absentes sur base ancienne : on ignore */ }

  return jsonResp({ mac: dev.mac, license, presence, sources, localSources, device });
}

// =========================================================
//  MESSAGES PERSISTANTS PAR APPAREIL (« boîte de réception »)
// =========================================================
//  Déposer un mot à UNE seule MAC, livré à sa PROCHAINE OUVERTURE même si
//  l'appareil était hors ligne (façon WhatsApp). L'app lit sa boîte via
//  GET /api/device-messages/:mac (worker.js public) qui marque « livré »
//  → accusé de réception visible ici (delivered_at).
async function ensureDeviceMessagesTable(env) {
  await env.DB.prepare(
    'CREATE TABLE IF NOT EXISTS device_messages (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, mac TEXT, title TEXT, body TEXT, ' +
      'kind TEXT, duration_sec INTEGER, created_at INTEGER, ' +
      'delivered_at INTEGER, read_at INTEGER)',
  ).run();
  try {
    await env.DB.prepare(
      'CREATE INDEX IF NOT EXISTS idx_devmsg_mac ON device_messages(mac, delivered_at)',
    ).run();
  } catch (_) { /* index déjà présent */ }
}

/// Résout la MAC cible depuis :id (ID de ligne OU MAC), avec cloisonnement :
/// l'owner peut viser N'IMPORTE QUELLE MAC (même sans fiche device) ; un
/// revendeur uniquement une MAC qui lui appartient (fiche device requise).
/// Renvoie { mac } ou { error }.
async function resolveTargetMac(env, id, user) {
  const key = String(id || '');
  const isReseller = user && user.role === 'reseller';
  const dev = await env.DB
    .prepare('SELECT mac, reseller_id FROM devices WHERE id = ? OR mac = ?')
    .bind(key, key.toUpperCase())
    .first();
  if (dev) {
    if (isReseller && dev.reseller_id !== user.sub) {
      return { error: errResp('forbidden', 'Cet appareil ne vous appartient pas', 403) };
    }
    return { mac: dev.mac };
  }
  if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(key)) {
    return { error: errResp('not_found', 'Device not found', 404) };
  }
  if (isReseller) return { error: errResp('not_found', 'Device not found', 404) };
  return { mac: key.toUpperCase() };
}

async function handleDeviceMessageCreate(request, env, id, user) {
  await ensureDeviceMessagesTable(env);
  const t = await resolveTargetMac(env, id, user);
  if (t.error) return t.error;
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const title = (body.title || '').toString().trim().slice(0, 120);
  const msg = (body.body || '').toString().trim().slice(0, 500);
  if (!title && !msg) {
    return errResp('missing_fields', 'title or body required', 400);
  }
  const kindRaw = (body.kind || 'info').toString().trim().toLowerCase();
  const kind = ['info', 'success', 'warning'].includes(kindRaw) ? kindRaw : 'info';
  let dur = parseInt(body.durationSec, 10);
  if (!Number.isFinite(dur)) dur = 45;
  dur = Math.max(3, Math.min(120, dur));
  const now = Date.now();
  const res = await env.DB
    .prepare(
      'INSERT INTO device_messages (mac, title, body, kind, duration_sec, created_at) ' +
        'VALUES (?, ?, ?, ?, ?, ?)',
    )
    .bind(t.mac, title, msg, kind, dur, now)
    .run();
  await logAudit(env, request, user, 'device_message.create',
    { type: 'device_message', id: (res.meta && res.meta.last_row_id) || null },
    null, { mac: t.mac, title });
  return jsonResp({ ok: true, mac: t.mac }, 201);
}

async function handleDeviceMessagesList(env, id, user) {
  await ensureDeviceMessagesTable(env);
  const t = await resolveTargetMac(env, id, user);
  if (t.error) return t.error;
  const rs = await env.DB
    .prepare(
      'SELECT id, title, body, kind, duration_sec, created_at, delivered_at, read_at ' +
        'FROM device_messages WHERE mac = ? ORDER BY id DESC LIMIT 20',
    )
    .bind(t.mac)
    .all();
  return jsonResp({ items: rs.results || [] });
}

async function handleDevicesCreate(request, env, actor) {
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  if (!body.customer_id || !body.mac) {
    return errResp('missing_fields', 'customer_id and mac required', 400);
  }
  if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(body.mac)) {
    return errResp('bad_mac', 'mac must be MK:XX:XX:XX:XX:XX', 400);
  }
  const id = genId('dev');
  const now = Date.now();
  try {
    await env.DB
      .prepare(
        `INSERT INTO devices (id, customer_id, mac, label,
                              first_seen_at, last_seen_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
      )
      .bind(id, body.customer_id, body.mac, body.label || null, now, now)
      .run();
  } catch (e) {
    return errResp('duplicate_mac', 'This MAC already exists', 409);
  }
  await logAudit(env, request, actor, 'device.create', { type: 'device', id }, null, body);
  return jsonResp({ id }, 201);
}

// Verifie qu'un revendeur a le droit d'agir sur ce device (le sien),
// ou que c'est l'owner. Renvoie le device, ou une reponse d'erreur.
async function deviceForActor(env, id, user) {
  // Accepte l'ID de ligne OU la MAC : ainsi TOUTES les pages du panel qui
  // n'ont qu'une MAC (Centre de contrôle, En ligne, Activations, Historique,
  // Références, Familles…) peuvent ouvrir la fiche 360° en cliquant la MAC,
  // sans devoir résoudre l'ID d'abord. Les ID (uuid préfixé) et les MAC
  // (MK:XX:…) ne se collisionnent pas.
  const key = String(id || '');
  const dev = await env.DB
    .prepare(
      'SELECT id, mac, reseller_id, block_status FROM devices WHERE id = ? OR mac = ?',
    )
    .bind(key, key.toUpperCase())
    .first();
  if (!dev) return { error: errResp('not_found', 'Device not found', 404) };
  if (user && user.role === 'reseller' && dev.reseller_id !== user.sub) {
    return { error: errResp('forbidden', 'Cet appareil ne vous appartient pas', 403) };
  }
  return { dev };
}

// PATCH /devices/:id { block_status: 'active'|'frozen'|'banned' }
// Geler (rappel de paiement), bannir (abus), ou reactiver une MAC.
async function handleDeviceUpdate(request, env, id, actor, user) {
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const r = await deviceForActor(env, id, user);
  if (r.error) return r.error;
  // Bloquer/geler/bannir = droit 'block' (revendeur). L'owner a tout.
  if (body.block_status !== undefined && !resellerCan(user, 'block')) {
    return errResp('forbidden', "Ton compte n'a pas le droit de bloquer un client.", 403);
  }
  const allowed = ['active', 'frozen', 'banned'];
  const next = body.block_status === 'active' ? null : body.block_status;
  if (body.block_status !== undefined && !allowed.includes(body.block_status)) {
    return errResp('bad_status', "block_status doit etre 'active', 'frozen' ou 'banned'", 400);
  }
  await env.DB.prepare('UPDATE devices SET block_status = ? WHERE id = ?')
    .bind(next ?? null, id).run();
  await logAudit(env, request, actor, 'device.block',
    { type: 'device', id }, { block_status: r.dev.block_status }, { block_status: next });
  return jsonResp({ updated: 1, block_status: next });
}

// DELETE /devices/:id — supprime la MAC (et ses licences en cascade).
// NB : si l'app reste installee, elle se re-enregistrera au prochain
// heartbeat (nouvel essai). Pour stopper un abuseur, prefere 'banned'.
async function handleDeviceDelete(env, id, actor, user) {
  const r = await deviceForActor(env, id, user);
  if (r.error) return r.error;
  await env.DB.prepare('DELETE FROM devices WHERE id = ?').bind(id).run();
  await logAudit(env, null, actor, 'device.delete',
    { type: 'device', id }, { mac: r.dev.mac }, null);
  return jsonResp({ deleted: 1 });
}

// =========================================================
//  LICENSES HANDLERS
// =========================================================
//  Le coeur du systeme. Activer = creer une license.
//  POST /api/v1/licenses
//    { customer_id, device_id, app_id, plan: '1m'|'3m'|'6m'|'1y'|'lifetime',
//      custom_days?: number }
//
//  Le serveur calcule expires_at depuis plan + now :
//    1m → +30 jours, 3m → +90, 6m → +180, 1y → +365, lifetime → null
//    custom_days → +custom_days
// =========================================================

function planToDays(plan, customDays) {
  // Essais courts GRATUITS : 'trial_2h', 'trial_24h', 'trial_48h'…
  // → fraction de jour (les heures fonctionnent dans le calcul
  // d'expiration : days * 24h * 60min… donc 2/24 jour = 2 heures pile).
  const hm = /^trial_(\d+)h$/.exec(plan || '');
  if (hm) return Number(hm[1]) / 24;
  // Essais GRATUITS en JOURS : 'trial_7d', 'trial_3d'… (ex. l'essai
  // standard de 7 jours proposé dans le panel d'activation).
  const dm = /^trial_(\d+)d$/.exec(plan || '');
  if (dm) return Number(dm[1]);
  switch (plan) {
    case '1m':
    case 'monthly': return 30;
    case '3m':
    case 'quarterly': return 90;
    case '6m':
    case 'biannual': return 180;
    case '1y':
    case 'yearly': return 365;
    case 'lifetime': return null;
    case 'custom': return customDays && customDays > 0 ? customDays : 30;
    case 'trial': return 7;
    default: return 30;
  }
}

async function handleLicensesList(request, env, user) {
  const url = new URL(request.url);
  const status = url.searchParams.get('status');
  const appId = url.searchParams.get('app_id');
  let sql = `SELECT l.id, l.customer_id, l.device_id, l.app_id, l.status,
                    l.plan, l.started_at, l.expires_at, l.auto_renew, l.reseller_id,
                    c.name as customer_name, c.email as customer_email,
                    d.mac as device_mac, d.label as device_label,
                    a.name as app_name
             FROM licenses l
             JOIN customers c ON l.customer_id = c.id
             JOIN devices   d ON l.device_id   = d.id
             JOIN apps      a ON l.app_id      = a.id`;
  const where = []; const binds = [];
  if (status) { where.push('l.status = ?'); binds.push(status); }
  if (appId)  { where.push('l.app_id = ?'); binds.push(appId); }
  if (user && user.role === 'reseller') {
    where.push('l.reseller_id = ?');
    binds.push(user.sub);
  }
  if (where.length) sql += ' WHERE ' + where.join(' AND ');
  sql += ' ORDER BY l.created_at DESC LIMIT 200';
  const rs = await env.DB.prepare(sql).bind(...binds).all();
  return jsonResp({ items: rs.results || [] });
}

async function handleLicensesCreate(request, env, actor) {
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  if (!body.customer_id || !body.device_id || !body.app_id) {
    return errResp('missing_fields',
      'customer_id, device_id and app_id required', 400);
  }
  const id = genId('lic');
  const now = Date.now();
  const days = planToDays(body.plan, body.custom_days);
  const expiresAt = days === null ? null : now + days * 24 * 60 * 60 * 1000;
  try {
    await env.DB
      .prepare(
        `INSERT INTO licenses
          (id, customer_id, device_id, app_id, status, plan,
           started_at, expires_at, auto_renew, reseller_id, notes,
           created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .bind(
        id,
        body.customer_id,
        body.device_id,
        body.app_id,
        'active',
        body.plan || '1m',
        now,
        expiresAt,
        body.auto_renew ? 1 : 0,
        body.reseller_id || null,
        body.notes || null,
        now,
        now,
      )
      .run();
  } catch (e) {
    return errResp('duplicate_license',
      'This device already has a license for this app', 409);
  }
  await logAudit(env, request, actor, 'license.create',
    { type: 'license', id }, null, { ...body, expires_at: expiresAt });
  return jsonResp({ id, expires_at: expiresAt }, 201);
}

async function handleLicensesUpdate(request, env, id, actor) {
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const before = await env.DB.prepare('SELECT * FROM licenses WHERE id = ?').bind(id).first();
  if (!before) return errResp('not_found', 'License not found', 404);
  const fields = ['status', 'plan', 'expires_at', 'auto_renew', 'notes'];
  const sets = []; const vals = [];
  for (const f of fields) {
    if (body[f] !== undefined) {
      sets.push(`${f} = ?`);
      vals.push(f === 'auto_renew' ? (body[f] ? 1 : 0) : body[f]);
    }
  }
  if (sets.length === 0) return jsonResp({ updated: 0 });
  sets.push('updated_at = ?'); vals.push(Date.now());
  vals.push(id);
  await env.DB.prepare(`UPDATE licenses SET ${sets.join(', ')} WHERE id = ?`).bind(...vals).run();
  await logAudit(env, request, actor, 'license.update', { type: 'license', id }, before, body);
  return jsonResp({ updated: 1 });
}

async function handleLicensesRenew(request, env, id, actor) {
  let body = {};
  try { body = await request.json(); } catch (_) {}
  const before = await env.DB.prepare('SELECT * FROM licenses WHERE id = ?').bind(id).first();
  if (!before) return errResp('not_found', 'License not found', 404);
  const days = planToDays(body.plan || before.plan || '1y', body.custom_days);
  const now = Date.now();
  // On etend a partir de la date la plus tardive entre maintenant et l'expiry
  // actuel, pour qu'un renouvellement avant expiration cumule les jours
  // (au lieu de remettre a now+1y et perdre les jours restants).
  const base = before.expires_at && before.expires_at > now ? before.expires_at : now;
  const newExpiry = days === null ? null : base + days * 24 * 60 * 60 * 1000;
  await env.DB
    .prepare(
      `UPDATE licenses
       SET status = 'active', plan = ?, expires_at = ?, updated_at = ?
       WHERE id = ?`,
    )
    .bind(body.plan || before.plan, newExpiry, now, id)
    .run();
  await logAudit(env, request, actor, 'license.renew',
    { type: 'license', id }, before, { plan: body.plan, expires_at: newExpiry });
  return jsonResp({ updated: 1, expires_at: newExpiry });
}

// =========================================================
//  RESELLERS · CREDITS · ACTIVATION (panel revendeurs)
// =========================================================

/// `true` si l'acteur est proprietaire de la plateforme (toi/admins),
/// par opposition a un revendeur cloisonne.
function isOwner(user) {
  return user && (user.role === 'super_admin' || user.role === 'admin');
}

// ----- Login revendeur (table `resellers`, role JWT 'reseller') -----
// =========================================================
//  REVENDEURS — droits À LA CARTE (cases à cocher) + inscription
// =========================================================
//  L'admin coche EXACTEMENT les droits qu'il accorde à chaque revendeur
//  (pas de niveaux figés). Liste canonique des droits attribuables :
export const RESELLER_CAPS_ALL = [
  'activate',     // activer un client
  'block',        // bloquer / geler / bannir un client
  'transfer',     // transférer un client (changement d'appareil)
  'buy_credits',  // demander un rechargement de crédits (owner approuve)
  'sources',      // pousser une source (playlist) aux clients
  'devices',      // voir ses appareils
  'activations',  // voir ses activations
  'resellers',    // créer/gérer des sous-revendeurs (OWNER l'accorde seul)
  'admin_monitor', // MODE ADMIN MONITORING : voir les sessions admin séparées
];

// Droits cochés PAR DÉFAUT à la création d'un revendeur (règle produit :
// activer / bloquer / transférer / achat de crédit). « resellers » n'y est
// JAMAIS : seul l'owner peut accorder le droit de créer des sous-revendeurs.
export const RESELLER_DEFAULT_CAPS = ['activate', 'block', 'transfer', 'buy_credits'];

// =========================================================
//  TRÉSORERIE — réserve de crédits de l'owner (à distribuer)
// =========================================================
//  L'owner part d'une RÉSERVE de 1 000 000 crédits. Chaque crédit donné à
//  un revendeur (mint / approbation de demande) DÉCRÉMENTE cette réserve ;
//  reprendre des crédits la RECRÉDITE. Bouton « Régénérer » = remettre la
//  réserve à 1 000 000 (ou en ajouter). 1 crédit = 9,90 € (= 1 an) → sert
//  au compteur d'argent (crédits distribués / utilisés × valeur).
export const OWNER_POOL_START = 1000000;
export const CREDIT_VALUE_EUR_DEFAULT = 9.90;

async function getOwnerPool(env) {
  await ensureAppConfigTable(env);
  const s = await _cfgGetStr(env, 'owner_credit_pool');
  if (s === '') { await _cfgSet(env, 'owner_credit_pool', OWNER_POOL_START); return OWNER_POOL_START; }
  const n = parseInt(s, 10);
  return Number.isFinite(n) ? n : OWNER_POOL_START;
}
async function setOwnerPool(env, value) {
  await _cfgSet(env, 'owner_credit_pool', Math.max(0, Math.floor(value)));
}
async function getCreditValueEur(env) {
  const s = await _cfgGetStr(env, 'credit_value_eur');
  const n = parseFloat(s);
  return Number.isFinite(n) && n > 0 ? n : CREDIT_VALUE_EUR_DEFAULT;
}

//  Ancien modèle « niveaux » — gardé UNIQUEMENT pour dériver les droits
//  des comptes créés avant les cases à cocher (rétro-compat).
const RESELLER_LEGACY_LEVEL = {
  basique: ['activate'],
  standard: ['activate', 'sources'],
  confiance: ['activate', 'sources', 'resellers', 'devices', 'activations'],
};

/// Normalise les droits d'un revendeur en tableau. Priorité au champ
/// `permissions` (JSON). Sinon on dérive de l'ancien `level`. Sinon, le
/// minimum vital : activer des appareils.
export function resellerPerms(permissionsVal, level) {
  if (Array.isArray(permissionsVal)) return permissionsVal;
  if (typeof permissionsVal === 'string' && permissionsVal) {
    try { const a = JSON.parse(permissionsVal); if (Array.isArray(a)) return a; } catch (_) {}
  }
  return RESELLER_LEGACY_LEVEL[level] || ['activate'];
}

/// Ne garde que les droits connus (anti-injection) avant stockage.
export function sanitizePerms(arr) {
  if (!Array.isArray(arr)) return [];
  return RESELLER_CAPS_ALL.filter((c) => arr.includes(c));
}

/// true si l'acteur a le droit `cap`. L'admin (super_admin) a TOUT ;
/// un revendeur n'a que ce que l'admin lui a coché.
export function resellerCan(user, cap) {
  if (!user || user.role !== 'reseller') return true;
  return resellerPerms(user.permissions, user.level).includes(cap);
}

/// Ajoute les colonnes `level` (legacy) et `permissions` si absentes.
async function ensureResellerLevel(env) {
  try {
    await env.DB
      .prepare("ALTER TABLE resellers ADD COLUMN level TEXT NOT NULL DEFAULT 'basique'")
      .run();
  } catch (_) { /* colonne déjà présente */ }
  try {
    await env.DB.prepare('ALTER TABLE resellers ADD COLUMN permissions TEXT').run();
  } catch (_) { /* colonne déjà présente */ }
}

// ----- Auto-inscription revendeur (PUBLIC, via le lien unique) -----
//  Le revendeur ouvre le lien, choisit identifiant + mot de passe. Le
//  compte est créé en statut 'pending' (0 crédit, droit 'activate' par
//  défaut) : il n'a AUCUN accès tant que l'admin ne l'a pas activé et ne
//  lui a pas coché ses droits + donné des crédits. L'admin garde la main.
async function handleResellerSignup(request, env) {
  // Anti-spam : 5 inscriptions / heure par IP (le lien est public).
  if (!await rateLimitHit(env, request, 'signup', 5, 60 * 60 * 1000)) {
    return errResp('rate_limited', 'Trop d\'inscriptions. Réessaie plus tard.', 429);
  }
  await ensureResellerLevel(env);
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const email = (body.email || '').trim().toLowerCase();
  const password = body.password || '';
  const name = (body.name || '').trim() || null;
  if (!email || !password) {
    return errResp('missing_fields', 'Identifiant et mot de passe requis', 400);
  }
  if (email.length < 3) return errResp('bad_email', 'Identifiant trop court', 400);
  if (password.length < 4) {
    return errResp('weak_password', 'Mot de passe trop court (min. 4)', 400);
  }
  const existing = await env.DB
    .prepare('SELECT id FROM resellers WHERE email = ?').bind(email).first();
  if (existing) return errResp('email_taken', 'Cet identifiant est déjà pris', 409);
  const id = genId('rsl');
  const now = Date.now();
  const hash = await hashPassword(password);
  await env.DB
    .prepare(
      `INSERT INTO resellers
        (id, email, password_hash, name, credit_balance_cents, credit_balance,
         commission_rate, status, level, permissions, created_at)
       VALUES (?, ?, ?, ?, 0, 0, 0.20, 'pending', 'basique', ?, ?)`,
    )
    .bind(id, email, hash, name, JSON.stringify(['activate']), now)
    .run();
  return jsonResp({ ok: true, pending: true }, 201);
}

async function handleResellerLogin(request, env) {
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const email = (body.email || '').trim().toLowerCase();
  const password = body.password || '';
  if (!email || !password) {
    return errResp('missing_fields', 'email and password required', 400);
  }
  // Anti-brute-force : 10 tentatives / 10 min par IP. Succès = reset.
  if (!await rateLimitHit(env, request, 'rlogin', 10, 10 * 60 * 1000)) {
    return errResp('rate_limited',
      'Trop de tentatives de connexion. Réessaie dans ~10 minutes.', 429);
  }
  await ensureResellerLevel(env);
  const row = await env.DB
    .prepare('SELECT id, email, password_hash, name, status, level, permissions, credit_balance FROM resellers WHERE email = ?')
    .bind(email)
    .first();
  if (!row) return errResp('bad_credentials', 'Invalid credentials', 401);
  // Vérifie d'abord le mot de passe (évite de révéler le statut d'un
  // compte sur une mauvaise saisie), puis distingue pending/suspended.
  const ok = await verifyPassword(password, row.password_hash);
  if (!ok) return errResp('bad_credentials', 'Invalid credentials', 401);
  if (row.status === 'pending') {
    return errResp('pending', 'Compte en attente de validation par l\'administrateur.', 403);
  }
  if (row.status !== 'active') {
    return errResp('suspended', 'Compte suspendu. Contacte l\'administrateur.', 403);
  }
  await rateLimitReset(env, request, 'rlogin'); // succès → on libère l'IP
  const level = row.level || 'basique';
  const permissions = resellerPerms(row.permissions, level);
  const token = await signJwt(
    { sub: row.id, email: row.email, role: 'reseller', name: row.name, level, permissions },
    env.ADMIN_SECRET,
  );
  return jsonResp({
    token,
    user: {
      id: row.id, email: row.email, name: row.name,
      role: 'reseller', level, permissions, credit_balance: row.credit_balance,
    },
  });
}

// ----- /me : profil de l'acteur courant (+ solde si revendeur) -----
async function handleMe(env, user) {
  if (user.role === 'reseller') {
    await ensureResellerLevel(env);
    const r = await env.DB
      .prepare('SELECT id, email, name, status, level, permissions, credit_balance, commission_rate FROM resellers WHERE id = ?')
      .bind(user.sub)
      .first();
    if (!r) return errResp('not_found', 'Reseller not found', 404);
    return jsonResp({ user: {
      ...r,
      level: r.level || 'basique',
      permissions: resellerPerms(r.permissions, r.level),
      role: 'reseller',
    } });
  }
  return jsonResp({ user });
}

// ----- Changer SON PROPRE mot de passe (admin OU revendeur) -----
async function handleChangeOwnPassword(request, env, user, actor) {
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const current = body.current_password || '';
  const next = body.new_password || '';
  // Comptes admin/revendeur = accès à TOUT le parc clients → minimum 8.
  // (4 était trop faible pour des identifiants à fort privilège.)
  if (!next || next.length < 8) {
    return errResp('weak_password', 'Le nouveau mot de passe doit faire au moins 8 caracteres', 400);
  }
  const table = user.role === 'reseller' ? 'resellers' : 'admin_users';
  const row = await env.DB
    .prepare(`SELECT password_hash FROM ${table} WHERE id = ?`)
    .bind(user.sub).first();
  if (!row) return errResp('not_found', 'Compte introuvable', 404);
  const ok = await verifyPassword(current, row.password_hash);
  if (!ok) return errResp('bad_current', 'Mot de passe actuel incorrect', 401);
  const hash = await hashPassword(next);
  await env.DB.prepare(`UPDATE ${table} SET password_hash = ? WHERE id = ?`)
    .bind(hash, user.sub).run();
  await logAudit(env, request, actor, 'password.change_self',
    { type: user.role === 'reseller' ? 'reseller' : 'admin', id: user.sub }, null, null);
  return jsonResp({ ok: true });
}

// ----- plan_costs : cout en credits par plan -----
async function handlePlanCostsList(env) {
  const rs = await env.DB
    .prepare('SELECT plan, credits FROM plan_costs ORDER BY credits ASC')
    .all();
  return jsonResp({ items: rs.results || [] });
}

async function handlePlanCostsUpdate(request, env, actor) {
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const costs = body.costs || body;  // { monthly: 1, yearly: 10, ... }
  const entries = Object.entries(costs)
    .filter(([, v]) => Number.isFinite(Number(v)));
  if (entries.length === 0) {
    return errResp('missing_fields', 'costs map required', 400);
  }
  const stmts = entries.map(([plan, credits]) =>
    env.DB.prepare(
      `INSERT INTO plan_costs (plan, credits) VALUES (?, ?)
       ON CONFLICT(plan) DO UPDATE SET credits = excluded.credits`,
    ).bind(plan, Math.max(0, Math.round(Number(credits)))),
  );
  await env.DB.batch(stmts);
  await logAudit(env, request, actor, 'plan_costs.update',
    { type: 'plan_costs', id: 'all' }, null, costs);
  return jsonResp({ updated: entries.length });
}

/// Cout en credits d'un plan (table plan_costs, avec defauts de secours).
async function planCreditCost(env, plan) {
  // Tout essai ('trial', 'trial_2h', 'trial_24h'…) est GRATUIT : 0 crédit.
  // On peut donc activer un test même avec 0 crédit / sans paiement.
  if (typeof plan === 'string' && plan.startsWith('trial')) return 0;
  const row = await env.DB
    .prepare('SELECT credits FROM plan_costs WHERE plan = ?')
    .bind(plan)
    .first();
  if (row) return row.credits;
  // Défauts de secours (si la table plan_costs n'a pas la ligne) :
  // 1 crédit = 1 an, 2 crédits = à vie (cf. migration 009).
  const def = { trial: 0, monthly: 1, quarterly: 3, biannual: 5, yearly: 1, lifetime: 2, custom: 1 };
  return def[plan] != null ? def[plan] : 1;
}

// ----- Resellers CRUD (owner) -----
async function handleResellersList(env, user) {
  await ensureResellerLevel(env);
  // Owner : tout l'arbre. Revendeur : seulement SES sous-revendeurs directs.
  const reseller = user && user.role === 'reseller';
  const where = reseller ? 'WHERE r.parent_reseller_id = ?' : '';
  const binds = reseller ? [user.sub] : [];
  const rs = await env.DB
    .prepare(
      `SELECT r.id, r.email, r.name, r.status, r.level, r.permissions, r.credit_balance,
              r.commission_rate, r.parent_reseller_id, r.created_at,
              (SELECT COUNT(*) FROM devices d   WHERE d.reseller_id = r.id) as devices,
              (SELECT COUNT(*) FROM licenses l  WHERE l.reseller_id = r.id) as licenses,
              (SELECT COUNT(*) FROM resellers s WHERE s.parent_reseller_id = r.id) as sub_resellers
       FROM resellers r ${where} ORDER BY r.created_at DESC LIMIT 500`,
    )
    .bind(...binds)
    .all();
  // On renvoie `permissions` en tableau prêt à cocher côté panel.
  const items = (rs.results || []).map((r) => ({
    ...r,
    permissions: resellerPerms(r.permissions, r.level),
  }));
  return jsonResp({ items });
}

async function handleResellersGet(env, id, user) {
  const row = await env.DB
    .prepare('SELECT id, email, name, status, credit_balance, commission_rate, parent_reseller_id, created_at FROM resellers WHERE id = ?')
    .bind(id)
    .first();
  if (!row) return errResp('not_found', 'Reseller not found', 404);
  // Un revendeur ne voit que lui-meme ou ses enfants directs.
  if (user && user.role === 'reseller'
      && id !== user.sub && row.parent_reseller_id !== user.sub) {
    return errResp('forbidden', 'Forbidden', 403);
  }
  return jsonResp(row);
}

async function handleResellersCreate(request, env, actor, user) {
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const email = (body.email || '').trim().toLowerCase();
  const password = body.password || '';
  if (!email || !password) {
    return errResp('missing_fields', 'email and password required', 400);
  }
  const isReseller = user && user.role === 'reseller';
  const parentId = isReseller ? user.sub : null;
  // Crédits = OWNER uniquement. Un revendeur qui crée un sous-revendeur ne
  // peut PAS lui transférer de crédits (le sous-revendeur démarre à 0 ;
  // c'est l'owner qui le rechargera). Seul l'owner sème un solde initial.
  const initial = isOwner(user)
    ? Math.max(0, parseInt(body.credit_balance || 0, 10) || 0)
    : 0;
  const commission = Number.isFinite(Number(body.commission_rate))
    ? Number(body.commission_rate) : 0.20;

  // Droits du nouveau revendeur. Owner : ce qu'il coche (ou les défauts).
  // Revendeur créant un sous-revendeur : défauts SANS jamais 'resellers'
  // (seul l'owner accorde le droit de créer des sous-revendeurs).
  const requestedPerms = Array.isArray(body.permissions) ? body.permissions : RESELLER_DEFAULT_CAPS;
  const newPerms = isOwner(user)
    ? sanitizePerms(requestedPerms)
    : sanitizePerms(RESELLER_DEFAULT_CAPS).filter((c) => c !== 'resellers');

  // Si c'est un revendeur qui cree un sous-revendeur, les credits
  // initiaux sont TRANSFERES depuis son propre solde (pas crees).
  let parentBalanceAfter = null;
  if (isReseller && initial > 0) {
    const parent = await env.DB
      .prepare('SELECT credit_balance FROM resellers WHERE id = ?')
      .bind(user.sub).first();
    if (!parent) return errResp('not_found', 'Parent reseller not found', 404);
    if (parent.credit_balance < initial) {
      return errResp('insufficient_credits',
        `Credits insuffisants (besoin ${initial}, solde ${parent.credit_balance})`, 402);
    }
    parentBalanceAfter = parent.credit_balance - initial;
  }

  const id = genId('rsl');
  const now = Date.now();
  const hash = await hashPassword(password);
  await ensureResellerLevel(env); // garantit la colonne `permissions`
  try {
    await env.DB
      .prepare(
        `INSERT INTO resellers
          (id, email, password_hash, name, credit_balance_cents,
           credit_balance, commission_rate, status, parent_reseller_id,
           permissions, created_at)
         VALUES (?, ?, ?, ?, 0, ?, ?, 'active', ?, ?, ?)`,
      )
      .bind(id, email, hash, body.name || null, initial, commission, parentId,
            JSON.stringify(newPerms), now)
      .run();
  } catch (e) {
    return errResp('duplicate_email', 'A reseller with this email already exists', 409);
  }

  // Ecritures de credits (atomiques).
  const stmts = [];
  if (initial > 0) {
    stmts.push(env.DB.prepare(
      `INSERT INTO credit_ledger
        (id, reseller_id, delta, reason, balance_after, actor_type, actor_id, note, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(genId('cl'), id, initial, parentId ? 'transfer_in' : 'issue',
           initial, actor.type, actor.id, 'Credits initiaux', now));
  }
  if (isReseller && initial > 0) {
    stmts.push(env.DB.prepare('UPDATE resellers SET credit_balance = ? WHERE id = ?')
      .bind(parentBalanceAfter, user.sub));
    stmts.push(env.DB.prepare(
      `INSERT INTO credit_ledger
        (id, reseller_id, delta, reason, balance_after, actor_type, actor_id, note, created_at)
       VALUES (?, ?, ?, 'transfer_out', ?, ?, ?, ?, ?)`,
    ).bind(genId('cl'), user.sub, -initial, parentBalanceAfter, actor.type, actor.id,
           'Vers ' + email, now));
  }
  if (stmts.length) await env.DB.batch(stmts);

  await logAudit(env, request, actor, 'reseller.create',
    { type: 'reseller', id }, null, { email, name: body.name, initial, parent: parentId });
  return jsonResp({ id, credit_balance: initial }, 201);
}

// DELETE /resellers/:id — supprimer un revendeur.
//  • Owner : peut supprimer n'importe quel revendeur.
//  • Revendeur : uniquement SES sous-revendeurs directs (s'il a le droit
//    'resellers', déjà vérifié en amont).
//  Sécurité : on refuse s'il reste des sous-revendeurs rattachés (il faut
//  d'abord les traiter) pour ne pas créer d'orphelins. Le solde de crédits
//  du revendeur supprimé est simplement perdu (compte fermé) ; ses clients
//  (devices/licences) restent — ils sont détachés du revendeur (reseller_id
//  remis à NULL) et repassent sous la maison mère.
async function handleResellersDelete(env, id, actor, user) {
  const before = await env.DB.prepare('SELECT * FROM resellers WHERE id = ?').bind(id).first();
  if (!before) return errResp('not_found', 'Reseller not found', 404);
  // Un revendeur ne supprime que ses enfants directs.
  if (user && user.role === 'reseller' && before.parent_reseller_id !== user.sub) {
    return errResp('forbidden', 'Forbidden', 403);
  }
  // Anti-orphelins : refuser s'il a encore des sous-revendeurs.
  const kids = await env.DB
    .prepare('SELECT COUNT(*) AS n FROM resellers WHERE parent_reseller_id = ?')
    .bind(id).first();
  if (kids && kids.n > 0) {
    return errResp('has_children',
      'Ce revendeur a encore des sous-revendeurs. Traite-les d\'abord.', 409);
  }
  // Détache ses clients (ils repassent à la maison mère) puis supprime.
  await env.DB.batch([
    env.DB.prepare('UPDATE devices SET reseller_id = NULL WHERE reseller_id = ?').bind(id),
    env.DB.prepare('UPDATE customers SET reseller_id = NULL WHERE reseller_id = ?').bind(id),
    env.DB.prepare('UPDATE licenses SET reseller_id = NULL WHERE reseller_id = ?').bind(id),
    env.DB.prepare('DELETE FROM resellers WHERE id = ?').bind(id),
  ]);
  await logAudit(env, null, actor, 'reseller.delete',
    { type: 'reseller', id }, { email: before.email }, null);
  return jsonResp({ deleted: 1 });
}

async function handleResellersUpdate(request, env, id, actor, user) {
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const before = await env.DB.prepare('SELECT * FROM resellers WHERE id = ?').bind(id).first();
  if (!before) return errResp('not_found', 'Reseller not found', 404);
  // Un revendeur ne peut modifier que ses propres enfants directs.
  if (user && user.role === 'reseller' && before.parent_reseller_id !== user.sub) {
    return errResp('forbidden', 'Forbidden', 403);
  }
  await ensureResellerLevel(env);
  const sets = []; const vals = [];
  if (body.name !== undefined) { sets.push('name = ?'); vals.push(body.name); }
  if (body.status !== undefined) { sets.push('status = ?'); vals.push(body.status); }
  // DROITS À LA CARTE (cases cochées par l'admin) — owner uniquement.
  // On ne garde que les droits connus puis on stocke en JSON.
  if (body.permissions !== undefined && isOwner(user)) {
    sets.push('permissions = ?');
    vals.push(JSON.stringify(sanitizePerms(body.permissions)));
  }
  // Seul l'owner peut changer la commission.
  if (body.commission_rate !== undefined && isOwner(user)) {
    sets.push('commission_rate = ?'); vals.push(Number(body.commission_rate));
  }
  if (body.password) { sets.push('password_hash = ?'); vals.push(await hashPassword(body.password)); }
  if (sets.length === 0) return jsonResp({ updated: 0 });
  vals.push(id);
  await env.DB.prepare(`UPDATE resellers SET ${sets.join(', ')} WHERE id = ?`).bind(...vals).run();
  await logAudit(env, request, actor, 'reseller.update', { type: 'reseller', id }, before, body);
  return jsonResp({ updated: 1 });
}

// ----- Credits : owner emet (mint) ; revendeur TRANSFERE a ses enfants -----
async function handleResellerCreditsIssue(request, env, id, actor, user) {
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const amount = parseInt(body.amount, 10);
  if (!Number.isFinite(amount) || amount === 0) {
    return errResp('bad_amount', 'amount required (positif = ajouter, negatif = retirer)', 400);
  }
  const target = await env.DB
    .prepare('SELECT credit_balance, parent_reseller_id FROM resellers WHERE id = ?')
    .bind(id).first();
  if (!target) return errResp('not_found', 'Reseller not found', 404);
  const now = Date.now();

  // RÈGLE ARGENT : SEUL l'owner émet/retire des crédits. Un revendeur ne
  // peut jamais donner de crédits (ni à ses sous-revendeurs) — « c'est moi
  // seul qui donne les crédits ». Les revendeurs passent par une DEMANDE
  // de rechargement (/credit-requests) que l'owner approuve.
  if (!isOwner(user)) {
    return errResp('forbidden', "Seul l'administrateur émet des crédits.", 403);
  }

  // --- OWNER : donne / reprend des credits DEPUIS SA RÉSERVE (pool) ---
  if (isOwner(user)) {
    const newBalance = target.credit_balance + amount;
    if (newBalance < 0) {
      return errResp('insufficient_credits', 'Le solde resultant serait negatif', 400);
    }
    // La réserve owner encadre la distribution : donner décrémente le pool,
    // reprendre le recrédite. On ne distribue jamais plus qu'on n'a.
    const pool = await getOwnerPool(env);
    if (amount > 0 && pool < amount) {
      return errResp('pool_empty',
        `Réserve de crédits insuffisante (reste ${pool}). Régénère la réserve.`, 402);
    }
    await setOwnerPool(env, pool - amount); // amount<0 → pool augmente
    await env.DB.batch([
      env.DB.prepare('UPDATE resellers SET credit_balance = ? WHERE id = ?').bind(newBalance, id),
      env.DB.prepare(
        `INSERT INTO credit_ledger
          (id, reseller_id, delta, reason, balance_after, actor_type, actor_id, note, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(genId('cl'), id, amount, amount > 0 ? 'issue' : 'adjust', newBalance,
             actor.type, actor.id, body.note || null, now),
    ]);
    await logAudit(env, request, actor, 'reseller.credits',
      { type: 'reseller', id }, { balance: target.credit_balance }, { amount, balance: newBalance });
    return jsonResp({ credit_balance: newBalance, delta: amount });
  }

  // --- REVENDEUR : transfert depuis SON solde vers un de SES enfants ---
  if (target.parent_reseller_id !== user.sub) {
    return errResp('forbidden', 'Ce revendeur n\'est pas votre sous-revendeur', 403);
  }
  const parent = await env.DB
    .prepare('SELECT credit_balance FROM resellers WHERE id = ?').bind(user.sub).first();
  let parentAfter; let childAfter;
  if (amount > 0) {
    // Donner au sous-revendeur.
    if (parent.credit_balance < amount) {
      return errResp('insufficient_credits',
        `Credits insuffisants (besoin ${amount}, solde ${parent.credit_balance})`, 402);
    }
    parentAfter = parent.credit_balance - amount;
    childAfter = target.credit_balance + amount;
  } else {
    // Reprendre au sous-revendeur (amount negatif).
    const take = -amount;
    if (target.credit_balance < take) {
      return errResp('insufficient_credits',
        'Le sous-revendeur n\'a pas assez de credits a reprendre', 400);
    }
    childAfter = target.credit_balance + amount; // amount < 0
    parentAfter = parent.credit_balance + take;
  }
  await env.DB.batch([
    env.DB.prepare('UPDATE resellers SET credit_balance = ? WHERE id = ?').bind(childAfter, id),
    env.DB.prepare('UPDATE resellers SET credit_balance = ? WHERE id = ?').bind(parentAfter, user.sub),
    env.DB.prepare(
      `INSERT INTO credit_ledger
        (id, reseller_id, delta, reason, balance_after, actor_type, actor_id, note, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(genId('cl'), id, amount, amount > 0 ? 'transfer_in' : 'transfer_out',
           childAfter, actor.type, actor.id, body.note || null, now),
    env.DB.prepare(
      `INSERT INTO credit_ledger
        (id, reseller_id, delta, reason, balance_after, actor_type, actor_id, note, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(genId('cl'), user.sub, -amount, amount > 0 ? 'transfer_out' : 'transfer_in',
           parentAfter, actor.type, actor.id, body.note || null, now),
  ]);
  await logAudit(env, request, actor, 'reseller.credits.transfer',
    { type: 'reseller', id }, { balance: target.credit_balance }, { amount, balance: childAfter });
  return jsonResp({ credit_balance: childAfter, delta: amount, your_balance: parentAfter });
}

async function handleResellerCreditsList(env, id, user) {
  // Owner : n'importe lequel. Revendeur : soi-meme ou un enfant direct.
  if (user && user.role === 'reseller' && id !== user.sub) {
    const t = await env.DB
      .prepare('SELECT parent_reseller_id FROM resellers WHERE id = ?').bind(id).first();
    if (!t || t.parent_reseller_id !== user.sub) {
      return errResp('forbidden', 'Forbidden', 403);
    }
  }
  const rs = await env.DB
    .prepare(
      `SELECT id, delta, reason, balance_after, ref_device_mac, ref_license_id, note, created_at
       FROM credit_ledger WHERE reseller_id = ? ORDER BY created_at DESC LIMIT 300`,
    )
    .bind(id)
    .all();
  return jsonResp({ items: rs.results || [] });
}

// ----- DEMANDES DE RECHARGEMENT (achat de crédit) -----
//  Le revendeur DEMANDE des crédits ; l'owner APPROUVE → les crédits sont
//  émis. Le revendeur ne s'auto-crédite jamais (« c'est moi seul »).
async function ensureCreditRequestsTable(env) {
  await env.DB
    .prepare(
      'CREATE TABLE IF NOT EXISTS credit_requests (' +
        'id TEXT PRIMARY KEY, reseller_id TEXT NOT NULL, amount INTEGER NOT NULL, ' +
        "status TEXT NOT NULL DEFAULT 'pending', note TEXT, " +
        'decided_by TEXT, decided_at INTEGER, created_at INTEGER NOT NULL)',
    )
    .run();
  try {
    await env.DB
      .prepare('CREATE INDEX IF NOT EXISTS idx_credit_req_status ON credit_requests(status, created_at)')
      .run();
  } catch (_) { /* index déjà présent */ }
}

async function handleCreditRequestCreate(request, env, actor, user) {
  // Réservé aux revendeurs ayant le droit « achat de crédit ».
  if (!user || user.role !== 'reseller') {
    return errResp('forbidden', 'Réservé aux revendeurs.', 403);
  }
  if (!resellerCan(user, 'buy_credits')) {
    return errResp('forbidden', "Ton compte n'a pas le droit de demander des crédits.", 403);
  }
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const amount = parseInt(body.amount, 10);
  if (!Number.isFinite(amount) || amount <= 0) {
    return errResp('bad_amount', 'amount doit être un entier positif', 400);
  }
  await ensureCreditRequestsTable(env);
  const id = genId('creq');
  const now = Date.now();
  await env.DB
    .prepare(
      "INSERT INTO credit_requests (id, reseller_id, amount, status, note, created_at) " +
        "VALUES (?, ?, ?, 'pending', ?, ?)",
    )
    .bind(id, user.sub, amount, (body.note || '').toString().slice(0, 300) || null, now)
    .run();
  await logAudit(env, request, actor, 'credit_request.create',
    { type: 'credit_request', id }, null, { amount });
  return jsonResp({ ok: true, id, amount, status: 'pending' }, 201);
}

async function handleCreditRequestsList(env, user) {
  await ensureCreditRequestsTable(env);
  if (isOwner(user)) {
    const rs = await env.DB
      .prepare(
        `SELECT cr.id, cr.reseller_id, cr.amount, cr.status, cr.note,
                cr.decided_at, cr.created_at, r.email AS reseller_email, r.name AS reseller_name
         FROM credit_requests cr LEFT JOIN resellers r ON r.id = cr.reseller_id
         ORDER BY (cr.status = 'pending') DESC, cr.created_at DESC LIMIT 200`,
      )
      .all();
    return jsonResp({ items: rs.results || [] });
  }
  if (user && user.role === 'reseller') {
    const rs = await env.DB
      .prepare(
        `SELECT id, reseller_id, amount, status, note, decided_at, created_at
         FROM credit_requests WHERE reseller_id = ? ORDER BY created_at DESC LIMIT 100`,
      )
      .bind(user.sub)
      .all();
    return jsonResp({ items: rs.results || [] });
  }
  return errResp('forbidden', 'Forbidden', 403);
}

async function handleCreditRequestDecide(request, env, id, action, actor, user) {
  await ensureCreditRequestsTable(env);
  const req = await env.DB
    .prepare('SELECT id, reseller_id, amount, status FROM credit_requests WHERE id = ?')
    .bind(id).first();
  if (!req) return errResp('not_found', 'Demande introuvable', 404);
  if (req.status !== 'pending') {
    return errResp('already_decided', 'Cette demande a déjà été traitée.', 409);
  }
  const now = Date.now();
  if (action === 'reject') {
    await env.DB
      .prepare("UPDATE credit_requests SET status = 'rejected', decided_by = ?, decided_at = ? WHERE id = ?")
      .bind(user.sub, now, id).run();
    await logAudit(env, request, actor, 'credit_request.reject', { type: 'credit_request', id }, null, null);
    return jsonResp({ ok: true, status: 'rejected' });
  }
  // approve → émettre les crédits DEPUIS LA RÉSERVE owner + marquer approuvé.
  const target = await env.DB
    .prepare('SELECT credit_balance FROM resellers WHERE id = ?').bind(req.reseller_id).first();
  if (!target) return errResp('not_found', 'Revendeur introuvable', 404);
  const pool = await getOwnerPool(env);
  if (pool < req.amount) {
    return errResp('pool_empty',
      `Réserve de crédits insuffisante (reste ${pool}). Régénère la réserve.`, 402);
  }
  await setOwnerPool(env, pool - req.amount);
  const newBalance = (target.credit_balance || 0) + req.amount;
  await env.DB.batch([
    env.DB.prepare('UPDATE resellers SET credit_balance = ? WHERE id = ?').bind(newBalance, req.reseller_id),
    env.DB.prepare(
      `INSERT INTO credit_ledger
        (id, reseller_id, delta, reason, balance_after, actor_type, actor_id, note, created_at)
       VALUES (?, ?, ?, 'issue', ?, ?, ?, ?, ?)`,
    ).bind(genId('cl'), req.reseller_id, req.amount, newBalance, actor.type, actor.id,
           'Demande approuvée', now),
    env.DB.prepare("UPDATE credit_requests SET status = 'approved', decided_by = ?, decided_at = ? WHERE id = ?")
      .bind(user.sub, now, id),
  ]);
  await logAudit(env, request, actor, 'credit_request.approve',
    { type: 'credit_request', id }, null, { amount: req.amount, balance: newBalance });
  return jsonResp({ ok: true, status: 'approved', credit_balance: newBalance });
}

// ----- TRÉSORERIE : réserve owner + compteur d'argent -----
async function handleTreasury(env) {
  const pool = await getOwnerPool(env);
  const cv = await getCreditValueEur(env);
  // Distribué = crédits émis vers les revendeurs (mint 'issue' positif).
  const dist = await env.DB
    .prepare("SELECT COALESCE(SUM(delta),0) AS s FROM credit_ledger WHERE reason = 'issue' AND delta > 0")
    .first();
  // Utilisés = crédits consommés par les activations/renouvellements.
  const cons = await env.DB
    .prepare("SELECT COALESCE(SUM(-delta),0) AS s FROM credit_ledger WHERE reason IN ('activation','renew') AND delta < 0")
    .first();
  const distributed = (dist && dist.s) || 0;
  const consumed = (cons && cons.s) || 0;
  const eur = (n) => Math.round(n * cv * 100) / 100;
  return jsonResp({
    pool,
    poolStart: OWNER_POOL_START,
    creditValueEur: cv,
    distributed,
    consumed,
    poolEur: eur(pool),
    distributedEur: eur(distributed),
    consumedEur: eur(consumed),
  });
}

async function handleTreasuryRegenerate(request, env, actor, user) {
  let body = {};
  try { body = await request.json(); } catch (_) { /* corps optionnel */ }
  const cur = await getOwnerPool(env);
  const add = parseInt(body.amount, 10);
  // amount fourni & positif → on AJOUTE ; sinon → on REMET à 1 000 000.
  const next = Number.isFinite(add) && add > 0 ? cur + add : OWNER_POOL_START;
  await setOwnerPool(env, next);
  // Valeur du crédit ajustable (optionnel).
  if (body.creditValueEur !== undefined) {
    const cv = parseFloat(body.creditValueEur);
    if (Number.isFinite(cv) && cv > 0) await _cfgSet(env, 'credit_value_eur', cv);
  }
  await logAudit(env, request, actor, 'treasury.regenerate',
    { type: 'treasury', id: 'pool' }, { pool: cur }, { pool: next });
  return jsonResp({ ok: true, pool: next });
}

// ----- TRANSFERT d'abonnement (ancienne MAC → nouvelle MAC) -----
//  RIGUEUR BUSINESS : un client qui a PAYÉ ne doit JAMAIS perdre son
//  accès parce que l'identifiant de son appareil a changé (nouveau
//  téléphone, réinstallation, mise à jour qui a changé l'ANDROID_ID…).
//  Ici on DÉPLACE la licence + la source de l'ancienne MAC vers la
//  nouvelle, en gardant EXACTEMENT le temps restant. GRATUIT (aucun
//  crédit débité) : changer d'appareil ne se paie pas.
async function handleDeviceTransfer(request, env, user, actor) {
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const oldMac = (body.old_mac || '').trim().toUpperCase();
  const newMac = (body.new_mac || '').trim().toUpperCase();
  const macRx = /^MK(?::[0-9A-F]{2}){5}$/i;
  if (!macRx.test(oldMac)) return errResp('bad_mac', 'Ancienne MAC invalide.', 400);
  if (!macRx.test(newMac)) return errResp('bad_mac', 'Nouvelle MAC invalide.', 400);
  if (oldMac === newMac) return errResp('same_mac', 'Les deux MAC sont identiques.', 400);

  const isReseller = user.role === 'reseller';
  const now = Date.now();

  const oldDev = await env.DB
    .prepare('SELECT id, customer_id, reseller_id FROM devices WHERE mac = ?')
    .bind(oldMac).first();
  if (!oldDev) return errResp('not_found', 'Ancienne MAC introuvable.', 404);
  if (isReseller && oldDev.reseller_id && oldDev.reseller_id !== user.sub) {
    return errResp('forbidden', 'Cet appareil ne t\'appartient pas.', 403);
  }

  // Combien de licences à déplacer (pour le retour). 0 = on déplace au
  // moins la source (utile si le client a juste réinstallé).
  const lics = await env.DB
    .prepare('SELECT id, expires_at, status FROM licenses WHERE device_id = ?')
    .bind(oldDev.id).all();
  const licRows = lics.results || [];

  // Nouveau device : on réutilise le MÊME client (identité préservée).
  let newDev = await env.DB
    .prepare('SELECT id, reseller_id FROM devices WHERE mac = ?')
    .bind(newMac).first();
  let newDeviceId;
  if (newDev) {
    if (isReseller && newDev.reseller_id && newDev.reseller_id !== user.sub) {
      return errResp('forbidden', 'La nouvelle MAC appartient à un autre revendeur.', 403);
    }
    newDeviceId = newDev.id;
    await env.DB.prepare(
      'UPDATE devices SET customer_id = ?, reseller_id = COALESCE(reseller_id, ?), block_status = NULL, last_seen_at = ? WHERE id = ?',
    ).bind(oldDev.customer_id, oldDev.reseller_id, now, newDeviceId).run();
  } else {
    newDeviceId = genId('dev');
    await env.DB.prepare(
      `INSERT INTO devices (id, customer_id, mac, label, reseller_id, first_seen_at, last_seen_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    ).bind(newDeviceId, oldDev.customer_id, newMac,
           body.label || 'Transfert', oldDev.reseller_id, now, now).run();
  }

  // Déplace les licences vers le nouveau device (temps restant intact).
  await env.DB.prepare(
    'UPDATE licenses SET device_id = ?, customer_id = ?, updated_at = ? WHERE device_id = ?',
  ).bind(newDeviceId, oldDev.customer_id, now, oldDev.id).run();

  // Déplace la source IPTV : si la nouvelle MAC en avait déjà une, on la
  // remplace par celle de l'ancienne (le client garde SES identifiants).
  try {
    await env.DB.prepare('DELETE FROM device_sources WHERE mac = ?').bind(newMac).run();
    await env.DB.prepare('UPDATE device_sources SET mac = ?, updated_at = ? WHERE mac = ?')
      .bind(newMac, now, oldMac).run();
  } catch (_) { /* pas de source à déplacer */ }

  // L'ancien appareil n'a plus de licence → il redevient inactif tout seul.
  await logAudit(env, request, actor, 'device.transfer',
    { type: 'device', id: oldDev.id },
    { old_mac: oldMac }, { new_mac: newMac, moved_licenses: licRows.length });

  return jsonResp({
    ok: true,
    old_mac: oldMac,
    new_mac: newMac,
    moved_licenses: licRows.length,
  });
}

// ----- ACTIVATION par MAC (owner ou revendeur autonome) -----
//  Trouve-ou-cree le client + le device (cle = MAC), cree OU renouvelle
//  la licence pour l'app, et DEBITE les credits du revendeur selon le
//  cout du plan. C'est l'endpoint que le portail revendeur appelle.
async function handleActivate(request, env, user, actor) {
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const mac = (body.mac || '').trim().toUpperCase();
  const plan = body.plan || 'monthly';
  const appId = body.app_id || 'app_7motion';
  if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(mac)) {
    return errResp('bad_mac', 'mac must be MK:XX:XX:XX:XX:XX', 400);
  }

  const isReseller = user.role === 'reseller';

  // ----- Plans autorisés selon le rôle (sécurité serveur) -----
  //  Les REVENDEURS ne vendent que : 1 an (1 crédit), à vie (2 crédits),
  //  et les essais gratuits (0 crédit) pour faire tester un prospect.
  //  L'activation 'monthly' (1 mois) — et 3/6 mois — est RÉSERVÉE à
  //  l'administrateur. On bloque ici côté serveur : masquer le bouton
  //  dans le panel ne suffit pas (un revendeur pourrait appeler l'API).
  const isTrialPlan = typeof plan === 'string' && plan.startsWith('trial');
  const RESELLER_PLANS = ['yearly', 'lifetime'];
  if (isReseller && !isTrialPlan && !RESELLER_PLANS.includes(plan)) {
    return errResp(
      'plan_forbidden',
      'Ce plan est réservé à l’administrateur. Les revendeurs activent 1 an (1 crédit) ou à vie (2 crédits).',
      403,
    );
  }

  // Revendeur a debiter : lui-meme s'il est revendeur ; sinon, si l'owner
  // precise un reseller_id, on debite ce revendeur (vente pour son compte).
  const chargeResellerId = isReseller ? user.sub : (body.reseller_id || null);
  const cost = await planCreditCost(env, plan);

  let resellerRow = null;
  if (chargeResellerId) {
    resellerRow = await env.DB
      .prepare('SELECT id, status, credit_balance FROM resellers WHERE id = ?')
      .bind(chargeResellerId).first();
    if (!resellerRow) return errResp('not_found', 'Reseller not found', 404);
    if (resellerRow.status !== 'active') {
      return errResp('reseller_suspended', 'Reseller is suspended', 403);
    }
    if (resellerRow.credit_balance < cost) {
      return errResp('insufficient_credits',
        `Credits insuffisants (besoin ${cost}, solde ${resellerRow.credit_balance})`, 402);
    }
  }

  const now = Date.now();
  const days = planToDays(plan, body.custom_days);

  // 1) Device par MAC (find-or-create).
  const device = await env.DB
    .prepare('SELECT id, customer_id, reseller_id FROM devices WHERE mac = ?')
    .bind(mac).first();
  let customerId; let deviceId;

  if (device) {
    // Cloisonnement : un revendeur ne peut activer que SES devices,
    // ou un device orphelin (qu'il s'approprie).
    if (isReseller && device.reseller_id && device.reseller_id !== user.sub) {
      return errResp('forbidden', 'This device belongs to another reseller', 403);
    }
    deviceId = device.id;
    customerId = device.customer_id;
    if (chargeResellerId && !device.reseller_id) {
      await env.DB
        .prepare('UPDATE devices SET reseller_id = ?, last_seen_at = ? WHERE id = ?')
        .bind(chargeResellerId, now, deviceId).run();
    }
  } else {
    customerId = genId('cus');
    deviceId = genId('dev');
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO customers (id, email, name, phone, reseller_id, notes, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(customerId, body.customer_email || null,
             body.customer_name || ('Client ' + mac.slice(-5)),
             null, chargeResellerId, null, now, now),
      env.DB.prepare(
        `INSERT INTO devices (id, customer_id, mac, label, reseller_id, first_seen_at, last_seen_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      ).bind(deviceId, customerId, mac, body.label || null, chargeResellerId, now, now),
    ]);
  }

  // 2) Licence (device, app) : renouvelle si elle existe, sinon cree.
  const existing = await env.DB
    .prepare('SELECT id, expires_at FROM licenses WHERE device_id = ? AND app_id = ?')
    .bind(deviceId, appId).first();
  let licenseId; let finalExpiry; let renewed = false;

  if (existing) {
    renewed = true;
    licenseId = existing.id;
    const base = existing.expires_at && existing.expires_at > now ? existing.expires_at : now;
    finalExpiry = days === null ? null : base + days * 24 * 60 * 60 * 1000;
    await env.DB.prepare(
      `UPDATE licenses
       SET status='active', plan=?, expires_at=?, reseller_id=COALESCE(reseller_id, ?), updated_at=?
       WHERE id=?`,
    ).bind(plan, finalExpiry, chargeResellerId, now, licenseId).run();
  } else {
    licenseId = genId('lic');
    finalExpiry = days === null ? null : now + days * 24 * 60 * 60 * 1000;
    await env.DB.prepare(
      `INSERT INTO licenses
        (id, customer_id, device_id, app_id, status, plan, started_at,
         expires_at, auto_renew, reseller_id, created_at, updated_at)
       VALUES (?, ?, ?, ?, 'active', ?, ?, ?, 0, ?, ?, ?)`,
    ).bind(licenseId, customerId, deviceId, appId, plan, now, finalExpiry, chargeResellerId, now, now).run();
  }

  // 2b) Activer = degeler : si l'appareil etait gele/banni, l'activation
  // (le client a paye) le remet en service. Sinon le block_status
  // primerait sur la licence et l'app resterait bloquee.
  await env.DB.prepare('UPDATE devices SET block_status = NULL WHERE id = ?')
    .bind(deviceId).run();

  // 2c) Source(s) IPTV (Xtream/M3U) optionnelle(s) : si l'appel joint un
  // objet `source` (unique) OU un tableau `sources` (TRIO 1-3), on l'assigne
  // à la MAC. L'app la récupèrera via GET /api/device-source/:mac et la
  // chargera automatiquement. NB : `upsertDeviceSource` attend un TABLEAU —
  // on enveloppe donc toujours (bug historique : un objet seul → `.map`
  // indéfini → 500, l'activation échouait ET le push temps réel ne partait
  // pas puisque withRt ne publie que sur 2xx).
  const rawSources = Array.isArray(body.sources)
    ? body.sources
    : (body.source ? [body.source] : []);
  if (rawSources.length > 0) {
    const normalized = [];
    for (const raw of rawSources.slice(0, 3)) {
      const norm = normalizeSource(raw);
      if (norm.error) return errResp('bad_source', norm.error, 400);
      normalized.push(norm.source);
    }
    await upsertDeviceSource(env, mac, normalized);
  }

  // 3) Debit credits (revendeur) + ecriture au ledger, atomiquement.
  let balanceAfter = null;
  if (chargeResellerId && cost > 0) {
    balanceAfter = resellerRow.credit_balance - cost;
    await env.DB.batch([
      env.DB.prepare('UPDATE resellers SET credit_balance = ? WHERE id = ?').bind(balanceAfter, chargeResellerId),
      env.DB.prepare(
        `INSERT INTO credit_ledger
          (id, reseller_id, delta, reason, balance_after, ref_license_id,
           ref_device_mac, actor_type, actor_id, note, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(genId('cl'), chargeResellerId, -cost, renewed ? 'renew' : 'activation',
             balanceAfter, licenseId, mac, actor.type, actor.id, plan, now),
    ]);
  }

  await logAudit(env, request, actor, renewed ? 'activate.renew' : 'activate.create',
    { type: 'license', id: licenseId }, null,
    { mac, plan, app_id: appId, cost, reseller_id: chargeResellerId });

  return jsonResp({
    ok: true,
    license_id: licenseId,
    device_id: deviceId,
    customer_id: customerId,
    mac,
    plan,
    expires_at: finalExpiry,
    credits_charged: chargeResellerId ? cost : 0,
    credit_balance: balanceAfter,
    renewed,
  }, 201);
}
