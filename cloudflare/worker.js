// =========================================================
//  7 MOTION — Cloudflare Worker (backend admin + clients)
// =========================================================
//
//  Mini backend serverless qui remplace le hack GitHub Gist.
//  Tourne sur le free tier Cloudflare (100 000 req/jour suffisent
//  largement pour des centaines de clients).
//
//  ENDPOINTS
//  ─────────
//
//  Côté ADMIN (protégés par X-Admin-Secret) :
//
//    GET    /admin/clients           → liste tous les clients
//    POST   /admin/clients           → crée un client
//    GET    /admin/clients/:mac      → détails d'un client
//    PUT    /admin/clients/:mac      → met à jour un client
//    DELETE /admin/clients/:mac      → supprime un client
//
//  Côté CLIENT (pas d'auth, le MAC est l'identifiant) :
//
//    GET    /config/:mac             → renvoie le bloc playlists
//                                       du client, ou 404 si
//                                       jamais configuré
//
//  Le client app appelle /config/<sa-mac> toutes les 30 min.
//  L'admin app gère les /admin/clients avec son X-Admin-Secret.
//
//  STORAGE
//  ───────
//
//  Workers KV : key = `client:<MAC>` → value = JSON du client.
//  Key spéciale `_index` = liste des MAC enregistrées (pour
//  alimenter la vue admin "Liste des clients").
//
//  SÉCURITÉ
//  ────────
//
//    - X-Admin-Secret obligatoire pour tous les /admin/*. Comparé
//      en temps constant pour éviter les attaques timing.
//    - Le secret est stocké en variable d'environnement
//      `ADMIN_SECRET` (settings du Worker côté Cloudflare).
//      JAMAIS hardcodé ici.
//    - Pas d'auth sur /config/:mac : le MAC est l'identifiant (~10^14
//      combinaisons en hex, brute-force ~impossible avec le
//      rate-limit Cloudflare gratuit). Le pire qui peut arriver
//      si un MAC fuite : un attaquant voit les URLs Xtream d'UN
//      client — incident isolé, pas un breach général.
//    - CORS permissif (Access-Control-Allow-Origin: *) parce que
//      l'app mobile n'envoie pas de cookie de toute façon.
//
//  DÉPLOIEMENT — voir README.md à côté de ce fichier.
// =========================================================

// ----- Constantes APK / téléchargement -----
//
// URL du GitHub release qui pointe TOUJOURS vers le dernier APK
// (le tag "latest" est overwrite à chaque push du workflow CI,
//  donc le binaire qui répond à cette URL est toujours à jour).
const APK_URL =
  'https://github.com/manzilionellm-dotcom/tvking/releases/download/latest/app-debug.apk';

