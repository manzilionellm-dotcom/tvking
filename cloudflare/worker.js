// =========================================================
//  BLACK7 ROYAL — Cloudflare Worker (backend admin + clients)
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

// API v1 — App Licensing Platform (cf. cloudflare/api_v1.js)
// Routee depuis le bas du fetch() en haut de la chaine de match.
// verifyJwt est reutilise ici pour authentifier le WebSocket admin
// (/api/v1/rt/ws) AVANT de forwarder au Durable Object temps reel.
import { apiV1, verifyJwt } from './api_v1.js';
// Temps réel (cf. cloudflare/realtime.js + docs/REALTIME-PROTOCOL.md) :
// Durable Object « RealtimeHub » (WebSockets appareils + panel) et helper
// publishRt() (publication fail-open après une mutation). La classe DO
// DOIT être ré-exportée par le module d'entrée (voir export plus bas).
import { RealtimeHub, publishRt } from './realtime.js';
// Ré-export OBLIGATOIRE : wrangler.toml déclare
// [durable_objects] class_name = "RealtimeHub" — le runtime cherche la
// classe dans le module principal (main = worker.js).
export { RealtimeHub };
// Migration KV → D1 (cf. cloudflare/migrate_kv_to_d1.js) — exposee
// via POST /admin/migrate-to-d1 et protegee par X-Admin-Secret.
import { runMigration } from './migrate_kv_to_d1.js';
// Cast receiver HTML (cf. cloudflare/cast_receiver.js) — page CAF
// hebergee a /cast-receiver, URL a coller dans la Google Cast SDK
// Developer Console pour obtenir un Receiver Application ID.
import { castReceiverHtml } from './cast_receiver.js';
// Récepteur « Caster sur un écran » (cf. cloudflare/screen_receiver.js) —
// page générique servie à /e/<CODE> que n'importe quel navigateur de TV
// ouvre. Voir handleScreen() pour l'appairage + la signalisation.
import { screenReceiverHtml, screenPairHtml } from './screen_receiver.js';
// Page d'accueil officielle (site VIP) servie sur la racine /. Source éditable :
// marketing/website/index.html → régénérer cloudflare/landing.js après modif.
import { landingHtml } from './landing.js';
// « Mon espace » : page client (façon IBO Player Pro) pour gérer sa playlist.
import { portalHtml } from './portal.js';
// PWA : manifeste, service worker et icônes (le site s'installe comme une app).
import { PWA_MANIFEST, PWA_SW, PWA_ICON_192, PWA_ICON_512, PWA_APPLE_ICON, OG_IMAGE } from './pwa_assets.js';

// ----- Constantes APK / téléchargement -----
//
// URL du GitHub release qui pointe TOUJOURS vers le dernier APK
// (le tag "latest" est overwrite à chaque push du workflow CI,
//  donc le binaire qui répond à cette URL est toujours à jour).
// Depuis la release SIGNÉE, l'APK canonique s'appelle `7motion.apk`.
// `app-debug.apk` (même binaire) reste publié en parallèle comme
// filet de sécurité, mais on sert le nom propre par défaut.
// MAISON MÈRE : on sert la release `prod` — la SEULE que rien d'autre
// n'écrase (publiée uniquement par la branche claude/maison-mere-phone).
// Fini le clobber : le lien client /vip pointe toujours sur la vraie
// dernière app (MK retiré, import animé, traductions, engagement, etc.).
const APK_URL =
  'https://github.com/manzilionellm-dotcom/tvking/releases/download/prod/7motion.apk';

// APK de DeFew TV (version télévision) — release `tv-latest`. Servi via la
// route propre `/tv` (Downloader sur box Android TV / Fire TV).
// MAISON MÈRE TV : release protégée « tv-prod » (publiée uniquement par la
// branche claude/maison-mere-phone) → le lien client TV (/tv, /777…) ne peut
// plus être écrasé par une autre branche.
const TV_APK_URL =
  'https://github.com/manzilionellm-dotcom/tvking/releases/download/tv-prod/defew-tv.apk';

// NB : les wrappers WebView / NOVA+ et Red Room ont été RETIRÉS du
// projet. Deux apps sont distribuées : 7 MOTION mobile (`APK_URL`) et
// DeFew TV (`TV_APK_URL`), chacune via son lien court (/app et /tv).

// ===========================================================
//  Proxy APK avec cache edge Cloudflare (perf Downloader)
// ===========================================================
//  Pourquoi proxy plutot que 302 vers GitHub ?
//
//  Diag terrain 2026-06-01 : Downloader sur SHIELD telecharge tres
//  lentement quand le 302 envoie vers `objects.githubusercontent.com`
//  (CDN GitHub via Fastly), depuis l'Europe.
//
//  En proxy via Worker avec `cf: { cacheEverything, cacheTtl }`, la
//  1ere requete fetch depuis GitHub puis Cloudflare cache le binaire
//  sur l'edge le plus proche du user. Les requetes suivantes sont
//  servies par Cloudflare = beaucoup plus rapide (200-300 Mb/s en
//  Europe vs 5-20 Mb/s GitHub direct).
//
//  Trade-offs :
//    + Tous les users dans le meme colo Cloudflare benificient du
//      cache mutuel (un user download => les suivants vont vite).
//    + Pas de cout bandwidth (Workers free tier).
//    + Le filename qu'on impose (Content-Disposition) est
//      controle par nous, pas par GitHub.
//    - Decalage de cacheTtl secondes entre un nouveau release CI
//      et la propagation. 5 min = acceptable (les builds CI ne se
//      poussent pas plus vite).
//    - Bytes count vers la requete quotidienne Worker (100k/jour
//      free) mais pas vers la bandwidth.
//
async function proxyApk(upstreamUrl, suggestedFilename, bust) {
  let response;
  // ANTI-CACHE : si un parametre ?v=... est fourni, on contourne le cache
  // edge — on ajoute un cache-buster a l'URL upstream (nouvelle cle de
  // cache) ET on ne met (quasi) rien en cache. Utile quand un client a
  // recu un vieux fichier en cache et qu'on veut le forcer a re-telecharger
  // la toute derniere version.
  let target = upstreamUrl;
  if (bust) {
    target += (target.indexOf('?') >= 0 ? '&' : '?') + 'cb=' + encodeURIComponent(bust);
  }
  try {
    response = await fetch(target, {
      cf: {
        cacheEverything: true,
        // Sans bust : APK (200) en cache 5 min (perf), erreurs non cachees.
        // Avec bust : on ne cache (presque) rien -> toujours frais.
        cacheTtlByStatus: bust
          ? { '200-299': 1, '300-399': 1, '400-599': 0 }
          : { '200-299': 300, '300-399': 10, '400-599': 0 },
      },
    });
  } catch (e) {
    return new Response(`APK upstream unreachable: ${e?.message ?? e}`, {
      status: 502,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
    });
  }
  if (!response.ok) {
    return new Response(`APK upstream returned ${response.status}`, {
      status: 502,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
    });
  }
  // On garde la majorite des headers upstream (Content-Length,
  // Content-Type, etc.) mais on REMPLACE Content-Disposition pour
  // que Downloader sauvegarde sous un nom propre + on force le
  // Cache-Control public pour les CDN intermediaires.
  const headers = new Headers(response.headers);
  headers.set(
    'Content-Disposition',
    `attachment; filename="${suggestedFilename}"`,
  );
  headers.set('Content-Type', 'application/vnd.android.package-archive');
  headers.set('Cache-Control', 'public, max-age=300');
  return new Response(response.body, {
    status: 200,
    headers,
  });
}

// ===========================================================
//  Monétisation — Trial / Subscription / Freeze
// ===========================================================
//  Politique :
//    - Tout client qui ouvre l'app la 1ère fois reçoit un essai
//      gratuit de TRIAL_DAYS. Au-delà, son `paid` doit être passé
//      à true par l'admin (manuellement, depuis le panel) sinon
//      l'app affiche un écran 'essai expiré' bloquant.
//    - L'admin peut GELER (`status: 'frozen'`) ou BANNIR
//      (`status: 'banned'`) un client à tout moment. L'app détecte
//      via `GET /api/status/:mac` au démarrage et bloque la lecture.
//    - L'app PINGUE le serveur via `POST /api/heartbeat` à chaque
//      ouverture — ça met à jour `last_seen_at` et crée la fiche
//      automatiquement au 1er lancement.
// ===========================================================

const TRIAL_DAYS = 7;
const DAY_MS = 24 * 60 * 60 * 1000;

/// Calcule l'état de monétisation d'un client à partir de sa fiche
/// KV. Renvoie un objet sérialisable que l'app cliente peut lire
/// pour décider quoi afficher (lecture normale, écran d'expiration,
/// écran de gel).
function computeStatus(client, now = Date.now()) {
  if (!client) {
    return {
      exists: false,
      status: 'unknown',
      paid: false,
      trial_until: 0,
      days_left: 0,
      expired: false,
      frozen: false,
      banned: false,
    };
  }
  const status = client.status || 'active';
  const paid = client.paid === true;
  const trialUntil =
    client.trial_until || (client.added_at || now) + TRIAL_DAYS * DAY_MS;
  const daysLeft = Math.ceil((trialUntil - now) / DAY_MS);
  const expired = !paid && trialUntil <= now;
  // plan = type d'abonnement pour l'affichage app ('lifetime' = à vie,
  // '1y'/'custom' = durée limitée, 'trial' = essai, 'expired' = fini).
  // paid_until = date de fin (ms epoch) ; null = à vie.
  const plan = client.plan || (paid ? 'lifetime' : (expired ? 'expired' : 'trial'));
  const paidUntil = client.paid_until !== undefined ? client.paid_until : null;
  return {
    exists: true,
    status,
    paid,
    plan,
    paid_until: paidUntil,
    trial_until: trialUntil,
    days_left: Math.max(0, daysLeft),
    expired,
    frozen: status === 'frozen',
    banned: status === 'banned',
  };
}

// =========================================================
//  PONT KV → D1 (panel revendeurs)
// =========================================================
//  L'app figee lit son etat via /api/status/:mac et /api/heartbeat,
//  historiquement servis depuis KV. Quand un revendeur active une MAC
//  dans le panel, la licence est ecrite en D1 (api_v1.js). Pour que
//  l'app figee HONORE cette activation SANS la modifier, on consulte
//  D1 EN PRIORITE ici : si une licence D1 existe pour la MAC, son etat
//  prime ; sinon on retombe sur l'ancien comportement KV (trial local).
//
//  Renvoie un objet au MEME format que computeStatus(), ou null si pas
//  de licence D1 (ou D1 non deploye → fallback KV transparent).
// =========================================================
// Durée d'essai (jours) PILOTÉE DEPUIS LE PANEL (Tarifs → app_config.trial_days,
// écrit par api_v1 handlePricingPut). Repli sur TRIAL_DAYS (7) si non défini ou
// table absente → AUCUN changement de comportement tant que le panel ne fixe
// pas la valeur. C'est ce qui rend l'essai réglable sans rebuild de l'app.
async function getTrialDays(env) {
  if (!env.DB) return TRIAL_DAYS;
  try {
    const r = await env.DB
      .prepare("SELECT value FROM app_config WHERE key = 'trial_days'")
      .first();
    const td = parseInt(r && r.value, 10);
    return Number.isFinite(td) && td >= 0 ? td : TRIAL_DAYS;
  } catch (_) {
    return TRIAL_DAYS;
  }
}

async function d1StatusForMac(env, mac, now = Date.now()) {
  if (!env.DB) return null;
  let dev;
  try {
    dev = await env.DB
      .prepare('SELECT id, first_seen_at, block_status FROM devices WHERE mac = ?')
      .bind(mac).first();
  } catch (_) {
    // Table/binding absents (D1 pas encore deploye) → fallback KV.
    return null;
  }
  if (!dev) return null; // pas connu en D1 → le caller (heartbeat) le creera

  // --- Blocage manuel par l'admin/revendeur (prime sur tout) ---
  // 'banned' = abus (app affiche "banni") ; 'frozen' = rappel de paiement
  // (app affiche "compte gele"). Voir endpoint PATCH /devices/:id.
  if (dev.block_status === 'banned' || dev.block_status === 'frozen') {
    const banned = dev.block_status === 'banned';
    return {
      exists: true,
      status: dev.block_status,
      paid: false,
      plan: banned ? 'banned' : 'frozen',
      paid_until: null,
      trial_until: now,
      days_left: 0,
      expired: false,
      frozen: !banned,
      banned,
      source: 'd1-block',
    };
  }

  // Meilleure licence pour ce device : lifetime d'abord, sinon expiry max.
  const lic = await env.DB
    .prepare(
      `SELECT status AS lstatus, expires_at FROM licenses
       WHERE device_id = ?
       ORDER BY (expires_at IS NULL) DESC, expires_at DESC LIMIT 1`,
    )
    .bind(dev.id).first();

  // --- Cas 1 : une licence existe (activee par admin/revendeur) ---
  if (lic) {
    const lstatus = lic.lstatus || 'active';
    const lifetime = lic.expires_at === null || lic.expires_at === undefined;
    const expiresAt = lifetime ? now + 36500 * DAY_MS : lic.expires_at;
    const expired = !lifetime && expiresAt <= now;
    const banned = lstatus === 'banned';
    const frozen = lstatus === 'frozen';
    const active = lstatus === 'active' && !expired;
    return {
      exists: true,
      status: banned ? 'banned' : frozen ? 'frozen' : 'active',
      paid: active,            // licence active = debloque l'app
      // plan pour l'affichage app : 'lifetime' (à vie, expires_at NULL)
      // sinon 'paid' (abonnement à durée) ; paid_until = fin (null=à vie).
      plan: lifetime ? 'lifetime' : 'paid',
      paid_until: lifetime ? null : expiresAt,
      trial_until: expiresAt,
      days_left: lifetime ? 36500 : Math.max(0, Math.ceil((expiresAt - now) / DAY_MS)),
      expired: expired && !lifetime,
      frozen,
      banned,
      source: 'd1',
    };
  }

  // --- Cas 2 : device connu mais PAS de licence → ESSAI (durée réglable) ---
  // L'essai court depuis first_seen_at. Après la durée configurée (panel),
  // expired=true → l'app bloque → le client doit venir te voir pour être activé.
  const trialDays = await getTrialDays(env);
  const trialUntil = (dev.first_seen_at || now) + trialDays * DAY_MS;
  const expired = trialUntil <= now;
  return {
    exists: true,
    status: 'active',
    paid: false,
    plan: expired ? 'expired' : 'trial',
    paid_until: null,
    trial_until: trialUntil,
    days_left: Math.max(0, Math.ceil((trialUntil - now) / DAY_MS)),
    expired,
    frozen: false,
    banned: false,
    source: 'd1-trial',
  };
}

// Présence « en ligne » : table séparée (on ne touche PAS au schéma
// `devices`). On garde la dernière IP + pays + horodatage par MAC. Le
// panel considère « en ligne » = vu il y a moins de quelques minutes.
// =========================================================
//  SCALABILITÉ (5M+ appareils) — préparé UNE fois par isolate Worker
// =========================================================
//  Les DDL idempotents (ADD COLUMN / CREATE INDEX) coûtent cher s'ils sont
//  rejoués à CHAQUE heartbeat (des millions de fois/jour). On les exécute UNE
//  seule fois par isolate (drapeaux mémoire), puis on ne fait plus que des
//  écritures. Les INDEX gardent les requêtes rapides même à des millions de
//  lignes (recherche panel, agrégation Tendances, statut par MAC).
let _scaleSchemaReady = false;
let _presenceReady = false;
let _trendingCache = { at: 0, items: [] };
// Caches sport (TheSportsDB, gratuit) — par isolate, 10 min. Proxy : la clé/URL
// reste cote serveur, et on ne tape pas l'API a chaque requete client.
const _SPORTSDB = 'https://www.thesportsdb.com/api/v1/json/3';
let _sportsTeamCache = {};   // idTeam -> { at, data }
let _sportsSearchCache = {}; // requete(min) -> { at, data }

async function ensureScaleSchema(env) {
  if (_scaleSchemaReady || !env.DB) return;
  for (const col of ['device_model TEXT', 'android_build TEXT',
      'android_release TEXT', 'app_build INTEGER', 'platform TEXT',
      'android_id TEXT', 'app_version TEXT', 'local_sources_json TEXT',
      'recent_json TEXT']) {
    try { await env.DB.prepare('ALTER TABLE devices ADD COLUMN ' + col).run(); } catch (_) {}
  }
  for (const idx of [
    'CREATE INDEX IF NOT EXISTS idx_presence_lastseen ON presence(last_seen)',
    'CREATE INDEX IF NOT EXISTS idx_presence_channel ON presence(channel)',
    'CREATE INDEX IF NOT EXISTS idx_devices_lastseen ON devices(last_seen_at)',
    'CREATE INDEX IF NOT EXISTS idx_devices_androidid ON devices(android_id)',
    'CREATE INDEX IF NOT EXISTS idx_devices_reseller ON devices(reseller_id)',
    'CREATE INDEX IF NOT EXISTS idx_licenses_device ON licenses(device_id)',
  ]) {
    try { await env.DB.prepare(idx).run(); } catch (_) {}
  }
  _scaleSchemaReady = true;
}

async function recordPresence(env, mac, ip, country, now, channel) {
  if (!env.DB) return;
  try {
    // DDL UNE fois par isolate (au lieu d'à chaque heartbeat — gros gain à
    // l'échelle de millions d'appareils). L'upsert, lui, tourne à chaque fois.
    if (!_presenceReady) {
      await env.DB.prepare(
        'CREATE TABLE IF NOT EXISTS presence (' +
          'mac TEXT PRIMARY KEY, ip TEXT, country TEXT, last_seen INTEGER, channel TEXT)'
      ).run();
      try { await env.DB.prepare('ALTER TABLE presence ADD COLUMN channel TEXT').run(); } catch (_) {}
      try { await env.DB.prepare('CREATE INDEX IF NOT EXISTS idx_presence_lastseen ON presence(last_seen)').run(); } catch (_) {}
      _presenceReady = true;
    }
    // L'app envoie `channel` à CHAQUE heartbeat (nom de la chaîne en cours,
    // ou '' si elle ne regarde rien) → on reflète toujours l'état courant.
    const chan = (channel === undefined || channel === null) ? null : String(channel).slice(0, 120);
    await env.DB
      .prepare(
        'INSERT INTO presence (mac, ip, country, last_seen, channel) VALUES (?, ?, ?, ?, ?) ' +
          'ON CONFLICT(mac) DO UPDATE SET ip = excluded.ip, ' +
          'country = excluded.country, last_seen = excluded.last_seen, channel = excluded.channel'
      )
      .bind(mac, ip, country, now, chan)
      .run();
  } catch (_) {
    // best-effort : la présence ne doit jamais faire échouer un heartbeat.
  }
}

// « Tendances en direct » : agrège la table `presence` pour renvoyer les
// chaînes les plus regardées EN CE MOMENT (vues dans les 15 dernières minutes)
// avec leur nombre de spectateurs. Lecture seule, best-effort (jamais d'erreur
// 500 — renvoie une liste vide si la base n'est pas prête).
async function handleTrending(env) {
  if (!env.DB) return json({ items: [] });
  // CACHE 60 s : l'agrégation GROUP BY sur la table présence (potentiellement
  // des millions de lignes) ne doit PAS tourner à chaque appel. On la recalcule
  // au plus une fois par minute et par isolate → coût D1 négligeable même si des
  // millions d'apps demandent les Tendances en boucle.
  const now = Date.now();
  if (now - _trendingCache.at < 60_000) {
    return json({ items: _trendingCache.items });
  }
  try {
    const since = now - 15 * 60 * 1000; // « en ligne » = vu < 15 min
    const rs = await env.DB.prepare(
      "SELECT channel, COUNT(*) AS n FROM presence " +
        "WHERE channel IS NOT NULL AND channel != '' AND last_seen >= ? " +
        "GROUP BY channel ORDER BY n DESC LIMIT 25",
    ).bind(since).all();
    const items = (rs.results || []).map((r) => ({
      channel: r.channel,
      count: r.n,
    }));
    _trendingCache = { at: now, items };
    return json({ items });
  } catch (_) {
    // En cas d'erreur on sert le dernier cache connu (jamais d'échec dur).
    return json({ items: _trendingCache.items });
  }
}

// =========================================================
//  SPORT (TheSportsDB) — recherche d'equipe + derniers/prochains matchs
// =========================================================
//  Proxy + cache 10 min. Le client n'appelle JAMAIS TheSportsDB directement.

// GET /api/sports/search?q=<nom> -> { teams: [{id,name,badge,league,sport}] }
async function handleSportsSearch(url) {
  const q = (url.searchParams.get('q') || '').trim();
  if (q.length < 2) return json({ teams: [] });
  const key = q.toLowerCase();
  const now = Date.now();
  const c = _sportsSearchCache[key];
  if (c && now - c.at < 600000) return json(c.data);
  try {
    const r = await fetch(
      `${_SPORTSDB}/searchteams.php?t=${encodeURIComponent(q)}`,
    );
    const j = await r.json().catch(() => ({}));
    const teams = ((j && j.teams) || []).slice(0, 20).map((t) => ({
      id: t.idTeam,
      name: t.strTeam,
      badge: t.strTeamBadge || t.strBadge || '',
      league: t.strLeague || '',
      sport: t.strSport || '',
    }));
    const data = { teams };
    _sportsSearchCache[key] = { at: now, data };
    return json(data);
  } catch (_) {
    return json({ teams: [] });
  }
}

// GET /api/sports/team/:id -> { last: [ev], next: [ev] } (ev = match + score)
async function handleSportsTeam(id) {
  const now = Date.now();
  const c = _sportsTeamCache[id];
  if (c && now - c.at < 600000) return json(c.data);
  const mapEv = (e) => ({
    id: e.idEvent,
    name: e.strEvent || '',
    home: e.strHomeTeam || '',
    away: e.strAwayTeam || '',
    homeScore: (e.intHomeScore === null || e.intHomeScore === undefined)
      ? null : String(e.intHomeScore),
    awayScore: (e.intAwayScore === null || e.intAwayScore === undefined)
      ? null : String(e.intAwayScore),
    date: e.dateEvent || '',
    time: e.strTime || '',
    timestamp: e.strTimestamp || '', // ISO UTC (pour programmer les alarmes)
    status: e.strStatus || '',
    league: e.strLeague || '',
  });
  let last = [];
  let next = [];
  try {
    const r = await fetch(`${_SPORTSDB}/eventslast.php?id=${encodeURIComponent(id)}`);
    const j = await r.json().catch(() => ({}));
    last = ((j && j.results) || []).map(mapEv);
  } catch (_) { /* gratuit : best-effort */ }
  try {
    const r = await fetch(`${_SPORTSDB}/eventsnext.php?id=${encodeURIComponent(id)}`);
    const j = await r.json().catch(() => ({}));
    next = ((j && j.events) || []).map(mapEv);
  } catch (_) { /* eventsnext parfois reserve : on ignore */ }
  const data = { last, next };
  _sportsTeamCache[id] = { at: now, data };
  return json(data);
}

// Enregistre AUTOMATIQUEMENT une MAC dans la base au 1er heartbeat :
// cree un client "auto" + le device (l'essai 7 j demarre a first_seen_at).
// Ainsi TOUTE app installee apparait dans ton panel, sans rien faire.
async function ensureD1Device(env, mac, now = Date.now()) {
  if (!env.DB) return;
  try {
    const dev = await env.DB
      .prepare('SELECT id FROM devices WHERE mac = ?').bind(mac).first();
    if (dev) {
      await env.DB.prepare('UPDATE devices SET last_seen_at = ? WHERE id = ?')
        .bind(now, dev.id).run();
      return;
    }
    const cid = 'cus_' + crypto.randomUUID().replace(/-/g, '').slice(0, 18);
    const did = 'dev_' + crypto.randomUUID().replace(/-/g, '').slice(0, 18);
    await env.DB.batch([
      env.DB.prepare(
        'INSERT INTO customers (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)',
      ).bind(cid, 'Auto ' + mac, now, now),
      env.DB.prepare(
        'INSERT INTO devices (id, customer_id, mac, first_seen_at, last_seen_at) VALUES (?, ?, ?, ?, ?)',
      ).bind(did, cid, mac, now, now),
    ]);
  } catch (_) {
    // Course possible entre 2 heartbeats simultanes (mac UNIQUE) → ignore.
  }
}

// Enrichit la fiche device avec le modèle + le numéro de build Android +
// le build de l'app (envoyés par le heartbeat). Colonnes additives
// (idempotentes). On n'écrase JAMAIS avec du vide.
async function updateDeviceInfo(env, mac, body) {
  if (!env.DB || !body) return;
  // Les colonnes sont créées une fois par isolate via ensureScaleSchema().
  try {
    const model = (body.model ? String(body.model) : '').slice(0, 80);
    const build = (body.build ? String(body.build) : '').slice(0, 120);
    const release = (body.android ? String(body.android) : '').slice(0, 20);
    const appBuild = parseInt(body.appBuild, 10) || 0;
    // ANDROID_ID brut (graine de la MAC) + version lisible de l'app : champs
    // « entreprise » pour recherche/vérification dans le panel.
    const androidId = (body.androidId ? String(body.androidId) : '').slice(0, 32);
    const appVersion = (body.appVersion ? String(body.appVersion) : '').slice(0, 24);
    // 'tv' (DeFew TV) ou 'mobile' (The Few) — pour distinguer dans le panel.
    const platform = (body.platform === 'tv' || body.platform === 'mobile')
      ? body.platform : '';
    // INVENTAIRE des sources présentes sur l'appareil (sans mot de passe).
    // On normalise/borne (max 5) puis on sérialise en JSON pour la colonne
    // local_sources_json. '' = pas d'info envoyée → on n'écrase pas l'existant.
    let srcJson = '';
    if (Array.isArray(body.sources)) {
      const list = body.sources.slice(0, 5).map((s) => ({
        type: s && s.type === 'm3u' ? 'm3u' : 'xtream',
        name: (s && s.name ? String(s.name) : '').slice(0, 60),
        server: (s && s.server ? String(s.server) : '').slice(0, 200),
        username: (s && s.username ? String(s.username) : '').slice(0, 80),
        channels: Number.isFinite(s && s.channels) ? (s.channels | 0) : 0,
        active: !!(s && s.active),
      }));
      srcJson = JSON.stringify(list);
    }
    // HISTORIQUE de visionnage (ids de chaînes, du + récent au + ancien, max
    // 50). Sérialisé dans recent_json → permet de RESTAURER l'historique sur
    // une 2e box (ou après réinstallation de la même source). Sans identifiant
    // sensible : juste des ids tvg-id/stream_id propres à la playlist.
    let recentJson = '';
    if (Array.isArray(body.recent)) {
      const ids = body.recent
        .slice(0, 50)
        .map((x) => String(x || '').slice(0, 80))
        .filter((x) => x.length > 0);
      if (ids.length) recentJson = JSON.stringify(ids);
    }
    if (!model && !build && !release && !appBuild && !platform &&
        !androidId && !appVersion && !srcJson && !recentJson) return;
    // UNE SEULE écriture (au lieu de 4) : le CASE n'écrase JAMAIS un champ
    // existant avec une valeur vide → robuste ET économe en écritures D1.
    await env.DB
      .prepare(
        "UPDATE devices SET " +
          "device_model = CASE WHEN ? != '' THEN ? ELSE device_model END, " +
          "android_build = CASE WHEN ? != '' THEN ? ELSE android_build END, " +
          "android_release = CASE WHEN ? != '' THEN ? ELSE android_release END, " +
          "app_build = CASE WHEN ? != 0 THEN ? ELSE app_build END, " +
          "android_id = CASE WHEN ? != '' THEN ? ELSE android_id END, " +
          "app_version = CASE WHEN ? != '' THEN ? ELSE app_version END, " +
          "platform = CASE WHEN ? != '' THEN ? ELSE platform END, " +
          "local_sources_json = CASE WHEN ? != '' THEN ? ELSE local_sources_json END, " +
          "recent_json = CASE WHEN ? != '' THEN ? ELSE recent_json END " +
          "WHERE mac = ?"
      )
      .bind(
        model, model, build, build, release, release, appBuild, appBuild,
        androidId, androidId, appVersion, appVersion, platform, platform,
        srcJson, srcJson, recentJson, recentJson, mac,
      )
      .run();
  } catch (_) {
    // best-effort : ne jamais faire échouer un heartbeat.
  }
}

