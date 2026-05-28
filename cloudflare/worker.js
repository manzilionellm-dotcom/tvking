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

// Variante Red Room (flavor adulte 18+ du MÊME repo). Publiée sur
// une release dédiée `redroom-latest` par le job CI `build_redroom`.
// Le binaire a un applicationId différent (`com.redroom.player`),
// donc l'installation NE remplace PAS l'app 7 MOTION sur le téléphone
// du client — les deux peuvent cohabiter.
const REDROOM_APK_URL =
  'https://github.com/manzilionellm-dotcom/tvking/releases/download/redroom-latest/redroom.apk';

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

const TRIAL_DAYS = 10;
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
  const existing = await readClient(env, mac);

  if (!existing) {
    // 1er heartbeat de ce MAC → on crée sa fiche, trial 10 jours.
    const fresh = {
      name: '',
      playlists: [],
      added_at: now,
      updated_at: now,
      status: 'active',
      paid: false,
      trial_until: now + TRIAL_DAYS * DAY_MS,
      note: '',
      last_seen_at: now,
      first_seen_at: now,
    };
    await writeClient(env, mac, fresh);
    return json({ ok: true, created: true, ...computeStatus(fresh, now) });
  }

  // Fiche existe : on rafraîchit last_seen_at sans toucher au reste.
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

    // /admin/panel — page HTML du panel admin (auth via input dans la page)
    if (segments[0] === 'admin' && segments[1] === 'panel' && segments.length === 2) {
      if (request.method !== 'GET') return badRequest('only GET');
      return new Response(ADMIN_PANEL_HTML, { headers: HTML_HEADERS });
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

    // /redroom — variante adulte 18+. Pointe vers la release
    // dédiée `redroom-latest`. Le binaire a son propre applicationId
    // donc il s'installe à côté de 7 MOTION sans collision.
    // /redroom/dl est un alias pour cohérence avec /dl du 7 MOTION.
    if (
      (segments.length === 1 && segments[0] === 'redroom') ||
      (segments.length === 2 && segments[0] === 'redroom' && segments[1] === 'dl')
    ) {
      return Response.redirect(REDROOM_APK_URL, 302);
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
      'admin', 'config', 'dl', 'install', 'api', 'panel',
      'redroom',
      'favicon.ico', 'robots.txt', 'sitemap.xml',
    ]);
    if (segments.length === 1 && !RESERVED.has(segments[0].toLowerCase())) {
      return Response.redirect(APK_URL, 302);
    }

    return notFound('Unknown route. Try /, /dl, /config/:mac or /admin/clients');
  },
};
