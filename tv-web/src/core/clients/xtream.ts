// =========================================================
//  xtream.ts — Client API Xtream Codes
// =========================================================
//  Xtream Codes est l'API la plus repandue chez les fournisseurs IPTV
//  (90% du marche). L'utilisateur fournit `URL serveur + user + pass`
//  et tout passe par `player_api.php` avec un parametre `action=...`.
//
//  Endpoints supportes en Phase 2 :
//    - authenticate           : sans `action` ou `action=` vide
//    - get_live_categories    : categories Live
//    - get_live_streams       : chaines Live (optionnellement filtrees
//                               par categorie via &category_id=...)
//    - get_vod_categories     : categories VOD (films) -- reserve Phase 4
//    - get_series_categories  : categories Series -- reserve Phase 4
//
//  Construction de l'URL d'un flux Live :
//    `${serverUrl}/live/${username}/${password}/${streamId}.${container}`
//  Par defaut container = `ts` (MPEG-TS brut). Certains fournisseurs
//  servent aussi `.m3u8` (HLS) — on essaie `.ts` en priorite par compat
//  TVs anciennes (Tizen / webOS de 2020 ont des decoders HLS capricieux).
//
//  Pas de gestion de cookies, pas de retry au niveau client — c'est
//  des appels statelass HTTP GET avec query params. Si l'utilisateur
//  a des problemes de fiabilite, c'est cote provider, pas cote nous.
// =========================================================

import type { Channel } from '../models/channel.js';
import { logger } from '../observability/structured_logger.js';

/** Identifiants Xtream — saisis par l'utilisateur, jamais hardcoded. */
export interface XtreamCredentials {
  /**
   * URL du serveur SANS slash final et SANS le `/player_api.php`. Ex :
   * `http://pro.example.com:8080`.
   * On accepte avec ou sans port. http ou https. Le constructeur du
   * client normalise (strip trailing slash + accept variantes).
   */
  readonly serverUrl: string;
  readonly username: string;
  readonly password: string;
}

/** Reponse `authenticate` Xtream — sous-ensemble qu'on utilise reellement. */
export interface XtreamAuthInfo {
  /** Le compte est-il actif (string "Active" attendue). */
  readonly status: string;
  /** Date d'expiration (timestamp Unix en secondes), null si lifetime. */
  readonly expiresAt: number | null;
  /** Nombre max de connexions simultanees autorisees. null si inconnu. */
  readonly maxConnections: number | null;
  /** Nombre de connexions actives au moment de la requete. */
  readonly activeConnections: number | null;
  /** Le compte est-il un essai gratuit ? */
  readonly isTrial: boolean;
}

/** Categorie Live retournee par `get_live_categories`. */
export interface XtreamLiveCategory {
  readonly id: string;
  readonly name: string;
  readonly parentId: string | null;
}

/** Erreur typee, pour que le caller affiche un message approprie. */
export class XtreamError extends Error {
  constructor(
    message: string,
    public readonly code:
      | 'auth_failed'
      | 'network'
      | 'invalid_response'
      | 'unknown',
    public readonly cause?: unknown,
  ) {
    super(message);
    this.name = 'XtreamError';
  }
}

export class XtreamClient {
  private readonly serverUrl: string;
  private readonly username: string;
  private readonly password: string;

  constructor(credentials: XtreamCredentials) {
    this.serverUrl = normalizeServerUrl(credentials.serverUrl);
    this.username = credentials.username;
    this.password = credentials.password;
  }

  // ===========================================================
  //  Auth + meta
  // ===========================================================

