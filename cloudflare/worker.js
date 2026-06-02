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
const APK_URL =
  'https://github.com/manzilionellm-dotcom/tvking/releases/download/latest/app-debug.apk';

// Variante Red Room (flavor adulte 18+ du MÊME repo). Publiée sur
// une release dédiée `redroom-latest` par le job CI `build_redroom`.
// Le binaire a un applicationId différent (`com.redroom.player`),
// donc l'installation NE remplace PAS l'app 7 MOTION sur le téléphone
// du client — les deux peuvent cohabiter.
const REDROOM_APK_URL =
  'https://github.com/manzilionellm-dotcom/tvking/releases/download/redroom-latest/redroom.apk';

// Version Android TV / Fire TV (Downloader-friendly). APK Kotlin
// WebView qui embarque tv-web/dist/. Cible SHIELD, Fire TV Stick
// 4K Max, Chromecast Google TV. Publiee sur la release `tv-latest`
// par le workflow CI `build-tv-wrapper.yml`. URL stable courte :
//   https://99999.7themotion.com/tv  ->  Downloader friendly.
const TV_APK_URL =
  'https://github.com/manzilionellm-dotcom/tvking/releases/download/tv-latest/tv-king-tv.apk';

// NOVA+ : nouvelle app TV (front Next.js exporte en statique, embarque
// dans un wrapper WebView). Publiee sur la release `nova-latest` par le
// workflow CI `build-nova-tv.yml`. Lien court Downloader :
//   https://99999.7themotion.com/nova
const NOVA_APK_URL =
  'https://github.com/manzilionellm-dotcom/tvking/releases/download/nova-latest/nova.apk';

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
  return {
    exists: true,
    status,
    paid,
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
      trial_until: expiresAt,
      days_left: lifetime ? 36500 : Math.max(0, Math.ceil((expiresAt - now) / DAY_MS)),
      expired: expired && !lifetime,
      frozen,
      banned,
      source: 'd1',
    };
  }

  // --- Cas 2 : device connu mais PAS de licence → ESSAI 7 jours ---
  // L'essai court depuis first_seen_at. Apres TRIAL_DAYS, expired=true →
  // l'app bloque → le client doit venir te voir pour etre active.
  const trialUntil = (dev.first_seen_at || now) + TRIAL_DAYS * DAY_MS;
  const expired = trialUntil <= now;
  return {
    exists: true,
    status: 'active',
    paid: false,
    trial_until: trialUntil,
    days_left: Math.max(0, Math.ceil((trialUntil - now) / DAY_MS)),
    expired,
    frozen: false,
    banned: false,
    source: 'd1-trial',
  };
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
  <title>7 MOTION — Panel admin</title>
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
  <h1>7 MOTION</h1>
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
async function handleHeartbeat(request, env) {
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

  // --- Chemin D1 (par defaut des que la base est branchee) ---
  // On enregistre AUTOMATIQUEMENT la MAC (essai 7 j), puis on renvoie son
  // etat. Toute app installee apparait ainsi dans le panel admin.
  if (env.DB) {
    await ensureD1Device(env, mac, now);
    const d1 = await d1StatusForMac(env, mac, now);
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
//  STATUS PUBLIC — appelé par l'app à chaque démarrage juste
//  après le heartbeat, pour savoir si elle doit afficher
//  l'écran 'essai expiré' ou 'compte gelé'.
// =========================================================
async function handlePublicStatus(env, mac) {
  if (!MAC_RX.test(mac)) return badRequest('invalid mac');
  // D1 en priorite. Si la MAC n'est pas encore connue (status appele
  // avant le heartbeat), on la cree pour demarrer l'essai 7 j.
  if (env.DB) {
    let d1 = await d1StatusForMac(env, mac);
    if (!d1) {
      await ensureD1Device(env, mac);
      d1 = await d1StatusForMac(env, mac);
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
  const existing = await readClient(env, mac);
  if (!existing) return notFound(`Client ${mac} introuvable`);

  const now = Date.now();
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
      updated.paid = true;
      break;
    case 'mark_unpaid':
      updated.paid = false;
      break;
    case 'renew': {
      const days = Number(body?.days) > 0 ? Number(body.days) : 365;
      updated.trial_until = now + days * DAY_MS;
      break;
    }
    case 'note':
      updated.note = String(body?.note || '');
      break;
    default:
      return badRequest(
        'action must be one of: freeze, unfreeze, ban, mark_paid, mark_unpaid, renew, note',
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
  // métadonnées admin comme added_at).
  return json({
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
  if (!env.DB) return json({ mac, source: null });
  try {
    const row = await env.DB
      .prepare(
        `SELECT type, label, server_url, username, password, m3u_url, epg_url, updated_at
           FROM device_sources WHERE mac = ?`,
      )
      .bind(mac.toUpperCase())
      .first();
    return json({ mac: mac.toUpperCase(), source: row || null });
  } catch (_) {
    // Table absente / D1 indisponible → pas de source assignée.
    return json({ mac, source: null });
  }
}

// ----- Routeur -----

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: JSON_HEADERS });
    }

    const url = new URL(request.url);

    // ===== API v1 (App Licensing Platform — D1 backed) =====
    // Tout le namespace /api/v1/* part dans le module api_v1.js.
    // Coexiste avec les anciens /admin/* et /api/* qui restent
    // intacts (compat ascendante apps mobiles deployees).
    if (url.pathname.startsWith('/api/v1/')) {
      return apiV1(request, env);
    }

    const segments = url.pathname.split('/').filter(Boolean);

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
      return handleHeartbeat(request, env);
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

    // / — landing page HTML (téléchargement + tuto Downloader)
    if (segments.length === 0) {
      return new Response(LANDING_HTML, { headers: HTML_HEADERS });
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

    // /install — alias canal alternatif (utile si on veut router
    // par device class plus tard : /install?tv=firetv, etc.)
    if (segments.length === 1 && segments[0] === 'install') {
      return proxyApk(APK_URL, '7motion.apk', url.searchParams.get('v'));
    }

    // /redroom — variante adulte 18+. Pointe vers la release
    // dédiée `redroom-latest`. Le binaire a son propre applicationId
    // donc il s'installe à côté de 7 MOTION sans collision.
    // /redroom/dl est un alias pour cohérence avec /dl du 7 MOTION.
    if (
      (segments.length === 1 && segments[0] === 'redroom') ||
      (segments.length === 2 && segments[0] === 'redroom' && segments[1] === 'dl')
    ) {
      return proxyApk(REDROOM_APK_URL, 'redroom.apk', url.searchParams.get('v'));
    }

    // /tv — version Android TV / Fire TV (WebView wrapper de tv-web).
    // C'est l'URL courte a coller dans Downloader sur la SHIELD :
    //   "https://99999.7themotion.com/tv"
    // Proxy via cache edge Cloudflare pour des telechargements
    // rapides cote SHIELD (vs 302 vers GitHub release direct qui
    // est lent depuis l'Europe).
    if (
      (segments.length === 1 && segments[0] === 'tv') ||
      (segments.length === 2 && segments[0] === 'tv' && segments[1] === 'dl')
    ) {
      return proxyApk(TV_APK_URL, 'tv-king-tv.apk', url.searchParams.get('v'));
    }

    // /nova — app NOVA+ pour Android TV / Fire TV. URL courte a coller
    // dans Downloader : "https://99999.7themotion.com/nova". Proxy via
    // le cache edge Cloudflare (telechargements rapides cote TV).
    if (
      (segments.length === 1 && segments[0] === 'nova') ||
      (segments.length === 2 && segments[0] === 'nova' && segments[1] === 'dl')
    ) {
      return proxyApk(NOVA_APK_URL, 'nova.apk', url.searchParams.get('v'));
    }

    // /cast-receiver — page HTML CAF pour Google Cast Custom Receiver.
    // URL a coller dans la Google Cast SDK Developer Console.
    // Query string ?app=redroom bascule le branding sur Red Room ;
    // sans query string, c'est le branding 7 MOTION par defaut.
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
      'redroom', 'tv',
      'cast-receiver', 'cast-skin.css',
      'favicon.ico', 'robots.txt', 'sitemap.xml',
    ]);
    if (segments.length === 1 && !RESERVED.has(segments[0].toLowerCase())) {
      return proxyApk(APK_URL, '7motion.apk', url.searchParams.get('v'));
    }

    return notFound('Unknown route. Try /, /dl, /config/:mac or /admin/clients');
  },
};