// Landing page HTML servie sur la racine. Style Maison Noir :
// fond noir, ember rouge, typo sobre. Optimisée pour téléphones
// ET pour les navigateurs intégrés des Smart TV (pas de JS).
const LANDING_HTML = `<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>7 MOTION — Téléchargement</title>
  <meta name="description" content="Lecteur IPTV premium 7 MOTION. Téléchargez l'APK Android/Fire TV/Android TV.">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: #0A0A0C;
      color: #F2F2F4;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
    }
    .card {
      max-width: 520px;
      width: 100%;
      padding: 32px;
      border-radius: 18px;
      background: linear-gradient(180deg, #16161A 0%, #0E0E12 100%);
      border: 1px solid rgba(214, 174, 96, 0.25);
      box-shadow: 0 0 40px rgba(214, 174, 96, 0.08);
    }
    .brand {
      display: flex;
      align-items: baseline;
      gap: 10px;
      justify-content: center;
      margin-bottom: 8px;
    }
    .brand h1 {
      font-size: 32px;
      letter-spacing: 4px;
      font-weight: 700;
      color: #F2F2F4;
    }
    .badge {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 22px;
      height: 22px;
      border-radius: 50%;
      background: #3897F0;
      color: white;
      font-size: 14px;
      font-weight: 900;
    }
    .tagline {
      text-align: center;
      color: #8E8E94;
      font-size: 12px;
      letter-spacing: 2px;
      margin-bottom: 32px;
    }
    .dl {
      display: block;
      width: 100%;
      padding: 18px;
      border-radius: 12px;
      background: #D6AE60;
      color: #0A0A0C;
      text-align: center;
      font-size: 18px;
      font-weight: 700;
      text-decoration: none;
      letter-spacing: 0.5px;
      transition: transform 0.15s;
    }
    .dl:hover { transform: translateY(-1px); }
    .dl small {
      display: block;
      font-size: 11px;
      font-weight: 500;
      opacity: 0.8;
      margin-top: 4px;
      letter-spacing: 1px;
    }
    .steps {
      margin-top: 28px;
      padding-top: 20px;
      border-top: 1px solid rgba(214, 174, 96, 0.18);
    }
    .steps h2 {
      font-size: 13px;
      letter-spacing: 1.5px;
      color: #D6AE60;
      margin-bottom: 12px;
      text-transform: uppercase;
    }
    .steps ol {
      padding-left: 22px;
      color: #C4C4CA;
      font-size: 13px;
      line-height: 1.7;
    }
    .steps code {
      background: #1F1F25;
      padding: 2px 6px;
      border-radius: 4px;
      font-size: 12px;
      color: #D6AE60;
    }
    .legal {
      margin-top: 24px;
      padding-top: 16px;
      border-top: 1px solid rgba(214, 174, 96, 0.12);
      font-size: 10.5px;
      color: #6E6E74;
      line-height: 1.5;
      text-align: center;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="brand">
      <h1>7 MOTION</h1>
      <span class="badge">&check;</span>
    </div>
    <p class="tagline">THE FEW &middot; NOT FOR EVERYONE</p>

    <a class="dl" href="/dl">
      Télécharger l'APK
      <small>Android &middot; Fire TV &middot; Android TV</small>
    </a>

    <div class="steps">
      <h2>Installation via Downloader</h2>
      <ol>
        <li>Lance <strong>Downloader</strong> sur ta Fire TV / Android TV</li>
        <li>Tape l'URL : <code>7themotion.com/dl</code>
            <br>ou un code court : <code>7themotion.com/1</code>, <code>7themotion.com/666666</code></li>
        <li>Bouton <strong>GO</strong> &rarr; téléchargement automatique</li>
        <li>Bouton <strong>Install</strong> quand le téléchargement finit</li>
      </ol>
    </div>

    <p class="legal">
      7 MOTION ne vend, ne distribue et ne fournit aucun flux IPTV,
      aucune chaîne ni aucun contenu. Apportez votre propre
      abonnement auprès du fournisseur de votre choix.
    </p>
  </div>
</body>
</html>`;

const HTML_HEADERS = {
  'Content-Type': 'text/html; charset=utf-8',
  'Cache-Control': 'public, max-age=300',
  'Access-Control-Allow-Origin': '*',
};

const JSON_HEADERS = {
  'Content-Type': 'application/json; charset=utf-8',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'X-Admin-Secret, Content-Type',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
  'Cache-Control': 'no-store',
};

const TEXT_HEADERS = {
  'Content-Type': 'text/plain; charset=utf-8',
  'Access-Control-Allow-Origin': '*',
};

// Regex MAC virtuelle 7 MOTION : MK:XX:XX:XX:XX:XX en hex.
const MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/i;

// ----- Helpers réponse -----

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function notFound(msg = 'Not found') {
  return new Response(msg, { status: 404, headers: TEXT_HEADERS });
}

function badRequest(msg) {
  return json({ error: msg }, 400);
}

function unauthorized() {
  return json({ error: 'unauthorized' }, 401);
}

// ----- Comparaison en temps constant pour le secret admin -----

function safeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

