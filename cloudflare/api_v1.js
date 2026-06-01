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
    if (parts[1] === 'me' && request.method === 'GET') {
      const a = await requireAuth(request, env);
      if (a.error) return a.error;
      return jsonResp({ user: a.user });
    }
  }

  // --- Tout le reste requiert un JWT ---
  const a = await requireAuth(request, env);
  if (a.error) return a.error;
  const actor = { type: 'admin', id: a.user.sub };

  // /stats/overview
  if (parts[0] === 'stats' && parts[1] === 'overview') {
    return handleStatsOverview(env);
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

  // /customers
  if (parts[0] === 'customers') {
    if (parts.length === 1) {
      if (request.method === 'GET') return handleCustomersList(request, env);
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
      if (request.method === 'GET') return handleDevicesList(request, env);
      if (request.method === 'POST') return handleDevicesCreate(request, env, actor);
    }
  }

  // /licenses
  if (parts[0] === 'licenses') {
    if (parts.length === 1) {
      if (request.method === 'GET') return handleLicensesList(request, env);
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
  const ok = await verifyPassword(password, row.password_hash);
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

async function handleStatsOverview(env) {
  const now = Date.now();
  const month = 30 * 24 * 60 * 60 * 1000;

  const [
    customers,
    devices,
    licenses,
    activeLicenses,
    expiredLicenses,
    apps,
    paidLastMonth,
  ] = await Promise.all([
    env.DB.prepare('SELECT COUNT(*) as n FROM customers').first(),
    env.DB.prepare('SELECT COUNT(*) as n FROM devices').first(),
    env.DB.prepare('SELECT COUNT(*) as n FROM licenses').first(),
    env.DB
      .prepare(
        `SELECT COUNT(*) as n FROM licenses
         WHERE status = 'active' AND (expires_at IS NULL OR expires_at > ?)`,
      )
      .bind(now)
      .first(),
    env.DB
      .prepare(
        `SELECT COUNT(*) as n FROM licenses
         WHERE expires_at IS NOT NULL AND expires_at <= ?`,
      )
      .bind(now)
      .first(),
    env.DB.prepare('SELECT COUNT(*) as n FROM apps WHERE is_active = 1').first(),
    env.DB
      .prepare(
        `SELECT COALESCE(SUM(amount_cents), 0) as cents
         FROM payments WHERE status = 'succeeded' AND paid_at > ?`,
      )
      .bind(now - month)
      .first(),
  ]);

  return jsonResp({
    customers: customers.n,
    devices: devices.n,
    licenses: licenses.n,
    active_licenses: activeLicenses.n,
    expired_licenses: expiredLicenses.n,
    apps: apps.n,
    revenue_30d_cents: paidLastMonth.cents,
  });
}

// =========================================================
//  APPS HANDLERS
// =========================================================

async function handleAppsList(env) {
  const rs = await env.DB
    .prepare(
      `SELECT id, name, package_name, primary_color, tagline,
              default_iptv_server, default_playlist_type, pricing_json,
              is_active, created_at, updated_at
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
           is_active, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
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
//  CUSTOMERS HANDLERS
// =========================================================

async function handleCustomersList(request, env) {
  const url = new URL(request.url);
  const search = (url.searchParams.get('q') || '').trim();
  let sql = `SELECT id, email, name, phone, reseller_id, created_at
             FROM customers`;
  const binds = [];
  if (search) {
    sql += ` WHERE email LIKE ? OR name LIKE ? OR phone LIKE ?`;
    binds.push(`%${search}%`, `%${search}%`, `%${search}%`);
  }
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
//  DEVICES HANDLERS
// =========================================================

async function handleDevicesList(request, env) {
  const url = new URL(request.url);
  const q = (url.searchParams.get('q') || '').trim();
  let sql = `SELECT d.id, d.customer_id, d.mac, d.label,
                    d.first_seen_at, d.last_seen_at,
                    c.name as customer_name, c.email as customer_email
             FROM devices d LEFT JOIN customers c ON d.customer_id = c.id`;
  const binds = [];
  if (q) {
    sql += ` WHERE d.mac LIKE ? OR d.label LIKE ? OR c.name LIKE ?`;
    binds.push(`%${q}%`, `%${q}%`, `%${q}%`);
  }
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
    case 'trial': return 10;
    default: return 30;
  }
}

async function handleLicensesList(request, env) {
  const url = new URL(request.url);
  const status = url.searchParams.get('status');
  const appId = url.searchParams.get('app_id');
  let sql = `SELECT l.id, l.customer_id, l.device_id, l.app_id, l.status,
                    l.plan, l.started_at, l.expires_at, l.auto_renew,
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
