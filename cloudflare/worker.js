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
import { apiV1 } from './api_v1.js';
// Migration KV → D1 (cf. cloudflare/migrate_kv_to_d1.js) — exposee
// via POST /admin/migrate-to-d1 et protegee par X-Admin-Secret.
import { runMigration } from './migrate_kv_to_d1.js';
// Cast receiver HTML (cf. cloudflare/cast_receiver.js) — page CAF
// hebergee a /cast-receiver, URL a coller dans la Google Cast SDK
// Developer Console pour obtenir un Receiver Application ID.
import { castReceiverHtml } from './cast_receiver.js';

// ----- Constantes APK / téléchargement -----
//
// URL du GitHub release qui pointe TOUJOURS vers le dernier APK
// (le tag "latest" est overwrite à chaque push du workflow CI,
//  donc le binaire qui répond à cette URL est toujours à jour).
// Depuis la release SIGNÉE, l'APK canonique s'appelle `7motion.apk`.
// `app-debug.apk` (même binaire) reste publié en parallèle comme
// filet de sécurité, mais on sert le nom propre par défaut.
const APK_URL =
  'https://github.com/manzilionellm-dotcom/tvking/releases/download/latest/7motion.apk';

// APK de DeFew TV (version télévision) — release `tv-latest`. Servi via la
// route propre `/tv` (Downloader sur box Android TV / Fire TV).
const TV_APK_URL =
  'https://github.com/manzilionellm-dotcom/tvking/releases/download/tv-latest/defew-tv.apk';

// NB : les variantes TV (Android TV / Fire TV, wrappers WebView, NOVA+)
// et Red Room ont été RETIRÉES du projet. Seule l'app mobile 7 MOTION
// (`APK_URL` ci-dessus) est encore construite et distribuée.

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

// Landing page HTML servie sur la racine. Style Maison Noir :
// fond noir, ember rouge, typo sobre. Optimisée pour téléphones
// ET pour les navigateurs intégrés des Smart TV (pas de JS).
const LANDING_HTML = `<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>BLACK7 ROYAL — Téléchargement</title>
  <meta name="description" content="Lecteur IPTV premium BLACK7 ROYAL. Téléchargez l'APK Android/Fire TV/Android TV.">
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
      <h1>BLACK7 ROYAL</h1>
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
        <li>Tape l'URL : <code>__HOST__/dl</code>
            <br>ou un code court : <code>__HOST__/1</code>, <code>__HOST__/666666</code></li>
        <li>Bouton <strong>GO</strong> &rarr; téléchargement automatique</li>
        <li>Bouton <strong>Install</strong> quand le téléchargement finit</li>
      </ol>
    </div>

    <p class="legal">
      BLACK7 ROYAL ne vend, ne distribue et ne fournit aucun flux IPTV,
      aucune chaîne ni aucun contenu. Apportez votre propre
      abonnement auprès du fournisseur de votre choix.
    </p>
  </div>
</body>
</html>`;

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
      '<td class="mac">' + escapeHtml(c.mac) + '</td>' +
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

async function ensureFamilySchema(env) {
  if (!env.DB) return false;
  try {
    await env.DB.prepare(
      'CREATE TABLE IF NOT EXISTS family_links (' +
      'member_mac TEXT PRIMARY KEY, owner_mac TEXT NOT NULL, created_at INTEGER)',
    ).run();
    await env.DB.prepare(
      'CREATE TABLE IF NOT EXISTS family_codes (' +
      'code TEXT PRIMARY KEY, owner_mac TEXT NOT NULL, expires_at INTEGER NOT NULL)',
    ).run();
    await env.DB.prepare(
      'CREATE INDEX IF NOT EXISTS idx_family_owner ON family_links(owner_mac)',
    ).run();
    return true;
  } catch (_) {
    return false;
  }
}