  /**
   * Verifie la validite des credentials et recupere les infos de compte.
   * Endpoint : `${serverUrl}/player_api.php?username=...&password=...`
   * (sans action) — convention Xtream pour le ping d'auth.
   */
  async authenticate(): Promise<XtreamAuthInfo> {
    const url = this.buildApiUrl();
    const json = await this.fetchJson(url);

    // Format attendu :
    //   { user_info: { status: "Active", exp_date: "...", auth: 1, ... },
    //     server_info: { ... } }
    if (
      typeof json !== 'object' ||
      json === null ||
      !('user_info' in json)
    ) {
      logger.warn('xtream', 'auth.invalid_shape', {
        host: hostOf(this.serverUrl),
      });
      throw new XtreamError(
        'Reponse Xtream malformee',
        'invalid_response',
      );
    }
    const ui = (json as { user_info: Record<string, unknown> }).user_info;
    const auth = ui['auth'];
    if (auth === 0 || auth === '0') {
      logger.warn('xtream', 'auth.failed', { host: hostOf(this.serverUrl) });
      throw new XtreamError(
        'Identifiants refuses par le serveur',
        'auth_failed',
      );
    }

    const info: XtreamAuthInfo = {
      status: typeof ui['status'] === 'string' ? (ui['status'] as string) : 'Unknown',
      expiresAt: parseNumericOrNull(ui['exp_date']),
      maxConnections: parseNumericOrNull(ui['max_connections']),
      activeConnections: parseNumericOrNull(ui['active_cons']),
      isTrial: ui['is_trial'] === '1' || ui['is_trial'] === 1,
    };
    logger.info('xtream', 'auth.success', {
      host: hostOf(this.serverUrl),
      status: info.status,
      isTrial: info.isTrial,
    });
    return info;
  }

  // ===========================================================
  //  Live channels
  // ===========================================================

  /**
   * Recupere les categories Live. Renvoie un tableau vide si le
   * fournisseur n'en publie pas (cas observe sur certains revendeurs
   * low-cost qui mettent tout en "Uncategorized").
   */
  async getLiveCategories(): Promise<XtreamLiveCategory[]> {
    const url = this.buildApiUrl({ action: 'get_live_categories' });
    const json = await this.fetchJson(url);
    if (!Array.isArray(json)) {
      logger.warn('xtream', 'live_categories.invalid_shape', {});
      return [];
    }
    return json
      .filter((c): c is Record<string, unknown> => typeof c === 'object' && c !== null)
      .map((c) => ({
        id: String(c['category_id'] ?? ''),
        name:
          typeof c['category_name'] === 'string'
            ? (c['category_name'] as string)
            : 'Sans nom',
        parentId:
          c['parent_id'] != null && c['parent_id'] !== 0
            ? String(c['parent_id'])
            : null,
      }))
      .filter((c) => c.id.length > 0);
  }

  /**
   * Recupere les chaines Live, optionnellement filtrees par categorie.
   * Mappe directement sur le modele `Channel` partage avec le parser
   * M3U — l'UI ne fait AUCUNE difference entre les deux sources.
   */
  async getLiveStreams(categoryId?: string): Promise<Channel[]> {
    const params: Record<string, string> = { action: 'get_live_streams' };
    if (categoryId !== undefined && categoryId !== '') {
      params['category_id'] = categoryId;
    }
    const url = this.buildApiUrl(params);
    const json = await this.fetchJson(url);
    if (!Array.isArray(json)) {
      logger.warn('xtream', 'live_streams.invalid_shape', {});
      return [];
    }

    const channels: Channel[] = [];
    let index = 0;
    for (const item of json) {
      if (typeof item !== 'object' || item === null) continue;
      const o = item as Record<string, unknown>;
      const streamId = parseNumericOrNull(o['stream_id']);
      if (streamId === null) continue;
      const name =
        typeof o['name'] === 'string' && (o['name'] as string).length > 0
          ? (o['name'] as string)
          : `Chaîne ${streamId}`;
      const streamIcon =
        typeof o['stream_icon'] === 'string' && (o['stream_icon'] as string).length > 0
          ? (o['stream_icon'] as string)
          : null;
      // Container : `ts` par defaut, mais certains fournisseurs publient
      // explicitement m3u8 via container_extension.
      const containerRaw = o['container_extension'];
      const container =
        typeof containerRaw === 'string' && containerRaw.length > 0
          ? containerRaw
          : 'ts';
      const url = this.buildLiveStreamUrl(streamId, container);
      const groupRaw = o['category_name'];
      const group =
        typeof groupRaw === 'string' && groupRaw.length > 0
          ? (groupRaw as string)
          : null;
      const epgRaw = o['epg_channel_id'];
      const epgId =
        typeof epgRaw === 'string' && epgRaw.length > 0
          ? (epgRaw as string)
          : null;
      channels.push({
        id: `xtream:${streamId}`,
        name,
        url,
        logoUrl: streamIcon,
        group,
        epgId,
        orderIndex: index++,
      });
    }
    logger.info('xtream', 'live_streams.loaded', {
      count: channels.length,
      categoryId: categoryId ?? null,
    });
    return channels;
  }

