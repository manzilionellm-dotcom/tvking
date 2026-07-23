// =========================================================
//  config.js — Configuration de la passerelle (100 % via env)
// =========================================================
//  Aucune valeur secrète en dur. Tout se règle par variables
//  d'environnement (voir .env.example). La passerelle est une
//  MAISON MÈRE : elle parle à UNE ligne fournisseur et mutualise
//  seulement les flux identiques — elle ne contourne aucune limite.
// =========================================================

function str(name, def) {
  const v = process.env[name];
  return v === undefined || v === '' ? def : v;
}
function int(name, def) {
  const v = parseInt(process.env[name] ?? '', 10);
  return Number.isFinite(v) ? v : def;
}
function bool(name, def) {
  const v = (process.env[name] ?? '').toLowerCase();
  if (v === '') return def;
  return v === '1' || v === 'true' || v === 'yes' || v === 'on';
}

// Base upstream sans slash final (ex. http://mon-fournisseur.com:8080).
function trimSlash(u) {
  return (u || '').replace(/\/+$/, '');
}

export const config = {
  // --- Réseau local de la passerelle ---
  host: str('HOST', '0.0.0.0'),
  port: int('PORT', 8088),
  // URL publique de la passerelle (sert à réécrire les M3U / server_info
  // pour que les apps tapent le VPS et non le fournisseur). Ex :
  // https://tv.mondomaine.com . Sans slash final.
  publicBase: trimSlash(str('PUBLIC_BASE', '')),

  // --- Ligne fournisseur (« maison mère ») ---
  upstreamBase: trimSlash(str('UPSTREAM_BASE', '')),
  // Lignes de SECOURS (failover). Liste séparée par des virgules. Si la ligne
  // principale meurt (réseau/5xx/refus), la passerelle bascule sur la
  // suivante SANS couper les spectateurs. Vide = pas de failover (comportement
  // historique, une seule ligne). Toutes partagent UPSTREAM_USER/PASS.
  upstreamBases: [
    trimSlash(str('UPSTREAM_BASE', '')),
    ...str('UPSTREAM_BASE_FALLBACKS', '')
      .split(',')
      .map((s) => trimSlash(s.trim()))
      .filter((s) => s.length > 0),
  ].filter((s) => s.length > 0),
  upstreamUser: str('UPSTREAM_USER', ''),
  upstreamPass: str('UPSTREAM_PASS', ''),
  // Nombre MAX de connexions simultanées AUTORISÉES par le fournisseur sur
  // cette ligne. La passerelle ne dépassera JAMAIS ce chiffre (elle refuse
  // proprement au-delà). C'est ta protection anti-ban.
  providerMaxConnections: int('PROVIDER_MAX_CONNECTIONS', 5),

  // User-Agent envoyé au fournisseur (comme un vrai lecteur IPTV).
  userAgent: str('UPSTREAM_USER_AGENT', 'VLC/3.0.18 LibVLC/3.0.18'),
  // Accepter les certificats TLS invalides côté upstream (fréquent en IPTV).
  allowInsecureTls: bool('ALLOW_INSECURE_TLS', true),
  // Redirections HTTP suivies vers l'upstream.
  maxRedirects: int('UPSTREAM_MAX_REDIRECTS', 5),

  // --- Multiplexage / streaming live ---
  // Après le départ du DERNIER spectateur d'une chaîne, on garde la
  // connexion upstream ouverte ce petit délai (zapping aller-retour rapide),
  // puis on ferme (libère une connexion fournisseur).
  streamIdleGraceMs: int('STREAM_IDLE_GRACE_MS', 8000),
  // Si un client est trop lent (réseau saturé) et accumule plus que ça en
  // mémoire tampon, on le coupe pour protéger les autres spectateurs.
  clientBufferMaxBytes: int('CLIENT_BUFFER_MAX_BYTES', 8 * 1024 * 1024),
  // Plafond mémoire GLOBAL des files d'attente clients (somme de tous les
  // writableLength). Au-delà, on coupe les clients les plus lents pour ne
  // jamais faire tomber tout le process par OOM (conteneur 512 Mo).
  // 0 = désactivé.
  globalClientBufferMaxBytes: int('GLOBAL_CLIENT_BUFFER_MAX_BYTES', 128 * 1024 * 1024),
  // Période de la ronde anti-backpressure (ms) qui applique le plafond global.
  backpressureSweepMs: int('BACKPRESSURE_SWEEP_MS', 2000),
  // Reconnexion upstream : nb d'essais et backoff de base (ms).
  upstreamRetries: int('UPSTREAM_RETRIES', 6),
  upstreamRetryBaseMs: int('UPSTREAM_RETRY_BASE_MS', 500),

  // --- Détection des connexions clientes MORTES (anti-slots fantômes) ---
  // Une box qui disparaît brutalement (coupure secteur/réseau) ne ferme pas
  // proprement sa socket : sans détection, elle retient indéfiniment un slot
  // de la ligne fournisseur. On arme un keepalive TCP (le noyau sonde le pair
  // et coupe la socket morte → l'événement 'close' se déclenche → le slot est
  // libéré). initialDelay = délai d'inactivité avant la 1re sonde.
  socketKeepAliveMs: int('SOCKET_KEEPALIVE_MS', 30_000),
  // Garde-fou anti-slow-loris sur la PHASE REQUÊTE entrante uniquement
  // (en-têtes/corps de la requête HTTP du client — PAS la durée du flux de
  // réponse, qui reste illimitée pour le live). 0 = illimité.
  headersTimeoutMs: int('HEADERS_TIMEOUT_MS', 60_000),
  requestTimeoutMs: int('REQUEST_TIMEOUT_MS', 60_000),

  // --- Anti-abus : limite de débit des endpoints coûteux (get.php,
  // player_api.php) PAR utilisateur. Une box buggée qui martèle la playlist
  // ne doit pas saturer la ligne / l'event-loop. Généreux par défaut (un
  // rafraîchissement normal est rare). 0 = désactivé.
  apiRateLimit: int('API_RATE_LIMIT', 60),
  apiRateWindowMs: int('API_RATE_WINDOW_MS', 10_000),

  // --- Sécurité / admin ---
  // Jeton exigé pour /admin/* et /metrics (en-tête Authorization: Bearer …
  // ou ?token=). Vide = endpoints admin désactivés (recommandé de le poser).
  adminToken: str('ADMIN_TOKEN', ''),
  // Fichier JSON des utilisateurs (papa + clones). Voir users.example.json.
  usersFile: str('USERS_FILE', '/data/users.json'),

  // --- Identité de DIFFUSION (liste de test mutualisée) ---
  // Utilisateur PARTAGÉ, en lecture seule, que le panel embarque dans les URLs
  // de la petite liste de test (à la place des identifiants fournisseur → la
  // ligne réelle n'apparaît jamais dans le M3U servi). Tous les testeurs
  // l'emploient : le hub mutualise les chaînes identiques → le fournisseur ne
  // voit qu'UNE connexion. Ces valeurs doivent correspondre à
  // « Utilisateur/mot de passe gateway » saisis dans la console maître.
  // Vide = pas d'identité de diffusion (repli identifiants fournisseur).
  broadcastUser: str('BROADCAST_USER', ''),
  broadcastPass: str('BROADCAST_PASS', ''),
  // Plafond de TESTEURS SIMULTANÉS sur l'identité de diffusion. À NE PAS
  // confondre avec PROVIDER_MAX_CONNECTIONS : ce dernier borne les connexions
  // FOURNISSEUR (côté amont, dans hub.js) ; celui-ci borne les sessions CLIENT
  // de l'identité partagée (côté aval). Comme les testeurs regardent les mêmes
  // quelques chaînes, la mutualisation garde l'amont à ~1 connexion même avec
  // beaucoup de testeurs → cette valeur peut être généreuse.
  broadcastMaxStreams: int('BROADCAST_MAX_STREAMS', 100),

  // --- Journalisation ---
  logLevel: str('LOG_LEVEL', 'info'), // debug | info | warn | error
};