/// MAC du propriétaire si `mac` est un MEMBRE d'une famille, sinon null.
async function familyOwnerOf(env, mac) {
  if (!env.DB) return null;
  try {
    const row = await env.DB
      .prepare('SELECT owner_mac FROM family_links WHERE member_mac = ?')
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
    return json({ ok: false, error: 'family_unavailable' });
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
  const cnt = await env.DB
    .prepare('SELECT COUNT(*) AS n FROM family_links WHERE owner_mac = ?')
    .bind(mac).first();
  const members = (cnt && Number(cnt.n)) || 0;
  if (members >= FAMILY_MAX_MEMBERS) {
    return json({ ok: false, error: 'family_full', members, max: FAMILY_MAX_MEMBERS });
  }
  // Code à 6 chiffres (facile à taper à la télécommande), 1 seul actif par
  // propriétaire (le nouveau remplace l'ancien).
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  const code = String(100000 + (buf[0] % 900000));
  const expiresAt = Date.now() + FAMILY_CODE_TTL_MS;
  await env.DB.prepare('DELETE FROM family_codes WHERE owner_mac = ?').bind(mac).run();
  await env.DB
    .prepare('INSERT INTO family_codes (code, owner_mac, expires_at) VALUES (?, ?, ?)')
    .bind(code, mac, expiresAt).run();
  return json({ ok: true, code, expires_at: expiresAt, members, max: FAMILY_MAX_MEMBERS });
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
    return json({ ok: false, error: 'family_unavailable' });
  }
  const row = await env.DB
    .prepare('SELECT owner_mac, expires_at FROM family_codes WHERE code = ?')
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
  // Plafond : 4 membres (hors ce mac s'il re-tape le code).
  const cnt = await env.DB
    .prepare('SELECT COUNT(*) AS n FROM family_links WHERE owner_mac = ? AND member_mac != ?')
    .bind(owner, mac).first();
  if (((cnt && Number(cnt.n)) || 0) >= FAMILY_MAX_MEMBERS) {
    return json({ ok: false, error: 'family_full', max: FAMILY_MAX_MEMBERS });
  }
  await env.DB
    .prepare('INSERT OR REPLACE INTO family_links (member_mac, owner_mac, created_at) VALUES (?, ?, ?)')
    .bind(mac, owner, Date.now()).run();
  return json({ ok: true, owner: maskMac(owner) });
}

/// GET /api/family/info/:mac → vue famille (propriétaire OU membre).
async function handleFamilyInfo(env, rawMac) {
  const mac = String(rawMac || '').toUpperCase();
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  if (!env.DB || !(await ensureFamilySchema(env))) {
    return json({ ok: false, error: 'family_unavailable' });
  }
  const ownerMac = await familyOwnerOf(env, mac);
  if (ownerMac) {
    return json({ ok: true, role: 'member', owner: maskMac(ownerMac) });
  }
  const rows = await env.DB
    .prepare('SELECT member_mac, created_at FROM family_links WHERE owner_mac = ? ORDER BY created_at ASC')
    .bind(mac).all();
  const members = ((rows && rows.results) || []).map((r) => ({
    mac: r.member_mac, // le propriétaire voit SES appareils en clair
    since: r.created_at,
  }));
  const codeRow = await env.DB
    .prepare('SELECT code, expires_at FROM family_codes WHERE owner_mac = ? AND expires_at > ?')
    .bind(mac, Date.now()).first();
  return json({
    ok: true,
    role: 'owner',
    members,
    max: FAMILY_MAX_MEMBERS,
    code: codeRow ? codeRow.code : null,
    code_expires_at: codeRow ? codeRow.expires_at : null,
  });
}