// Landing page : voir cloudflare/landing.js (landingHtml), servie sur la racine /.

// ============================================================
//  Panel admin web — page HTML autonome servie à /admin/panel
// ============================================================
//  L'admin tape https://7themotion.com/admin/panel dans son
//  navigateur (ordi ou téléphone). Il voit un formulaire de
//  login (X-Admin-Secret), puis la liste de tous les clients
//  avec leurs statuts trial / paid / frozen / banned. Chaque
//  ligne a des boutons d'action rapide.
//
//  Pas de framework — HTML + CSS + JS vanilla pour rester
//  ultra léger (sert en 1 round-trip, charge en < 50 ms).
//  Le secret admin est stocké en sessionStorage (vidé à la
//  fermeture du navigateur — meilleur que localStorage pour
//  le risque de fuite).
// ============================================================
const ADMIN_PANEL_HTML = `<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>BLACK7 ROYAL — Panel admin</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: #0A0A0C;
      color: #F0EDE9;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      min-height: 100vh;
      padding: 24px;
    }
    h1 {
      font-size: 22px;
      letter-spacing: 4px;
      font-weight: 700;
      margin-bottom: 4px;
    }
    .tagline {
      color: #7E7872;
      font-size: 11px;
      letter-spacing: 2px;
      margin-bottom: 28px;
    }
    .card {
      background: linear-gradient(180deg, #14141A 0%, #0E0E12 100%);
      border: 1px solid rgba(214, 58, 48, 0.25);
      border-radius: 14px;
      padding: 20px;
      margin-bottom: 18px;
    }
    label {
      display: block;
      font-size: 11px;
      letter-spacing: 1.5px;
      color: #B6B0A8;
      margin-bottom: 6px;
      text-transform: uppercase;
    }
    input[type="text"], input[type="password"], textarea {
      width: 100%;
      padding: 12px 14px;
      background: #1C1C24;
      border: 1px solid rgba(255,255,255,0.08);
      border-radius: 10px;
      color: #F0EDE9;
      font-size: 14px;
      font-family: inherit;
    }
    input:focus, textarea:focus {
      outline: none;
      border-color: #D63A30;
    }
    button {
      padding: 10px 16px;
      background: #D63A30;
      color: #050507;
      border: 0;
      border-radius: 10px;
      font-weight: 700;
      cursor: pointer;
      font-family: inherit;
      font-size: 13px;
    }
    button:hover { background: #FF5A4A; }
    button.ghost {
      background: transparent;
      color: #B6B0A8;
      border: 1px solid rgba(255,255,255,0.12);
    }
    button.ghost:hover { color: #F0EDE9; border-color: #D63A30; }
    button.danger { background: #8E1F1D; color: #F0EDE9; }
    button.danger:hover { background: #B02E2A; }
    .row-actions button {
      margin-right: 6px;
      margin-bottom: 4px;
      padding: 6px 10px;
      font-size: 11px;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
    }
    th, td {
      padding: 12px 10px;
      text-align: left;
      border-bottom: 1px solid rgba(255,255,255,0.06);
      vertical-align: top;
    }
    th {
      font-size: 10px;
      letter-spacing: 1.5px;
      color: #7E7872;
      text-transform: uppercase;
      font-weight: 600;
    }
    .mac {
      font-family: monospace;
      color: #D63A30;
      font-weight: 700;
    }
    .badge {
      display: inline-block;
      padding: 2px 8px;
      border-radius: 4px;
      font-size: 10px;
      letter-spacing: 1px;
      font-weight: 700;
      text-transform: uppercase;
    }
    .badge.active { background: rgba(95,169,117,0.18); color: #5FA975; }
    .badge.frozen { background: rgba(214,152,71,0.18); color: #D69847; }
    .badge.banned { background: rgba(232,74,62,0.18); color: #E84A3E; }
    .badge.paid { background: rgba(214,58,48,0.18); color: #D63A30; }
    .badge.unpaid { background: rgba(126,120,114,0.18); color: #7E7872; }
    .filter-bar {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      margin-bottom: 14px;
    }
    .filter-bar button {
      padding: 6px 12px;
      font-size: 11px;
      background: transparent;
      color: #B6B0A8;
      border: 1px solid rgba(255,255,255,0.10);
    }
    .filter-bar button.active {
      background: #D63A30;
      color: #050507;
      border-color: #D63A30;
    }
    #empty {
      padding: 40px;
      text-align: center;
      color: #7E7872;
      font-size: 13px;
    }
    .stat {
      display: inline-block;
      margin-right: 22px;
      padding: 4px 0;
    }
    .stat strong {
      font-size: 18px;
      color: #D63A30;
      display: block;
    }
    .stat span {
      font-size: 10px;
      letter-spacing: 1.5px;
      color: #7E7872;
      text-transform: uppercase;
    }
    @media (max-width: 720px) {
      table { font-size: 11px; }
      th, td { padding: 8px 6px; }
    }
    /* Ligne cliquable → fiche détail (le MAC devient un lien évident). */
    td.mac { cursor: pointer; text-decoration: underline; text-underline-offset: 3px; }
    td.mac:hover { color: #FF5A4A; }
    /* ===== Fiche détail (modale plein écran) ===== */
    .overlay {
      position: fixed; inset: 0; z-index: 50;
      background: rgba(4,4,7,0.78);
      display: none; align-items: flex-start; justify-content: center;
      padding: 24px; overflow-y: auto;
    }
    .overlay.open { display: flex; }
    .sheet {
      width: 100%; max-width: 640px;
      background: linear-gradient(180deg, #16161C 0%, #0E0E12 100%);
      border: 1px solid rgba(214,58,48,0.35);
      border-radius: 16px; padding: 22px;
      box-shadow: 0 24px 60px rgba(0,0,0,0.6);
    }
    .sheet-head {
      display: flex; align-items: center; justify-content: space-between;
      margin-bottom: 4px;
    }
    .sheet-head .x {
      background: transparent; border: 1px solid rgba(255,255,255,0.14);
      color: #B6B0A8; border-radius: 8px; padding: 6px 12px;
    }
    .sheet h2 { font-size: 15px; letter-spacing: 1px; }
    .sheet .sub {
      font-family: monospace; color: #D63A30; font-weight: 700;
      font-size: 14px; margin-bottom: 16px;
    }
    .grp {
      border: 1px solid rgba(255,255,255,0.07);
      border-radius: 12px; padding: 12px 14px; margin-bottom: 12px;
    }
    .grp h3 {
      font-size: 10px; letter-spacing: 1.6px; color: #7E7872;
      text-transform: uppercase; margin-bottom: 10px; font-weight: 700;
    }
    .kv { display: flex; justify-content: space-between; gap: 12px; padding: 5px 0; font-size: 13px; }
    .kv .k { color: #8E8880; }
    .kv .v { color: #F0EDE9; text-align: right; word-break: break-word; font-weight: 600; }
    .kv .v.mono { font-family: monospace; }
    .dot { display:inline-block; width:8px; height:8px; border-radius:50%; margin-right:6px; vertical-align:middle; }
    .dot.on { background:#5FA975; box-shadow:0 0 8px #5FA975; }
    .dot.off { background:#7E7872; }
    .sheet .row-actions { margin-top: 6px; }
  </style>
</head>
<body>
  <h1>BLACK7 ROYAL</h1>
  <div class="tagline">PANEL ADMIN</div>

  <!-- ===== ÉCRAN LOGIN ===== -->
  <div id="login-card" class="card">
    <label>Secret admin (ADMIN_SECRET du Worker)</label>
    <input type="password" id="secret-input" placeholder="••••••••••••" autocomplete="off">
    <div style="margin-top:14px">
      <button onclick="login()">Se connecter</button>
      <button class="ghost" onclick="document.getElementById('secret-input').value=''">Effacer</button>
    </div>
    <div id="login-error" style="color:#E84A3E;font-size:12px;margin-top:10px;display:none"></div>
  </div>

  <!-- ===== ÉCRAN PRINCIPAL (caché tant que pas loggé) ===== -->
  <div id="main" style="display:none">
    <div class="card">
      <div class="stat"><strong id="stat-total">0</strong><span>Clients total</span></div>
      <div class="stat"><strong id="stat-active">0</strong><span>Actifs</span></div>
      <div class="stat"><strong id="stat-paid">0</strong><span>Payants</span></div>
      <div class="stat"><strong id="stat-frozen">0</strong><span>Gelés</span></div>
      <div class="stat"><strong id="stat-expired">0</strong><span>Essai expiré</span></div>
      <button class="ghost" style="float:right" onclick="refresh()">↻ Actualiser</button>
      <button class="ghost" style="float:right;margin-right:6px" onclick="logout()">Déconnexion</button>
    </div>

    <!-- ===== ANNONCE BROADCAST (notif à tous les utilisateurs) ===== -->
    <div class="card">
      <strong style="display:block;margin-bottom:8px">📣 Envoyer une annonce</strong>
      <div style="font-size:12px;color:#9aa;margin-bottom:8px">
        Notifie TOUS les utilisateurs (ceux qui ont laissé les annonces
        activées). Ex. nouveau contenu, info importante.
      </div>
      <input id="ann-title" placeholder="Titre (ex. Nouveau contenu ajouté)"
        style="width:100%;margin-bottom:6px;padding:8px;border-radius:8px;border:1px solid #333;background:#111;color:#fff">
      <textarea id="ann-body" placeholder="Message" rows="2"
        style="width:100%;margin-bottom:6px;padding:8px;border-radius:8px;border:1px solid #333;background:#111;color:#fff"></textarea>
      <button class="ghost" onclick="sendAnnouncement()">Envoyer à tous</button>
      <button class="ghost" style="margin-left:6px" onclick="clearAnnouncement()">Retirer l'annonce</button>
      <span id="ann-status" style="font-size:12px;margin-left:8px"></span>
    </div>

    <div class="card">
      <div class="filter-bar">
        <button data-filter="all" class="active" onclick="setFilter('all')">Tous</button>
        <button data-filter="trial" onclick="setFilter('trial')">En essai</button>
        <button data-filter="paid" onclick="setFilter('paid')">Payants</button>
        <button data-filter="expired" onclick="setFilter('expired')">Essai expiré</button>
        <button data-filter="frozen" onclick="setFilter('frozen')">Gelés</button>
        <button data-filter="banned" onclick="setFilter('banned')">Bannis</button>
      </div>
      <table>
        <thead>
          <tr>
            <th>MAC</th>
            <th>Nom</th>
            <th>Statut</th>
            <th>Essai</th>
            <th>Vu</th>
            <th>Note</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody id="tbody"></tbody>
      </table>
      <div id="empty" style="display:none">Aucun client dans cette catégorie.</div>
    </div>
  </div>

  <!-- ===== FICHE DÉTAIL (modale) — clic sur un MAC ===== -->
  <div id="detail-overlay" class="overlay" onclick="if(event.target===this)closeDetail()">
    <div class="sheet">
      <div class="sheet-head">
        <h2>FICHE APPAREIL</h2>
        <button class="x" onclick="closeDetail()">✕ Fermer</button>
      </div>
      <div class="sub" id="detail-mac">—</div>
      <div id="detail-body"></div>
    </div>
  </div>

<script>
const SECRET_KEY = '_7m_admin_secret';
let allClients = [];
let currentFilter = 'all';

function getSecret() {
  return sessionStorage.getItem(SECRET_KEY) || '';
}

function setSecret(s) {
  sessionStorage.setItem(SECRET_KEY, s);
}

function clearSecret() {
  sessionStorage.removeItem(SECRET_KEY);
}

function login() {
  const s = document.getElementById('secret-input').value.trim();
  if (!s) return showLoginError('Entre le secret admin.');
  setSecret(s);
  refresh();
}

function logout() {
  clearSecret();
  document.getElementById('login-card').style.display = 'block';
  document.getElementById('main').style.display = 'none';
  document.getElementById('secret-input').value = '';
}

function showLoginError(msg) {
  const el = document.getElementById('login-error');
  el.textContent = msg;
  el.style.display = 'block';
}

async function api(path, opts = {}) {
  const headers = Object.assign(
    { 'X-Admin-Secret': getSecret(), 'Content-Type': 'application/json' },
    opts.headers || {},
  );
  const resp = await fetch(path, Object.assign({}, opts, { headers }));
  if (resp.status === 401) {
    clearSecret();
    logout();
    showLoginError('Secret invalide ou expiré.');
    throw new Error('unauthorized');
  }
  return resp;
}

async function sendAnnouncement() {
  const title = document.getElementById('ann-title').value.trim();
  const body = document.getElementById('ann-body').value.trim();
  const status = document.getElementById('ann-status');
  if (!title && !body) {
    status.textContent = 'Titre ou message requis.';
    status.style.color = '#E84A3E';
    return;
  }
  status.textContent = 'Envoi…';
  status.style.color = '#9aa';
  try {
    const resp = await api('/api/announcement', {
      method: 'POST',
      body: JSON.stringify({ title, body }),
    });
    if (resp.ok) {
      status.textContent = '✅ Annonce envoyée.';
      status.style.color = '#3DD68C';
      document.getElementById('ann-title').value = '';
      document.getElementById('ann-body').value = '';
    } else {
      status.textContent = 'Erreur ' + resp.status;
      status.style.color = '#E84A3E';
    }
  } catch (e) {
    status.textContent = 'Erreur réseau.';
    status.style.color = '#E84A3E';
  }
}

async function clearAnnouncement() {
  const status = document.getElementById('ann-status');
  status.textContent = 'Suppression…';
  status.style.color = '#9aa';
  try {
    const resp = await api('/api/announcement', { method: 'DELETE' });
    status.textContent = resp.ok ? '✅ Annonce retirée.' : 'Erreur ' + resp.status;
    status.style.color = resp.ok ? '#3DD68C' : '#E84A3E';
  } catch (e) {
    status.textContent = 'Erreur réseau.';
    status.style.color = '#E84A3E';
  }
}

async function refresh() {
  try {
    const resp = await api('/admin/clients');
    if (!resp.ok) {
      showLoginError('Erreur ' + resp.status + ' — secret correct ?');
      logout();
      return;
    }
    const list = await resp.json();
    allClients = list;
    document.getElementById('login-card').style.display = 'none';
    document.getElementById('main').style.display = 'block';
    render();
  } catch (e) {
    console.error(e);
  }
}

function setFilter(f) {
  currentFilter = f;
  document.querySelectorAll('.filter-bar button').forEach(b => {
    b.classList.toggle('active', b.dataset.filter === f);
  });
  render();
}

function filterClients(list) {
  const now = Date.now();
  switch (currentFilter) {
    case 'trial':
      return list.filter(c => !c.paid && (c.status || 'active') === 'active' && (c.trial_until || 0) > now);
    case 'paid':
      return list.filter(c => c.paid);
    case 'expired':
      return list.filter(c => !c.paid && (c.trial_until || 0) <= now && (c.status || 'active') !== 'banned');
    case 'frozen':
      return list.filter(c => c.status === 'frozen');
    case 'banned':
      return list.filter(c => c.status === 'banned');
    default:
      return list;
  }
}

function daysLeft(client) {
  const now = Date.now();
  const trial = client.trial_until || 0;
  return Math.ceil((trial - now) / (24 * 60 * 60 * 1000));
}

function formatDate(ts) {
  if (!ts) return '—';
  const d = new Date(ts);
  const day = String(d.getDate()).padStart(2, '0');
  const month = String(d.getMonth() + 1).padStart(2, '0');
  return day + '/' + month + ' ' + String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
}

function escapeHtml(s) {
  return String(s || '').replace(/[&<>"']/g, ch => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[ch]));
}

function render() {
  const filtered = filterClients(allClients);
  const tbody = document.getElementById('tbody');
  const empty = document.getElementById('empty');

  // Stats globales
  const now = Date.now();
  document.getElementById('stat-total').textContent = allClients.length;
  document.getElementById('stat-active').textContent = allClients.filter(c => (c.status || 'active') === 'active').length;
  document.getElementById('stat-paid').textContent = allClients.filter(c => c.paid).length;
  document.getElementById('stat-frozen').textContent = allClients.filter(c => c.status === 'frozen').length;
  document.getElementById('stat-expired').textContent = allClients.filter(c => !c.paid && (c.trial_until || 0) <= now && c.status !== 'banned').length;

  if (filtered.length === 0) {
    tbody.innerHTML = '';
    empty.style.display = 'block';
    return;
  }
  empty.style.display = 'none';

  tbody.innerHTML = filtered.map(c => {
    const days = daysLeft(c);
    const status = c.status || 'active';
    const paid = c.paid === true;
    const statusBadge = '<span class="badge ' + status + '">' + status + '</span>';
    const paidBadge = paid
      ? '<span class="badge paid">Payé</span>'
      : days > 0
        ? '<span class="badge unpaid">Essai ' + days + 'j</span>'
        : '<span class="badge unpaid">Expiré</span>';
    return '<tr>' +
      '<td class="mac" onclick="openDetail(\\''+c.mac+'\\')" title="Voir la fiche complète">' + escapeHtml(c.mac) + '</td>' +
      '<td>' + escapeHtml(c.name || '—') + '</td>' +
      '<td>' + statusBadge + ' ' + paidBadge + '</td>' +
      '<td>' + (days > 0 ? days + 'j' : '—') + '</td>' +
      '<td>' + formatDate(c.last_seen_at) + '</td>' +
      '<td style="max-width:160px;font-size:11px;color:#B6B0A8">' + escapeHtml(c.note || '') + '</td>' +
      '<td class="row-actions">' +
        (paid ? '<button class="ghost" onclick="action(\\''+c.mac+'\\',\\'mark_unpaid\\')">Annuler payé</button>' : '<button onclick="action(\\''+c.mac+'\\',\\'mark_paid\\')">✓ Marquer payé</button>') +
        '<button class="ghost" onclick="renew(\\''+c.mac+'\\')">↻ Renouveler</button>' +
        (status === 'frozen' ? '<button onclick="action(\\''+c.mac+'\\',\\'unfreeze\\')">▶ Réactiver</button>' : '<button class="ghost" onclick="action(\\''+c.mac+'\\',\\'freeze\\')">❄ Geler</button>') +
        (status === 'banned' ? '<button onclick="action(\\''+c.mac+'\\',\\'unfreeze\\')">▶ Débannir</button>' : '<button class="danger" onclick="action(\\''+c.mac+'\\',\\'ban\\')">⛔ Bannir</button>') +
        '<button class="ghost" onclick="editNote(\\''+c.mac+'\\')">📝 Note</button>' +
        '<button class="ghost" onclick="familyMenu(\\''+c.mac+'\\')">👪 Famille</button>' +
      '</td>' +
    '</tr>';
  }).join('');
}

async function action(mac, act) {
  try {
    const resp = await api('/admin/clients/' + encodeURIComponent(mac) + '/action', {
      method: 'POST',
      body: JSON.stringify({ action: act }),
    });
    if (!resp.ok) return alert('Erreur ' + resp.status);
    await refresh();
  } catch (e) {
    if (e.message !== 'unauthorized') alert(e.message);
  }
}

// ============================================================
//  FICHE DÉTAIL — clic sur un MAC → tout savoir sur le porteur
// ============================================================
//  Une modale qui affiche TOUT ce que le serveur sait de l'appareil :
//  abonnement (payé / essai / gelé / banni), connexion live (en ligne,
//  dernière connexion, IP, pays, chaîne en cours), matériel + version
//  app, plan famille, sources assignées — et les mêmes boutons d'action
//  que le tableau. « Le seul maître de tout. »
let detailMac = null;

function fmtFull(ts) {
  if (!ts) return '—';
  const d = new Date(ts);
  const p = n => String(n).padStart(2, '0');
  return p(d.getDate()) + '/' + p(d.getMonth() + 1) + '/' + d.getFullYear() +
    ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
}

function ago(ts) {
  if (!ts) return '';
  const s = Math.floor((Date.now() - ts) / 1000);
  if (s < 60) return 'il y a ' + s + ' s';
  const m = Math.floor(s / 60);
  if (m < 60) return 'il y a ' + m + ' min';
  const h = Math.floor(m / 60);
  if (h < 24) return 'il y a ' + h + ' h';
  return 'il y a ' + Math.floor(h / 24) + ' j';
}

function kv(k, v, mono) {
  const val = (v == null || v === '') ? '—' : escapeHtml(String(v));
  return '<div class="kv"><span class="k">' + escapeHtml(k) + '</span>' +
    '<span class="v' + (mono ? ' mono' : '') + '">' + val + '</span></div>';
}

function kvRaw(k, vHtml) {
  return '<div class="kv"><span class="k">' + escapeHtml(k) + '</span>' +
    '<span class="v">' + vHtml + '</span></div>';
}

async function openDetail(mac) {
  detailMac = mac;
  document.getElementById('detail-mac').textContent = mac;
  document.getElementById('detail-body').innerHTML =
    '<div style="padding:20px;text-align:center;color:#7E7872">Chargement…</div>';
  document.getElementById('detail-overlay').classList.add('open');
  try {
    const resp = await api('/admin/clients/' + encodeURIComponent(mac));
    if (!resp.ok) {
      document.getElementById('detail-body').innerHTML =
        '<div style="padding:20px;color:#E84A3E">Erreur ' + resp.status + '</div>';
      return;
    }
    renderDetail(await resp.json());
  } catch (e) {
    if (e.message !== 'unauthorized') {
      document.getElementById('detail-body').innerHTML =
        '<div style="padding:20px;color:#E84A3E">' + escapeHtml(e.message) + '</div>';
    }
  }
}

function closeDetail() {
  document.getElementById('detail-overlay').classList.remove('open');
  detailMac = null;
}

function renderDetail(c) {
  const now = Date.now();
  const meta = c.meta || {};
  const status = c.status || 'active';
  const paid = c.paid === true;
  const days = daysLeft(c);
  const p = meta.presence || null;
  const online = !!(p && p.last_seen && (now - p.last_seen) < 5 * 60 * 1000);

  // --- Abonnement ---
  const paidBadge = paid
    ? '<span class="badge paid">Payé</span>'
    : (days > 0 ? '<span class="badge unpaid">Essai ' + days + 'j</span>'
                : '<span class="badge unpaid">Expiré</span>');
  let g = '<div class="grp"><h3>Abonnement</h3>';
  g += kvRaw('État', '<span class="badge ' + status + '">' + status + '</span> ' + paidBadge);
  g += kv('Payé', paid ? 'Oui' : 'Non');
  g += kv('Essai restant', days > 0 ? days + ' jour(s)' : 'Aucun');
  g += kv('Essai jusqu\\'au', fmtFull(c.trial_until));
  if (c.name) g += kv('Nom', c.name);
  if (c.note) g += kv('Note', c.note);
  g += '</div>';

  // --- Connexion (live) ---
  const lastSeen = (p && p.last_seen) || c.last_seen_at ||
    (meta.device && meta.device.last_seen_at) || 0;
  g += '<div class="grp"><h3>Connexion</h3>';
  g += kvRaw('En ligne', '<span class="dot ' + (online ? 'on' : 'off') + '"></span>' +
    (online ? 'Oui' : 'Non'));
  g += kvRaw('Dernière connexion', lastSeen
    ? escapeHtml(fmtFull(lastSeen)) + ' <span style="color:#7E7872">(' + ago(lastSeen) + ')</span>'
    : '—');
  g += kv('Adresse IP', p ? p.ip : '', true);
  g += kv('Pays', p ? p.country : '');
  g += kv('Chaîne en cours', p ? p.channel : '');
  g += '</div>';

  // --- Appareil ---
  const d = meta.device || {};
  g += '<div class="grp"><h3>Appareil</h3>';
  g += kv('Modèle', d.device_model);
  g += kv('Plateforme', d.platform);
  g += kv('Android', d.android_release
    ? (d.android_release + (d.android_build ? (' (' + d.android_build + ')') : '')) : '');
  g += kv('Version app', d.app_version
    ? (d.app_version + (d.app_build ? (' (' + d.app_build + ')') : '')) : '');
  g += kv('ID Android', d.android_id, true);
  g += kv('Revendeur', d.reseller_id);
  g += kv('Première vue', d.first_seen_at ? fmtFull(d.first_seen_at)
    : (c.added_at ? fmtFull(c.added_at) : ''));
  g += '</div>';

  // --- Famille ---
  const f = meta.family;
  if (f) {
    g += '<div class="grp"><h3>Famille</h3>';
    if (f.role === 'member') {
      g += kv('Rôle', 'Membre');
      g += kv('Propriétaire', f.owner, true);
    } else {
      g += kv('Rôle', 'Propriétaire');
      g += kv('Plan', (f.enabled ? 'Activé' : 'Non activé') +
        ' (' + (f.members ? f.members.length : 0) + '/' + (f.max || 4) + ')');
      (f.members || []).forEach((m, i) => {
        g += kv('  ' + (i + 1) + '. ' + (m.label || 'Sans nom'), m.mac, true);
      });
    }
    g += '</div>';
  }

  // --- Sources assignées ---
  const srcs = meta.sources || [];
  g += '<div class="grp"><h3>Sources (' + srcs.length + ')</h3>';
  if (srcs.length) {
    srcs.forEach((s, i) => {
      const line = (s.type || '?') + (s.label ? (' · ' + s.label) : '') +
        (s.origin ? (' · ' + s.origin) : '');
      g += kv('#' + (i + 1) + ' ' + line, s.server_url || (s.has_m3u ? 'M3U' : ''));
      if (s.username) {
        g += kv('   utilisateur', s.username + (s.has_password ? ' · ****' : ''), true);
      }
    });
  } else {
    g += kv('Assignées', 'Aucune');
  }
  g += '</div>';

  // --- Actions (mêmes que le tableau) ---
  const mac = c.mac;
  g += '<div class="row-actions">';
  g += paid
    ? '<button class="ghost" onclick="detailAction(\\'' + mac + '\\',\\'mark_unpaid\\')">Annuler payé</button>'
    : '<button onclick="detailAction(\\'' + mac + '\\',\\'mark_paid\\')">✓ Marquer payé</button>';
  g += '<button class="ghost" onclick="renew(\\'' + mac + '\\').then(()=>openDetail(\\'' + mac + '\\'))">↻ Renouveler</button>';
  g += status === 'frozen'
    ? '<button onclick="detailAction(\\'' + mac + '\\',\\'unfreeze\\')">▶ Réactiver</button>'
    : '<button class="ghost" onclick="detailAction(\\'' + mac + '\\',\\'freeze\\')">❄ Geler</button>';
  g += status === 'banned'
    ? '<button onclick="detailAction(\\'' + mac + '\\',\\'unfreeze\\')">▶ Débannir</button>'
    : '<button class="danger" onclick="detailAction(\\'' + mac + '\\',\\'ban\\')">⛔ Bannir</button>';
  g += '<button class="ghost" onclick="editNote(\\'' + mac + '\\').then(()=>openDetail(\\'' + mac + '\\'))">📝 Note</button>';
  g += '</div>';

  document.getElementById('detail-body').innerHTML = g;
}

async function detailAction(mac, act) {
  await action(mac, act);
  if (detailMac === mac) openDetail(mac); // rafraîchit la fiche
}

// ===== GESTION FAMILLE (revendeur) =====
// Un seul bouton 👪 → menu : voir la famille, activer/désactiver le plan,
// AJOUTER un membre soi-même (MAC), le nommer, le retirer. Le client n'a
// rien à taper : le membre hérite du statut dès son prochain démarrage.
async function familyAction(mac, payload) {
  const resp = await api('/admin/clients/' + encodeURIComponent(mac) + '/action', {
    method: 'POST',
    body: JSON.stringify(payload),
  });
  if (!resp.ok) { alert('Erreur ' + resp.status); return false; }
  return true;
}

async function familyMenu(mac) {
  try {
    // Vue famille (endpoint public en lecture — mêmes données que l'app).
    let info = null;
    try {
      const r = await fetch('/api/family/info/' + encodeURIComponent(mac));
      info = await r.json();
    } catch (_) {}
    const plan = info && info.plan === true;
    const members = (info && info.members) || [];
    let txt = 'PLAN FAMILLE de ' + mac + '\\n';
    txt += 'Option : ' + (plan ? 'ACTIVÉE (' + members.length + '/' + (info.max || 4) + ' proches)' : 'NON activée') + '\\n';
    if (info && info.code) txt += 'Code en cours : ' + info.code + '\\n';
    if (members.length) {
      txt += '\\nMembres :\\n';
      for (let i = 0; i < members.length; i++) {
        txt += '  ' + (i + 1) + '. ' + (members[i].label || 'Sans nom') + ' — ' + members[i].mac + '\\n';
      }
    }
    txt += '\\nAction ?\\n 1 = Activer le plan (choisir le max)\\n 2 = Ajouter un membre (MAC + nom)\\n 3 = Nommer un membre\\n 4 = Retirer un membre\\n 5 = Désactiver le plan';
    const choice = prompt(txt, '');
    if (choice === null || choice === '') return;
    if (choice === '1') {
      const m = prompt('Combien de proches autorisés (max 6) ?', '4');
      if (m === null) return;
      if (await familyAction(mac, { action: 'family_on', max: Number(m) || 4 })) {
        alert('Plan Famille ACTIVÉ pour ' + mac);
      }
    } else if (choice === '2') {
      const member = prompt('MAC du membre à ajouter (MK:XX:XX:XX:XX:XX) :', 'MK:');
      if (!member) return;
      const label = prompt('Nom du membre (Papa, Maman…) — vide = sans nom :', '') || '';
      if (await familyAction(mac, { action: 'family_add', member: member.trim(), label })) {
        alert('Membre ajouté. Il aura l\\'accès à son prochain démarrage.');
      }
    } else if (choice === '3') {
      const member = prompt('MAC du membre à nommer :', members[0] ? members[0].mac : 'MK:');
      if (!member) return;
      const label = prompt('Nouveau nom :', '');
      if (label === null) return;
      await familyAction(mac, { action: 'family_rename', member: member.trim(), label });
    } else if (choice === '4') {
      const member = prompt('MAC du membre à RETIRER :', members[0] ? members[0].mac : 'MK:');
      if (!member) return;
      if (await familyAction(mac, { action: 'family_remove', member: member.trim() })) {
        alert('Membre retiré.');
      }
    } else if (choice === '5') {
      if (await familyAction(mac, { action: 'family_off' })) {
        alert('Plan Famille désactivé (les liens sont conservés).');
      }
    }
    await refresh();
  } catch (e) {
    if (e.message !== 'unauthorized') alert(e.message);
  }
}

async function renew(mac) {
  const days = prompt('Renouveler de combien de jours ?', '365');
  if (!days) return;
  try {
    const resp = await api('/admin/clients/' + encodeURIComponent(mac) + '/action', {
      method: 'POST',
      body: JSON.stringify({ action: 'renew', days: Number(days) }),
    });
    if (!resp.ok) return alert('Erreur ' + resp.status);
    await refresh();
  } catch (e) {
    if (e.message !== 'unauthorized') alert(e.message);
  }
}

async function editNote(mac) {
  const current = (allClients.find(c => c.mac === mac) || {}).note || '';
  const note = prompt('Note pour ' + mac + ' :', current);
  if (note === null) return; // annulé
  try {
    const resp = await api('/admin/clients/' + encodeURIComponent(mac) + '/action', {
      method: 'POST',
      body: JSON.stringify({ action: 'note', note }),
    });
    if (!resp.ok) return alert('Erreur ' + resp.status);
    await refresh();
  } catch (e) {
    if (e.message !== 'unauthorized') alert(e.message);
  }
}

// Boot : si on a déjà un secret en session, on tente direct
if (getSecret()) {
  refresh();
}
// Touche Enter dans le champ secret = login
document.getElementById('secret-input').addEventListener('keydown', e => {
  if (e.key === 'Enter') login();
});
</script>
</body>
</html>`;

