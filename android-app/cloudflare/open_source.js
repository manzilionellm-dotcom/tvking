// =========================================================
//  open_source.js — Source libre, sans catalogue de serveurs
// =========================================================
//  Le panel et l'application ne montrent plus « Serveur 1, Serveur 2 ».
//  Ici on vérifie seulement qu'une source collée par quelqu'un est
//  complète, pour N'IMPORTE QUEL hôte http(s). Pas de liste blanche.
//
//  La table `default_servers` et GET /api/servers restent en place :
//  une application déjà installée peut encore demander l'adresse d'un
//  serveur qu'on lui avait enregistré. Ce module sait retrouver cette
//  adresse à partir de l'identifiant, sans la présenter comme un choix.
//
//  Aucune adresse réelle, aucun mot de passe réel : les tests passent
//  par des hôtes bidons (exemple.invalid).
// =========================================================

/// Construit l'objet stocké à partir du corps JSON (panel ou « Mon espace »).
/// Même forme qu'avant pour xtream et m3u, afin de ne pas casser les
/// abonnés déjà poussés. `player` est le lien get.php.
export function buildOpenSource(body) {
  const src = body && typeof body === 'object' ? body : {};
  const type = String(src.type || '').trim().toLowerCase();
  const label = (String(src.label || '').trim() || 'Ma playlist').slice(0, 80);
  const epgRaw = String(src.epg_url || '').trim();
  const epg = epgRaw && /^https?:\/\//i.test(epgRaw) ? epgRaw.slice(0, 2048) : null;

  if (type === 'xtream') {
    const built = xtreamFields(src.server_url, src.username, src.password);
    if (built.error) return built;
    return { source: { ...built.source, label, epg_url: epg } };
  }
  if (type === 'm3u') {
    const url = httpUrl(src.m3u_url);
    if (url.error) return { error: 'm3u requires m3u_url' === url.code
      ? 'm3u requires m3u_url'
      : url.error };
    return {
      source: {
        type: 'm3u',
        label,
        server_url: null,
        username: null,
        password: null,
        m3u_url: url.value,
        epg_url: epg,
      },
    };
  }
  if (type === 'player') {
    const parsed = parsePlayerLink(src.m3u_url || src.url || '');
    if (parsed.error) return parsed;
    return { source: { ...parsed.source, label, epg_url: epg } };
  }
  return { error: "type must be 'xtream' or 'm3u'" };
}

/// Lien get.php / player_api.php → compte Xtream si les deux
/// identifiants sont dans l'adresse. Sinon une phrase française.
/// Une liste .m3u collée par erreur est gardée comme liste M3U.
export function parsePlayerLink(raw) {
  const url = httpUrl(raw);
  if (url.error) {
    return { error: 'Colle une adresse qui commence par http:// ou https://.' };
  }
  let uri;
  try {
    uri = new URL(url.value);
  } catch (_) {
    return { error: 'Colle une adresse qui commence par http:// ou https://.' };
  }
  if (isPlayerPath(uri.pathname)) {
    const user = (uri.searchParams.get('username') || '').trim();
    const pass = (uri.searchParams.get('password') || '').trim();
    if (!user || !pass) {
      return {
        error: 'Ce lien de lecteur n\'a pas de nom d\'utilisateur ou de mot de passe.',
      };
    }
    return {
      source: {
        type: 'xtream',
        server_url: originOf(uri),
        username: user.slice(0, 256),
        password: pass.slice(0, 256),
        m3u_url: null,
      },
    };
  }
  return {
    source: {
      type: 'm3u',
      server_url: null,
      username: null,
      password: null,
      m3u_url: url.value,
    },
  };
}

/// Retrouve l'adresse d'un serveur DÉJÀ enregistré (ancienne app qui
/// connaît encore l'identifiant). Ne fabrique rien si l'identifiant
/// est inconnu. Le libellé « Serveur 1 » n'est pas renvoyé : l'appelant
/// n'a pas à l'afficher.
export function resolveRegisteredServer(rows, id) {
  const key = String(id || '').trim();
  if (!key || !Array.isArray(rows)) return null;
  for (const row of rows) {
    if (!row || String(row.id) !== key) continue;
    const url = String(row.url || '').trim();
    if (!url) return null;
    return { id: key, url };
  }
  return null;
}

function xtreamFields(serverRaw, userRaw, passRaw) {
  let server = String(serverRaw || '').trim();
  let user = String(userRaw || '').trim();
  let pass = String(passRaw || '').trim();
  if (server && !/^[a-z][a-z0-9+.-]*:\/\//i.test(server)) {
    server = `http://${server}`;
  }
  if (!server || !/^https?:\/\//i.test(server)) {
    return { error: 'xtream requires server_url, username, password' };
  }
  let uri;
  try {
    uri = new URL(server);
  } catch (_) {
    return { error: 'server_url must start with http(s)://' };
  }
  if (uri.protocol !== 'http:' && uri.protocol !== 'https:') {
    return { error: 'server_url must start with http(s)://' };
  }
  if (isPlayerPath(uri.pathname)) {
    if (!user) user = (uri.searchParams.get('username') || '').trim();
    if (!pass) pass = (uri.searchParams.get('password') || '').trim();
    server = originOf(uri);
  } else {
    server = server.replace(/\/+$/, '').slice(0, 2048);
  }
  user = user.slice(0, 256);
  pass = pass.slice(0, 256);
  if (!server || !user || !pass) {
    return { error: 'xtream requires server_url, username, password' };
  }
  return {
    source: {
      type: 'xtream',
      server_url: server,
      username: user,
      password: pass,
      m3u_url: null,
    },
  };
}

/// Adresse http(s) avec un hôte, quel qu'il soit. `code` sert à garder
/// les messages historiques du Worker pour les corps incomplets.
function httpUrl(raw) {
  const value = String(raw || '').trim().slice(0, 2048);
  if (!value) return { error: 'm3u requires m3u_url', code: 'm3u requires m3u_url' };
  if (!/^https?:\/\//i.test(value)) {
    return { error: 'm3u_url must start with http(s)://' };
  }
  let uri;
  try {
    uri = new URL(value);
  } catch (_) {
    return { error: 'm3u_url must start with http(s)://' };
  }
  if (!uri.hostname) return { error: 'm3u_url must start with http(s)://' };
  return { value };
}

function isPlayerPath(pathname) {
  const path = String(pathname || '').toLowerCase();
  return path.endsWith('get.php') || path.endsWith('player_api.php');
}

function originOf(uri) {
  return `${uri.protocol}//${uri.host}`;
}