// Validation minimale au démarrage : on refuse de démarrer sans ligne.
export function validateConfig(cfg = config) {
  const missing = [];
  if (!cfg.upstreamBase) missing.push('UPSTREAM_BASE');
  if (!cfg.upstreamUser) missing.push('UPSTREAM_USER');
  if (!cfg.upstreamPass) missing.push('UPSTREAM_PASS');
  if (cfg.providerMaxConnections < 1) missing.push('PROVIDER_MAX_CONNECTIONS>=1');
  return missing;
}

// =========================================================
//  warnConfig — avertissements NON bloquants au démarrage
// =========================================================
//  Pourquoi une fonction séparée de validateConfig : ces points ne DOIVENT PAS
//  empêcher le démarrage (le gateway http/IP FONCTIONNE — les apps joignent la
//  façade). Mais ils changent la VÉRIFIABILITÉ du diagnostic. On applique donc
//  EXACTEMENT le même contrat que le Worker (validateFacadeBase) : seul
//  `https + vrai domaine` est SONDABLE par le relais Cloudflare → diagnostic
//  « vert » vérifiable. Le reste reste « informatif » (ambre). Aligner les deux
//  côtés évite qu'un opérateur croie être « vert » alors que la façade n'est
//  pas sondable. On AVERTIT clairement, on ne bloque pas.
export function warnConfig(cfg = config) {
  const warnings = [];
  const add = (code, message) => warnings.push({ code, message });

  const pb = cfg.publicBase;
  if (!pb) {
    add('public_base_missing',
      'PUBLIC_BASE non défini : les playlists ne sont PAS réécrites sur la ' +
      'façade → les apps reçoivent les URLs fournisseur (moins stable/privé). ' +
      'Renseigne PUBLIC_BASE=https://ton-domaine (voir gateway/README).');
    return warnings; // rien d'autre à analyser sans base publique.
  }

  let u = null;
  try { u = new URL(pb); } catch (_) { /* URL illisible */ }
  if (!u) {
    add('public_base_invalid',
      `PUBLIC_BASE invalide (« ${pb} ») : attendu http(s)://domaine, sans slash final.`);
    return warnings;
  }

  const host = u.hostname;
  // Même heuristique que le Worker : IPv4 brute / IPv6 littéral = non sondable ;
  // domaine = au moins un point ET une lettre (ex. gw.mondomaine.com).
  const isIp = /^\d{1,3}(\.\d{1,3}){3}$/.test(host) || host.includes(':') || host.startsWith('[');
  const isDomain = !isIp && /[a-zA-Z]/.test(host) && host.includes('.');

  if (u.protocol !== 'https:') {
    add('public_base_not_https',
      `PUBLIC_BASE en ${u.protocol.replace(':', '')} : tes apps joignent la ` +
      'façade, mais le relais Cloudflare ne peut PAS la sonder → le diagnostic ' +
      'reste « informatif » (ambre), jamais « vert ». Recommandé : https + ' +
      'domaine (Caddy + Let’s Encrypt, voir gateway/README).');
  } else if (isIp) {
    add('public_base_ip',
      'PUBLIC_BASE en https mais sur une IP brute : le relais Cloudflare ne ' +
      'sonde pas une IP → diagnostic « informatif ». Recommandé : un vrai ' +
      'domaine (ex. https://gw.mondomaine.com).');
  } else if (!isDomain) {
    add('public_base_not_domain',
      'PUBLIC_BASE sans domaine complet : joignable par les apps seulement → ' +
      'diagnostic « informatif ». Recommandé : un domaine complet en https.');
  }

  return warnings;
}