// Politique de confidentialité servie sur /confidentialite (et /privacy).
// Page autonome (CSS inline), sobre, lisible mobile + TV. Décrit fidèlement ce
// que l'app collecte (identifiant d'appareil, modèle, version, IP, historique
// de visionnage) et pourquoi (activation, fonctionnement, synchro multi-box).
const PRIVACY_HTML = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>The Few — Politique de confidentialité</title>
<style>
  body{background:#0A0A0C;color:#EDEAE3;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;line-height:1.6;margin:0;padding:32px}
  .wrap{max-width:780px;margin:0 auto}
  h1{color:#CCB089;font-size:28px;margin:0 0 4px}
  h2{color:#E6CFA4;font-size:19px;margin:28px 0 8px}
  p,li{color:#CFC9BF;font-size:15px}
  a{color:#CCB089}
  .muted{color:#8A8377;font-size:13px}
  code{color:#E6CFA4}
</style>
</head>
<body><div class="wrap">
  <h1>Politique de confidentialité — The Few</h1>
  <p class="muted">Éditeur : 7 MOTION · Dernière mise à jour : 2026.</p>

  <p>The Few (« l'application ») est un lecteur multimédia pour téléphones,
  téléviseurs et box (Android, Android TV, Fire TV, Google TV). L'application ne fournit, n'héberge ni
  ne revend aucun contenu : l'utilisateur charge sa propre source (liste M3U ou
  identifiants Xtream). Cette politique explique les données traitées et leur
  finalité.</p>

  <h2>1. Données que nous traitons</h2>
  <ul>
    <li><b>Identifiant d'appareil</b> (adresse virtuelle dérivée de l'appareil) :
      pour reconnaître l'appareil et gérer son abonnement/activation.</li>
    <li><b>Modèle de l'appareil, version d'Android et version de l'application</b> :
      pour le support technique et la compatibilité.</li>
    <li><b>Adresse IP et pays</b> (fournis par le réseau) : pour la sécurité, la
      présence « en ligne » et le bon acheminement du service.</li>
    <li><b>Historique de visionnage</b> (identifiants de chaînes récemment
      ouvertes) : pour proposer « Récemment » / « Pour vous » et synchroniser
      votre historique entre vos appareils.</li>
  </ul>
  <p>Nous ne collectons <b>pas</b> votre nom, votre adresse postale, vos
  contacts, ni de données biométriques. Les identifiants de votre source IPTV
  (mot de passe) ne sont <b>pas</b> transmis pour l'historique.</p>

  <h2>2. Finalités</h2>
  <p>Gestion de l'abonnement/activation, fonctionnement et sécurité du service,
  synchronisation de l'expérience entre vos appareils, support technique et
  amélioration de l'application.</p>

  <h2>3. Partage</h2>
  <p>Nous ne <b>vendons pas</b> vos données et ne les partageons pas à des fins
  publicitaires. Les données transitent par notre infrastructure d'hébergement
  (Cloudflare) strictement pour faire fonctionner le service.</p>

  <h2>4. Conservation</h2>
  <p>Données d'activation/abonnement : conservées pendant la durée du service
  puis jusqu'à 24 mois. Journaux techniques et présence : environ 6 mois.</p>

  <h2>5. Vos droits</h2>
  <p>Vous pouvez demander l'accès, la rectification ou la suppression des
  données liées à votre appareil en nous contactant. La suppression de
  l'appareil dans notre système efface les données associées.</p>

  <h2>6. Âge minimum</h2>
  <p>L'application s'adresse aux personnes de 16 ans et plus. Un
  <b>Mode Enfants</b> protégé par code permet de masquer le contenu adulte.</p>

  <h2>7. Contact</h2>
  <p>Pour toute question relative à cette politique ou à vos données :
  <a href="mailto:contact@7themotion.com">contact@7themotion.com</a>.</p>

  <p class="muted">En utilisant The Few, vous acceptez la présente politique.
  Vous devez disposer des droits nécessaires pour le contenu que vous lisez via
  vos propres sources.</p>
</div></body>
</html>`;

const HTML_HEADERS = {
  'Content-Type': 'text/html; charset=utf-8',
  'Cache-Control': 'public, max-age=300',
  'Access-Control-Allow-Origin': '*',
};

const JSON_HEADERS = {
  'Content-Type': 'application/json; charset=utf-8',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Authorization, X-Admin-Secret, Content-Type',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
  'Cache-Control': 'no-store',
};

const TEXT_HEADERS = {
  'Content-Type': 'text/plain; charset=utf-8',
  'Access-Control-Allow-Origin': '*',
};

// Regex MAC virtuelle BLACK7 ROYAL : MK:XX:XX:XX:XX:XX en hex.
const MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/i;

// Décode une MAC reçue dans le PATH : un client web peut encoder les « : » en
// %3A (encodeURIComponent). `url.pathname` n'étant pas décodé, on le fait ici,
// sinon MAC_RX rejette « MK%3A24%3A… » (invalid mac). Tolérant si déjà en clair.
function decodeMacPath(mac) {
  try { return decodeURIComponent(String(mac || '')); } catch (_) { return String(mac || ''); }
}

// =========================================================
//  Proxy Cast (/cast-sign + /cast-proxy)
// =========================================================
//  Le récepteur Cast custom (mpegts.js, /cast-receiver) tourne en HTTPS ; il ne
//  peut PAS fetch un flux IPTV .ts en HTTP (contenu mixte) ni sans en-têtes CORS.
//  /cast-proxy sert d'intermédiaire : MÊME origine que le récepteur, en HTTPS,
//  CORS ouvert, et re-typé video/mp2t → mpegts.js le lit. On protège l'endpoint
//  par un token HMAC signé par /cast-sign (secret Worker CAST_PROXY_SECRET, JAMAIS
//  embarqué dans l'app) + un anti-SSRF (refus des IP privées / hôtes locaux).

// UA « lecteur connu » : des panels Xtream ne servent le vrai flux qu'aux
// signatures de lecteurs répandus.
const CAST_PROXY_UA = 'VLC/3.0.20 LibVLC/3.0.20';

// HMAC-SHA256(secret, message) → hex. Web Crypto (dispo dans le runtime Worker).
async function hmacHex(secret, message) {
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// (La comparaison à temps constant `safeEqual` est déjà définie plus bas dans
//  ce fichier — réutilisée ici pour vérifier le token du proxy Cast.)

// Anti-SSRF : n'autorise que http(s) vers un hôte PUBLIC. Refuse localhost, les
// domaines *.local et les IP littérales privées / réservées (RFC1918, loopback,
// link-local, CGNAT, IPv6 ULA/loopback/link-local). Un hôte en nom de domaine
// est laissé passer (le runtime Worker ne route de toute façon pas vers les
// réseaux privés), mais une IP littérale privée est bloquée nettement.
function isSafeUpstream(rawUrl) {
  let u;
  try { u = new URL(rawUrl); } catch (_) { return false; }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') return false;
  let host = u.hostname.toLowerCase();
  if (host === 'localhost' || host.endsWith('.local') || host.endsWith('.internal')) return false;
  // IPv6 littéral entre crochets → new URL garde les crochets dans hostname.
  if (host.startsWith('[')) host = host.slice(1, -1);
  // IPv4 littérale ?
  const m = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (m) {
    const o = m.slice(1).map((n) => parseInt(n, 10));
    if (o.some((n) => n > 255)) return false;
    const [a, b] = o;
    if (a === 10) return false;                       // 10.0.0.0/8
    if (a === 127) return false;                      // loopback
    if (a === 0) return false;                        // 0.0.0.0/8
    if (a === 169 && b === 254) return false;         // link-local
    if (a === 172 && b >= 16 && b <= 31) return false; // 172.16.0.0/12
    if (a === 192 && b === 168) return false;         // 192.168.0.0/16
    if (a === 100 && b >= 64 && b <= 127) return false; // CGNAT 100.64.0.0/10
    if (a >= 224) return false;                       // multicast / réservé
    return true;
  }
  // IPv6 littérale : bloque loopback (::1), ULA (fc00::/7), link-local (fe80::/10),
  // non-spécifié (::). Laisse passer le reste (adresses globales).
  if (host.includes(':')) {
    if (host === '::1' || host === '::') return false;
    if (host.startsWith('fc') || host.startsWith('fd')) return false;
    if (host.startsWith('fe8') || host.startsWith('fe9') ||
        host.startsWith('fea') || host.startsWith('feb')) return false;
    return true;
  }
  return true; // nom de domaine
}

// GET /vendor/mpegts.js — sert mpegts.js en MÊME ORIGINE que le récepteur Cast.
// Pourquoi : la page /cast-receiver chargeait mpegts.js depuis cdn.jsdelivr.net ;
// si le CDN est lent/bloqué sur le réseau de la TV, TOUT le chemin MPEG-TS meurt.
// Ici le Worker tire la lib une fois (jsdelivr, repli unpkg), la met en cache
// edge (caches.default) et la sert avec un cache long. Version ÉPINGLÉE — ne pas
// passer en "latest" (le récepteur doit rester reproductible).
const MPEGTS_JS_VERSION = '1.7.3';
const MPEGTS_JS_SOURCES = [
  `https://cdn.jsdelivr.net/npm/mpegts.js@${MPEGTS_JS_VERSION}/dist/mpegts.js`,
  `https://unpkg.com/mpegts.js@${MPEGTS_JS_VERSION}/dist/mpegts.js`,
];

async function handleVendorMpegts(ctx) {
  const cache = caches.default;
  // Clé de cache synthétique versionnée : un bump de version invalide
  // naturellement l'ancienne entrée.
  const cacheKey = new Request(
    'https://vendor-cache.internal/mpegts-' + MPEGTS_JS_VERSION + '.js',
  );
  const hit = await cache.match(cacheKey);
  if (hit) return hit;
  for (const src of MPEGTS_JS_SOURCES) {
    try {
      const upstream = await fetch(src);
      if (!upstream.ok) continue;
      const body = await upstream.arrayBuffer();
      const resp = new Response(body, {
        status: 200,
        headers: {
          'Content-Type': 'application/javascript; charset=utf-8',
          // 7 jours : la version est épinglée, le contenu est immuable.
          'Cache-Control': 'public, max-age=604800, immutable',
          'Access-Control-Allow-Origin': '*',
        },
      });
      try { ctx.waitUntil(cache.put(cacheKey, resp.clone())); } catch (_) {}
      return resp;
    } catch (_) { /* CDN suivant */ }
  }
  // Tous les CDN KO : 502 SANS cache — le <script> de repli de la page
  // receiver (jsdelivr direct) prend alors le relais côté TV.
  return new Response('mpegts.js unavailable', {
    status: 502,
    headers: { 'Cache-Control': 'no-store' },
  });
}

// GET /cast-sign?u=<url> — renvoie l'URL /cast-proxy signée (HMAC + expiration).
async function handleCastSign(env, url) {
  const secret = env.CAST_PROXY_SECRET;
  if (!secret) return json({ ok: false, error: 'proxy_unconfigured' }, 503);
  const u = url.searchParams.get('u') || '';
  if (!u || !isSafeUpstream(u)) return badRequest('invalid or private upstream url');
  const exp = Math.floor(Date.now() / 1000) + 12 * 3600; // 12 h
  const sig = (await hmacHex(secret, u + '\n' + exp)).slice(0, 32);
  const origin = url.origin || 'https://app.7themotion.com';
  const proxyUrl = origin + '/cast-proxy?u=' + encodeURIComponent(u) +
    '&e=' + exp + '&t=' + sig;
  return json({ ok: true, url: proxyUrl, expires_at: exp });
}

// GET/HEAD /cast-proxy?u=&e=&t= — vérifie le token puis STREAME l'upstream.
// Reponse d'erreur du proxy Cast AVEC en-tetes CORS : sans ACAO, le
// receiver (mpegts.js/fetch cross-origin) ne peut PAS lire le status de
// l'erreur → echec muet, debug impossible. On expose donc l'erreur.
function castProxyError(msg, status, upstreamStatus) {
  const headers = {
    'Content-Type': 'text/plain; charset=UTF-8',
    'Access-Control-Allow-Origin': '*',
    // L'overlay debug du receiver (fetch cross-origin) doit pouvoir LIRE
    // cet en-tête : sans Expose-Headers, X-Upstream-Status est invisible.
    'Access-Control-Expose-Headers': 'X-Upstream-Status',
    'Cache-Control': 'no-store',
  };
  if (upstreamStatus != null) headers['X-Upstream-Status'] = String(upstreamStatus);
  return new Response(msg, { status, headers });
}

async function handleCastProxy(env, url, method) {
  const secret = env.CAST_PROXY_SECRET;
  if (!secret) return castProxyError('proxy unconfigured', 503);
  const u = url.searchParams.get('u') || '';
  const e = url.searchParams.get('e') || '';
  const t = url.searchParams.get('t') || '';
  if (!u || !e || !t) return castProxyError('missing params', 400);

  // Expiration (borne aussi le futur pour éviter un token « éternel »).
  const exp = parseInt(e, 10);
  const now = Math.floor(Date.now() / 1000);
  if (!Number.isFinite(exp) || exp < now || exp > now + 24 * 3600) {
    return castProxyError('token expired', 403);
  }
  // Token HMAC.
  const expected = (await hmacHex(secret, u + '\n' + e)).slice(0, 32);
  if (!safeEqual(t, expected)) return castProxyError('bad token', 403);
  // Anti-SSRF (revalidé à chaque appel, indépendamment de la signature).
  if (!isSafeUpstream(u)) return castProxyError('forbidden upstream', 403);

  // Suivi MANUEL des redirects (≤3), avec re-validation anti-SSRF de chaque saut.
  //
  // DIAGNOSTIC (2026-07-06) : on distingue désormais 3 échecs différents,
  // parce que « upstream error 502 » générique ne disait pas POURQUOI la TV
  // n'avait pas d'image. Les 3 causes typiques quand le TÉLÉPHONE lit le flux
  // mais que le WORKER (IP datacenter Cloudflare) échoue :
  //   • status 4xx/5xx renvoyé par le fournisseur  → il RÉPOND mais REFUSE
  //     (403/456 = IP datacenter blacklistée ou limite de connexions ;
  //      404 = token de redirection périmé).
  //   • fetch qui JETTE (connexion refusée / reset) → le fournisseur DROP
  //     carrément la connexion depuis l'IP Cloudflare.
  // On remonte le vrai status (corps + en-tête X-Upstream-Status) pour que
  // l'overlay debug du receiver et le diagnostic réseau le montrent.
  let target = u;
  let resp = null;
  let threw = null;
  for (let i = 0; i <= 3; i++) {
    try {
      resp = await fetch(target, {
        method: method === 'HEAD' ? 'HEAD' : 'GET',
        redirect: 'manual',
        headers: { 'User-Agent': CAST_PROXY_UA, Accept: '*/*' },
      });
    } catch (e) {
      threw = e;
      resp = null;
      break;
    }
    if (resp.status >= 300 && resp.status < 400) {
      const loc = resp.headers.get('location');
      if (!loc) break;
      let next;
      try { next = new URL(loc, target).toString(); } catch (_) { break; }
      if (!isSafeUpstream(next)) return castProxyError('forbidden redirect', 403);
      target = next;
      continue;
    }
    break;
  }
  if (!resp) {
    // Le fournisseur a coupé la connexion depuis l'IP Cloudflare (blocage
    // datacenter le plus souvent). Message explicite pour le diagnostic.
    const why = (threw && threw.message) ? String(threw.message).slice(0, 80) : 'no response';
    return castProxyError('upstream unreachable from proxy: ' + why, 502, 0);
  }
  if (resp.status >= 400) {
    // Le fournisseur RÉPOND mais refuse : on renvoie SON status pour lever
    // l'ambiguïté (403/456 = blocage IP/connexions, 404 = token périmé).
    return castProxyError('upstream status=' + resp.status, 502, resp.status);
  }
  // ANTI PAGE D'ERREUR (terrain 2026-07-10, panel thekung) : certains
  // panels répondent 200 avec une page HTML (« limite de connexions »,
  // portail anti-bot) au lieu du flux. La re-typer video/mp2t enverrait
  // du HTML à mpegts.js → la TV reste en « loading » pour toujours
  // (aucune frame, 8/8 échecs silencieux). Un vrai flux IPTV arrive en
  // video/mp2t, application/octet-stream ou sans Content-Type — tout
  // corps explicitement textuel est une page d'erreur déguisée.
  const upCt = (resp.headers.get('content-type') || '').toLowerCase();
  if (upCt.startsWith('text/') || upCt.includes('html') ||
      upCt.includes('json') || upCt.includes('xml')) {
    return castProxyError(
      'upstream content-type=' + upCt.slice(0, 40), 502, resp.status);
  }

  const headers = {
    'Content-Type': 'video/mp2t',
    'Access-Control-Allow-Origin': '*',
    'Cache-Control': 'no-store',
  };
  // HEAD : pas de corps ; GET : STREAM pass-through (resp.body est un
  // ReadableStream → aucune mise en tampon complète côté Worker).
  if (method === 'HEAD') return new Response(null, { status: 200, headers });
  return new Response(resp.body, { status: 200, headers });
}

// ----- Helpers réponse -----

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

// Politique de confidentialité (page /privacy) — requise par les stores
// (Google Play, Huawei AppGallery…). Texte honnête : l'app est un LECTEUR,
// l'utilisateur apporte sa propre source, aucune donnée vendue.
function privacyHtml() {
  const updated = '10 juin 2026';
  return `<!doctype html><html lang="fr"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>7 MOTION — Politique de confidentialité</title>
<style>
  body{margin:0;background:#0A0A0C;color:#E8E8EC;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;line-height:1.6}
  .wrap{max-width:760px;margin:0 auto;padding:32px 20px 64px}
  h1{font-size:26px;margin:0 0 4px}h2{font-size:18px;margin:28px 0 8px;color:#fff}
  .muted{color:#9A9AA2;font-size:13px}a{color:#FF5A4A}
  code{background:#16121C;padding:1px 6px;border-radius:5px}
</style></head><body><div class="wrap">
<h1>Politique de confidentialité — 7 MOTION</h1>
<p class="muted">Dernière mise à jour : ${updated}</p>

<h2>1. Nature de l'application</h2>
<p>7 MOTION est un <strong>lecteur multimédia</strong>. L'application ne vend,
n'héberge et ne fournit AUCUN contenu, flux, chaîne, playlist (M3U) ni
abonnement. L'utilisateur fournit lui-même sa propre source (lien M3U ou
identifiants Xtream) et reste seul responsable de son contenu et de sa licéité.</p>

<h2>2. Données que nous traitons</h2>
<ul>
<li><strong>Identifiant d'appareil</strong> : un identifiant technique
(« MAC virtuelle » dérivée de l'appareil) sert à reconnaître l'installation et
à activer le service. Il ne contient pas votre nom.</li>
<li><strong>Adresse IP et pays</strong> : fournis automatiquement par le réseau
lors des connexions, utilisés pour la sécurité, la présence « en ligne » et des
messages ciblés par pays. L'IP n'est pas revendue.</li>
<li><strong>Modèle et version d'appareil</strong> : pour le support et les
statistiques techniques.</li>
<li><strong>Vos sources IPTV</strong> (URL M3U / identifiants Xtream) : stockées
<strong>localement sur votre appareil</strong> ; une copie peut être sauvegardée,
liée à votre identifiant d'appareil, pour vous permettre de la retrouver après
réinstallation.</li>
<li><strong>Avis</strong> que vous envoyez volontairement.</li>
</ul>

<h2>3. Ce que nous NE faisons PAS</h2>
<p>Pas de vente de données personnelles, pas de pistage publicitaire tiers, pas
de collecte de contacts, photos ou localisation précise.</p>

<h2>4. Lecture & cast</h2>
<p>Les flux que vous chargez sont lus localement ou diffusés (cast) vers un
appareil de votre réseau (TV DLNA, Chromecast). Le contenu transite directement
entre votre source et votre appareil/TV.</p>

<h2>5. Conservation & suppression</h2>
<p>Vos sources locales sont effacées si vous désinstallez l'application ou les
retirez. Pour supprimer les données liées à votre identifiant d'appareil,
contactez-nous (voir ci-dessous).</p>

<h2>6. Sécurité</h2>
<p>Les échanges avec nos serveurs se font en HTTPS. Les mots de passe
administrateurs sont stockés sous forme hachée.</p>

<h2>7. Enfants</h2>
<p>L'application n'est pas destinée aux enfants de moins de 13 ans.</p>

<h2>8. Contact</h2>
<p>Pour toute question ou demande de suppression : <a href="mailto:lionel930031@gmail.com">lionel930031@gmail.com</a>.</p>

<p class="muted">En utilisant 7 MOTION, vous acceptez la présente politique.</p>
</div></body></html>`;
}

// Conditions d'utilisation (pages /terms, /conditions, /cgu). POSITIONNEMENT
// JURIDIQUE des lecteurs sérieux (TiviMate, OTT Navigator…) : l'app est un
// LECTEUR multimédia neutre ; elle ne vend / ne fournit / n'héberge AUCUN
// contenu ni lien M3U ; l'abonnement éventuel rémunère le LOGICIEL, pas le
// contenu. À coller dans la fiche des stores et à lier dans le panel.
function termsHtml() {
  const updated = '22 juin 2026';
  return `<!doctype html><html lang="fr"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>7 MOTION — Conditions d'utilisation</title>
<style>
  body{margin:0;background:#0A0A0C;color:#E8E8EC;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;line-height:1.6}
  .wrap{max-width:760px;margin:0 auto;padding:32px 20px 64px}
  h1{font-size:26px;margin:0 0 4px}h2{font-size:18px;margin:28px 0 8px;color:#fff}
  .muted{color:#9A9AA2;font-size:13px}a{color:#FF5A4A}
  strong{color:#fff}
</style></head><body><div class="wrap">
<h1>Conditions d'utilisation — 7 MOTION</h1>
<p class="muted">Dernière mise à jour : ${updated}</p>

<h2>1. Nature de l'application — un LECTEUR, rien d'autre</h2>
<p>7 MOTION est un <strong>lecteur multimédia</strong> (player) permettant de lire
des flux audio/vidéo fournis par l'utilisateur. L'application
<strong>ne fournit pas, ne vend pas, n'héberge pas, ne diffuse pas et n'indexe
aucune</strong> chaîne de télévision, flux, contenu audiovisuel, ni liste de
lecture (M3U) ou identifiants de portail (Xtream). <strong>Aucun contenu n'est
inclus, préchargé ou commercialisé</strong> avec l'application.</p>

<h2>2. Contenu fourni par l'utilisateur</h2>
<p>L'utilisateur fournit lui-même ses propres sources (lien M3U / identifiants
Xtream), obtenues auprès de son propre fournisseur. L'utilisateur est
<strong>seul responsable</strong> des contenus qu'il ajoute, lit ou diffuse,
ainsi que de la détention des droits, licences et abonnements nécessaires.</p>

<h2>3. Abonnement = le LOGICIEL, pas le contenu</h2>
<p>Tout paiement ou abonnement éventuel rémunère <strong>uniquement
l'utilisation de l'application</strong> (le lecteur et ses fonctionnalités :
interface, favoris, enregistrement local, EPG, etc.). Il ne constitue
<strong>en aucun cas</strong> l'achat, la vente, la location ou la fourniture de
chaînes, de flux ou de contenus audiovisuels.</p>

<h2>4. Usage licite</h2>
<p>L'utilisateur s'engage à utiliser l'application <strong>conformément aux lois
en vigueur</strong> dans son pays et à ne pas l'utiliser pour accéder à des
contenus illégaux ou portant atteinte aux droits d'auteur. Toute utilisation
illicite est strictement interdite et relève de la seule responsabilité de
l'utilisateur.</p>

<h2>5. Contenus tiers — absence de responsabilité</h2>
<p>L'éditeur n'a aucun contrôle sur les contenus tiers accessibles via les
sources fournies par l'utilisateur et ne saurait en être tenu responsable. Il ne
garantit ni la disponibilité, ni la légalité, ni la qualité de ces contenus.</p>

<h2>6. Propriété intellectuelle & réclamations</h2>
<p>Toutes les marques, logos et contenus appartiennent à leurs propriétaires
respectifs. L'application n'hébergeant aucun contenu, toute réclamation relative
à des droits d'auteur doit être adressée au <strong>fournisseur de la source
concernée</strong>. Pour signaler un usage abusif de l'application :
<a href="mailto:lionel930031@gmail.com">lionel930031@gmail.com</a>.</p>

<h2>7. Fourniture « en l'état »</h2>
<p>L'application est fournie « telle quelle », sans garantie de disponibilité
continue ni d'absence d'erreurs. L'éditeur peut faire évoluer ou suspendre tout
ou partie des fonctionnalités.</p>

<h2>8. Données personnelles</h2>
<p>Le traitement des données est décrit dans notre
<a href="/privacy">politique de confidentialité</a>.</p>

<h2>9. Acceptation</h2>
<p>En installant ou en utilisant 7 MOTION, l'utilisateur reconnaît avoir lu et
accepté les présentes conditions.</p>

<p class="muted">Contact : <a href="mailto:lionel930031@gmail.com">lionel930031@gmail.com</a></p>
</div></body></html>`;
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

// ----- Rate-limit applicatif des endpoints PUBLICS (anti-abus / anti-énumération) -----
//  Réutilise la table `rate_limits` (MÊME schéma que api_v1.js → coexistence
//  sans conflit). Clé = bucket + IP appelante (CF-Connecting-IP). FAIL-OPEN :
//  un incident D1 (ou D1 absent) ne bloque JAMAIS un client légitime — la
//  sécurité ne doit pas casser le service. Renvoie `true` si AUTORISÉ.
function clientIp(request) {
  return request.headers.get('CF-Connecting-IP')
    || request.headers.get('X-Forwarded-For')
    || 'unknown';
}
async function rateLimitOk(env, request, bucket, maxAttempts, windowMs) {
  if (!env || !env.DB) return true; // pas de D1 → on ne bloque pas
  try {
    await env.DB.prepare(
      'CREATE TABLE IF NOT EXISTS rate_limits (k TEXT PRIMARY KEY, '
      + 'count INTEGER NOT NULL, window_start INTEGER NOT NULL)',
    ).run();
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
function tooManyRequests() {
  return json(
    { error: 'rate_limited', message: 'Trop de requêtes, réessaie dans un instant.' },
    429,
  );
}

// ----- Réponse JSON SANS CORS '*' (endpoints liés à un appareil) -----
//  Les endpoints qui renvoient des données rattachées à une MAC (source +
//  identifiants IPTV, backup, config playlists) ne doivent PAS être lisibles
//  par un site web tiers depuis un navigateur. En N'ENVOYANT PAS d'en-tête
//  `Access-Control-Allow-Origin`, le navigateur bloque toute lecture
//  cross-origin. Le client NATIF (Flutter http) n'est pas soumis au CORS →
//  l'app continue de fonctionner normalement. Défense anti-moisson d'identifiants.
const JSON_HEADERS_PRIVATE = {
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
};
function jsonPrivate(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS_PRIVATE });
}

// ===== Annonces broadcast (admin -> apps) =====
//  La table est auto-créée au 1er appel : on évite ainsi de toucher au
//  schéma D1 / aux migrations existantes (zéro risque sur le déploiement).
async function ensureAnnouncementsTable(env) {
  await env.DB.prepare(
    'CREATE TABLE IF NOT EXISTS app_broadcasts (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'title TEXT, body TEXT, url TEXT, created_at INTEGER)'
  ).run();
  // Migrations additives (idempotentes), alignées sur api_v1.js :
  // `kind` (catégorie), `cta` (libellé bouton), `country` (ciblage géo :
  // '' = tout le monde, sinon code ISO type 'SE'). SQLite lève si la
  // colonne existe déjà → on ignore.
  for (const col of ['kind TEXT', 'cta TEXT', 'country TEXT',
      'expires_at INTEGER', 'active INTEGER DEFAULT 1']) {
    try {
      await env.DB.prepare(
        'ALTER TABLE app_broadcasts ADD COLUMN ' + col
      ).run();
    } catch (_) { /* déjà présente */ }
  }
}

// GET /api/announcement (public) — dernière annonce CIBLÉE pour le pays
// de l'app qui demande (Cloudflare fournit le pays), ou globale, ET non
// expirée. {} si aucune. country='' = tout le monde ; expires_at = 0/NULL
// = pas d'expiration ; sinon l'annonce disparaît d'elle-même passé ce ms.
async function handleGetAnnouncement(env, request) {
  if (!env.DB) return json({});
  try {
    await ensureAnnouncementsTable(env);
    // Interrupteur GLOBAL (panel) : si les notifications sont coupées, on
    // ne renvoie RIEN — aucune app n'affiche ni ne notifie d'annonce.
    await ensureAppConfigTable(env);
    const sw = await env.DB
      .prepare("SELECT value FROM app_config WHERE key = 'announcements_enabled'")
      .first();
    if (sw && sw.value === '0') return json({});

    const reqCountry =
        (request && request.headers.get('CF-IPCountry')) || '';
    const nowMs = Date.now();
    const row = await env.DB
      .prepare(
        'SELECT id, title, body, url, kind, cta, country, created_at ' +
          'FROM app_broadcasts ' +
          "WHERE (country IS NULL OR country = '' OR country = ?) " +
          'AND (expires_at IS NULL OR expires_at = 0 OR expires_at > ?) ' +
          'AND (active IS NULL OR active = 1) ' +
          'ORDER BY id DESC LIMIT 1'
      )
      .bind(reqCountry, nowMs)
      .first();
    if (!row) return json({});
    return json({
      id: row.id,
      title: row.title || '',
      body: row.body || '',
      url: row.url || '',
      kind: row.kind || '',
      cta: row.cta || '',
      country: row.country || '',
      created_at: row.created_at || 0,
    });
  } catch (_) {
    return json({});
  }
}

// GET /api/home-layout (public) — disposition de l'accueil pilotée par
// l'admin (Module 1/8). Renvoie {items, version}. Items vide → l'app
// garde son ordre par défaut (dégradation gracieuse).
async function handleGetHomeLayout(env) {
  if (!env.DB) return json({ items: [], version: 0 });
  try {
    await env.DB.prepare(
      'CREATE TABLE IF NOT EXISTS home_layout (' +
        'key TEXT PRIMARY KEY, position INTEGER, enabled INTEGER DEFAULT 1, ' +
        "ribbon TEXT DEFAULT '', featured INTEGER DEFAULT 0, updated_at INTEGER)"
    ).run();
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
    return json({ items, version });
  } catch (_) {
    return json({ items: [], version: 0 });
  }
}

// Table clé/valeur générique (mise à jour forcée, etc.). Idempotente.
async function ensureAppConfigTable(env) {
  await env.DB.prepare(
    'CREATE TABLE IF NOT EXISTS app_config (key TEXT PRIMARY KEY, value TEXT)'
  ).run();
}

// GET /api/featured (public) — "Favori du jour" piloté par le panel.
// Renvoie {name, note} : la chaîne mise en avant du jour + une note.
// '' = rien (l'app affiche son HERO normal).
async function handleGetFeatured(env) {
  if (!env.DB) return json({ name: '', note: '' });
  try {
    await ensureAppConfigTable(env);
    const n = await env.DB
      .prepare("SELECT value FROM app_config WHERE key = 'featured_name'")
      .first();
    const note = await env.DB
      .prepare("SELECT value FROM app_config WHERE key = 'featured_note'")
      .first();
    return json({
      name: (n && n.value) || '',
      note: (note && note.value) || '',
    });
  } catch (_) {
    return json({ name: '', note: '' });
  }
}

// GET /api/greeting (public) — accueil personnalisé : ville + météo,
// déduites de l'IP via Cloudflare (request.cf) → AUCUNE permission de
// localisation requise sur la TV. Météo via Open-Meteo (gratuit, sans clé).
// Renvoie {city, country, tempC, weatherCode}. Tout est best-effort.
async function handleGreeting(request) {
  const cf = request.cf || {};
  const city = cf.city ? String(cf.city) : '';
  const country = cf.country ? String(cf.country) : '';
  const lat = cf.latitude;
  const lon = cf.longitude;
  let tempC = null;
  let weatherCode = null;
  if (lat && lon) {
    try {
      const r = await fetch(
        'https://api.open-meteo.com/v1/forecast?latitude=' + lat +
          '&longitude=' + lon + '&current=temperature_2m,weather_code',
        { cf: { cacheTtl: 900, cacheEverything: true } },
      );
      if (r.ok) {
        const j = await r.json();
        if (j && j.current) {
          tempC = j.current.temperature_2m;
          weatherCode = j.current.weather_code;
        }
      }
    } catch (_) { /* météo best-effort */ }
  }
  return json({ city, country, tempC, weatherCode });
}

// GET /api/theme (public) — thème de l'app piloté par le panel.
// Renvoie {appName, accent, bg} : nom affiché + couleur d'accent (hex
// #RRGGBB) + mode de fond ('dark'|'light'). Valeurs vides = l'app garde
// ses défauts (BLACK7 ROYAL, braise, sombre).
async function handleGetTheme(env, platform) {
  const empty = { appName: '', accent: '', bg: '' };
  if (!env.DB) return json(empty);
  // Thème PAR PLATEFORME : suffixe '_tv' pour DeFew TV, rien pour le mobile.
  const sfx = platform === 'tv' ? '_tv' : '';
  try {
    await ensureAppConfigTable(env);
    const get = (k) => env.DB
      .prepare('SELECT value FROM app_config WHERE key = ?').bind(k).first();
    const name = await get('theme_name' + sfx);
    const accent = await get('theme_accent' + sfx);
    const bg = await get('theme_bg' + sfx);
    const theme = {
      appName: (name && name.value) || '',
      accent: (accent && accent.value) || '',
      bg: (bg && bg.value) || '',
    };
    // AUTOMATISATION : si une règle date→thème est active aujourd'hui, elle
    // PRIME sur le thème manuel (ex. décembre → preset Noël). Évalué ici,
    // au moment où l'app lit le thème : aucun cron nécessaire.
    try {
      const autoRow = await get('theme_automations' + sfx);
      const rules = autoRow && autoRow.value ? JSON.parse(autoRow.value) : [];
      const hit = pickActiveThemeRule(rules, new Date());
      if (hit) {
        if (hit.accent) theme.accent = hit.accent;
        if (hit.bg) theme.bg = hit.bg;
        if (hit.appName) theme.appName = hit.appName;
      }
    } catch (_) { /* pas d'automatisation valide → thème manuel */ }
    return json(theme);
  } catch (_) {
    return json(empty);
  }
}

// Retourne la 1ère règle d'automatisation ACTIVE pour la date donnée, ou
// null. `month` (1-12) = tout le mois. Sinon `from`/`to` ('MMDD') = plage
// (gère le passage d'année, ex. 1215→0105). UTC pour rester simple.
function pickActiveThemeRule(rules, now) {
  if (!Array.isArray(rules)) return null;
  const md = (now.getUTCMonth() + 1) * 100 + now.getUTCDate(); // ex. 1225
  const month = now.getUTCMonth() + 1;
  for (const r of rules) {
    if (!r || !r.enabled) continue;
    if (r.month && Number(r.month) === month) return r;
    if (r.from && r.to && /^\d{4}$/.test(r.from) && /^\d{4}$/.test(r.to)) {
      const from = parseInt(r.from, 10);
      const to = parseInt(r.to, 10);
      const inRange = from <= to ? (md >= from && md <= to) : (md >= from || md <= to);
      if (inRange) return r;
    }
  }
  return null;
}

// GET /api/ad (public) — vidéo publicitaire jouée au démarrage de l'app.
// Renvoie {enabled, url, skip, freq}. enabled=false → l'app ne montre rien.
async function handleGetAd(env) {
  const empty = { enabled: false, url: '', skip: 5, freq: 'always' };
  if (!env.DB) return json(empty);
  try {
    await ensureAppConfigTable(env);
    const get = async (k) => {
      const r = await env.DB
        .prepare('SELECT value FROM app_config WHERE key = ?')
        .bind(k).first();
      return r && r.value != null ? String(r.value) : '';
    };
    const url = await get('ad_url');
    const enabled = (await get('ad_enabled')) === '1' && url.length > 0;
    const skipRaw = parseInt(await get('ad_skip'), 10);
    const freq = (await get('ad_freq')) || 'always';
    return json({
      enabled,
      url,
      skip: Number.isFinite(skipRaw) && skipRaw >= 0 ? skipRaw : 5,
      freq,
    });
  } catch (_) {
    return json(empty);
  }
}

// GET /api/pricing (public) — tarifs affichés dans l'app, pilotés par le
// panel « Tarifs ». Renvoie {currency, lifetime, yearly, trialDays,
// promoEnabled, promoMessage}. Défauts maison si rien posé : à vie 9,9 € ·
// 1 an 4,9 € · essai 7 jours. Le prix est une CHAÎNE (on garde la virgule
// décimale française "9,9" telle quelle pour l'affichage).
async function handleGetPricing(env) {
  const def = {
    currency: '€',
    lifetime: '9,9',
    yearly: '4,9',
    trialDays: 7,
    promoEnabled: false,
    promoMessage: '',
  };
  if (!env.DB) return json(def);
  try {
    await ensureAppConfigTable(env);
    const get = async (k) => {
      const r = await env.DB
        .prepare('SELECT value FROM app_config WHERE key = ?')
        .bind(k).first();
      return r && r.value != null ? String(r.value) : '';
    };
    const currency = (await get('price_currency')) || def.currency;
    const lifetime = (await get('price_lifetime')) || def.lifetime;
    const yearly = (await get('price_yearly')) || def.yearly;
    const td = parseInt(await get('trial_days'), 10);
    const trialDays = Number.isFinite(td) && td >= 0 ? td : def.trialDays;
    const promoMessage = await get('promo_msg');
    const promoEnabled =
        (await get('promo_enabled')) === '1' && promoMessage.length > 0;
    return json({ currency, lifetime, yearly, trialDays, promoEnabled, promoMessage });
  } catch (_) {
    return json(def);
  }
}

// GET /api/feedback-prompt (public) — invitation à laisser un avis.
// Renvoie {enabled, message}. L'app affiche un message doux invitant le
// client à écrire son avis / ses idées d'amélioration.
async function handleGetFeedbackPrompt(env) {
  const empty = { enabled: false, message: '' };
  if (!env.DB) return json(empty);
  try {
    await ensureAppConfigTable(env);
    const e = await env.DB
      .prepare("SELECT value FROM app_config WHERE key = 'feedback_enabled'")
      .first();
    const m = await env.DB
      .prepare("SELECT value FROM app_config WHERE key = 'feedback_msg'")
      .first();
    return json({
      enabled: !!(e && e.value === '1'),
      message: (m && m.value) || '',
    });
  } catch (_) {
    return json(empty);
  }
}

// POST /api/feedback (public) — le client envoie son avis. Body
// {mac?, rating?, message}. Stocké en base, lisible depuis le panel.
async function ensureFeedbackTable(env) {
  await env.DB.prepare(
    'CREATE TABLE IF NOT EXISTS feedback (id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'mac TEXT, country TEXT, rating INTEGER, message TEXT, created_at INTEGER)'
  ).run();
}
async function handlePostFeedback(request, env) {
  if (!env.DB) return json({ ok: false }, 503);
  let body;
  try { body = await request.json(); } catch (_) { return badRequest('bad json'); }
  const message = (body && body.message ? String(body.message) : '')
    .trim().slice(0, 2000);
  if (!message) return badRequest('message vide');
  const mac = (body && body.mac ? String(body.mac) : '').slice(0, 64);
  let rating = parseInt(body && body.rating, 10);
  if (!Number.isFinite(rating) || rating < 0 || rating > 5) rating = 0;
  const country = (request.cf && request.cf.country)
    ? String(request.cf.country) : '';
  try {
    await ensureFeedbackTable(env);
    await env.DB
      .prepare('INSERT INTO feedback (mac, country, rating, message, created_at) ' +
        'VALUES (?, ?, ?, ?, ?)')
      .bind(mac, country, rating, message, Date.now())
      .run();
    return json({ ok: true });
  } catch (_) {
    return json({ ok: false }, 500);
  }
}

// GET /api/app-version (public) — mise à jour forcée pilotée par le panel.
// Renvoie {minBuildTs, latestBuildTs} (secondes epoch). Si `?build=<sec>`
// est fourni et plus récent que le dernier connu, on le mémorise → le
// bouton « Forcer » du panel sait quel build exiger.
async function handleGetAppVersion(request, env) {
  if (!env.DB) return json({ minBuildTs: 0, latestBuildTs: 0 });
  try {
    await ensureAppConfigTable(env);
    const url = new URL(request.url);
    // Mise à jour forcée PAR PLATEFORME : clés suffixées '_tv' pour DeFew TV
    // (les builds mobile et TV ont des horodatages différents).
    const sfx = url.searchParams.get('platform') === 'tv' ? '_tv' : '';
    const latestKey = 'latest_build_ts' + sfx;
    const minKey = 'min_build_ts' + sfx;
    const build = parseInt(url.searchParams.get('build') || '0', 10);
    if (Number.isFinite(build) && build > 0) {
      const row = await env.DB
        .prepare('SELECT value FROM app_config WHERE key = ?').bind(latestKey)
        .first();
      const cur = row ? parseInt(row.value, 10) || 0 : 0;
      if (build > cur) {
        await env.DB
          .prepare(
            'INSERT INTO app_config (key, value) VALUES (?, ?) ' +
              'ON CONFLICT(key) DO UPDATE SET value = excluded.value'
          )
          .bind(latestKey, String(build))
          .run();
      }
    }
    const minRow = await env.DB
      .prepare('SELECT value FROM app_config WHERE key = ?').bind(minKey)
      .first();
    const latRow = await env.DB
      .prepare('SELECT value FROM app_config WHERE key = ?').bind(latestKey)
      .first();
    return json({
      minBuildTs: minRow ? parseInt(minRow.value, 10) || 0 : 0,
      latestBuildTs: latRow ? parseInt(latRow.value, 10) || 0 : 0,
    });
  } catch (_) {
    return json({ minBuildTs: 0, latestBuildTs: 0 });
  }
}

// POST /api/announcement (admin) — crée une annonce. Body {title, body, url?}.
async function handlePostAnnouncement(request, env) {
  if (!env.DB) return json({ error: 'db_unbound' }, 500);
  let payload = {};
  try {
    payload = await request.json();
  } catch (_) {}
  const title = (payload.title || '').toString().slice(0, 120);
  const body = (payload.body || '').toString().slice(0, 500);
  const url = (payload.url || '').toString().slice(0, 300);
  if (!title && !body) return badRequest('title or body required');
  try {
    await ensureAnnouncementsTable(env);
    const res = await env.DB
      .prepare(
        'INSERT INTO app_broadcasts (title, body, url, created_at) ' +
          'VALUES (?, ?, ?, ?)'
      )
      .bind(title, body, url, Date.now())
      .run();
    return json({ ok: true, id: (res.meta && res.meta.last_row_id) || null });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
}

// DELETE /api/announcement (admin) — efface toutes les annonces.
async function handleClearAnnouncements(env) {
  if (!env.DB) return json({ error: 'db_unbound' }, 500);
  try {
    await ensureAnnouncementsTable(env);
    await env.DB.prepare('DELETE FROM app_broadcasts').run();
    return json({ ok: true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
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
  // playlists est optionnel sur les updates partiels — l'admin peut
  // vouloir juste passer paid=true sans toucher aux playlists.
  if (body.playlists !== undefined) {
    if (!Array.isArray(body.playlists)) {
      return 'playlists must be an array';
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
  }
  if (body.status !== undefined) {
    if (!['active', 'frozen', 'banned'].includes(body.status)) {
      return 'status must be active, frozen or banned';
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
  // Enrichissement DÉTAIL : quand l'admin clique une ligne, il veut TOUT
  // savoir sur le porteur. On agrège les données live/matérielles sans
  // jamais faire échouer la lecture (best-effort par brique).
  const meta = await readClientDetailMeta(env, mac);
  return json({ mac, ...data, meta });
}

// =========================================================
//  Détail complet d'un appareil (clic sur une ligne du panel)
// =========================================================
//  Agrège TOUT ce que le serveur sait de l'appareil :
//    • présence LIVE  : IP, pays, chaîne en cours, dernière vue ;
//    • matériel + app : modèle, Android, plateforme, version + build ;
//    • famille         : rôle (propriétaire/membre), proches liés ;
//    • sources         : listes assignées (mots de passe MASQUÉS).
//  Best-effort ABSOLU : chaque brique est isolée dans son try/catch —
//  une base absente ou une table manquante renvoie un champ vide, jamais
//  une erreur. Le panel dégrade proprement (affiche « — »).
// =========================================================
async function readClientDetailMeta(env, mac) {
  const meta = { presence: null, device: null, family: null, sources: [] };
  if (!env.DB) return meta;
  const MAC = String(mac || '').toUpperCase();

  // Présence live (table `presence`, écrite à chaque heartbeat).
  try {
    const p = await env.DB
      .prepare('SELECT ip, country, last_seen, channel FROM presence WHERE mac = ?')
      .bind(mac).first();
    if (p) {
      meta.presence = {
        ip: p.ip || '',
        country: p.country || '',
        last_seen: p.last_seen || 0,
        channel: p.channel || '',
      };
    }
  } catch (_) {}

  // Matériel + version app + horodatages + blocage (table `devices`).
  try {
    const d = await env.DB
      .prepare('SELECT * FROM devices WHERE mac = ?')
      .bind(mac).first();
    if (d) {
      meta.device = {
        first_seen_at: d.first_seen_at || 0,
        last_seen_at: d.last_seen_at || 0,
        device_model: d.device_model || '',
        android_release: d.android_release || '',
        android_build: d.android_build || '',
        platform: d.platform || '',
        app_version: d.app_version || '',
        app_build: d.app_build || 0,
        android_id: d.android_id || '',
        reseller_id: d.reseller_id || '',
        block_status: d.block_status || '',
      };
    }
  } catch (_) {}

  // Famille (propriétaire / membre) — mêmes tables que /api/family/info.
  try {
    if (await ensureFamilySchema(env)) {
      const ownerMac = await familyOwnerOf(env, MAC);
      if (ownerMac) {
        meta.family = { role: 'member', owner: ownerMac };
      } else {
        const plan = await familyPlanFor(env, MAC);
        const rows = await env.DB
          .prepare('SELECT member_mac, label FROM app_family_links WHERE owner_mac = ? ORDER BY created_at ASC')
          .bind(MAC).all();
        const members = ((rows && rows.results) || []).map((r) => ({
          mac: r.member_mac,
          label: r.label || '',
        }));
        if (plan.enabled || members.length) {
          meta.family = {
            role: 'owner',
            enabled: plan.enabled,
            max: plan.max,
            members,
          };
        }
      }
    }
  } catch (_) {}

  // Sources assignées (device_sources, clé en MAJUSCULES). Les mots de
  // passe ne sortent JAMAIS : on renvoie seulement leur présence.
  try {
    const { items } = await readDeviceSourceItems(env, MAC);
    meta.sources = (items || []).map((s) => ({
      type: s.type || '',
      label: s.label || '',
      origin: s.origin || '',
      server_url: s.server_url || '',
      username: s.username || '',
      has_password: !!s.password,
      has_m3u: !!s.m3u_url,
    }));
  } catch (_) {}

  return meta;
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
  const addedAt = existing?.added_at || now;

  // Merge intelligent : si un champ n'est PAS dans le body, on
  // conserve sa valeur précédente (update partiel). Permet à
  // l'admin de modifier UN champ à la fois depuis le panel sans
  // devoir renvoyer tout l'objet.
  const merged = {
    name: body.name !== undefined ? body.name : existing?.name || '',
    playlists: body.playlists !== undefined
      ? body.playlists
      : existing?.playlists || [],
    added_at: addedAt,
    updated_at: now,
    // Monétisation
    status: body.status || existing?.status || 'active',
    paid: body.paid !== undefined ? !!body.paid : existing?.paid === true,
    trial_until:
      body.trial_until !== undefined
        ? body.trial_until
        : existing?.trial_until || addedAt + TRIAL_DAYS * DAY_MS,
    note: body.note !== undefined ? body.note : existing?.note || '',
    last_seen_at: existing?.last_seen_at || 0,
  };
  await writeClient(env, body.mac, merged);
  return json({ ok: true, mac: body.mac, ...merged });
}

// =========================================================
//  HEARTBEAT — appelé par l'app cliente à chaque démarrage
// =========================================================
//  Si la fiche n'existe pas → on la crée avec trial 10 jours.
//  Si la fiche existe → on met à jour last_seen_at.
//  Toujours public (pas d'auth) : l'identifiant est le MAC,
//  comme pour /config/:mac.
// =========================================================
async function handleHeartbeat(request, env, ctx) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return badRequest('invalid JSON body');
  }
  const mac = body?.mac;
  if (!mac || !MAC_RX.test(mac)) {
    return badRequest('invalid mac, expected MK:XX:XX:XX:XX:XX');
  }

  const now = Date.now();

  // Présence « en ligne » : on mémorise IP + pays (fournis GRATUITEMENT
  // par Cloudflare) + l'instant. Sert au panel « En ligne » et au ciblage
  // géographique des annonces. Best-effort, ne bloque jamais le heartbeat.
  const ip = request.headers.get('CF-Connecting-IP') || '';
  const country = request.headers.get('CF-IPCountry') || '';
  // `channel` = nom de la chaîne en cours de visionnage (envoyé par l'app),
  // ou '' si elle ne regarde rien. Affiché dans le panel « En ligne ».
  const channel = typeof body.channel === 'string' ? body.channel : '';
  // `defer` = exécute une écriture best-effort EN ARRIÈRE-PLAN (waitUntil) :
  // la réponse part tout de suite, l'écriture continue après. À 5M, ça
  // raccourcit le chemin critique et réduit la contention D1. Repli `await`
  // (renvoie la promesse) si le runtime ne fournit pas `ctx`.
  const defer = (p) => {
    if (ctx && typeof ctx.waitUntil === 'function') { ctx.waitUntil(p); return null; }
    return p;
  };

  // Présence (panel « En ligne ») = purement best-effort → en fond.
  defer(recordPresence(env, mac, ip, country, now, channel));

  // --- Chemin D1 (par defaut des que la base est branchee) ---
  // On enregistre AUTOMATIQUEMENT la MAC (essai 7 j), puis on renvoie son
  // etat. Toute app installee apparait ainsi dans le panel admin.
  if (env.DB) {
    // Prépare colonnes + index UNE fois par isolate (doit précéder
    // updateDeviceInfo qui écrit dans ces colonnes).
    await ensureScaleSchema(env);
    await ensureD1Device(env, mac, now);
    // Enrichissement (modèle, build…) pas nécessaire à la réponse → en fond.
    defer(updateDeviceInfo(env, mac, body));
    // « Conscient de la famille » : un membre hérite du statut du proprio.
    const d1 = await familyStatusForMac(env, mac, now);
    if (d1) return json({ ok: true, created: true, ...d1 });
  }

  // --- Repli KV (si D1 pas branchee) ---
  const existing = await readClient(env, mac);
  if (!existing) {
    const fresh = {
      name: '', playlists: [], added_at: now, updated_at: now,
      status: 'active', paid: false, trial_until: now + TRIAL_DAYS * DAY_MS,
      note: '', last_seen_at: now, first_seen_at: now,
    };
    await writeClient(env, mac, fresh);
    return json({ ok: true, created: true, ...computeStatus(fresh, now) });
  }
  const updated = { ...existing, last_seen_at: now };
  await writeClient(env, mac, updated);
  return json({ ok: true, created: false, ...computeStatus(updated, now) });
}

// =========================================================
//  ABONNEMENT FAMILLE (partage type Netflix — 5 appareils max)
// =========================================================
//  Le PROPRIÉTAIRE (abonnement payé) génère un CODE d'invitation à 6
//  chiffres (48 h). Un proche le tape sur SON appareil → sa MAC est
//  RATTACHÉE à l'abonnement du propriétaire : même statut (payé/expiré/
//  gelé suivent le propriétaire automatiquement) et même source IPTV.
//
//  GARDE-FOUS :
//   • 1 propriétaire + 4 membres max (5 appareils) ;
//   • le blocage manuel (banni/gelé) d'un APPAREIL prime toujours ;
//   • un membre ne peut pas inviter à son tour (pas de chaînes de partage) ;
//   • FAIL-OPEN total : si les tables famille manquent ou si D1 tousse,
//     tout se comporte EXACTEMENT comme avant (aucun client bloqué).
//
//  ⚠️ Connexions SIMULTANÉES : c'est la ligne Xtream (max_connections du
//  panel IPTV) qui limite le nombre de flux en même temps — pas l'app.
// =========================================================
const FAMILY_MAX_MEMBERS = 4; // + le propriétaire = 5 appareils
const FAMILY_CODE_TTL_MS = 48 * 60 * 60 * 1000; // code valable 48 h

// Dernière erreur de création du schéma famille (diagnostic — lisible dans
// la réponse `family_unavailable` pour comprendre un échec en prod).
let _familySchemaError = '';

async function ensureFamilySchema(env) {
  if (!env.DB) { _familySchemaError = 'no_db_binding'; return false; }
  try {
    await env.DB.prepare(
      'CREATE TABLE IF NOT EXISTS app_family_links (' +
      'member_mac TEXT PRIMARY KEY, owner_mac TEXT NOT NULL, created_at INTEGER)',
    ).run();
    await env.DB.prepare(
      'CREATE TABLE IF NOT EXISTS app_family_codes (' +
      'code TEXT PRIMARY KEY, owner_mac TEXT NOT NULL, expires_at INTEGER NOT NULL)',
    ).run();
    await env.DB.prepare(
      'CREATE INDEX IF NOT EXISTS idx_app_family_owner ON app_family_links(owner_mac)',
    ).run();
    // PLAN FAMILLE = OPTION VENDUE : le partage n'est possible que si le
    // revendeur l'a ACTIVÉ pour ce client (bouton 👪 du panel → action
    // family_on). Table des droits : owner_mac → activé + nb max de proches.
    await env.DB.prepare(
      'CREATE TABLE IF NOT EXISTS app_family_plan (' +
      'owner_mac TEXT PRIMARY KEY, enabled INTEGER NOT NULL DEFAULT 0, ' +
      'max_members INTEGER, updated_at INTEGER)',
    ).run();
    // Nom du membre (« Papa », « Maman »… façon profils Netflix). ALTER
    // best-effort : échoue en silence si la colonne existe déjà.
    try {
      await env.DB.prepare('ALTER TABLE app_family_links ADD COLUMN label TEXT').run();
    } catch (_) { /* colonne déjà présente */ }
    _familySchemaError = '';
    return true;
  } catch (e) {
    _familySchemaError = String((e && e.message) || e).slice(0, 200);
    return false;
  }
}

/// Réponse « famille indisponible » AVEC la cause (diagnostic).
function familyUnavailable() {
  return json({ ok: false, error: 'family_unavailable', detail: _familySchemaError });
}

/// Droits « Plan Famille » du propriétaire [mac] : activé ? combien de
/// proches max ? (Option VENDUE : le revendeur l'active via le panel.)
async function familyPlanFor(env, mac) {
  const off = { enabled: false, max: FAMILY_MAX_MEMBERS };
  if (!env.DB) return off;
  try {
    const row = await env.DB
      .prepare('SELECT enabled, max_members FROM app_family_plan WHERE owner_mac = ?')
      .bind(String(mac).toUpperCase()).first();
    if (!row) return off;
    return {
      enabled: Number(row.enabled) === 1,
      max: Number(row.max_members) > 0
          ? Number(row.max_members)
          : FAMILY_MAX_MEMBERS,
    };
  } catch (_) {
    return off; // table absente → option non activée (comportement sûr)
  }
}

/// MAC du propriétaire si `mac` est un MEMBRE d'une famille dont le PLAN est
/// ACTIVÉ, sinon null. La jointure sur app_family_plan est LE verrou : si le
/// revendeur désactive l'option, les membres cessent d'hériter immédiatement
/// (statut ET source) sans supprimer les liens (réactivation = tout revient).
async function familyOwnerOf(env, mac) {
  if (!env.DB) return null;
  try {
    const row = await env.DB
      .prepare(
        'SELECT l.owner_mac AS owner_mac FROM app_family_links l ' +
        'JOIN app_family_plan p ON p.owner_mac = l.owner_mac AND p.enabled = 1 ' +
        'WHERE l.member_mac = ?',
      )
      .bind(String(mac).toUpperCase()).first();
    return row ? row.owner_mac : null;
  } catch (_) {
    return null; // tables absentes → comportement historique
  }
}

function maskMac(mac) {
  const s = String(mac || '');
  return s.length > 8 ? '…' + s.slice(-8) : s;
}

/// Statut « conscient de la famille » : la licence PROPRE de l'appareil
/// prime si elle est jouable ; sinon, si l'appareil est rattaché à un
/// propriétaire PAYÉ et jouable, il hérite de son statut. Le blocage
/// manuel (banni/gelé) de l'appareil lui-même prime sur tout.
async function familyStatusForMac(env, mac, now = Date.now()) {
  const own = await d1StatusForMac(env, mac, now);
  // Blocage manuel de CET appareil → prime (contrôle admin/revendeur).
  if (own && (own.banned || own.frozen) && own.source === 'd1-block') return own;
  // Sa propre licence est jouable → elle prime.
  if (own && own.paid && !own.expired) return own;
  const ownerMac = await familyOwnerOf(env, mac);
  if (!ownerMac) return own;
  try {
    const ost = await d1StatusForMac(env, ownerMac, now);
    if (ost && ost.paid && !ost.expired && !ost.frozen && !ost.banned) {
      // L'appareil hérite du statut du propriétaire (payé, échéance, plan).
      return { ...ost, family: true, family_owner: maskMac(ownerMac) };
    }
  } catch (_) { /* fail-open */ }
  return own;
}

/// POST /api/family/invite  { mac }  → génère le code d'invitation.
async function handleFamilyInvite(request, env) {
  let body;
  try { body = await request.json(); } catch (_) { return badRequest('invalid JSON body'); }
  const mac = String(body?.mac || '').toUpperCase();
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  if (!env.DB || !(await ensureFamilySchema(env))) {
    return familyUnavailable();
  }
  // Un membre ne peut pas devenir propriétaire (pas de chaînes de partage).
  if (await familyOwnerOf(env, mac)) {
    return json({ ok: false, error: 'is_member' });
  }
  // Réservé aux abonnements PAYÉS et jouables.
  const st = await d1StatusForMac(env, mac);
  if (!st || !st.paid || st.expired || st.frozen || st.banned) {
    return json({ ok: false, error: 'not_paid' });
  }
  // PLAN FAMILLE = OPTION VENDUE : sans activation par le revendeur, pas
  // d'invitation (l'app affiche « demande l'option à ton vendeur »).
  const plan = await familyPlanFor(env, mac);
  if (!plan.enabled) {
    return json({ ok: false, error: 'plan_required' });
  }
  const cnt = await env.DB
    .prepare('SELECT COUNT(*) AS n FROM app_family_links WHERE owner_mac = ?')
    .bind(mac).first();
  const members = (cnt && Number(cnt.n)) || 0;
  if (members >= plan.max) {
    return json({ ok: false, error: 'family_full', members, max: plan.max });
  }
  // Code à 6 chiffres (facile à taper à la télécommande), 1 seul actif par
  // propriétaire (le nouveau remplace l'ancien).
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  const code = String(100000 + (buf[0] % 900000));
  const expiresAt = Date.now() + FAMILY_CODE_TTL_MS;
  await env.DB.prepare('DELETE FROM app_family_codes WHERE owner_mac = ?').bind(mac).run();
  await env.DB
    .prepare('INSERT INTO app_family_codes (code, owner_mac, expires_at) VALUES (?, ?, ?)')
    .bind(code, mac, expiresAt).run();
  return json({ ok: true, code, expires_at: expiresAt, members, max: plan.max });
}

/// POST /api/family/join  { mac, code }  → rattache l'appareil au proprio.
async function handleFamilyJoin(request, env) {
  let body;
  try { body = await request.json(); } catch (_) { return badRequest('invalid JSON body'); }
  const mac = String(body?.mac || '').toUpperCase();
  const code = String(body?.code || '').trim();
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  if (!/^[0-9]{6}$/.test(code)) return json({ ok: false, error: 'code_invalid' });
  if (!env.DB || !(await ensureFamilySchema(env))) {
    return familyUnavailable();
  }
  const row = await env.DB
    .prepare('SELECT owner_mac, expires_at FROM app_family_codes WHERE code = ?')
    .bind(code).first();
  if (!row || Number(row.expires_at) < Date.now()) {
    return json({ ok: false, error: 'code_invalid' });
  }
  const owner = String(row.owner_mac).toUpperCase();
  if (owner === mac) return json({ ok: false, error: 'own_code' });
  // Le propriétaire doit TOUJOURS être payé au moment du rattachement.
  const ost = await d1StatusForMac(env, owner);
  if (!ost || !ost.paid || ost.expired || ost.frozen || ost.banned) {
    return json({ ok: false, error: 'owner_not_paid' });
  }
  // Le PLAN FAMILLE du propriétaire doit être actif (option vendue).
  const plan = await familyPlanFor(env, owner);
  if (!plan.enabled) {
    return json({ ok: false, error: 'plan_required' });
  }
  // Plafond du plan (hors ce mac s'il re-tape le code).
  const cnt = await env.DB
    .prepare('SELECT COUNT(*) AS n FROM app_family_links WHERE owner_mac = ? AND member_mac != ?')
    .bind(owner, mac).first();
  if (((cnt && Number(cnt.n)) || 0) >= plan.max) {
    return json({ ok: false, error: 'family_full', max: plan.max });
  }
  await env.DB
    .prepare('INSERT OR REPLACE INTO app_family_links (member_mac, owner_mac, created_at) VALUES (?, ?, ?)')
    .bind(mac, owner, Date.now()).run();
  return json({ ok: true, owner: maskMac(owner) });
}

/// GET /api/family/info/:mac → vue famille (propriétaire OU membre).
async function handleFamilyInfo(env, rawMac) {
  const mac = String(rawMac || '').toUpperCase();
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  if (!env.DB || !(await ensureFamilySchema(env))) {
    return familyUnavailable();
  }
  const ownerMac = await familyOwnerOf(env, mac);
  if (ownerMac) {
    return json({ ok: true, role: 'member', owner: maskMac(ownerMac) });
  }
  const plan = await familyPlanFor(env, mac);
  const rows = await env.DB
    .prepare('SELECT member_mac, label, created_at FROM app_family_links WHERE owner_mac = ? ORDER BY created_at ASC')
    .bind(mac).all();
  const members = ((rows && rows.results) || []).map((r) => ({
    mac: r.member_mac, // le propriétaire voit SES appareils en clair
    label: r.label || null, // « Papa », « Maman »… (nommé dans l'app)
    since: r.created_at,
  }));
  const codeRow = await env.DB
    .prepare('SELECT code, expires_at FROM app_family_codes WHERE owner_mac = ? AND expires_at > ?')
    .bind(mac, Date.now()).first();
  return json({
    ok: true,
    role: 'owner',
    plan: plan.enabled, // false → l'app affiche « option à demander au vendeur »
    members,
    max: plan.max,
    code: codeRow ? codeRow.code : null,
    code_expires_at: codeRow ? codeRow.expires_at : null,
  });
}

/// POST /api/family/rename { mac, member, label } — le PROPRIÉTAIRE nomme un
/// appareil de sa famille (« Papa », « Maman »… façon profils Netflix).
async function handleFamilyRename(request, env) {
  let body;
  try { body = await request.json(); } catch (_) { return badRequest('invalid JSON body'); }
  const mac = String(body?.mac || '').toUpperCase();
  const member = String(body?.member || '').toUpperCase();
  if (!MAC_RX.test(mac) || !MAC_RX.test(member)) return badRequest('invalid mac');
  if (!env.DB || !(await ensureFamilySchema(env))) {
    return familyUnavailable();
  }
  const label = String(body?.label || '').trim().slice(0, 24);
  // Seul le propriétaire du lien peut nommer (WHERE owner_mac = mac).
  await env.DB
    .prepare('UPDATE app_family_links SET label = ? WHERE member_mac = ? AND owner_mac = ?')
    .bind(label.length > 0 ? label : null, member, mac).run();
  return json({ ok: true });
}

/// POST /api/family/remove { mac, member? } — le propriétaire détache un
/// membre ; sans `member`, l'appareil se détache LUI-MÊME (quitter).
async function handleFamilyRemove(request, env) {
  let body;
  try { body = await request.json(); } catch (_) { return badRequest('invalid JSON body'); }
  const mac = String(body?.mac || '').toUpperCase();
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  if (!env.DB || !(await ensureFamilySchema(env))) {
    return familyUnavailable();
  }
  const member = String(body?.member || '').toUpperCase();
  if (member) {
    // Détachement par le PROPRIÉTAIRE uniquement (le lien doit lui appartenir).
    await env.DB
      .prepare('DELETE FROM app_family_links WHERE member_mac = ? AND owner_mac = ?')
      .bind(member, mac).run();
  } else {
    await env.DB
      .prepare('DELETE FROM app_family_links WHERE member_mac = ?')
      .bind(mac).run();
  }
  return json({ ok: true });
}

// =========================================================
//  STATUS PUBLIC — appelé par l'app à chaque démarrage juste
//  après le heartbeat, pour savoir si elle doit afficher
//  l'écran 'essai expiré' ou 'compte gelé'.
// =========================================================
async function handlePublicStatus(env, mac) {
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  // D1 en priorite. Si la MAC n'est pas encore connue (status appele
  // avant le heartbeat), on la cree pour demarrer l'essai 7 j.
  if (env.DB) {
    // « Conscient de la famille » : un membre rattaché hérite du statut
    // (payé/échéance) de son propriétaire — cf. familyStatusForMac.
    let d1 = await familyStatusForMac(env, mac);
    if (!d1) {
      await ensureD1Device(env, mac);
      d1 = await familyStatusForMac(env, mac);
    }
    if (d1) return json(d1);
  }
  const data = await readClient(env, mac);
  return json(computeStatus(data));
}

// =========================================================
//  ACTIONS RAPIDES ADMIN — boutons du panel web qui mutent
//  un seul champ à la fois sans nécessiter de renvoyer tout
//  l'objet client.
//
//  POST /admin/clients/:mac/action  body: { action: 'freeze' | ... }
//
//  Actions supportées :
//    freeze     → status = 'frozen'
//    unfreeze   → status = 'active'
//    ban        → status = 'banned'
//    mark_paid  → paid = true
//    mark_unpaid→ paid = false
//    renew      → trial_until = now + (body.days || 365) * DAY_MS
//    note       → note = body.note
// =========================================================

// Publication temps réel après une action admin legacy : l'appareil
// re-fetch son statut, et les panels ouverts (autres onglets/admins)
// reçoivent `changed` pour rafraîchir leurs listes — même comportement
// que le wrapper withRt d'api_v1.js. Les deux publications partent EN
// PARALLÈLE (une seule latence de hub, pas deux). Fail-open comme
// publishRt : jamais d'erreur remontée au client HTTP.
async function publishAdminStatusSync(env, mac) {
  const [rt] = await Promise.all([
    publishRt(env, {
      targets: [mac.toUpperCase()],
      event: { type: 'sync', what: 'status' },
    }),
    publishRt(env, {
      targets: 'admins',
      event: { type: 'changed', scope: 'devices', mac: mac.toUpperCase() },
    }),
  ]);
  return rt;
}

async function handleAdminAction(request, env, mac) {
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return badRequest('invalid JSON body');
  }
  const action = body?.action;
  const now = Date.now();

  // ===============================================================
  //  CHEMIN D1 — la SOURCE DE VÉRITÉ que l'app LIT (/api/status).
  //
  //  CORRECTIF "l'activation à distance ne marche plus" : avant, ces
  //  actions n'écrivaient que dans le KV (client:mac), alors que
  //  l'app lit l'état dans D1 (table `licenses`/`devices`). Les
  //  appareils récents n'existent QUE dans D1 (créés au heartbeat),
  //  donc le panel ne pouvait plus rien activer. On écrit désormais
  //  directement en D1 (licence + block_status), exactement comme
  //  l'endpoint d'activation /api/v1. app_id par défaut 'app_7motion'
  //  (d1StatusForMac ignore l'app_id, il prend la meilleure licence).
  // ===============================================================
  if (env.DB) {
    await ensureD1Device(env, mac, now);
    const dev = await env.DB
      .prepare('SELECT id, customer_id FROM devices WHERE mac = ?')
      .bind(mac).first();
    if (!dev) return notFound(`Device ${mac} introuvable`);
    const APP_ID = 'app_7motion';

    // Crée ou renouvelle la licence active du device. expiresAt=null
    // → abonnement À VIE. Activer = on dégèle aussi le device (sinon
    // un block_status résiduel primerait sur la licence).
    async function setLicense(plan, expiresAt) {
      const lic = await env.DB
        .prepare(
          `SELECT id FROM licenses WHERE device_id = ?
           ORDER BY (expires_at IS NULL) DESC, expires_at DESC LIMIT 1`,
        ).bind(dev.id).first();
      if (lic) {
        await env.DB.prepare(
          `UPDATE licenses SET status='active', plan=?, expires_at=?, updated_at=? WHERE id=?`,
        ).bind(plan, expiresAt, now, lic.id).run();
      } else {
        const lid = 'lic_' + crypto.randomUUID().replace(/-/g, '').slice(0, 18);
        await env.DB.prepare(
          `INSERT INTO licenses
            (id, customer_id, device_id, app_id, status, plan, started_at,
             expires_at, auto_renew, reseller_id, created_at, updated_at)
           VALUES (?, ?, ?, ?, 'active', ?, ?, ?, 0, ?, ?, ?)`,
        ).bind(lid, dev.customer_id, dev.id, APP_ID, plan, now, expiresAt, null, now, now).run();
      }
      await env.DB.prepare('UPDATE devices SET block_status = NULL WHERE id = ?')
        .bind(dev.id).run();
    }

    switch (action) {
      case 'freeze':
        await env.DB.prepare('UPDATE devices SET block_status=? WHERE id=?')
          .bind('frozen', dev.id).run();
        break;
      case 'unfreeze':
        await env.DB.prepare('UPDATE devices SET block_status=NULL WHERE id=?')
          .bind(dev.id).run();
        break;
      case 'ban':
        await env.DB.prepare('UPDATE devices SET block_status=? WHERE id=?')
          .bind('banned', dev.id).run();
        break;
      // « Marquer payé » historique = activation À VIE (comportement
      // attendu par le revendeur). Alias explicite : activate_lifetime.
      case 'mark_paid':
      case 'activate_lifetime':
        await setLicense('lifetime', null);
        break;
      case 'activate_year':
        await setLicense('1y', now + 365 * DAY_MS);
        break;
      case 'renew': {
        const days = Number(body?.days) > 0 ? Number(body.days) : 365;
        const cur = await env.DB
          .prepare(
            `SELECT expires_at FROM licenses WHERE device_id = ?
             ORDER BY (expires_at IS NULL) DESC, expires_at DESC LIMIT 1`,
          ).bind(dev.id).first();
        if (cur && cur.expires_at === null) {
          await setLicense('lifetime', null); // déjà à vie → reste à vie
        } else {
          const base = cur && cur.expires_at && cur.expires_at > now ? cur.expires_at : now;
          await setLicense(days >= 365 ? '1y' : 'custom', base + days * DAY_MS);
        }
        break;
      }
      case 'mark_unpaid':
        await env.DB.prepare(
          `UPDATE licenses SET status='inactive', updated_at=? WHERE device_id=?`,
        ).bind(now, dev.id).run();
        break;
      case 'note': {
        // La note est une métadonnée admin → conservée en KV (sans
        // effet sur le statut lu par l'app).
        const ex = (await readClient(env, mac)) || { mac, added_at: now };
        await writeClient(env, mac, { ...ex, note: String(body?.note || ''), updated_at: now });
        break;
      }
      // PLAN FAMILLE (option vendue) : autorise ce client à PARTAGER son
      // abonnement (code d'invitation, `max` proches — défaut 4, plafond 6).
      // family_off NE supprime PAS les liens : les membres cessent d'hériter
      // immédiatement, et tout revient si l'option est réactivée.
      case 'family_on': {
        await ensureFamilySchema(env);
        const max = Number(body?.max) > 0 ? Math.min(Number(body.max), 6) : 4;
        await env.DB.prepare(
          'INSERT OR REPLACE INTO app_family_plan (owner_mac, enabled, max_members, updated_at) VALUES (?, 1, ?, ?)',
        ).bind(mac.toUpperCase(), max, now).run();
        break;
      }
      case 'family_off':
        await ensureFamilySchema(env);
        await env.DB.prepare(
          'INSERT OR REPLACE INTO app_family_plan (owner_mac, enabled, max_members, updated_at) VALUES (?, 0, NULL, ?)',
        ).bind(mac.toUpperCase(), now).run();
        break;
      // GESTION DIRECTE PAR LE REVENDEUR : ajouter/nommer/retirer un membre
      // de la famille de :mac SANS que le client tape de code. `family_add`
      // AUTO-ACTIVE le plan (défaut 4) s'il ne l'était pas — « active-moi ça »
      // en un seul geste. Le membre hérite du statut dès son prochain ping.
      case 'family_add': {
        await ensureFamilySchema(env);
        const member = String(body?.member || '').toUpperCase();
        if (!MAC_RX.test(member)) return badRequest('invalid member mac');
        if (member === mac.toUpperCase()) return badRequest('member = owner');
        let plan = await familyPlanFor(env, mac);
        if (!plan.enabled) {
          await env.DB.prepare(
            'INSERT OR REPLACE INTO app_family_plan (owner_mac, enabled, max_members, updated_at) VALUES (?, 1, 4, ?)',
          ).bind(mac.toUpperCase(), now).run();
          plan = { enabled: true, max: 4 };
        }
        const cnt = await env.DB
          .prepare('SELECT COUNT(*) AS n FROM app_family_links WHERE owner_mac = ? AND member_mac != ?')
          .bind(mac.toUpperCase(), member).first();
        if (((cnt && Number(cnt.n)) || 0) >= plan.max) {
          return json({ ok: false, error: 'family_full', max: plan.max });
        }
        const label = String(body?.label || '').trim().slice(0, 24);
        await env.DB.prepare(
          'INSERT OR REPLACE INTO app_family_links (member_mac, owner_mac, created_at, label) VALUES (?, ?, ?, ?)',
        ).bind(member, mac.toUpperCase(), now, label.length > 0 ? label : null).run();
        break;
      }
      case 'family_rename': {
        await ensureFamilySchema(env);
        const member = String(body?.member || '').toUpperCase();
        if (!MAC_RX.test(member)) return badRequest('invalid member mac');
        const label = String(body?.label || '').trim().slice(0, 24);
        await env.DB.prepare(
          'UPDATE app_family_links SET label = ? WHERE member_mac = ? AND owner_mac = ?',
        ).bind(label.length > 0 ? label : null, member, mac.toUpperCase()).run();
        break;
      }
      case 'family_remove': {
        await ensureFamilySchema(env);
        const member = String(body?.member || '').toUpperCase();
        if (!MAC_RX.test(member)) return badRequest('invalid member mac');
        await env.DB.prepare(
          'DELETE FROM app_family_links WHERE member_mac = ? AND owner_mac = ?',
        ).bind(member, mac.toUpperCase()).run();
        break;
      }
      default:
        return badRequest(
          'action must be one of: freeze, unfreeze, ban, mark_paid, '
          + 'activate_lifetime, activate_year, mark_unpaid, renew, note, '
          + 'family_on, family_off, family_add, family_rename, family_remove',
        );
    }

    // Miroir KV : le PANEL liste/affiche depuis le KV
    // (handleGetClientsList). Pour qu'il continue d'afficher le bon
    // statut SANS rien changer à son UI, on reflète l'action dans le
    // client KV (l'app, elle, lit le D1 ci-dessus). La 'note' a déjà
    // été écrite dans le switch. Best-effort : un échec du miroir ne
    // compromet pas l'écriture D1 (qui, elle, débloque l'app).
    if (action !== 'note') {
      try {
        const ex = (await readClient(env, mac)) || { mac, added_at: now, name: '' };
        const m = { ...ex, updated_at: now };
        switch (action) {
          case 'freeze': m.status = 'frozen'; break;
          case 'unfreeze': m.status = 'active'; break;
          case 'ban': m.status = 'banned'; break;
          case 'mark_paid':
          case 'activate_lifetime':
            m.status = 'active'; m.paid = true; m.plan = 'lifetime'; m.paid_until = null;
            break;
          case 'activate_year':
            m.status = 'active'; m.paid = true; m.plan = '1y';
            m.paid_until = now + 365 * DAY_MS; m.trial_until = m.paid_until;
            break;
          case 'renew': {
            const days = Number(body?.days) > 0 ? Number(body.days) : 365;
            const base = m.paid_until && m.paid_until > now ? m.paid_until : now;
            m.status = 'active'; m.paid = true; m.plan = days >= 365 ? '1y' : 'custom';
            m.paid_until = base + days * DAY_MS; m.trial_until = m.paid_until;
            break;
          }
          case 'mark_unpaid': m.paid = false; m.plan = null; m.paid_until = null; break;
        }
        await writeClient(env, mac, m);
      } catch (_) { /* miroir best-effort */ }
    }

    const fresh = await d1StatusForMac(env, mac, now);
    // Temps réel (fail-open) : si l'appareil est connecté au hub, il
    // re-fetch son statut IMMÉDIATEMENT (au lieu d'attendre le polling).
    // `rt.delivered ≥ 1` → le panel peut afficher « appliqué en direct ».
    const rt = await publishAdminStatusSync(env, mac);
    return json({ ok: true, mac, action, ...(fresh || {}), rt });
  }

  // ===============================================================
  //  CHEMIN KV (legacy, seulement si D1 indisponible). On enrichit
  //  du plan (à vie / 1 an) pour l'affichage côté app.
  // ===============================================================
  const existing = await readClient(env, mac);
  if (!existing) return notFound(`Client ${mac} introuvable`);
  const updated = { ...existing, updated_at: now };

  switch (action) {
    case 'freeze':
      updated.status = 'frozen';
      break;
    case 'unfreeze':
      updated.status = 'active';
      break;
    case 'ban':
      updated.status = 'banned';
      break;
    case 'mark_paid':
    case 'activate_lifetime':
      updated.paid = true;
      updated.plan = 'lifetime';
      updated.paid_until = null;
      break;
    case 'activate_year':
      updated.paid = true;
      updated.plan = '1y';
      updated.paid_until = now + 365 * DAY_MS;
      updated.trial_until = updated.paid_until;
      break;
    case 'mark_unpaid':
      updated.paid = false;
      updated.plan = null;
      updated.paid_until = null;
      break;
    case 'renew': {
      const days = Number(body?.days) > 0 ? Number(body.days) : 365;
      const base = updated.paid_until && updated.paid_until > now ? updated.paid_until : now;
      updated.paid = true;
      updated.plan = days >= 365 ? '1y' : 'custom';
      updated.paid_until = base + days * DAY_MS;
      updated.trial_until = updated.paid_until;
      break;
    }
    case 'note':
      updated.note = String(body?.note || '');
      break;
    default:
      return badRequest(
        'action must be one of: freeze, unfreeze, ban, mark_paid, '
        + 'activate_lifetime, activate_year, mark_unpaid, renew, note',
      );
  }

  await writeClient(env, mac, updated);
  // Même hook temps réel que le chemin D1 : fail-open, jamais bloquant.
  const rt = await publishAdminStatusSync(env, mac);
  return json({ ok: true, mac, ...updated, rt });
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
  // métadonnées admin comme added_at). `jsonPrivate` = pas de CORS '*'
  // (ces playlists peuvent contenir des identifiants/URLs sensibles).
  return jsonPrivate({
    name: data.name || '',
    playlists: data.playlists || [],
  });
}

// /api/servers — public.
//
//  Liste des serveurs IPTV par défaut proposés dans l'app
//  (« Serveur 1 », « Serveur 2 »…). Le client ne saisit JAMAIS d'URL :
//  il choisit un serveur dans cette liste et ne tape que son code
//  Xtream (utilisateur + mot de passe).
//
//  ⚠️ Conformité AGENTS.md règle n°2 : aucune URL de flux IPTV n'est
//  écrite en dur dans le code de PRODUCTION de l'app (lib/). Les URLs
//  vivent UNIQUEMENT côté serveur, dans la variable d'environnement
//  `DEFAULT_SERVERS` (cf. wrangler.toml [vars]). On peut donc les
//  changer puis `wrangler deploy` SANS re-publier l'app.
//
//  Format attendu de la variable (chaîne JSON) :
//    [{"id":"srv1","label":"Serveur 1","url":"http://exemple:8080"},
//     {"id":"srv2","label":"Serveur 2","url":"http://autre:8080"}]
//
//  `url` = base du serveur Xtream (avec le port si nécessaire), SANS
//  `/get.php` ni identifiants — l'app les ajoute à partir du code que
//  le client saisit.
//
//  Source de vérité :
//    1. Table D1 `default_servers` — éditée depuis le PANEL ADMIN
//       (ajouter / changer / supprimer des serveurs « Serveur 1, 2,
//       3… »). C'est la source normale.
//    2. Repli sur la variable d'environnement `DEFAULT_SERVERS` si la
//       base D1 est absente, vide, ou en erreur (ex. migration pas
//       encore jouée) — ça garantit que l'app a toujours au moins le
//       serveur par défaut.
async function handlePublicServers(env) {
  // --- 1. D1 (panel admin) ---
  if (env.DB) {
    try {
      const rs = await env.DB
        .prepare(
          `SELECT id, label, url FROM default_servers
            WHERE enabled = 1
            ORDER BY position ASC, created_at ASC`,
        )
        .all();
      const rows = (rs && rs.results) || [];
      if (rows.length > 0) {
        return json({
          servers: rows.map((r) => ({
            id: String(r.id),
            label: String(r.label),
            url: String(r.url).trim(),
          })),
        });
      }
    } catch (_) {
      // Table absente / D1 indisponible → on tombe sur le repli env.
    }
  }

  // --- 2. Repli : variable d'environnement DEFAULT_SERVERS ---
  let servers = [];
  const raw = env.DEFAULT_SERVERS;
  if (raw) {
    try {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        servers = parsed
          .filter((s) => s && typeof s.url === 'string' && s.url.trim())
          .map((s, i) => ({
            id: String(s.id || `srv${i + 1}`),
            label: String(s.label || `Serveur ${i + 1}`),
            url: String(s.url).trim(),
          }));
      }
    } catch (_) {
      // Variable mal formée : on renvoie une liste vide plutôt que
      // de faire planter l'app. L'admin verra le souci en testant.
    }
  }
  return json({ servers });
}

// /api/device-source/:mac — public.
//
//  Renvoie la source IPTV (Xtream/M3U) assignée à cet appareil par
//  son admin/revendeur depuis le panel. L'app la charge automatiquement
//  au démarrage — le client n'a RIEN à saisir.
//
//  Réponse :
//    { "mac": "MK:..", "source": null }                 (rien d'assigné)
//    { "mac": "MK:..", "source": { type:"xtream", ... }} (Xtream)
//    { "mac": "MK:..", "source": { type:"m3u", ... }}    (M3U)
//
//  Identifiant = la MAC (même modèle public que /config/:mac et
//  /api/status/:mac). Lecture en D1 (table device_sources).
// GET /api/device-messages/:mac (public) — la BOÎTE de messages persistants
// de l'appareil. Renvoie les messages NON ENCORE LIVRÉS, les marque livrés
// (accusé de réception côté panel via delivered_at), puis l'app les affiche.
// Best-effort : si la table n'existe pas / D1 absent → liste vide (jamais
// d'erreur qui casserait le boot de l'app).
async function handlePublicDeviceMessages(env, mac) {
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  const MAC = mac.toUpperCase();
  if (!env.DB) return json({ items: [] });
  try {
    await env.DB.prepare(
      'CREATE TABLE IF NOT EXISTS device_messages (' +
        'id INTEGER PRIMARY KEY AUTOINCREMENT, mac TEXT, title TEXT, body TEXT, ' +
        'kind TEXT, duration_sec INTEGER, created_at INTEGER, ' +
        'delivered_at INTEGER, read_at INTEGER)',
    ).run();
    const rs = await env.DB
      .prepare(
        'SELECT id, title, body, kind, duration_sec, created_at ' +
          'FROM device_messages WHERE mac = ? AND delivered_at IS NULL ' +
          'ORDER BY id ASC LIMIT 10',
      )
      .bind(MAC)
      .all();
    const items = (rs.results || []).map((r) => ({
      id: r.id,
      title: r.title || '',
      body: r.body || '',
      kind: r.kind || 'info',
      durationSec: r.duration_sec || 45,
      createdAt: r.created_at || 0,
    }));
    if (items.length) {
      // Marque « livré » — l'accusé de réception apparaît côté panel.
      const now = Date.now();
      const ids = items.map((i) => i.id);
      const ph = ids.map(() => '?').join(',');
      await env.DB
        .prepare(`UPDATE device_messages SET delivered_at = ? WHERE id IN (${ph})`)
        .bind(now, ...ids)
        .run();
    }
    return json({ items });
  } catch (_) {
    return json({ items: [] });
  }
}

// POST /api/device-messages/:mac/read {id} (public) — l'app confirme avoir
// AFFICHÉ le message à l'écran → read_at. Accusé de LECTURE (le panel montre
// « lu le… »). Best-effort, idempotent (ne réécrit pas un read_at existant).
async function handlePublicDeviceMessageRead(env, mac, request) {
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  const MAC = mac.toUpperCase();
  if (!env.DB) return json({ ok: true });
  let body;
  try { body = await request.json(); } catch (_) { body = {}; }
  const id = parseInt(body && body.id, 10);
  if (!Number.isFinite(id)) return json({ ok: true });
  try {
    await env.DB
      .prepare('UPDATE device_messages SET read_at = ? WHERE id = ? AND mac = ? AND read_at IS NULL')
      .bind(Date.now(), id, MAC)
      .run();
  } catch (_) { /* best-effort */ }
  return json({ ok: true });
}

async function handlePublicDeviceSource(env, mac) {
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  const MAC = mac.toUpperCase();

  // ===== SÉCURITÉ : verrou licence CÔTÉ SERVEUR =====
  //  On ne livre la source (= identifiants IPTV : serveur, user, mdp) QUE
  //  si l'abonnement de cet appareil est jouable. Si la licence est
  //  EXPIRÉE / GELÉE / BANNIE, on renvoie une source VIDE → un non-payant
  //  ne peut PAS récupérer les identifiants ni charger les flux, même s'il
  //  contourne l'écran de paiement de l'app. C'est le serveur qui décide,
  //  pas l'app (impossible à bidouiller côté client).
  //  - Appareil inconnu / tout neuf / essai en cours  → null = NON bloqué
  //    (d1StatusForMac renvoie null ou expired=false) → la source passe.
  //  - Incident DB (lecture statut impossible)         → fail-open (on ne
  //    coupe pas un client légitime sur une panne transitoire).
  if (env.DB) {
    try {
      // « Conscient de la famille » : un membre rattaché à un proprio payé
      // n'est PAS bloqué (il hérite de sa licence).
      const st = await familyStatusForMac(env, MAC);
      if (st && (st.expired || st.frozen || st.banned)) {
        return jsonPrivate({
          mac: MAC,
          source: null,
          sources: [],
          blocked: st.banned ? 'banned' : st.frozen ? 'frozen' : 'expired',
        });
      }
    } catch (_) {
      // fail-open : on ne bloque jamais sur un incident de lecture du statut.
    }
  }

  // 1) D1 `device_sources` — sources assignées via le portail api_v1
  //    (activation avec source). Source prioritaire.
  if (env.DB) {
    try {
      let row = await env.DB
        .prepare(
          `SELECT type, label, server_url, username, password, m3u_url, epg_url, sources_json, updated_at
             FROM device_sources WHERE mac = ?`,
        )
        .bind(MAC)
        .first();
      // FAMILLE : pas de source assignée à CE membre → il reçoit celle de
      // son PROPRIÉTAIRE (même abonnement, même bouquet). Best-effort.
      if (!row) {
        try {
          const ownerMac = await familyOwnerOf(env, MAC);
          if (ownerMac) {
            row = await env.DB
              .prepare(
                `SELECT type, label, server_url, username, password, m3u_url, epg_url, sources_json, updated_at
                   FROM device_sources WHERE mac = ?`,
              )
              .bind(String(ownerMac).toUpperCase())
              .first();
          }
        } catch (_) { /* fail-open */ }
      }
      if (row) {
        // TRIO : si un tableau de sources est stocké, on le renvoie en
        // entier (l'app charge les 3). Sinon, la source simple historique.
        let sources = [];
        if (row.sources_json) {
          try { sources = JSON.parse(row.sources_json) || []; } catch (_) { sources = []; }
        }
        if (!sources.length) {
          const { sources_json, updated_at, ...single } = row;
          sources = [single];
        }
        return jsonPrivate({ mac: MAC, source: sources[0] || null, sources });
      }
    } catch (_) {
      // Table absente / D1 indisponible → on tente le repli KV ci-dessous.
    }
  }

  // 2) REPLI KV (client.playlists) — CORRECTIF "l'app ne se connecte pas
  //    avec mon panel" : le PANEL intégré (/admin/panel) enregistre les
  //    playlists dans le KV, pas dans device_sources. Sans ce repli,
  //    l'app (qui lit device_sources) ne voyait jamais la source assignée
  //    via le panel. On convertit la 1ère playlist KV au format `source`
  //    attendu par l'app → la source est livrée quel que soit l'outil.
  try {
    const client = await readClient(env, MAC);
    const pls = client && Array.isArray(client.playlists) ? client.playlists : [];
    if (pls.length > 0) {
      const p = pls[0] || {};
      const label = p.name || (client && client.name) || 'Mon abonnement';
      const updatedAt = (client && client.updated_at) || 0;
      let source = null;
      if (p.type === 'xtream' && p.server && p.username && p.password) {
        source = {
          type: 'xtream',
          label,
          server_url: p.server,
          username: p.username,
          password: p.password,
          m3u_url: null,
          epg_url: p.epg_url || null,
          updated_at: updatedAt,
        };
      } else if (p.type === 'm3u' && p.url) {
        source = {
          type: 'm3u',
          label,
          server_url: null,
          username: null,
          password: null,
          m3u_url: p.url,
          epg_url: p.epg_url || null,
          updated_at: updatedAt,
        };
      }
      if (source) return jsonPrivate({ mac: MAC, source });
    }
  } catch (_) {
    // KV indisponible → pas de source.
  }

  return jsonPrivate({ mac: MAC, source: null });
}

// /api/self-source/:mac — SELF-SERVICE « Mon espace » (façon IBO Player Pro).
//  Le client gère LUI-MÊME PLUSIEURS playlists (M3U ou Xtream) sur SA propre MAC
//  depuis /mon-espace : les LIRE (GET), en AJOUTER / MODIFIER (POST), en
//  SUPPRIMER (DELETE). L'app lit ensuite /api/device-source/:mac et charge
//  TOUTES les sources (elle boucle sur le tableau `sources`).
//
//  MODÈLE MULTI-LISTES : une MAC = un tableau `sources_json` d'items. Chaque item
//  porte une `origin` : 'self' (posé par le client, MODIFIABLE) ou 'panel'
//  (assigné par TON panel = client payant, VERROUILLÉ). Un item sans origin est
//  traité comme 'panel' (défaut SÛR) — SAUF migration : si l'ancienne ligne
//  entière était marquée origin='self' (v1 mono-liste), ses items héritent
//  'self' (on ne casse pas le contrôle d'un client déjà passé par /mon-espace).
//
//  SÉCURITÉ :
//   1. VERROU PAYANTS : les items 'panel' ne sont JAMAIS modifiés/supprimés ici.
//      Le client peut TOUJOURS AJOUTER les siens à côté (« ça avale toujours »).
//   2. Le mot de passe Xtream n'est JAMAIS relu (GET ne le renvoie pas).
//   3. Plafond MAX_SELF_SOURCES items 'self' (anti-abus). Rate-limité (bucket
//      'dev'). La route GET /api/device-source/:mac (lue par l'app) reste
//      100 % INCHANGÉE.
const MAX_SELF_SOURCES = 20;

// Crée la table si besoin + garantit la colonne `origin` (migration idempotente).
async function ensureDeviceSourcesTable(env) {
  try {
    await env.DB.prepare(
      `CREATE TABLE IF NOT EXISTS device_sources (
         mac TEXT PRIMARY KEY, type TEXT NOT NULL, label TEXT, server_url TEXT,
         username TEXT, password TEXT, m3u_url TEXT, epg_url TEXT,
         sources_json TEXT, updated_at INTEGER NOT NULL)`,
    ).run();
  } catch (_) { /* déjà créée par le panel */ }
  try { await env.DB.prepare('ALTER TABLE device_sources ADD COLUMN origin TEXT').run(); } catch (_) { /* déjà là */ }
}

// Lit la liste d'items d'une MAC, NORMALISÉE : chaque item a une `origin`
// ('self'|'panel') et, pour les 'self', un `id` stable. Renvoie aussi si une
// écriture est nécessaire pour PERSISTER des ids fraîchement attribués.
async function readDeviceSourceItems(env, MAC) {
  let row;
  try {
    row = await env.DB.prepare(
      `SELECT type, label, server_url, username, password, m3u_url, epg_url, sources_json, origin
         FROM device_sources WHERE mac = ?`,
    ).bind(MAC).first();
  } catch (_) { row = null; }
  if (!row) return { items: [], needsPersist: false };

  let items = [];
  if (row.sources_json) {
    try { items = JSON.parse(row.sources_json) || []; } catch (_) { items = []; }
  }
  if (!Array.isArray(items) || !items.length) {
    // Repli ligne « simple » historique → 1 item depuis les colonnes plates.
    items = [{
      type: row.type, label: row.label, server_url: row.server_url,
      username: row.username, password: row.password, m3u_url: row.m3u_url, epg_url: row.epg_url,
    }];
  }
  // Migration douce : item sans origin → hérite de l'origin LIGNE si elle vaut
  // 'self' (client v1 mono-liste), sinon 'panel' (défaut sûr, protège payants).
  const rowSelf = String(row.origin || '') === 'self';
  let needsPersist = false;
  items = items.map((s) => {
    const it = { ...s };
    if (it.origin !== 'self' && it.origin !== 'panel') {
      it.origin = rowSelf ? 'self' : 'panel';
      needsPersist = true;
    }
    if (it.origin === 'self' && !it.id) { it.id = crypto.randomUUID(); needsPersist = true; }
    return it;
  });
  return { items, needsPersist };
}

// Écrit la liste complète : colonnes plates = items[0] (compat app/panel), plus
// `sources_json` (tableau entier) + `origin` ligne (= 'self' si TOUT est self).
async function writeDeviceSourceItems(env, MAC, items) {
  if (!items.length) {
    await env.DB.prepare('DELETE FROM device_sources WHERE mac = ?').bind(MAC).run();
    return;
  }
  const first = items[0];
  const rowOrigin = items.every((s) => s.origin === 'self') ? 'self' : 'panel';
  const jsonStr = JSON.stringify(items);
  await env.DB.prepare(
    `INSERT INTO device_sources
       (mac, type, label, server_url, username, password, m3u_url, epg_url, sources_json, origin, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(mac) DO UPDATE SET
       type=excluded.type, label=excluded.label, server_url=excluded.server_url,
       username=excluded.username, password=excluded.password, m3u_url=excluded.m3u_url,
       epg_url=excluded.epg_url, sources_json=excluded.sources_json,
       origin=excluded.origin, updated_at=excluded.updated_at`,
  ).bind(
    MAC, first.type, first.label || null, first.server_url || null, first.username || null,
    first.password || null, first.m3u_url || null, first.epg_url || null, jsonStr, rowOrigin, Date.now(),
  ).run();
}

// Vue publique d'un item : SANS mot de passe, avec l'info de verrouillage.
function publicItemView(it, idx) {
  const locked = it.origin !== 'self';
  return {
    id: it.id || (locked ? ('panel-' + idx) : null),
    origin: it.origin,
    locked,
    type: it.type || 'm3u',
    label: it.label || 'Ma playlist',
    server_url: it.server_url || null,
    username: it.username || null,
    m3u_url: it.m3u_url || null,
    epg_url: it.epg_url || null,
    has_password: !!it.password,
  };
}

// Valide + construit un item à partir du corps de requête (POST).
function buildSourceFromBody(body) {
  const type = String(body.type || '').trim().toLowerCase();
  const label = (String(body.label || '').trim() || 'Ma playlist').slice(0, 80);
  const epgRaw = String(body.epg_url || '').trim();
  const epg = epgRaw && /^https?:\/\//i.test(epgRaw) ? epgRaw.slice(0, 2048) : null;
  if (type === 'xtream') {
    const server = String(body.server_url || '').trim().slice(0, 2048);
    const user = String(body.username || '').trim().slice(0, 256);
    const pass = String(body.password || '').trim().slice(0, 256);
    if (!server || !user || !pass) return { error: 'xtream requires server_url, username, password' };
    if (!/^https?:\/\//i.test(server)) return { error: 'server_url must start with http(s)://' };
    return { source: { type: 'xtream', label, server_url: server, username: user, password: pass, m3u_url: null, epg_url: epg } };
  }
  if (type === 'm3u') {
    const m3u = String(body.m3u_url || '').trim().slice(0, 2048);
    if (!m3u) return { error: 'm3u requires m3u_url' };
    if (!/^https?:\/\//i.test(m3u)) return { error: 'm3u_url must start with http(s)://' };
    return { source: { type: 'm3u', label, server_url: null, username: null, password: null, m3u_url: m3u, epg_url: epg } };
  }
  return { error: "type must be 'xtream' or 'm3u'" };
}

// GET /api/self-source/:mac — liste des playlists de « Mon espace ».
async function handleSelfSourceGet(env, mac) {
  if (!env.DB) return json({ ok: false, error: 'db_unavailable' }, 503);
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  const MAC = mac.toUpperCase();
  await ensureDeviceSourcesTable(env);
  const { items, needsPersist } = await readDeviceSourceItems(env, MAC);
  // Persiste les ids/origins fraîchement attribués (migration douce, one-shot).
  if (needsPersist && items.length) {
    try { await writeDeviceSourceItems(env, MAC, items); } catch (_) { /* best-effort */ }
  }
  const view = items.map(publicItemView);
  const selfCount = items.filter((s) => s.origin === 'self').length;
  return json({
    ok: true, mac: MAC,
    items: view,
    count: view.length,
    canAdd: selfCount < MAX_SELF_SOURCES,
    maxItems: MAX_SELF_SOURCES,
  });
}

// POST /api/self-source/:mac — AJOUTE un item 'self' (ou MODIFIE un item 'self'
// existant si `id` est fourni). Ne touche JAMAIS un item 'panel'. « Avale
// toujours » : jamais bloqué par la présence d'une source panel.
async function handleSelfSource(env, mac, request) {
  if (!env.DB) return json({ ok: false, error: 'db_unavailable' }, 503);
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  const MAC = mac.toUpperCase();

  let body;
  try { body = await request.json(); } catch (_) { return badRequest('invalid json'); }

  const built = buildSourceFromBody(body);
  if (built.error) return badRequest(built.error);
  const source = built.source;

  await ensureDeviceSourcesTable(env);
  const { items } = await readDeviceSourceItems(env, MAC);
  const editId = body.id ? String(body.id) : null;

  if (editId) {
    // MODIFICATION : uniquement un item 'self' existant (panel = interdit).
    const idx = items.findIndex((s) => s.origin === 'self' && s.id === editId);
    if (idx < 0) {
      return json({ ok: false, reason: 'not_found', message: "Cette playlist n'existe pas ou est protégée." }, 404);
    }
    items[idx] = { ...source, origin: 'self', id: editId };
  } else {
    // AJOUT : plafond anti-abus sur les items 'self'.
    const selfCount = items.filter((s) => s.origin === 'self').length;
    if (selfCount >= MAX_SELF_SOURCES) {
      return json({
        ok: false, reason: 'too_many',
        message: 'Limite atteinte (' + MAX_SELF_SOURCES + ' playlists). Supprimez-en une pour en ajouter une autre.',
      }, 409);
    }
    items.push({ ...source, origin: 'self', id: crypto.randomUUID() });
  }

  try {
    await writeDeviceSourceItems(env, MAC, items);
  } catch (_) {
    return json({ ok: false, error: 'db_write_failed' }, 500);
  }
  return json({
    ok: true,
    message: editId
      ? 'Playlist mise à jour ! Ouvrez (ou redémarrez) l\'app.'
      : "Playlist ajoutée ! Ouvrez l'app (ou redémarrez-la) : vos chaînes vont apparaître.",
  });
}

// DELETE /api/self-source/:mac?id=<id> — supprime UN item 'self' (jamais panel).
//  Sans `id` : supprime TOUS les items 'self' (garde les 'panel' intacts).
async function handleSelfSourceDelete(env, mac, request) {
  if (!env.DB) return json({ ok: false, error: 'db_unavailable' }, 503);
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  const MAC = mac.toUpperCase();
  await ensureDeviceSourcesTable(env);

  let delId = null;
  try { delId = new URL(request.url).searchParams.get('id'); } catch (_) { delId = null; }

  const { items } = await readDeviceSourceItems(env, MAC);
  if (!items.length) return json({ ok: true, message: 'Aucune playlist à supprimer.' });

  let kept;
  if (delId) {
    const target = items.find((s) => s.id === delId);
    if (!target) return json({ ok: false, reason: 'not_found', message: 'Playlist introuvable.' }, 404);
    if (target.origin !== 'self') {
      return json({ ok: false, reason: 'locked', message: 'Cette playlist est gérée par votre conseiller.' }, 409);
    }
    kept = items.filter((s) => s.id !== delId);
  } else {
    // Purge de toutes les 'self', on garde les 'panel'.
    kept = items.filter((s) => s.origin !== 'self');
  }

  try {
    await writeDeviceSourceItems(env, MAC, kept);
  } catch (_) {
    return json({ ok: false, error: 'db_write_failed' }, 500);
  }
  return json({ ok: true, message: 'Playlist supprimée.' });
}

// /api/history/:mac — renvoie l'historique de visionnage (ids de chaînes)
// stocké pour cette MAC (rempli par le heartbeat). L'app le lit au démarrage
// pour restaurer « Récemment » / « Pour vous » sur une 2e box. Lecture seule,
// best-effort : jamais d'erreur bloquante.
async function handlePublicHistory(env, mac) {
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  const MAC = mac.toUpperCase();
  let recent = [];
  if (env.DB) {
    try {
      const row = await env.DB
        .prepare('SELECT recent_json FROM devices WHERE mac = ?')
        .bind(MAC)
        .first();
      if (row && row.recent_json) {
        try { recent = JSON.parse(row.recent_json) || []; } catch (_) { recent = []; }
      }
    } catch (_) {
      // colonne/table absente → historique vide.
    }
  }
  return json({ mac: MAC, recent });
}

// /api/m3u/:token — public. Résout un lien M3U de famille vers la vraie
// playlist. Le jeton (family_links) → source de la famille → on REDIRIGE
// vers la playlist upstream :
//   - Xtream : {server}/get.php?username=&password=&type=m3u_plus&output=ts
//   - M3U    : l'URL M3U telle quelle.
// Plusieurs jetons séparés peuvent pointer vers la MÊME source.
async function handlePublicFamilyM3u(env, rawToken) {
  if (!env.DB) return new Response('not found', { status: 404 });
  // Tolère un suffixe .m3u / .m3u8 dans l'URL.
  const token = String(rawToken || '').replace(/\.(m3u8?|ts)$/i, '').trim();
  if (!token) return new Response('not found', { status: 404 });
  try {
    const link = await env.DB
      .prepare('SELECT family_id FROM family_links WHERE token = ?')
      .bind(token).first();
    if (!link) return new Response('lien invalide', { status: 404 });
    const fam = await env.DB
      .prepare('SELECT source_json FROM families WHERE id = ?')
      .bind(link.family_id).first();
    if (!fam || !fam.source_json) return new Response('source absente', { status: 404 });
    let src;
    try { src = JSON.parse(fam.source_json); } catch (_) { src = null; }
    if (!src) return new Response('source invalide', { status: 404 });

    let target = null;
    if (src.type === 'xtream' && src.server_url && src.username && src.password) {
      const base = String(src.server_url).replace(/\/+$/, '');
      const u = encodeURIComponent(src.username);
      const p = encodeURIComponent(src.password);
      target = `${base}/get.php?username=${u}&password=${p}&type=m3u_plus&output=ts`;
    } else if (src.type === 'm3u' && src.m3u_url) {
      target = src.m3u_url;
    }
    if (!target) return new Response('source incomplète', { status: 404 });
    return Response.redirect(target, 302);
  } catch (_) {
    return new Response('erreur', { status: 500 });
  }
}

// /api/backup/:mac — public (GET + PUT).
//
//  Sauvegarde cloud "best-effort" des donnees LOCALES de l'utilisateur
//  (playlists qu'il a saisies + favoris), indexee par la MAC. Permet de
//  retrouver ses sources apres une REINSTALLATION sans les ressaisir ni
//  repayer (la MAC est derivee de l'ANDROID_ID, donc stable).
//
//  Le serveur stocke un blob JSON OPAQUE : il ne l'interprete pas.
//    GET  /api/backup/:mac        -> { mac, data: <obj|null>, updated_at }
//    PUT  /api/backup/:mac { data } -> upsert { ok, mac, updated_at }
//
//  Table creee a la volee (comme device_sources / default_servers).
async function handleDeviceBackup(request, env, mac, method) {
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  const MAC = mac.toUpperCase();
  if (!env.DB) return jsonPrivate({ mac: MAC, data: null, updated_at: 0 });

  try {
    await env.DB.prepare(
      `CREATE TABLE IF NOT EXISTS device_backups (
         mac        TEXT PRIMARY KEY,
         data_json  TEXT,
         updated_at INTEGER
       )`,
    ).run();
  } catch (_) {
    // Si la creation echoue, on degrade proprement plus bas.
  }

  if (method === 'GET') {
    try {
      const row = await env.DB
        .prepare('SELECT data_json, updated_at FROM device_backups WHERE mac = ?')
        .bind(MAC)
        .first();
      if (!row) return jsonPrivate({ mac: MAC, data: null, updated_at: 0 });
      let data = null;
      try {
        data = row.data_json ? JSON.parse(row.data_json) : null;
      } catch (_) {
        data = null;
      }
      return jsonPrivate({ mac: MAC, data, updated_at: row.updated_at || 0 });
    } catch (_) {
      return jsonPrivate({ mac: MAC, data: null, updated_at: 0 });
    }
  }

  if (method === 'PUT') {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return badRequest('invalid JSON body');
    }
    const data = body && body.data !== undefined ? body.data : body;
    let str;
    try {
      str = JSON.stringify(data);
    } catch (_) {
      return badRequest('data not serializable');
    }
    // Garde-fou taille : un backup de metadonnees est petit (< 256 Ko).
    if (str && str.length > 256 * 1024) return badRequest('backup too large');
    const now = Date.now();
    try {
      await env.DB.prepare(
        `INSERT INTO device_backups (mac, data_json, updated_at)
         VALUES (?, ?, ?)
         ON CONFLICT(mac) DO UPDATE SET
           data_json = excluded.data_json,
           updated_at = excluded.updated_at`,
      ).bind(MAC, str, now).run();
      return jsonPrivate({ ok: true, mac: MAC, updated_at: now });
    } catch (e) {
      // Pas de fuite de message interne au client (cf. P1-8) ; on loggue côté serveur.
      try { console.error('[backup] put failed', String(e && e.stack ? e.stack : e)); } catch (_) {}
      return jsonPrivate({ ok: false, error: 'backup_failed' }, 500);
    }
  }

  return badRequest('only GET/PUT supported on /api/backup/:mac');
}

// /api/ai/search — public POST. Traduit une phrase en LANGAGE NATUREL en
//  un FILTRE de recherche structuré (JSON) via Mistral. L'app applique
//  ensuite ce filtre LOCALEMENT a son catalogue (le catalogue ne quitte
//  jamais l'appareil → prive + peu couteux).
//
//  La cle Mistral vit en SECRET cote Worker (env.MISTRAL_API_KEY) —
//  jamais dans l'app. Tant que le secret n'est pas defini, l'endpoint
//  repond 503 (fonctionnalite dormante, aucun cout).
//
//  Modele par defaut : mistral-small-latest (rapide + peu cher, adapte a
//  une recherche tapee a chaque requete). Surchargeable via env.AI_MODEL.
//  API OpenAI-compatible : https://api.mistral.ai/v1/chat/completions.
async function handleAiSearch(request, env) {
  if (request.method !== 'POST') {
    return badRequest('only POST supported on /api/ai/search');
  }
  const key = env.MISTRAL_API_KEY;
  if (!key) {
    return json(
      { error: 'ai_disabled', message: 'Recherche IA non configurée.' },
      503,
    );
  }
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return badRequest('invalid JSON body');
  }
  const query =
    body && typeof body.query === 'string' ? body.query.trim() : '';
  if (!query) return badRequest('query required');
  if (query.length > 300) return badRequest('query too long');

  const model = env.AI_MODEL || 'mistral-small-latest';

  const system =
    "Tu convertis une requête utilisateur en langage naturel en un FILTRE de " +
    "recherche pour une application de lecteur multimédia (IPTV). Réponds " +
    "UNIQUEMENT par un objet JSON valide, sans texte autour, sans bloc de " +
    "code. Champs obligatoires : keywords (tableau de mots-clés simples, en " +
    "minuscules, sans articles, dans la langue de la requête) ; type " +
    "('live' pour chaînes/direct, 'movie' pour films, 'series' pour séries, " +
    "'any' si indéterminé) ; genres (tableau ; ex: sport, football, " +
    "actualités, enfants, musique, cinéma, documentaire) ; title_contains " +
    "(un titre précis si l'utilisateur en cite un, sinon chaîne vide) ; " +
    "language (langue si mentionnée, sinon chaîne vide). Laisse un champ " +
    "vide ([] ou '') s'il n'est pas pertinent. Exemple de réponse : " +
    '{"keywords":["foot","ligue 1"],"type":"live","genres":["sport",' +
    '"football"],"title_contains":"","language":"fr"}';

  try {
    const resp = await fetch('https://api.mistral.ai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${key}`,
      },
      body: JSON.stringify({
        model,
        max_tokens: 400,
        temperature: 0,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: query },
        ],
      }),
      // Time-out dur : une recherche doit rester rapide, et un amont qui pend
      // ne doit pas bloquer le worker. AbortSignal.timeout est supporté sur
      // le runtime Workers.
      signal: AbortSignal.timeout(8000),
    });
    if (!resp.ok) {
      // On NE log PAS le corps amont : selon le fournisseur il peut contenir
      // des détails internes (voire la clé en écho). On ne garde que le STATUT,
      // suffisant pour diagnostiquer (429/5xx/auth). Le corps n'est ni lu ni
      // renvoyé au client.
      console.error('[ai] upstream error', resp.status);
      return json({ error: 'ai_upstream', status: resp.status }, 502);
    }
    const data = await resp.json();
    // API OpenAI-compatible → le contenu du 1er choix est le JSON demandé.
    let filter = null;
    const content =
      data &&
      Array.isArray(data.choices) &&
      data.choices[0] &&
      data.choices[0].message &&
      typeof data.choices[0].message.content === 'string'
        ? data.choices[0].message.content
        : null;
    if (content) {
      try {
        filter = JSON.parse(content);
      } catch (_) {
        filter = null;
      }
    }
    if (!filter) return json({ error: 'ai_parse' }, 502);
    return json({ ok: true, filter });
  } catch (e) {
    try { console.error('[ai] error', String(e && e.stack ? e.stack : e)); } catch (_) {}
    return json({ error: 'ai_error' }, 502);
  }
}

// =========================================================
//  « Caster sur un écran » — appairage + signalisation (cross-réseau)
// =========================================================
//  Le téléphone crée une session (code court), affiche un QR pointant
//  vers /e/<CODE>. La TV ouvre ce lien (screen_receiver.js) et POLL
//  l'état. Le téléphone pousse des commandes (play/pause/stop). Le flux
//  IPTV est lu par la TV via la route proxy /cs/<b64>.ts (HTTPS) → pas
//  besoin que TV et téléphone soient sur le même réseau.
//
//  Stockage : table D1 `screen_sessions` (créée à la volée). Pas de
//  WebSocket → pas de Durable Objects. Signalisation = polling léger.
async function ensureScreenTable(env) {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS screen_sessions (
       code        TEXT PRIMARY KEY,
       state_json  TEXT,
       created_at  INTEGER,
       updated_at  INTEGER,
       expires_at  INTEGER
     )`,
  ).run();
}

function newScreenCode() {
  // 4 caractères base32 SANS ambigus (pas de 0/O/1/I) → facile à recopier.
  const ALPHA = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  const r = crypto.getRandomValues(new Uint8Array(4));
  let c = '';
  for (let i = 0; i < 4; i++) c += ALPHA[r[i] % ALPHA.length];
  return c;
}

// base64url compatible avec le décodeur de la route /cs/ (UTF-8 safe).
function screenB64Url(str) {
  const b = btoa(unescape(encodeURIComponent(str)));
  return b.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function handleScreen(request, env, segments) {
  if (!env.DB) return json({ error: 'db_unbound' }, 503);
  await ensureScreenTable(env);
  const now = Date.now();
  const TTL = 6 * 60 * 60 * 1000; // 6 h
  const origin = new URL(request.url).origin;

  // POST /api/screen/new — le téléphone crée une session.
  if (segments[2] === 'new' && request.method === 'POST') {
    let code = '';
    for (let i = 0; i < 6; i++) {
      code = newScreenCode();
      const ex = await env.DB.prepare(
        'SELECT code FROM screen_sessions WHERE code = ?',
      ).bind(code).first();
      if (!ex) break;
    }
    await env.DB.prepare(
      `INSERT INTO screen_sessions (code, state_json, created_at, updated_at, expires_at)
       VALUES (?, ?, ?, ?, ?)`,
    ).bind(code, JSON.stringify({ action: 'idle', seq: 0 }), now, now, now + TTL).run();
    return json({ ok: true, code, url: `${origin}/e/${code}` });
  }

  const code = String(segments[2] || '').toUpperCase();
  if (!/^[2-9A-Z]{4}$/.test(code)) return badRequest('bad code');

  // GET /api/screen/:code — l'écran lit l'état courant (polling).
  if (segments.length === 3 && request.method === 'GET') {
    const row = await env.DB.prepare(
      'SELECT state_json, expires_at FROM screen_sessions WHERE code = ?',
    ).bind(code).first();
    if (!row || (row.expires_at || 0) < now) return json({ action: 'expired' });
    let st;
    try { st = JSON.parse(row.state_json || '{}'); } catch (_) { st = { action: 'idle', seq: 0 }; }
    return json(st);
  }

  // POST /api/screen/:code/command — le téléphone pousse une commande.
  if (segments[3] === 'command' && request.method === 'POST') {
    const row = await env.DB.prepare(
      'SELECT state_json FROM screen_sessions WHERE code = ?',
    ).bind(code).first();
    if (!row) return json({ error: 'no_session' }, 404);
    let body;
    try { body = await request.json(); } catch (_) { return badRequest('bad json'); }
    let prev;
    try { prev = JSON.parse(row.state_json || '{}'); } catch (_) { prev = {}; }
    const seq = (prev.seq || 0) + 1;
    const action = String((body && body.action) || '');
    let state;
    if (action === 'play') {
      const raw = String((body && body.url) || '');
      if (!raw) return badRequest('url required');
      // Flux lu par la TV via le proxy HTTPS du Worker (cross-réseau).
      // On passe tout par /cs/<b64>.ts + mpegts.js (cas dominant IPTV) ;
      // un codec non lisible (HEVC) déclenche le repli côté récepteur.
      const playUrl = `${origin}/cs/${screenB64Url(raw)}.ts`;
      state = {
        action: 'play',
        type: 'ts',
        playUrl,
        title: String((body && body.title) || ''),
        paused: false,
        seq,
      };
    } else if (action === 'pause') {
      state = { ...prev, action: 'control', paused: true, seq };
    } else if (action === 'resume') {
      state = { ...prev, action: 'control', paused: false, seq };
    } else if (action === 'stop') {
      state = { action: 'idle', seq };
    } else {
      return badRequest('bad action');
    }
    const t = Date.now();
    await env.DB.prepare(
      'UPDATE screen_sessions SET state_json = ?, updated_at = ?, expires_at = ? WHERE code = ?',
    ).bind(JSON.stringify(state), t, t + TTL, code).run();
    return json({ ok: true, seq });
  }

  return badRequest('unsupported screen route');
}

// =========================================================
//  Temps réel — routes WebSocket (cf. docs/REALTIME-PROTOCOL.md)
// =========================================================
//  Deux portes d'entrée vers le Durable Object RealtimeHub :
//    GET /api/rt/device  (public, même niveau de confiance que /api/heartbeat)
//    GET /api/v1/rt/ws   (panel admin, JWT vérifié AVANT l'upgrade)
//  Le Worker fait ici TOUTE la validation (MAC, rate-limit, JWT, rôle),
//  puis forwarde la requête d'upgrade au hub via le binding env.RT_HUB.
//  Si le binding n'est pas déployé → 503 {error:'rt_unavailable'} et RIEN
//  d'autre ne casse (le polling existant reste le filet de sécurité).

// Forwarde une requête d'upgrade WebSocket au hub (instance unique
// 'hub-v1') sur un chemin interne, avec des headers additionnels.
function rtForwardToHub(env, request, internalPath, params, extraHeaders) {
  const stub = env.RT_HUB.get(env.RT_HUB.idFromName('hub-v1'));
  // Hôte factice : seul le pathname/query compte pour le fetch du DO.
  const fwd = new URL('https://rt-hub.internal' + internalPath);
  for (const [k, v] of Object.entries(params || {})) {
    if (v !== undefined && v !== null && v !== '') fwd.searchParams.set(k, v);
  }
  const headers = new Headers(request.headers);
  for (const [k, v] of Object.entries(extraHeaders || {})) {
    // SÉCURITÉ : on retire TOUJOURS l'en-tête entrant d'abord. Un client
    // dart:io peut envoyer ses propres X-RT-IP / X-RT-Country ; si la
    // valeur Cloudflare était vide (dev, proxy amont), un simple
    // `if (v) set` laisserait passer la valeur falsifiée du client
    // jusque dans la table presence.
    headers.delete(k);
    if (v) headers.set(k, v);
  }
  // `new Request(url, request)` + headers recopiés : l'en-tête Upgrade
  // voyage avec, le DO répond 101 et le socket est câblé bout à bout.
  return stub.fetch(new Request(fwd.toString(), { method: 'GET', headers }));
}

// GET /api/rt/device?mac=MK:…&platform=…&v=…&b=…&model=…
//  Socket APPAREIL. Public (l'identifiant est la MAC, comme /api/heartbeat) ;
//  validation MAC + rate-limit dédié pour couper l'énumération.
async function handleRtDeviceWs(request, env, url) {
  if ((request.headers.get('Upgrade') || '').toLowerCase() !== 'websocket') {
    return json({ error: 'upgrade_required' }, 426);
  }
  if (!env.RT_HUB) {
    return json({ error: 'rt_unavailable' }, 503);
  }
  // MAC : %3A décodé (client web), upper-case, format MK:XX:… strict.
  const mac = decodeMacPath(url.searchParams.get('mac') || '').trim().toUpperCase();
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  // Rate-limit bucket 'rt' : 30 connexions / 5 min / IP. FAIL-OPEN
  // (cf. rateLimitOk) : sans D1 on ne bloque jamais un client légitime.
  if (!(await rateLimitOk(env, request, 'rt', 30, 5 * 60 * 1000))) {
    return tooManyRequests();
  }
  // IP + pays captés ICI (le DO ne voit pas les headers Cloudflare) et
  // transmis en headers internes — même logique que le heartbeat.
  return rtForwardToHub(env, request, '/connect-device', {
    mac,
    platform: url.searchParams.get('platform') || '',
    v: url.searchParams.get('v') || '',
    b: url.searchParams.get('b') || '',
    model: url.searchParams.get('model') || '',
  }, {
    'X-RT-IP': request.headers.get('CF-Connecting-IP') || '',
    'X-RT-Country': request.headers.get('CF-IPCountry') || '',
  });
}

// GET /api/v1/rt/ws?token=<JWT>
//  Socket PANEL. Intercepté dans worker.js AVANT le mount apiV1 (un
//  upgrade WebSocket ne rentre pas dans le flux JSON de api_v1.js).
//  Le token passe en query : un navigateur ne peut pas mettre de header
//  sur un WebSocket. Vérifié via verifyJwt (même secret HS256) AVANT
//  l'upgrade ; les revendeurs sont refusés (v1 : admins uniquement).
async function handleRtAdminWs(request, env, url) {
  if ((request.headers.get('Upgrade') || '').toLowerCase() !== 'websocket') {
    return json({ error: 'upgrade_required', message: 'WebSocket upgrade attendu.' }, 426);
  }
  const token = url.searchParams.get('token') || '';
  const claims = token
    ? await verifyJwt(token, env.ADMIN_SECRET || 'dev-secret')
    : null;
  if (!claims) {
    // Forme d'erreur api_v1 : { error: code, message: humain }.
    return json({ error: 'unauthorized', message: 'Token invalide ou expiré.' }, 401);
  }
  if (claims.role === 'reseller') {
    return json({ error: 'forbidden', message: 'Le temps réel est réservé aux rôles admin.' }, 403);
  }
  if (!env.RT_HUB) {
    return json({ error: 'rt_unavailable' }, 503);
  }
  return rtForwardToHub(env, request, '/connect-admin', {}, {});
}

// ----- Routeur -----

export default {
  async fetch(request, env, ctx) {
    // FILET GLOBAL : aucune exception non rattrapée ne doit produire un 500
    // "1101" nu ni fuiter une stack/message interne au client. On loggue
    // côté serveur (visible via `wrangler tail`) et on renvoie un corps
    // générique avec un identifiant de corrélation.
    try {
      return await handleRequest(request, env, ctx);
    } catch (e) {
      const requestId =
        (globalThis.crypto && crypto.randomUUID && crypto.randomUUID())
        || Date.now().toString(36);
      try {
        console.error('[worker] unhandled error', requestId,
          e && e.stack ? e.stack : String(e));
      } catch (_) { /* logging best-effort */ }
      return json({ error: 'internal_error', request_id: requestId }, 500);
    }
  },
};

async function handleRequest(request, env, ctx) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: JSON_HEADERS });
    }

    const url = new URL(request.url);

    // ===== Liens de téléchargement « cool » (redirection masquée) =====
    //  Problème résolu : quand on partage l'URL directe GitHub
    //  (github.com/manzilionellm-dotcom/tvking/...), l'app Downloader
    //  AFFICHE cette adresse sur sa page de redirection → ça expose le
    //  nom du compte (= identité du propriétaire). On sert donc des liens
    //  COURTS et BRANDÉS qui font une simple redirection 302 vers l'APK.
    //  L'utilisateur ne tape que le lien cool ; Downloader suit la
    //  redirection tout seul et ne montre jamais l'URL GitHub.
    //
    //  Pour MASQUER COMPLÈTEMENT l'identité, brancher un domaine perso
    //  sur ce Worker (ex. https://black7.tv/royal). Sur le sous-domaine
    //  workers.dev, l'hôte reste visible mais l'URL GitHub, elle, est
    //  cachée.
    //
    //  Liens disponibles (insensibles à la casse) — TOUJOURS la dernière
    //  version (les tags `latest` / `tv-latest` sont réécrits par la CI à
    //  chaque build, donc ces liens ne périment jamais) :
    //    /app  /royal  /get  → 7 MOTION mobile (7motion.apk)
    //    /tv                 → DeFew TV (defew-tv.apk, Downloader/Fire TV)
    {
      const slug = url.pathname.replace(/^\/+|\/+$/g, '').toLowerCase();
      const DOWNLOADS = {
        app: APK_URL,
        royal: APK_URL,
        get: APK_URL,
        black7: APK_URL,
        tv: TV_APK_URL,
      };
      if (DOWNLOADS[slug]) {
        if (request.method !== 'GET' && request.method !== 'HEAD') {
          return badRequest('only GET supported on download links');
        }
        return Response.redirect(DOWNLOADS[slug], 302);
      }
    }

    // ===== Temps réel (WebSockets → Durable Object RealtimeHub) =====
    // /api/v1/rt/ws DOIT être intercepté AVANT le mount apiV1 : c'est un
    // upgrade WebSocket, pas une requête JSON (auth JWT par query, cf.
    // handleRtAdminWs). /api/rt/device est le pendant côté appareil.
    if (url.pathname === '/api/v1/rt/ws') {
      return handleRtAdminWs(request, env, url);
    }
    if (url.pathname === '/api/rt/device') {
      return handleRtDeviceWs(request, env, url);
    }

    // ===== API v1 (App Licensing Platform — D1 backed) =====
    // Tout le namespace /api/v1/* part dans le module api_v1.js.
    // Coexiste avec les anciens /admin/* et /api/* qui restent
    // intacts (compat ascendante apps mobiles deployees).
    if (url.pathname.startsWith('/api/v1/')) {
      return apiV1(request, env);
    }

    const segments = url.pathname.split('/').filter(Boolean);

    // ===== Rate-limit applicatif des endpoints publics =====
    //  Limites VOLONTAIREMENT généreuses : un usage normal (l'app pingue au
    //  plus quelques fois/min) n'est jamais gêné, mais on coupe l'énumération
    //  de MAC (device-source/backup/config/status/history) et l'abus de l'IA
    //  payante. Par IP appelante, fenêtre 60 s, FAIL-OPEN (cf. rateLimitOk).
    {
      const seg0 = segments[0] || '';
      const seg1 = segments[1] || '';
      let rl = null;
      if (seg0 === 'api') {
        if (seg1 === 'ai') rl = ['ai', 30];                        // 30 / min (LLM payant)
        else if (seg1 === 'device-source' || seg1 === 'backup'
          || seg1 === 'status' || seg1 === 'history'
          || seg1 === 'family'
          || seg1 === 'self-source') rl = ['dev', 120]; // anti-énumération MAC + anti-brute-force code famille
        else if (seg1 === 'heartbeat' || seg1 === 'trending'
          || seg1 === 'announcement' || seg1 === 'sports'
          || seg1 === 'feedback' || seg1 === 'm3u') rl = ['pub', 240];
        // L'écran récepteur poll ~40×/min ; on laisse large (TV + téléphone).
        else if (seg1 === 'screen') rl = ['scr', 600];
      } else if (seg0 === 'config') {
        rl = ['cfg', 120]; // /config/:mac — même protection anti-énumération
      } else if (seg0 === 'cast-proxy' || seg0 === 'cast-sign') {
        rl = ['dev', 240]; // proxy Cast : 1 requête par session de cast, large
      }
      if (rl && !(await rateLimitOk(env, request, rl[0], rl[1], 60 * 1000))) {
        return tooManyRequests();
      }
    }

    // /config/:mac — public
    if (segments[0] === 'config' && segments.length === 2) {
      if (request.method !== 'GET') {
        return badRequest('only GET supported on /config/:mac');
      }
      return handlePublicConfig(env, segments[1]);
    }

    // /api/heartbeat — public, l'app pingue à chaque démarrage
    if (segments[0] === 'api' && segments[1] === 'heartbeat' && segments.length === 2) {
      if (request.method !== 'POST') {
        return badRequest('only POST supported on /api/heartbeat');
      }
      return handleHeartbeat(request, env, ctx);
    }

    // /api/status/:mac — public, l'app demande son état trial/freeze
    if (segments[0] === 'api' && segments[1] === 'status' && segments.length === 3) {
      if (request.method !== 'GET') {
        return badRequest('only GET supported on /api/status/:mac');
      }
      return handlePublicStatus(env, segments[2]);
    }

    // /api/servers — public, l'app récupère les serveurs par défaut
    if (segments[0] === 'api' && segments[1] === 'servers' && segments.length === 2) {
      if (request.method !== 'GET') {
        return badRequest('only GET supported on /api/servers');
      }
      return await handlePublicServers(env);
    }

    // /api/device-source/:mac — public, l'app récupère sa source assignée
    if (segments[0] === 'api' && segments[1] === 'device-source' && segments.length === 3) {
      if (request.method !== 'GET') {
        return badRequest('only GET supported on /api/device-source/:mac');
      }
      return await handlePublicDeviceSource(env, segments[2]);
    }

    // /api/device-messages/:mac — public : l'app relève sa BOÎTE de messages
    // persistants (déposés depuis le panel). Renvoie les non-livrés, les
    // marque « livrés » (accusé de réception côté panel), puis l'app les
    // affiche. Livré même si l'appareil était hors ligne au moment de l'envoi.
    if (segments[0] === 'api' && segments[1] === 'device-messages' && segments.length === 3) {
      if (request.method !== 'GET') {
        return badRequest('only GET supported on /api/device-messages/:mac');
      }
      return await handlePublicDeviceMessages(env, decodeMacPath(segments[2]));
    }
    // /api/device-messages/:mac/read — l'app confirme avoir AFFICHÉ un
    // message (accusé de LECTURE : read_at). Le panel montre alors « lu le… ».
    if (segments[0] === 'api' && segments[1] === 'device-messages'
        && segments.length === 4 && segments[3] === 'read') {
      if (request.method !== 'POST') {
        return badRequest('only POST supported on /api/device-messages/:mac/read');
      }
      return await handlePublicDeviceMessageRead(env, decodeMacPath(segments[2]), request);
    }

    // /api/self-source/:mac — self-service « Mon espace » : le client LIT (GET),
    // AJOUTE/REMPLACE (POST) ou SUPPRIME (DELETE) SA propre playlist. Une source
    // posée par le panel (payante) reste verrouillée (cf. handlers, garde-fous).
    if (segments[0] === 'api' && segments[1] === 'self-source' && segments.length === 3) {
      const smac = decodeMacPath(segments[2]);
      if (request.method === 'GET') return await handleSelfSourceGet(env, smac);
      if (request.method === 'POST') return await handleSelfSource(env, smac, request);
      if (request.method === 'DELETE') return await handleSelfSourceDelete(env, smac, request);
      return badRequest('only GET, POST or DELETE supported on /api/self-source/:mac');
    }

    // /api/history/:mac — public, historique de visionnage synchronisé.
    // L'app le lit au démarrage pour RESTAURER « Récemment » + « Pour vous »
    // sur une 2e box (l'écriture se fait via le heartbeat). Lecture seule.
    if (segments[0] === 'api' && segments[1] === 'history' && segments.length === 3) {
      if (request.method !== 'GET') {
        return badRequest('only GET supported on /api/history/:mac');
      }
      return await handlePublicHistory(env, segments[2]);
    }

    // /api/family/* — ABONNEMENT FAMILLE (partage type Netflix, 5 appareils).
    // invite (proprio génère un code), join (un proche le tape), info
    // (vue famille), remove (détacher un membre / se détacher).
    if (segments[0] === 'api' && segments[1] === 'family') {
      if (segments[2] === 'invite' && segments.length === 3) {
        if (request.method !== 'POST') return badRequest('only POST supported');
        return handleFamilyInvite(request, env);
      }
      if (segments[2] === 'join' && segments.length === 3) {
        if (request.method !== 'POST') return badRequest('only POST supported');
        return handleFamilyJoin(request, env);
      }
      if (segments[2] === 'info' && segments.length === 4) {
        if (request.method !== 'GET') return badRequest('only GET supported');
        return handleFamilyInfo(env, segments[3]);
      }
      if (segments[2] === 'remove' && segments.length === 3) {
        if (request.method !== 'POST') return badRequest('only POST supported');
        return handleFamilyRemove(request, env);
      }
      if (segments[2] === 'rename' && segments.length === 3) {
        if (request.method !== 'POST') return badRequest('only POST supported');
        return handleFamilyRename(request, env);
      }
      return badRequest('unknown family endpoint');
    }

    // /api/trending — public, top des chaînes les plus regardées EN CE MOMENT
    // (preuve sociale temps réel parmi tous les appareils en ligne). Lecture
    // seule, jamais d'écriture → aucun risque pour l'activation.
    if (segments[0] === 'api' && segments[1] === 'trending' && segments.length === 2) {
      if (request.method !== 'GET') {
        return badRequest('only GET supported on /api/trending');
      }
      return await handleTrending(env);
    }

    // /api/sports/search?q= et /api/sports/team/:id — public (proxy TheSportsDB)
    if (segments[0] === 'api' && segments[1] === 'sports' &&
        segments[2] === 'search' && segments.length === 3) {
      if (request.method !== 'GET') return badRequest('only GET');
      return await handleSportsSearch(url);
    }
    if (segments[0] === 'api' && segments[1] === 'sports' &&
        segments[2] === 'team' && segments.length === 4) {
      if (request.method !== 'GET') return badRequest('only GET');
      return await handleSportsTeam(segments[3]);
    }

    // /api/m3u/:token — public. Lien M3U distribuable d'une FAMILLE : on
    // résout le jeton → source de la famille → on renvoie la playlist M3U
    // (redirection vers le get.php Xtream ou l'URL M3U). Plusieurs liens
    // séparés possibles, tous adossés à UNE seule source.
    if (segments[0] === 'api' && segments[1] === 'm3u' && segments.length === 3) {
      return await handlePublicFamilyM3u(env, segments[2]);
    }

    // /api/backup/:mac — public, sauvegarde/restauration cloud par MAC
    // (playlists saisies par l'utilisateur + favoris). GET + PUT.
    if (segments[0] === 'api' && segments[1] === 'backup' && segments.length === 3) {
      if (request.method !== 'GET' && request.method !== 'PUT') {
        return badRequest('only GET/PUT supported on /api/backup/:mac');
      }
      return await handleDeviceBackup(request, env, segments[2], request.method);
    }

    // /api/ai/search — public POST, recherche en langage naturel (Claude).
    if (segments[0] === 'api' && segments[1] === 'ai' && segments[2] === 'search' && segments.length === 3) {
      return await handleAiSearch(request, env);
    }

    // /api/announcement — annonces broadcast (admin -> toutes les apps).
    //   GET    : public, l'app lit la derniere annonce au demarrage.
    //   POST   : admin (X-Admin-Secret), cree une annonce.
    //   DELETE : admin, efface toutes les annonces ("couper").
    if (segments[0] === 'api' && segments[1] === 'announcement' && segments.length === 2) {
      if (request.method === 'GET') {
        return await handleGetAnnouncement(env, request);
      }
      if (request.method === 'POST') {
        if (!checkAdmin(request, env)) return unauthorized();
        return await handlePostAnnouncement(request, env);
      }
      if (request.method === 'DELETE') {
        if (!checkAdmin(request, env)) return unauthorized();
        return await handleClearAnnouncements(env);
      }
      return badRequest('only GET/POST/DELETE supported on /api/announcement');
    }

    // /api/home-layout — accueil dynamique (Centre de controle, Module 1/8).
    //   GET public : l'app lit l'ordre / visibilite / rubans des sections.
    //   L'ecriture se fait cote panel via /api/v1/home-layout (api_v1.js).
    if (segments[0] === 'api' && segments[1] === 'home-layout' && segments.length === 2) {
      if (request.method === 'GET') {
        return await handleGetHomeLayout(env);
      }
      return badRequest('only GET supported on /api/home-layout');
    }

    // /api/app-version — mise a jour forcee (pilotee depuis le panel).
    //   GET public ?build=<sec> : l'app lit minBuildTs et signale son
    //   propre build (pour memoriser le dernier build en circulation).
    //   L'admin pose le seuil via /api/v1/force-update (api_v1.js).
    if (segments[0] === 'api' && segments[1] === 'app-version' && segments.length === 2) {
      if (request.method === 'GET') {
        return await handleGetAppVersion(request, env);
      }
      return badRequest('only GET supported on /api/app-version');
    }

    // /api/theme — thème de l'app (nom + couleur) piloté depuis le panel.
    //   GET public : l'app lit le nom affiché + la couleur d'accent.
    //   L'ecriture se fait cote panel via /api/v1/theme (api_v1.js).
    if (segments[0] === 'api' && segments[1] === 'theme' && segments.length === 2) {
      if (request.method === 'GET') {
        return await handleGetTheme(env, url.searchParams.get('platform'));
      }
      return badRequest('only GET supported on /api/theme');
    }

    // /api/greeting — accueil personnalisé (ville + météo via IP).
    if (segments[0] === 'api' && segments[1] === 'greeting' && segments.length === 2) {
      return await handleGreeting(request);
    }

    // /api/ad — vidéo pub au démarrage (GET public). Réglée via le panel.
    if (segments[0] === 'api' && segments[1] === 'ad' && segments.length === 2) {
      if (request.method === 'GET') return await handleGetAd(env);
      return badRequest('only GET supported on /api/ad');
    }

    // /api/pricing — tarifs affichés dans l'app (GET public). Réglés via
    // le panel « Tarifs » (api/v1/pricing).
    if (segments[0] === 'api' && segments[1] === 'pricing' && segments.length === 2) {
      if (request.method === 'GET') return await handleGetPricing(env);
      return badRequest('only GET supported on /api/pricing');
    }

    // /api/feedback-prompt — invitation à laisser un avis (GET public).
    if (segments[0] === 'api' && segments[1] === 'feedback-prompt' && segments.length === 2) {
      if (request.method === 'GET') return await handleGetFeedbackPrompt(env);
      return badRequest('only GET supported on /api/feedback-prompt');
    }

    // /api/feedback — le client envoie son avis (POST public).
    if (segments[0] === 'api' && segments[1] === 'feedback' && segments.length === 2) {
      if (request.method === 'POST') return await handlePostFeedback(request, env);
      return badRequest('only POST supported on /api/feedback');
    }

    // /api/featured — "Favori du jour" (chaîne mise en avant). GET public.
    if (segments[0] === 'api' && segments[1] === 'featured' && segments.length === 2) {
      if (request.method === 'GET') {
        return await handleGetFeatured(env);
      }
      return badRequest('only GET supported on /api/featured');
    }

    // /admin/panel — page HTML du panel admin (auth via input dans la page)
    if (segments[0] === 'admin' && segments[1] === 'panel' && segments.length === 2) {
      if (request.method !== 'GET') return badRequest('only GET');
      return new Response(ADMIN_PANEL_HTML, { headers: HTML_HEADERS });
    }

    // /admin/migrate-to-d1 — migration one-shot KV → D1.
    // Protege par X-Admin-Secret comme tout /admin/*. Idempotent :
    // peut etre rejoue sans dupliquer (skip si device deja en D1).
    // Body optionnel : { dry_run: true } pour simuler sans ecrire.
    if (segments[0] === 'admin' && segments[1] === 'migrate-to-d1' &&
        segments.length === 2) {
      if (!checkAdmin(request, env)) return unauthorized();
      if (request.method !== 'POST') return badRequest('only POST');
      let body = {};
      try { body = await request.json(); } catch (_) {}
      const result = await runMigration(env, { dryRun: !!body.dry_run });
      return json(result);
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
      // /admin/clients/:mac/action — boutons d'action rapide du panel
      if (segments.length === 4 && segments[3] === 'action') {
        const mac = segments[2];
        if (request.method === 'POST') return handleAdminAction(request, env, mac);
        return badRequest('only POST on action');
      }
    }

    // / — landing page HTML (téléchargement + tuto Downloader).
    // On injecte le DOMAINE réellement utilisé par le visiteur (url.host)
    // à la place du placeholder __HOST__ : ainsi la page affiche TON
    // domaine (ex. tondomaine.com/dl) et n'expose jamais 7themotion.com.
    if (segments.length === 0) {
      return new Response(landingHtml(), { headers: HTML_HEADERS });
    }

    // /mon-espace — page client « Gérer ma playlist » (façon IBO Player Pro).
    // Le client entre sa MAC → ajoute / modifie / supprime SA playlist lui-même
    // (cf. portal.js + /api/self-source/:mac). noindex (outil, pas marketing).
    if (segments.length === 1 &&
        (segments[0] === 'mon-espace' || segments[0] === 'espace')) {
      return new Response(portalHtml(), { headers: HTML_HEADERS });
    }

    // ===== PWA : le site s'installe comme une application =====
    if (segments.length === 1) {
      const f = segments[0];
      if (f === 'manifest.webmanifest') {
        return new Response(PWA_MANIFEST, {
          headers: {
            'Content-Type': 'application/manifest+json; charset=utf-8',
            'Cache-Control': 'public, max-age=3600',
            'Access-Control-Allow-Origin': '*',
          },
        });
      }
      if (f === 'sw.js') {
        return new Response(PWA_SW, {
          headers: {
            'Content-Type': 'application/javascript; charset=utf-8',
            'Cache-Control': 'no-cache',
            'Service-Worker-Allowed': '/',
          },
        });
      }
      if (f === 'icon-192.png' || f === 'icon-512.png' || f === 'apple-touch-icon.png'
          || f === 'og-image.png') {
        const b64 = f === 'icon-192.png' ? PWA_ICON_192
          : f === 'icon-512.png' ? PWA_ICON_512
          : f === 'og-image.png' ? OG_IMAGE : PWA_APPLE_ICON;
        const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
        return new Response(bytes, {
          headers: {
            'Content-Type': 'image/png',
            'Cache-Control': 'public, max-age=31536000, immutable',
          },
        });
      }
      // SEO : robots.txt + sitemap.xml
      if (f === 'robots.txt') {
        return new Response(
          'User-agent: *\nAllow: /\nSitemap: https://app.7themotion.com/sitemap.xml\n',
          { headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'public, max-age=3600' } },
        );
      }
      if (f === 'sitemap.xml') {
        const sm = '<?xml version="1.0" encoding="UTF-8"?>\n' +
          '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
          '  <url><loc>https://app.7themotion.com/</loc><changefreq>weekly</changefreq><priority>1.0</priority></url>\n' +
          '</urlset>\n';
        return new Response(sm, { headers: { 'Content-Type': 'application/xml; charset=utf-8', 'Cache-Control': 'public, max-age=3600' } });
      }
    }

    // /confidentialite (et /privacy) — politique de confidentialité hébergée.
    // Amazon/Google/etc. exigent une URL publique de politique de
    // confidentialité. On la sert ICI, sur le domaine du client, sans dépendre
    // d'un hébergement externe. Le déploiement auto du worker la met en ligne.
    if (segments.length === 1 &&
        (segments[0] === 'confidentialite' || segments[0] === 'privacy')) {
      return new Response(PRIVACY_HTML, { headers: HTML_HEADERS });
    }

    // /cs/<b64url>.m3u8  et  /cs/<b64url>.ts — WRAP HLS pour le CAST.
    //
    //  Un Chromecast / Google TV ne lit PAS le MPEG-TS http brut des flux
    //  IPTV (format non supporte par Cast + mixed content : le receiver
    //  tourne en https et refuse un flux http). On re-sert donc le flux
    //  en HLS HTTPS depuis CE Worker (toujours allume) :
    //    - .m3u8 → playlist HLS "single infinite segment" (technique
    //      eprouvee IPTV->Cast ; PAS de #EXT-X-ENDLIST = le receiver lit
    //      le .ts continu jusqu'a fermeture TCP).
    //    - .ts   → pass-through streaming du flux upstream http (octets
    //      copies tel quel, AUCUN transcodage).
    //  L'URL upstream est encodee en base64url dans le chemin (stateless,
    //  pas de KV). Le Chromecast tire tout du Worker en https → le
    //  telephone peut s'eteindre, la TV continue.
    if (segments.length === 2 && segments[0] === 'cs') {
      const file = segments[1];
      const dotIdx = file.lastIndexOf('.');
      const b64 = dotIdx > 0 ? file.slice(0, dotIdx) : file;
      const ext = dotIdx > 0 ? file.slice(dotIdx + 1) : '';

      let upstream;
      try {
        let s = b64.replace(/-/g, '+').replace(/_/g, '/');
        while (s.length % 4) s += '=';
        upstream = decodeURIComponent(escape(atob(s)));
      } catch (e) {
        return new Response('bad token', { status: 400 });
      }

      if (ext === 'm3u8') {
        const manifest =
          '#EXTM3U\n' +
          '#EXT-X-VERSION:3\n' +
          '#EXT-X-TARGETDURATION:10\n' +
          '#EXT-X-MEDIA-SEQUENCE:0\n' +
          '#EXT-X-PLAYLIST-TYPE:EVENT\n' +
          '#EXTINF:10.0,\n' +
          b64 + '.ts\n';
        return new Response(manifest, {
          headers: {
            'Content-Type': 'application/vnd.apple.mpegurl',
            'Cache-Control': 'no-store, no-cache',
            'Access-Control-Allow-Origin': '*',
          },
        });
      }

      if (ext === 'ts') {
        let dst;
        try {
          dst = new URL(upstream);
        } catch (e) {
          return new Response('bad url', { status: 400 });
        }
        if (dst.protocol !== 'http:' && dst.protocol !== 'https:') {
          return new Response('bad proto', { status: 400 });
        }
        const up = await fetch(dst.toString(), {
          headers: {
            'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18',
            // Certains serveurs Xtream filtrent sur Referer/Accept ; on
            // se présente comme un lecteur normal du même hôte.
            'Referer': `${dst.protocol}//${dst.host}/`,
            'Accept': '*/*',
          },
          redirect: 'follow',
        });
        const h = new Headers();
        h.set('Content-Type', 'video/mp2t');
        h.set('Cache-Control', 'no-store, no-cache');
        h.set('Access-Control-Allow-Origin', '*');
        // Diagnostic : on EXPOSE le vrai code HTTP du serveur IPTV au
        // récepteur (sinon mpegts.js ne montre qu'un « HttpStatusCodeInvalid »
        // générique). Permet de distinguer 403 (IP bloquée), limite de
        // connexions, 404 (URL), etc.
        h.set('X-Upstream-Status', String(up.status));
        h.set('Access-Control-Expose-Headers', 'X-Upstream-Status');
        // En-tetes DLNA pour les renderers UPnP (LG webOS, Samsung...) qui
        // sondent l'URL avant de jouer : flux LIVE en streaming, pas de seek.
        h.set('transferMode.dlna.org', 'Streaming');
        h.set(
          'contentFeatures.dlna.org',
          'DLNA.ORG_OP=00;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000',
        );
        return new Response(up.body, { status: up.status, headers: h });
      }

      return new Response('bad ext', { status: 400 });
    }

    // /dl — proxy l'APK GitHub release a travers le cache edge
    // Cloudflare pour des telechargements rapides depuis Downloader.
    // Variante /dl/release pour aliasing futur (release vs beta).
    if (
      (segments.length === 1 && segments[0] === 'dl') ||
      (segments.length === 2 && segments[0] === 'dl' && segments[1] === 'release')
    ) {
      return proxyApk(APK_URL, '7motion.apk', url.searchParams.get('v'));
    }

    // /install, /vip, /thefew, /few, /app — alias de téléchargement
    // DIRECT (proxy de l'APK). « lien VIP » propre à donner tel quel :
    // collé dans Downloader, il télécharge l'app immédiatement, SANS
    // passer par aftv.news ni aucun email/compte. Nom de fichier
    // « TheFew.apk » côté client.
    if (
      segments.length === 1 &&
      ['install', 'vip', 'thefew', 'few', 'app'].includes(segments[0])
    ) {
      return proxyApk(APK_URL, 'TheFew.apk', url.searchParams.get('v'));
    }

    // /tv, /defewtv, /tvbox, /defew + CODES COURTS MÉMORABLES (/777, /7777,
    // /tv7) — alias de téléchargement DIRECT de l'APK DeFew TV (version TV).
    // TV_APK_URL pointe sur le tag `tv-latest` → TOUJOURS la dernière version.
    // Lien propre à coller dans Downloader. Fichier « DeFewTV.apk ».
    if (
      segments.length === 1 &&
      ['tv', 'defewtv', 'tvbox', 'defew', '777', '7777', 'tv7']
          .includes(segments[0].toLowerCase())
    ) {
      return proxyApk(TV_APK_URL, 'DeFewTV.apk', url.searchParams.get('v'));
    }

    // /privacy — Politique de confidentialité (exigée par Google Play,
    // Huawei AppGallery, etc.). URL à coller dans la fiche de chaque store.
    if (segments.length === 1 && segments[0] === 'privacy') {
      return new Response(privacyHtml(), {
        headers: {
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'public, max-age=3600',
        },
      });
    }

    // /terms (+ /conditions, /cgu) — Conditions d'utilisation (positionnement
    // « lecteur uniquement »). À coller dans la fiche des stores et à lier
    // depuis le panel / l'app.
    if (segments.length === 1 &&
        (segments[0] === 'terms' ||
            segments[0] === 'conditions' ||
            segments[0] === 'cgu')) {
      return new Response(termsHtml(), {
        headers: {
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'public, max-age=3600',
        },
      });
    }

    // (Red Room et les wrappers retirés : /redroom, /7tv, /seventv, /nova
    //  n'existent plus. Les téléchargements vivent en tête de handler :
    //  /app /royal /get → mobile, /tv → DeFew TV.)

    // /cast-sign?u=<url> — signe une URL upstream pour le proxy Cast.
    //  Le secret HMAC vit UNIQUEMENT côté Worker (jamais dans l'app publique).
    //  L'app appelle cet endpoint pour obtenir l'URL /cast-proxy signée à
    //  envoyer au récepteur custom. Renvoie { ok, url } (url = proxy signé,
    //  valable ~12 h). Refuse les URL non http(s) / IP privées (anti-SSRF).
    if (segments.length === 1 && segments[0] === 'cast-sign') {
      if (request.method !== 'GET') return badRequest('only GET on /cast-sign');
      return await handleCastSign(env, url);
    }

    // /cast-proxy?u=<url>&e=<exp>&t=<hmac> — proxy pass-through HTTPS→upstream
    //  pour le récepteur Cast custom (mpegts.js). Résout le blocage contenu
    //  mixte / CORS : le récepteur (page HTTPS) fetch cette URL HTTPS de MÊME
    //  origine (en-têtes CORS ouverts) au lieu du .ts HTTP brut. Vérifie le
    //  token HMAC (anti open-proxy), refuse les IP privées, suit ≤3 redirects,
    //  et STREAME la réponse en video/mp2t (pas de mise en tampon complète).
    if (segments.length === 1 && segments[0] === 'cast-proxy') {
      if (request.method !== 'GET' && request.method !== 'HEAD') {
        return badRequest('only GET/HEAD on /cast-proxy');
      }
      return await handleCastProxy(env, url, request.method);
    }

    // /vendor/mpegts.js — lib mpegts.js servie en même origine pour le
    // récepteur Cast (cache edge, version épinglée, repli multi-CDN).
    if (segments.length === 2 && segments[0] === 'vendor'
      && segments[1] === 'mpegts.js') {
      if (request.method !== 'GET') return badRequest('only GET on /vendor/*');
      return await handleVendorMpegts(ctx);
    }

    // /cast-receiver — page HTML CAF pour Google Cast Custom Receiver.
    // URL a coller dans la Google Cast SDK Developer Console.
    // Query string ?app=redroom bascule le branding sur Red Room ;
    // sans query string, c'est le branding BLACK7 ROYAL par defaut.
    if (segments.length === 1 && segments[0] === 'cast-receiver') {
      const flavor = url.searchParams.get('app') || '7motion';
      return new Response(castReceiverHtml(flavor), {
        headers: {
          'Content-Type': 'text/html; charset=utf-8',
          // Cache 10 minutes — la page receiver bouge peu, et le
          // Chromecast la recharge a chaque session de cast.
          'Cache-Control': 'public, max-age=600',
          'Access-Control-Allow-Origin': '*',
        },
      });
    }

    // /ecran (et alias /screen) — page d'APPAIRAGE : la TV n'a pas de
    // caméra, donc on lui fait OUVRIR cette adresse fixe puis TAPER le
    // code à 4 caractères (modèle YouTube/Netflix). Redirige vers /e/<CODE>.
    if (segments.length === 1 &&
        (segments[0] === 'ecran' || segments[0] === 'screen')) {
      return new Response(screenPairHtml(), {
        headers: {
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'public, max-age=600',
          'Access-Control-Allow-Origin': '*',
        },
      });
    }

    // /e/<CODE> — récepteur « Caster sur un écran » (n'importe quel
    // navigateur de TV). Cf. screen_receiver.js + handleScreen().
    if (segments.length === 2 && segments[0] === 'e') {
      const sc = String(segments[1] || '').toUpperCase();
      if (!/^[2-9A-Z]{4}$/.test(sc)) {
        return new Response('code invalide', { status: 400 });
      }
      return new Response(screenReceiverHtml(sc), {
        headers: {
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'no-store',
          'Access-Control-Allow-Origin': '*',
        },
      });
    }

    // /api/screen/* — création de session, état (polling), commandes.
    if (segments[0] === 'api' && segments[1] === 'screen') {
      return handleScreen(request, env, segments);
    }

    // /cast-skin.css — feuille de style pour Google Cast Styled
    // Media Receiver. Voie alternative au Custom Receiver, plus
    // simple a enregistrer cote Console (juste un CSS au lieu d'un
    // HTML complet). Sert le fichier cast_skin.css en CSS.
    if (segments.length === 1 && segments[0] === 'cast-skin.css') {
      // Le fichier statique CSS est embarque dans cast_receiver.js
      // version compactee pour eviter une 2e dependance d'import.
      // On le declare ici inline pour rester self-contained.
      const css = `cast-media-player{` +
        `--background-color:#0A0A0C;` +
        `--logo-image:url('https://raw.githubusercontent.com/manzilionellm-dotcom/tvking/main/assets/branding/logo_7motion.jpg');` +
        `--logo-background-color:#0A0A0C;` +
        `--splash-image:url('https://raw.githubusercontent.com/manzilionellm-dotcom/tvking/main/assets/branding/logo_7motion.jpg');` +
        `--splash-background-color:#0A0A0C;` +
        `--progress-color:#D63A30;` +
        `--break-color:#D63A30;` +
        `--buffer-color:rgba(255,90,74,0.45);` +
        `--play-icon-color:#F2F2F4;` +
        `--pause-icon-color:#F2F2F4;` +
        `}`;
      return new Response(css, {
        headers: {
          'Content-Type': 'text/css; charset=utf-8',
          'Cache-Control': 'public, max-age=3600',
          'Access-Control-Allow-Origin': '*',
        },
      });
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
    // Routes reservees : tout segment unique present ici n'est PAS
    // considere comme un code vanity Downloader et donc N'EST PAS
    // redirige vers l'APK par le catch-all. C'est une defense en
    // profondeur : si pour une raison X le `if` specifique d'une
    // route ci-dessus echoue a matcher (modif accidentelle, bug
    // wrangler bundle, edge avec ancien cache), le catch-all ne fera
    // PAS de redirect APK trompeur — il tombera proprement sur le
    // 404 final.
    const RESERVED = new Set([
      'admin', 'config', 'dl', 'install', 'api', 'panel',
      'redroom', 'tv', 'defewtv', 'tvbox', 'defew', '777', '7777', 'tv7',
      'cast-receiver', 'cast-skin.css', 'vendor',
      'favicon.ico', 'robots.txt', 'sitemap.xml',
    ]);
    if (segments.length === 1 && !RESERVED.has(segments[0].toLowerCase())) {
      return proxyApk(APK_URL, '7motion.apk', url.searchParams.get('v'));
    }

    return notFound('Unknown route. Try /, /dl, /config/:mac or /admin/clients');
}