function checkAdmin(request, env) {
  const provided = request.headers.get('X-Admin-Secret') || '';
  const expected = env.ADMIN_SECRET || '';
  if (!expected) {
    // L'admin n'a pas configuré son secret côté Worker → on
    // refuse tout pour ne pas exposer une instance sans protection.
    return false;
  }
  return safeEqual(provided, expected);
}

// ----- KV helpers -----

async function readIndex(env) {
  const raw = await env.KV_7MOTION.get('_index');
  if (!raw) return [];
  try {
    return JSON.parse(raw);
  } catch (_) {
    return [];
  }
}

async function writeIndex(env, list) {
  // Dédup + tri par added_at descendant si dispo
  const dedup = Array.from(new Set(list));
  await env.KV_7MOTION.put('_index', JSON.stringify(dedup));
}

async function readClient(env, mac) {
  const raw = await env.KV_7MOTION.get(`client:${mac}`);
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch (_) {
    return null;
  }
}

async function writeClient(env, mac, data) {
  await env.KV_7MOTION.put(`client:${mac}`, JSON.stringify(data));
  const idx = await readIndex(env);
  if (!idx.includes(mac)) {
    idx.push(mac);
    await writeIndex(env, idx);
  }
}

async function deleteClient(env, mac) {
  await env.KV_7MOTION.delete(`client:${mac}`);
  const idx = await readIndex(env);
  await writeIndex(env, idx.filter((m) => m !== mac));
}

// ----- Validation -----

function validateClientBody(body) {
  if (!body || typeof body !== 'object') return 'body must be a JSON object';
  if (!body.mac || !MAC_RX.test(body.mac)) {
    return 'invalid mac, expected MK:XX:XX:XX:XX:XX';
  }
  if (!Array.isArray(body.playlists) || body.playlists.length === 0) {
    return 'playlists must be a non-empty array';
  }
  for (const p of body.playlists) {
    if (!p || typeof p !== 'object') return 'each playlist must be an object';
    if (p.type !== 'm3u' && p.type !== 'xtream') {
      return 'playlist.type must be "m3u" or "xtream"';
    }
    if (p.type === 'm3u' && !p.url) {
      return 'm3u playlist requires url';
    }
    if (p.type === 'xtream' && (!p.server || !p.username || !p.password)) {
      return 'xtream playlist requires server, username, password';
    }
  }
  return null; // valid
}

// ----- Handlers -----

async function handleGetClientsList(env) {
  const macs = await readIndex(env);
  const out = [];
  for (const mac of macs) {
    const data = await readClient(env, mac);
    if (data) out.push({ mac, ...data });
  }
  // Plus récents d'abord
  out.sort((a, b) => (b.added_at || 0) - (a.added_at || 0));
  return json(out);
}

async function handleGetClient(env, mac) {
  const data = await readClient(env, mac);
  if (!data) return notFound(`Client ${mac} introuvable`);
  return json({ mac, ...data });
}

async function handleUpsertClient(request, env, mac) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return badRequest('invalid JSON body');
  }
  // Si la MAC vient de l'URL, on l'aligne dans le body
  if (mac) body.mac = mac;

  const err = validateClientBody(body);
  if (err) return badRequest(err);

  const now = Date.now();
  const existing = await readClient(env, body.mac);
  const merged = {
    name: body.name || existing?.name || '',
    playlists: body.playlists,
    added_at: existing?.added_at || now,
    updated_at: now,
  };
  await writeClient(env, body.mac, merged);
  return json({ ok: true, mac: body.mac, ...merged });
}

async function handleDeleteClient(env, mac) {
  await deleteClient(env, mac);
  return new Response(null, { status: 204, headers: JSON_HEADERS });
}

async function handlePublicConfig(env, mac) {
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  const data = await readClient(env, mac);
  if (!data) return notFound(`Aucun playlist configurée pour ${mac}`);
  // On ne renvoie au client que ce dont il a besoin (pas les
  // métadonnées admin comme added_at).
  return json({
    name: data.name || '',
    playlists: data.playlists || [],
  });
}

