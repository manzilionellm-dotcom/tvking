// =========================================================
//  openSource.ts — Le panel n'offre plus de catalogue
// =========================================================
//  Avant, activer une box proposait « Serveur 1, Serveur 2… » et
//  cachait l'adresse. Maintenant la personne (ou le revendeur qui
//  pousse une source) écrit l'adresse elle-même : M3U, Xtream, ou
//  lien de lecteur get.php. N'importe quel hôte. Plusieurs sources
//  restent possibles : chaque bloc est vérifié tout seul.
//
//  Les phrases d'erreur sont en français simple, les mêmes idées
//  que dans l'application.
// =========================================================

export type OpenPanelKind = 'xtream' | 'm3u' | 'player';

export type OpenPanelFields = {
  type: OpenPanelKind;
  serverUrl: string;
  username: string;
  password: string;
  link: string;
};

export type PushedSource =
  | {
      type: 'xtream';
      server_url: string;
      username: string;
      password: string;
      m3u_url?: null;
    }
  | {
      type: 'm3u';
      m3u_url: string;
      server_url?: null;
      username?: null;
      password?: null;
    };

export const ERR_NEED_URL =
  'Colle une adresse qui commence par http:// ou https://.';
export const ERR_NEED_XTREAM =
  "Indique l'adresse du serveur, le nom d'utilisateur et le mot de passe.";
export const ERR_NEED_PLAYER =
  "Ce lien de lecteur n'a pas de nom d'utilisateur ou de mot de passe.";

/// Chemin de l'ancienne page « Serveurs ». On le retire du menu.
export const SERVER_CATALOG_PATH = '/servers';

/// Enlève l'entrée du catalogue, où qu'elle soit dans un menu.
export function hideServerCatalog<T extends { to: string }>(items: T[]): T[] {
  return items.filter((item) => item.to !== SERVER_CATALOG_PATH);
}

/// Vérifie un bloc de source. Ne consulte aucune liste de serveurs :
/// l'adresse tapée est l'adresse utilisée, même si l'hôte est inconnu.
export function buildPushedSource(
  fields: OpenPanelFields,
): { source: PushedSource } | { error: string } {
  if (fields.type === 'xtream') {
    return xtreamFromFields(fields.serverUrl, fields.username, fields.password);
  }
  if (fields.type === 'player') {
    return playerFromLink(fields.link);
  }
  return m3uFromLink(fields.link);
}

function xtreamFromFields(
  serverRaw: string,
  userRaw: string,
  passRaw: string,
): { source: PushedSource } | { error: string } {
  let server = serverRaw.trim();
  let user = userRaw.trim();
  let pass = passRaw.trim();
  if (server && !/^[a-z][a-z0-9+.-]*:\/\//i.test(server)) {
    server = `http://${server}`;
  }
  if (!server) return { error: ERR_NEED_XTREAM };
  let uri: URL;
  try {
    uri = new URL(server);
  } catch {
    return { error: ERR_NEED_URL };
  }
  if (uri.protocol !== 'http:' && uri.protocol !== 'https:') {
    return { error: ERR_NEED_URL };
  }
  if (/get\.php$|player_api\.php$/i.test(uri.pathname)) {
    if (!user) user = (uri.searchParams.get('username') || '').trim();
    if (!pass) pass = (uri.searchParams.get('password') || '').trim();
    server = `${uri.protocol}//${uri.host}`;
  } else {
    server = server.replace(/\/+$/, '');
  }
  if (!server || !user || !pass) return { error: ERR_NEED_XTREAM };
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

function m3uFromLink(raw: string): { source: PushedSource } | { error: string } {
  const url = normalizeHttp(raw);
  if (!url) return { error: ERR_NEED_URL };
  return { source: { type: 'm3u', m3u_url: url, server_url: null, username: null, password: null } };
}

function playerFromLink(raw: string): { source: PushedSource } | { error: string } {
  const url = normalizeHttp(raw);
  if (!url) return { error: ERR_NEED_URL };
  let uri: URL;
  try {
    uri = new URL(url);
  } catch {
    return { error: ERR_NEED_URL };
  }
  if (/get\.php$|player_api\.php$/i.test(uri.pathname)) {
    const user = (uri.searchParams.get('username') || '').trim();
    const pass = (uri.searchParams.get('password') || '').trim();
    if (!user || !pass) return { error: ERR_NEED_PLAYER };
    return {
      source: {
        type: 'xtream',
        server_url: `${uri.protocol}//${uri.host}`,
        username: user,
        password: pass,
        m3u_url: null,
      },
    };
  }
  return { source: { type: 'm3u', m3u_url: url, server_url: null, username: null, password: null } };
}

function normalizeHttp(raw: string): string | null {
  const s = raw.trim();
  if (!s) return null;
  const withScheme = /^[a-z][a-z0-9+.-]*:\/\//i.test(s) ? s : `http://${s}`;
  try {
    const uri = new URL(withScheme);
    if (uri.protocol !== 'http:' && uri.protocol !== 'https:') return null;
    if (!uri.hostname) return null;
    return withScheme;
  } catch {
    return null;
  }
}
