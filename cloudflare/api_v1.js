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

async function signJwt(payload, secret, expMinutes = 60 * 24 * 7) {
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

async function verifyJwt(token, secret) {
  try {
    const [h, p, s] = token.split('.');
    if (!h || !p || !s) return null;
    const expectedSig = b64url(await hmacSha256(secret, `${h}.${p}`));
    if (s !== expectedSig) return null;
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
    return b64url(bits) === hashB64;
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
  const claims = await verifyJwt(m[1], env.ADMIN_SECRET || 'dev-secret');
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
async function bootstrapSuperAdminIfNeeded(env) {
  const count = await env.DB.prepare(
    'SELECT COUNT(*) as n FROM admin_users',
  ).first();
  if (count && count.n > 0) return false;
  const id = genId('adm');
  const now = Date.now();
  const pwd = await hashPassword(env.ADMIN_SECRET || 'change-me');
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

// =========================================================
//  ROUTER PRINCIPAL — point d'entree depuis worker.js
// =========================================================
//  worker.js fait : `if (path.startsWith('/api/v1/')) return apiV1(request, env)`
//  On parse ici la suite du path et on dispatch.
// =========================================================

export async function apiV1(request, env) {
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: JSON_HEADERS });
  }
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
    if (parts.length === 1) {
      if (request.method === 'GET') return handleResellersList(env, a.user);
      if (request.method === 'POST') return handleResellersCreate(request, env, actor, a.user);
    }
    if (parts.length === 2) {
      const rid = parts[1];
      if (request.method === 'GET') return handleResellersGet(env, rid, a.user);
      if (request.method === 'PATCH') return handleResellersUpdate(request, env, rid, actor, a.user);
    }
    if (parts.length === 3 && parts[2] === 'credits') {
      const rid = parts[1];
      if (request.method === 'POST') return handleResellerCreditsIssue(request, env, rid, actor, a.user);
      if (request.method === 'GET') return handleResellerCreditsList(env, rid, a.user);
    }
  }

  // /activate — activer un appareil par sa MAC (owner OU revendeur).
  // Cree client+device+licence et debite les credits du revendeur.
  if (parts[0] === 'activate' && parts.length === 1 && request.method === 'POST') {
    return handleActivate(request, env, a.user, actor);
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
    if (parts.length === 1) {
      if (request.method === 'GET') return handleServersList(env);
      if (request.method === 'POST') return handleServersCreate(request, env, actor);
    }
    if (parts.length === 2) {
      const sid = parts[1];
      if (request.method === 'PATCH') return handleServersUpdate(request, env, sid, actor);
      if (request.method === 'DELETE') return handleServersDelete(request, env, sid, actor);
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
    if (parts.length === 1) {
      if (request.method === 'GET') return handleAnnouncementsList(env);
      if (request.method === 'POST') {
        return handleAnnouncementsCreate(request, env, actor);
      }
      if (request.method === 'DELETE') {
        return handleAnnouncementsClear(env, actor, request);
      }
    }
    if (parts.length === 2 && request.method === 'DELETE') {
      return handleAnnouncementsDelete(env, parts[1], actor, request);
    }
  }

  // /home-layout — accueil dynamique (Module 1/8). Owner uniquement.
  if (parts[0] === 'home-layout') {
    if (a.user.role !== 'super_admin') {
      return errResp('forbidden', 'Owner only', 403);
    }
    if (parts.length === 1) {
      if (request.method === 'GET') return handleHomeLayoutGet(env);
      if (request.method === 'PUT') return handleHomeLayoutSave(request, env, actor);
    }
    if (parts.length === 2 && parts[1] === 'history' && request.method === 'GET') {
      return handleHomeLayoutHistory(env);
    }
    if (parts.length === 2 && parts[1] === 'restore' && request.method === 'POST') {
      return handleHomeLayoutRestore(request, env, actor);
    }
  }

  // /force-update — mise à jour forcée (bouton du panel). Owner uniquement.
  if (parts[0] === 'force-update') {
    if (a.user.role !== 'super_admin') {
      return errResp('forbidden', 'Owner only', 403);
    }
    if (parts.length === 1) {
      if (request.method === 'GET') return handleForceUpdateGet(env);
      if (request.method === 'POST') return handleForceUpdatePost(request, env, actor);
    }
  }

  // /sources/:mac — source IPTV (Xtream/M3U) assignée à un appareil
  // par sa MAC, poussée à l'app. Admin ET revendeurs (chacun provisionne
  // ses clients). GET pour relire, PUT pour (ré)assigner, DELETE pour
  // retirer.
  if (parts[0] === 'sources' && parts.length === 2) {
    const mac = parts[1];
    if (request.method === 'GET') return handleSourceGet(env, mac);
    if (request.method === 'PUT') return handleSourcePut(request, env, mac, actor);
    if (request.method === 'DELETE') return handleSourceDelete(request, env, mac, actor);
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

  // /devices
  if (parts[0] === 'devices') {
    if (parts.length === 1) {
      if (request.method === 'GET') return handleDevicesList(request, env, a.user);
      if (request.method === 'POST') return handleDevicesCreate(request, env, actor);
    }
    if (parts.length === 2) {
      const did = parts[1];
      // Geler / bannir / reactiver (block_status).
      if (request.method === 'PATCH') return handleDeviceUpdate(request, env, did, actor, a.user);
      // Supprimer la MAC.
      if (request.method === 'DELETE') return handleDeviceDelete(env, did, actor, a.user);
    }
  }

  // /licenses
  if (parts[0] === 'licenses') {
    if (parts.length === 1) {
      if (request.method === 'GET') return handleLicensesList(request, env, a.user);
      if (request.method === 'POST') return handleLicensesCreate(request, env, actor);
    }
    if (parts.length === 2) {
      const id = parts[1];
      if (request.method === 'PATCH') return handleLicensesUpdate(request, env, id, actor);
    }
    if (parts.length === 3 && parts[2] === 'renew') {
      return handleLicensesRenew(request, env, parts[1], actor);
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
  await env.DB
    .prepare('UPDATE admin_users SET last_login_at = ? WHERE id = ?')
    .bind(Date.now(), row.id)
    .run();

  const token = await signJwt(
    { sub: row.id, email: row.email, role: row.role, name: row.name },
    env.ADMIN_SECRET || 'dev-secret',
  );
  return jsonResp({
    token,
    user: { id: row.id, email: row.email, name: row.name, role: row.role },
  });
}

// =========================================================
//  STATS / DASHBOARD
// =========================================================

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
//  APPS HANDLERS
// =========================================================

async function handleAppsList(env) {
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
  for (const col of ['kind TEXT', 'cta TEXT']) {
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
      'SELECT id, title, body, url, kind, cta, created_at FROM app_broadcasts ' +
        'ORDER BY id DESC LIMIT 20'
    )
    .all();
  return jsonResp({ items: rs.results || [] });
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
  if (!title && !msg) {
    return errResp('missing_fields', 'title or body required', 400);
  }
  const now = Date.now();
  const res = await env.DB
    .prepare(
      'INSERT INTO app_broadcasts (title, body, url, kind, cta, created_at) ' +
        'VALUES (?, ?, ?, ?, ?, ?)'
    )
    .bind(title, msg, urlVal, kind, cta, now)
    .run();
  const id = (res.meta && res.meta.last_row_id) || null;
  await logAudit(env, request, actor, 'announcement.create',
    { type: 'announcement', id }, null, { title, body: msg, kind });
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

async function handleForceUpdateGet(env) {
  await ensureAppConfigTable(env);
  return jsonResp({
    minBuildTs: await _cfgGet(env, 'min_build_ts'),
    latestBuildTs: await _cfgGet(env, 'latest_build_ts'),
  });
}

async function handleForceUpdatePost(request, env, actor) {
  await ensureAppConfigTable(env);
  let body;
  try { body = await request.json(); } catch (_) {
    return errResp('bad_json', 'Invalid JSON body', 400);
  }
  const action = (body.action || '').toString();
  if (action === 'force') {
    const latest = await _cfgGet(env, 'latest_build_ts');
    if (!latest) {
      return errResp('no_build',
        'Aucun build récent détecté. Ouvre la dernière app une fois '
        + 'pour qu\'elle se signale, puis réessaie.', 400);
    }
    await _cfgSet(env, 'min_build_ts', latest);
    await logAudit(env, request, actor, 'force_update.on',
      { type: 'app_config', id: null }, null, { min_build_ts: latest });
    return jsonResp({ ok: true, minBuildTs: latest });
  }
  if (action === 'disable') {
    await _cfgSet(env, 'min_build_ts', 0);
    await logAudit(env, request, actor, 'force_update.off',
      { type: 'app_config', id: null }, null, null);
    return jsonResp({ ok: true, minBuildTs: 0 });
  }
  return errResp('bad_action', "action doit être 'force' ou 'disable'", 400);
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
}

/// Normalise + valide un objet source venant du panel. Retourne
/// { source } prêt à insérer, ou { error } si invalide.
function normalizeSource(raw) {
  if (!raw || typeof raw !== 'object') {
    return { error: 'source object required' };
  }
  const type = (raw.type || '').trim().toLowerCase();
  const label = (raw.label || '').trim() || null;
  const epg = (raw.epg_url || '').trim() || null;
  if (type === 'xtream') {
    const server = (raw.server_url || '').trim();
    const user = (raw.username || '').trim();
    const pass = (raw.password || '').trim();
    if (!server || !user || !pass) {
      return { error: 'xtream requires server_url, username, password' };
    }
    return { source: { type, label, server_url: server, username: user, password: pass, m3u_url: null, epg_url: epg } };
  }
  if (type === 'm3u') {
    const m3u = (raw.m3u_url || '').trim();
    if (!m3u) return { error: 'm3u requires m3u_url' };
    return { source: { type, label, server_url: null, username: null, password: null, m3u_url: m3u, epg_url: epg } };
  }
  return { error: "type must be 'xtream' or 'm3u'" };
}

/// Upsert (insère ou remplace) la source d'une MAC.
async function upsertDeviceSource(env, mac, source) {
  await ensureSourcesTable(env);
  await env.DB
    .prepare(
      `INSERT INTO device_sources
         (mac, type, label, server_url, username, password, m3u_url, epg_url, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(mac) DO UPDATE SET
         type=excluded.type, label=excluded.label, server_url=excluded.server_url,
         username=excluded.username, password=excluded.password,
         m3u_url=excluded.m3u_url, epg_url=excluded.epg_url,
         updated_at=excluded.updated_at`,
    )
    .bind(mac, source.type, source.label, source.server_url, source.username,
          source.password, source.m3u_url, source.epg_url, Date.now())
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
  return jsonResp({ mac: m, source: row || null });
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
  const norm = normalizeSource(body.source || body);
  if (norm.error) return errResp('bad_source', norm.error, 400);
  await upsertDeviceSource(env, m, norm.source);
  await logAudit(env, request, actor, 'source.set',
    { type: 'device_source', id: m }, null,
    { type: norm.source.type, label: norm.source.label });
  return jsonResp({ ok: true, mac: m });
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
//  DEVICES HANDLERS
// =========================================================

async function handleDevicesList(request, env, user) {
  const url = new URL(request.url);
  const q = (url.searchParams.get('q') || '').trim();
  let sql = `SELECT d.id, d.customer_id, d.mac, d.label, d.reseller_id,
                    d.block_status, d.first_seen_at, d.last_seen_at,
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
  const dev = await env.DB
    .prepare('SELECT id, mac, reseller_id, block_status FROM devices WHERE id = ?')
    .bind(id).first();
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
  const row = await env.DB
    .prepare('SELECT id, email, password_hash, name, status, credit_balance FROM resellers WHERE email = ?')
    .bind(email)
    .first();
  if (!row || row.status !== 'active') {
    return errResp('bad_credentials', 'Invalid credentials', 401);
  }
  const ok = await verifyPassword(password, row.password_hash);
  if (!ok) return errResp('bad_credentials', 'Invalid credentials', 401);
  const token = await signJwt(
    { sub: row.id, email: row.email, role: 'reseller', name: row.name },
    env.ADMIN_SECRET || 'dev-secret',
  );
  return jsonResp({
    token,
    user: {
      id: row.id, email: row.email, name: row.name,
      role: 'reseller', credit_balance: row.credit_balance,
    },
  });
}

// ----- /me : profil de l'acteur courant (+ solde si revendeur) -----
async function handleMe(env, user) {
  if (user.role === 'reseller') {
    const r = await env.DB
      .prepare('SELECT id, email, name, status, credit_balance, commission_rate FROM resellers WHERE id = ?')
      .bind(user.sub)
      .first();
    if (!r) return errResp('not_found', 'Reseller not found', 404);
    return jsonResp({ user: { ...r, role: 'reseller' } });
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
  if (!next || next.length < 4) {
    return errResp('weak_password', 'Le nouveau mot de passe doit faire au moins 4 caracteres', 400);
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
  // Owner : tout l'arbre. Revendeur : seulement SES sous-revendeurs directs.
  const reseller = user && user.role === 'reseller';
  const where = reseller ? 'WHERE r.parent_reseller_id = ?' : '';
  const binds = reseller ? [user.sub] : [];
  const rs = await env.DB
    .prepare(
      `SELECT r.id, r.email, r.name, r.status, r.credit_balance,
              r.commission_rate, r.parent_reseller_id, r.created_at,
              (SELECT COUNT(*) FROM devices d   WHERE d.reseller_id = r.id) as devices,
              (SELECT COUNT(*) FROM licenses l  WHERE l.reseller_id = r.id) as licenses,
              (SELECT COUNT(*) FROM resellers s WHERE s.parent_reseller_id = r.id) as sub_resellers
       FROM resellers r ${where} ORDER BY r.created_at DESC LIMIT 500`,
    )
    .bind(...binds)
    .all();
  return jsonResp({ items: rs.results || [] });
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
  const initial = Math.max(0, parseInt(body.credit_balance || 0, 10) || 0);
  const commission = Number.isFinite(Number(body.commission_rate))
    ? Number(body.commission_rate) : 0.20;

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
  try {
    await env.DB
      .prepare(
        `INSERT INTO resellers
          (id, email, password_hash, name, credit_balance_cents,
           credit_balance, commission_rate, status, parent_reseller_id, created_at)
         VALUES (?, ?, ?, ?, 0, ?, ?, 'active', ?, ?)`,
      )
      .bind(id, email, hash, body.name || null, initial, commission, parentId, now)
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
  const sets = []; const vals = [];
  if (body.name !== undefined) { sets.push('name = ?'); vals.push(body.name); }
  if (body.status !== undefined) { sets.push('status = ?'); vals.push(body.status); }
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

  // --- OWNER : frappe / retire des credits (creation depuis rien) ---
  if (isOwner(user)) {
    const newBalance = target.credit_balance + amount;
    if (newBalance < 0) {
      return errResp('insufficient_credits', 'Le solde resultant serait negatif', 400);
    }
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

  // 2c) Source IPTV (Xtream/M3U) optionnelle : si le panel a joint un
  // objet `source`, on l'assigne à la MAC. L'app la récupèrera via
  // GET /api/device-source/:mac et la chargera automatiquement.
  if (body.source) {
    const norm = normalizeSource(body.source);
    if (norm.error) return errResp('bad_source', norm.error, 400);
    await upsertDeviceSource(env, mac, norm.source);
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