  // ===========================================================
  //  URL builders (exposes pour tests)
  // ===========================================================

  /**
   * Construit l'URL de l'API player. Sans `action` = endpoint d'auth.
   * Public pour permettre des actions Xtream non encore wrappees.
   */
  buildApiUrl(params: Record<string, string> = {}): string {
    const search = new URLSearchParams({
      username: this.username,
      password: this.password,
      ...params,
    });
    return `${this.serverUrl}/player_api.php?${search.toString()}`;
  }

  /**
   * Construit l'URL absolue d'un flux Live.
   * `${serverUrl}/live/${user}/${pass}/${streamId}.${ext}`
   */
  buildLiveStreamUrl(streamId: number, container: string = 'ts'): string {
    // URL-encode les credentials pour gerer les caracteres speciaux
    // (un user avec un `&` ou un `+` est rare mais reel).
    const u = encodeURIComponent(this.username);
    const p = encodeURIComponent(this.password);
    return `${this.serverUrl}/live/${u}/${p}/${streamId}.${container}`;
  }

  // ===========================================================
  //  HTTP plumbing
  // ===========================================================

  private async fetchJson(url: string): Promise<unknown> {
    let response: Response;
    try {
      response = await fetch(url, {
        method: 'GET',
        headers: { Accept: 'application/json' },
      });
    } catch (e) {
      throw new XtreamError(
        'Connexion impossible au serveur Xtream',
        'network',
        e,
      );
    }
    if (!response.ok) {
      throw new XtreamError(
        `HTTP ${response.status} ${response.statusText}`,
        response.status === 401 || response.status === 403
          ? 'auth_failed'
          : 'network',
      );
    }
    try {
      return await response.json();
    } catch (e) {
      // Certains serveurs renvoient du HTML (page d'erreur) sur les
      // mauvais credentials au lieu d'un JSON propre.
      throw new XtreamError(
        'Le serveur a renvoye un format inattendu (JSON attendu)',
        'invalid_response',
        e,
      );
    }
  }
}

// ===========================================================
//  Helpers (exportes pour tests unitaires)
// ===========================================================

/**
 * Normalise une URL serveur saisie par l'utilisateur :
 *   - retire les slashes finaux
 *   - retire un suffixe `/player_api.php` que les users collent souvent
 *     par confusion
 *   - ne TOUCHE PAS au scheme (http vs https) — c'est au caller de
 *     verifier la securite avant de stocker.
 */
export function normalizeServerUrl(input: string): string {
  let s = input.trim();
  // Retire /player_api.php?... si l'utilisateur a colle un URL complet
  s = s.replace(/\/player_api\.php(\?.*)?$/i, '');
  // Retire les slashes finaux multiples
  s = s.replace(/\/+$/, '');
  return s;
}

/**
 * Parse une valeur Xtream qui peut etre soit un number, soit une string
 * de chiffres, soit `"0"` (= absent), soit un timestamp en secondes.
 * Retourne null pour les cas non-numeriques.
 */
function parseNumericOrNull(v: unknown): number | null {
  if (typeof v === 'number') {
    return Number.isFinite(v) ? v : null;
  }
  if (typeof v === 'string') {
    if (v.length === 0) return null;
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

/** Extrait le host d'une URL sans throw — pour logger sans token. */
function hostOf(url: string): string {
  try {
    return new URL(url).host;
  } catch {
    return '<invalid-url>';
  }
}