/// POST /api/family/remove { mac, member? } — le propriétaire détache un
/// membre ; sans `member`, l'appareil se détache LUI-MÊME (quitter).
async function handleFamilyRemove(request, env) {
  let body;
  try { body = await request.json(); } catch (_) { return badRequest('invalid JSON body'); }
  const mac = String(body?.mac || '').toUpperCase();
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  if (!env.DB || !(await ensureFamilySchema(env))) {
    return json({ ok: false, error: 'family_unavailable' });
  }
  const member = String(body?.member || '').toUpperCase();
  if (member) {
    // Détachement par le PROPRIÉTAIRE uniquement (le lien doit lui appartenir).
    await env.DB
      .prepare('DELETE FROM family_links WHERE member_mac = ? AND owner_mac = ?')
      .bind(member, mac).run();
  } else {
    await env.DB
      .prepare('DELETE FROM family_links WHERE member_mac = ?')
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
      default:
        return badRequest(
          'action must be one of: freeze, unfreeze, ban, mark_paid, '
          + 'activate_lifetime, activate_year, mark_unpaid, renew, note',
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
    return json({ ok: true, mac, action, ...(fresh || {}) });
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
  return json({ ok: true, mac, ...updated });
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
//  un FILTRE de recherche structuré (JSON) via Claude. L'app applique
//  ensuite ce filtre LOCALEMENT a son catalogue (le catalogue ne quitte
//  jamais l'appareil → prive + peu couteux).
//
//  La cle Anthropic vit en SECRET cote Worker (env.ANTHROPIC_API_KEY) —
//  jamais dans l'app. Tant que le secret n'est pas defini, l'endpoint
//  repond 503 (fonctionnalite dormante, aucun cout).
//
//  Modele par defaut : claude-haiku-4-5 (rapide + peu cher, adapte a une
//  recherche tapee a chaque requete). Surchargeable via env.AI_MODEL.
async function handleAiSearch(request, env) {
  if (request.method !== 'POST') {
    return badRequest('only POST supported on /api/ai/search');
  }
  const key = env.ANTHROPIC_API_KEY;
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

  const model = env.AI_MODEL || 'claude-haiku-4-5';

  const system =
    "Tu convertis une requête utilisateur en langage naturel en un FILTRE de " +
    "recherche pour une application de lecteur multimédia (IPTV). Réponds " +
    "UNIQUEMENT avec le filtre structuré. Champs : keywords (mots-clés " +
    "simples, en minuscules, sans articles, dans la langue de la requête) ; " +
    "type ('live' pour chaînes/direct, 'movie' pour films, 'series' pour " +
    "séries, 'any' si indéterminé) ; genres (ex: sport, football, " +
    "actualités, enfants, musique, cinéma, documentaire) ; title_contains " +
    "(un titre précis si l'utilisateur en cite un, sinon vide) ; language " +
    "(langue si mentionnée, sinon vide). Laisse un champ vide ([] ou '') " +
    "s'il n'est pas pertinent.";

  const schema = {
    type: 'object',
    properties: {
      keywords: { type: 'array', items: { type: 'string' } },
      type: { type: 'string', enum: ['live', 'movie', 'series', 'any'] },
      genres: { type: 'array', items: { type: 'string' } },
      title_contains: { type: 'string' },
      language: { type: 'string' },
    },
    required: ['keywords', 'type', 'genres', 'title_contains', 'language'],
    additionalProperties: false,
  };

  try {
    const resp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': key,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model,
        max_tokens: 400,
        system,
        messages: [{ role: 'user', content: query }],
        output_config: { format: { type: 'json_schema', schema } },
      }),
    });
    if (!resp.ok) {
      // On NE renvoie PAS le corps amont au client (peut contenir des détails
      // internes / la clé en écho selon le fournisseur). Log serveur uniquement.
      try {
        const t = await resp.text();
        console.error('[ai] upstream error', resp.status, t.slice(0, 300));
      } catch (_) { /* best-effort */ }
      return json({ error: 'ai_upstream', status: resp.status }, 502);
    }
    const data = await resp.json();
    // Structured outputs → le 1er bloc texte contient le JSON valide.
    let filter = null;
    if (Array.isArray(data.content)) {
      const textBlock = data.content.find((b) => b && b.type === 'text');
      if (textBlock && typeof textBlock.text === 'string') {
        try {
          filter = JSON.parse(textBlock.text);
        } catch (_) {
          filter = null;
        }
      }
    }
    if (!filter) return json({ error: 'ai_parse' }, 502);
    return json({ ok: true, filter });
  } catch (e) {
    try { console.error('[ai] error', String(e && e.stack ? e.stack : e)); } catch (_) {}
    return json({ error: 'ai_error' }, 502);
  }
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
    //  Liens disponibles (insensibles à la casse) :
    //    /royal    et /get   → BLACK7 ROYAL (7motion.apk)
    {
      const slug = url.pathname.replace(/^\/+|\/+$/g, '').toLowerCase();
      const GH = 'https://github.com/manzilionellm-dotcom/tvking/releases/download';
      const DOWNLOADS = {
        royal: `${GH}/latest/7motion.apk`,
        get: `${GH}/latest/7motion.apk`,
        black7: `${GH}/latest/7motion.apk`,
      };
      if (DOWNLOADS[slug]) {
        if (request.method !== 'GET' && request.method !== 'HEAD') {
          return badRequest('only GET supported on download links');
        }
        return Response.redirect(DOWNLOADS[slug], 302);
      }
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
          || seg1 === 'family') rl = ['dev', 120]; // anti-énumération MAC + anti-brute-force code famille
        else if (seg1 === 'heartbeat' || seg1 === 'trending'
          || seg1 === 'announcement' || seg1 === 'sports'
          || seg1 === 'feedback' || seg1 === 'm3u') rl = ['pub', 240];
      } else if (seg0 === 'config') {
        rl = ['cfg', 120]; // /config/:mac — même protection anti-énumération
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
      const html = LANDING_HTML.replaceAll('__HOST__', url.host);
      return new Response(html, { headers: HTML_HEADERS });
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
          headers: { 'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18' },
          redirect: 'follow',
        });
        const h = new Headers();
        h.set('Content-Type', 'video/mp2t');
        h.set('Cache-Control', 'no-store, no-cache');
        h.set('Access-Control-Allow-Origin', '*');
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

    // (Routes TV et Red Room retirées : /redroom, /tv, /7tv, /seventv,
    //  /nova n'existent plus — ces variantes ont été supprimées du projet.
    //  Seule l'app mobile 7 MOTION est distribuée, via /royal /get /install.)

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
      'cast-receiver', 'cast-skin.css',
      'favicon.ico', 'robots.txt', 'sitemap.xml',
    ]);
    if (segments.length === 1 && !RESERVED.has(segments[0].toLowerCase())) {
      return proxyApk(APK_URL, '7motion.apk', url.searchParams.get('v'));
    }

    return notFound('Unknown route. Try /, /dl, /config/:mac or /admin/clients');
}
