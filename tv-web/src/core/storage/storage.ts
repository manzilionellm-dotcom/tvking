// =========================================================
//  storage.ts — Persistance LocalStorage type-safe
// =========================================================
//  L'utilisateur a deja saisi sa playlist hier ; il n'a aucune envie
//  de la retaper a chaque relance. Cette couche centralise tout ce
//  qu'on persiste cote browser :
//
//    - Source courante (M3U URL ou credentials Xtream)
//    - Derniere chaine jouee (clef = channel.id)
//    - Favoris (ensemble de channel.id)
//
//  Conventions :
//    - 1 cle = 1 valeur JSON serialisable
//    - Prefixe `tv-web:` pour ne pas collisionner avec d'autres apps
//      qui partageraient le meme origin (cas Tizen / webOS qui ont une
//      origin unique pour TOUTES les apps web installees).
//    - Si JSON.parse echoue (donnee corrompue), on traite comme absente
//      au lieu de jeter — un user ne doit jamais voir un crash au boot
//      pour une cle pourrie.
//    - Si localStorage n'existe pas (mode privacy bloque, certaines TVs
//      anciennes), on tombe sur un cache memoire en fallback.
// =========================================================

import { logger } from '../observability/structured_logger.js';

const PREFIX = 'tv-web:';

/** Source courante de la playlist. Forme discriminee. */
export type PlaylistSource =
  | { readonly kind: 'm3u'; readonly url: string }
  | {
      readonly kind: 'xtream';
      readonly serverUrl: string;
      readonly username: string;
      readonly password: string;
    };

/**
 * Cle du dernier `PlaylistSource` utilise. Lu au boot pour pre-remplir
 * l'UI d'authentification.
 */
const K_LAST_SOURCE = `${PREFIX}last_source`;

/** Cle de l'identifiant de la derniere chaine jouee — reprise rapide. */
const K_LAST_CHANNEL_ID = `${PREFIX}last_channel_id`;

/** Cle de l'ensemble des favoris (array de channel.id). */
const K_FAVORITES = `${PREFIX}favorites`;

// ===========================================================
//  Backend storage (localStorage avec fallback memoire)
// ===========================================================

interface SyncStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

class MemoryStorage implements SyncStorage {
  private readonly map = new Map<string, string>();
  getItem(key: string): string | null {
    return this.map.get(key) ?? null;
  }
  setItem(key: string, value: string): void {
    this.map.set(key, value);
  }
  removeItem(key: string): void {
    this.map.delete(key);
  }
}

/**
 * Renvoie localStorage si dispo et fonctionnel (un test setItem est
 * fait pour detecter le mode private/incognito de certains
 * navigateurs ou les TVs qui bloquent l'ecriture). Sinon MemoryStorage
 * (les valeurs sont perdues au reload mais l'app ne crash pas).
 */
function pickBackend(): SyncStorage {
  try {
    if (typeof window === 'undefined' || !('localStorage' in window)) {
      return new MemoryStorage();
    }
    const probe = '__tvweb_probe__';
    window.localStorage.setItem(probe, '1');
    window.localStorage.removeItem(probe);
    return window.localStorage;
  } catch {
    logger.warn('storage', 'localstorage_unavailable', {});
    return new MemoryStorage();
  }
}

const backend = pickBackend();

// ===========================================================
//  Helpers JSON safe
// ===========================================================

function readJson<T>(key: string, validator: (v: unknown) => v is T): T | null {
  const raw = backend.getItem(key);
  if (raw === null) return null;
  try {
    const parsed: unknown = JSON.parse(raw);
    if (validator(parsed)) return parsed;
    logger.warn('storage', 'invalid_shape', { key });
    return null;
  } catch {
    logger.warn('storage', 'parse_error', { key });
    return null;
  }
}

function writeJson(key: string, value: unknown): void {
  try {
    backend.setItem(key, JSON.stringify(value));
  } catch (e) {
    // QuotaExceededError sur Tizen / mobile : on log et on continue.
    logger.warn('storage', 'write_failed', {
      key,
      error: e instanceof Error ? e.message : 'unknown',
    });
  }
}

// ===========================================================
//  API publique
// ===========================================================

/** Validateur runtime pour `PlaylistSource`. */
function isPlaylistSource(v: unknown): v is PlaylistSource {
  if (typeof v !== 'object' || v === null) return false;
  const o = v as Record<string, unknown>;
  if (o['kind'] === 'm3u') {
    return typeof o['url'] === 'string';
  }
  if (o['kind'] === 'xtream') {
    return (
      typeof o['serverUrl'] === 'string' &&
      typeof o['username'] === 'string' &&
      typeof o['password'] === 'string'
    );
  }
  return false;
}

export function loadLastSource(): PlaylistSource | null {
  return readJson(K_LAST_SOURCE, isPlaylistSource);
}

export function saveLastSource(src: PlaylistSource): void {
  writeJson(K_LAST_SOURCE, src);
}

export function clearLastSource(): void {
  backend.removeItem(K_LAST_SOURCE);
}

export function loadLastChannelId(): string | null {
  const raw = backend.getItem(K_LAST_CHANNEL_ID);
  return raw && raw.length > 0 ? raw : null;
}

export function saveLastChannelId(id: string): void {
  try {
    backend.setItem(K_LAST_CHANNEL_ID, id);
  } catch (e) {
    logger.warn('storage', 'write_failed', {
      key: K_LAST_CHANNEL_ID,
      error: e instanceof Error ? e.message : 'unknown',
    });
  }
}

function isStringArray(v: unknown): v is string[] {
  return Array.isArray(v) && v.every((x) => typeof x === 'string');
}

export function loadFavorites(): readonly string[] {
  const arr = readJson(K_FAVORITES, isStringArray);
  return arr ?? [];
}

export function saveFavorites(ids: readonly string[]): void {
  writeJson(K_FAVORITES, [...ids]);
}

export function toggleFavorite(id: string): readonly string[] {
  const current = new Set(loadFavorites());
  if (current.has(id)) {
    current.delete(id);
  } else {
    current.add(id);
  }
  const next = Array.from(current);
  saveFavorites(next);
  return next;
}

/**
 * Reserve aux tests — vide tout l'espace `tv-web:`. NE PAS appeler en
 * prod (purge les favoris de l'utilisateur).
 */
export function _testReset(): void {
  for (const k of [K_LAST_SOURCE, K_LAST_CHANNEL_ID, K_FAVORITES]) {
    backend.removeItem(k);
  }
}