// ----- Routeur -----

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: JSON_HEADERS });
    }

    const url = new URL(request.url);
    const segments = url.pathname.split('/').filter(Boolean);

    // /config/:mac — public
    if (segments[0] === 'config' && segments.length === 2) {
      if (request.method !== 'GET') {
        return badRequest('only GET supported on /config/:mac');
      }
      return handlePublicConfig(env, segments[1]);
    }

    // /admin/clients — auth requise
    if (segments[0] === 'admin' && segments[1] === 'clients') {
      if (!checkAdmin(request, env)) return unauthorized();

      // /admin/clients
      if (segments.length === 2) {
        if (request.method === 'GET') return handleGetClientsList(env);
        if (request.method === 'POST') return handleUpsertClient(request, env, null);
        return badRequest('method not allowed');
      }
      // /admin/clients/:mac
      if (segments.length === 3) {
        const mac = segments[2];
        if (!MAC_RX.test(mac)) return badRequest('invalid mac in URL');
        if (request.method === 'GET') return handleGetClient(env, mac);
        if (request.method === 'PUT') return handleUpsertClient(request, env, mac);
        if (request.method === 'DELETE') return handleDeleteClient(env, mac);
        return badRequest('method not allowed');
      }
    }

    // / — landing page HTML (téléchargement + tuto Downloader)
    if (segments.length === 0) {
      return new Response(LANDING_HTML, { headers: HTML_HEADERS });
    }

    // /dl — redirection 302 vers l'APK GitHub release.
    // Downloader (Fire TV / Android TV) suit le redirect et télécharge
    // le binaire. URL publique courte et propre, sans github visible.
    // Variante /dl/release pour aliasing futur (release vs beta).
    if (
      (segments.length === 1 && segments[0] === 'dl') ||
      (segments.length === 2 && segments[0] === 'dl' && segments[1] === 'release')
    ) {
      return Response.redirect(APK_URL, 302);
    }

    // /install — alias canal alternatif (utile si on veut router
    // par device class plus tard : /install?tv=firetv, etc.)
    if (segments.length === 1 && segments[0] === 'install') {
      return Response.redirect(APK_URL, 302);
    }

    // ===== CODES VANITY DOWNLOADER =====
    //
    // Tout segment unique non réservé est traité comme un code
    // vanity choisi par l'admin pour ses clients. Exemples :
    //
    //   https://7themotion.com/666666  → 302 APK
    //   https://7themotion.com/88888   → 302 APK
    //   https://7themotion.com/1       → 302 APK (ultra court)
    //   https://7themotion.com/x       → 302 APK (1 lettre)
    //
    // Avantage vs codes officiels AFTVnews (5 chiffres aléatoires) :
    //  - Admin choisit lui-même son code, peut viser un nombre
    //    mémorable (anniversaire, repeat digit, simple "1"…)
    //  - 100 % sous son contrôle (pas révocable par un tiers)
    //  - Marche sur n'importe quel client HTTP (Downloader, navigateur,
    //    curl, wget, lecteurs APK alternatifs…)
    //
    // Sécurité : on filtre les préfixes réservés pour ne pas
    // collisionner avec /admin/* et /config/*. On accepte tout
    // ce qui n'est PAS dans cette liste — y compris caractères
    // unicode, espaces encodés, etc. — parce que Downloader ne
    // supporte que ASCII de toute façon.
    const RESERVED = new Set([
      'admin', 'config', 'dl', 'install',
      'favicon.ico', 'robots.txt', 'sitemap.xml',
    ]);
    if (segments.length === 1 && !RESERVED.has(segments[0].toLowerCase())) {
      return Response.redirect(APK_URL, 302);
    }

    return notFound('Unknown route. Try /, /dl, /config/:mac or /admin/clients');
  },
};
