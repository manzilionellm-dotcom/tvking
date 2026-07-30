/*
 * Master accounts — one provider subscription line, N channels, C connections.
 *
 * An account owns three things the rest of the edge needs:
 *   - the channel map (from an M3U playlist, an explicit table, or a template),
 *   - the master device signature every upstream request must mirror,
 *   - the connection budget the provider allows (the slot pool capacity).
 *
 * Playlist fetches go through single-flight and a TTL cache: a hundred clients
 * hitting a cold edge cause ONE playlist download, and a refresh that fails
 * keeps serving the last good copy rather than blanking the channel map.
 */

import { SingleFlight } from "./singleflight.ts";
import { parseM3u, type M3uEntry, type M3uPlaylist } from "./m3u.ts";
import { systemClock, type Clock } from "./clock.ts";
import { masterDevice, type MasterDeviceName, type UpstreamIdentity } from "./sanitize.ts";
import { isMasterDeviceName } from "./sanitize.ts";
import type { ContentionPolicy } from "./slots.ts";
import type { OriginResolver, OriginTarget } from "./edge.ts";

export interface MasterAccountInput {
  id: string;
  label?: string;
  /** The master subscription line: an extended-M3U playlist URL. */
  playlistUrl?: string;
  /** Explicit channel map; wins over the playlist. */
  channels?: Record<string, string>;
  /** Last-resort URL template containing `{id}`. */
  channelTemplate?: string;
  /** Simultaneous connections the provider allows. Default 1. */
  maxConnections?: number;
  /** Named master device signature presented to the origin. Default "edge". */
  device?: MasterDeviceName;
  /** Full custom signature; overrides `device` when both are given. */
  identity?: UpstreamIdentity;
  /** Static credentials owned by the EDGE (never a client's). */
  headers?: Record<string, string>;
  /** Playlist cache lifetime. Default 10 minutes. */
  playlistTtlMs?: number;
  /** What to do when a client wants a channel and the budget is spent. */
  contention?: ContentionPolicy;
  /**
   * Programmatic escape hatch: resolve channels with a function instead of a
   * playlist. Used by the single-origin configuration and by tests; it wins
   * over every other source.
   */
  resolver?: OriginResolver;
}

export interface MasterAccount {
  id: string;
  label: string;
  playlistUrl?: string;
  channels?: Readonly<Record<string, string>>;
  channelTemplate?: string;
  maxConnections: number;
  device: MasterDeviceName;
  identity?: UpstreamIdentity;
  headers: Readonly<Record<string, string>>;
  playlistTtlMs: number;
  contention: ContentionPolicy;
  resolver?: OriginResolver;
}

export interface AccountSnapshot {
  id: string;
  label: string;
  maxConnections: number;
  device: MasterDeviceName;
  /** The exact User-Agent the origin sees for this account. */
  userAgent: string;
  contention: ContentionPolicy;
  source: "playlist" | "table" | "template" | "resolver" | "none";
  channelCount: number;
  playlistFetchedAt: number | null;
  playlistStale: boolean;
  playlistError: string | null;
  /** Credential field NAMES only — values never leave the process. */
  credentialHeaders: string[];
}

export type PlaylistFetcher = (
  url: string,
  identity: UpstreamIdentity,
  signal?: AbortSignal
) => Promise<string>;

export class AccountError extends Error {
  name = "AccountError";
}

const ACCOUNT_ID = /^[A-Za-z0-9._~-]{1,64}$/;
const DEFAULT_TTL_MS = 10 * 60 * 1000;

interface PlaylistCache {
  playlist: M3uPlaylist;
  fetchedAt: number;
  error: string | null;
}

export class AccountRegistry {
  #accounts = new Map<string, MasterAccount>();
  #playlists = new Map<string, PlaylistCache>();
  #flight = new SingleFlight<M3uPlaylist>();
  #fetch: PlaylistFetcher;
  #clock: Clock;

  constructor(options: { fetchPlaylist: PlaylistFetcher; clock?: Clock }) {
    this.#fetch = options.fetchPlaylist;
    this.#clock = options.clock ?? systemClock;
  }

  get size(): number {
    return this.#accounts.size;
  }

  upsert(input: MasterAccountInput): MasterAccount {
    if (!ACCOUNT_ID.test(input.id)) {
      throw new AccountError(`invalid account id: ${JSON.stringify(input.id)}`);
    }
    if (input.device !== undefined && !isMasterDeviceName(input.device)) {
      throw new AccountError(`unknown master device: ${String(input.device)}`);
    }
    const maxConnections = input.maxConnections ?? 1;
    if (!Number.isInteger(maxConnections) || maxConnections < 1) {
      throw new AccountError(`maxConnections must be a positive integer`);
    }
    for (const url of [input.playlistUrl].filter(Boolean) as string[]) {
      if (!/^https?:\/\//i.test(url)) throw new AccountError(`playlistUrl must be http(s)`);
    }
    if (input.channelTemplate && !input.channelTemplate.includes("{id}")) {
      throw new AccountError(`channelTemplate must contain {id}`);
    }
    if (!input.playlistUrl && !input.channels && !input.channelTemplate && !input.resolver) {
      throw new AccountError(`account ${input.id} has no playlistUrl, channels or channelTemplate`);
    }

    const account: MasterAccount = {
      id: input.id,
      label: input.label ?? input.id,
      playlistUrl: input.playlistUrl,
      channels: input.channels ? { ...input.channels } : undefined,
      channelTemplate: input.channelTemplate,
      maxConnections,
      device: input.device ?? "edge",
      identity: input.identity,
      headers: { ...(input.headers ?? {}) },
      playlistTtlMs: input.playlistTtlMs ?? DEFAULT_TTL_MS,
      contention: input.contention ?? "swap",
      resolver: input.resolver,
    };
    this.#accounts.set(account.id, account);
    // A changed playlist URL must not keep serving the old channel map.
    this.#playlists.delete(account.id);
    return account;
  }

  remove(id: string): boolean {
    this.#playlists.delete(id);
    return this.#accounts.delete(id);
  }

  get(id: string): MasterAccount | undefined {
    return this.#accounts.get(id);
  }

  list(): MasterAccount[] {
    return [...this.#accounts.values()];
  }

  /** The master device signature for this account, credentials included. */
  identity(id: string): UpstreamIdentity {
    const account = this.#accounts.get(id);
    if (!account) throw new AccountError(`unknown account: ${id}`);
    const base = account.identity ?? masterDevice(account.device);
    return {
      ...masterDevice(account.device),
      ...base,
      extra: { ...base.extra, ...account.headers },
    };
  }

  /** Channel list for the dashboard. */
  async channels(id: string, options: { refresh?: boolean } = {}): Promise<M3uEntry[]> {
    const account = this.#accounts.get(id);
    if (!account) throw new AccountError(`unknown account: ${id}`);
    if (account.resolver) return [];
    if (account.channels) {
      return Object.entries(account.channels).map(([channelId, url]) => ({
        id: channelId,
        name: channelId,
        url,
        attributes: {},
      }));
    }
    if (!account.playlistUrl) return [];
    const playlist = await this.#playlist(account, options.refresh ?? false);
    return playlist.entries;
  }

  /** Resolves a channel id to an origin target, or null (→ 404). */
  async resolve(id: string, channelId: string): Promise<OriginTarget | null> {
    const account = this.#accounts.get(id);
    if (!account) return null;

    if (account.resolver) return account.resolver(channelId);
    if (account.channels) {
      const url = account.channels[channelId];
      if (url) return { url, extra: account.headers };
    }
    if (account.playlistUrl) {
      const playlist = await this.#playlist(account, false);
      const entry = playlist.byId.get(channelId);
      if (entry) return { url: entry.url, extra: account.headers };
    }
    if (account.channelTemplate) {
      return {
        url: account.channelTemplate.replaceAll("{id}", encodeURIComponent(channelId)),
        extra: account.headers,
      };
    }
    return null;
  }

  snapshot(): AccountSnapshot[] {
    return this.list().map((account) => {
      const cache = this.#playlists.get(account.id);
      const source: AccountSnapshot["source"] = account.resolver
        ? "resolver"
        : account.channels
          ? "table"
          : account.playlistUrl
            ? "playlist"
            : account.channelTemplate
              ? "template"
              : "none";
      return {
        id: account.id,
        label: account.label,
        maxConnections: account.maxConnections,
        device: account.device,
        userAgent: this.identity(account.id).userAgent,
        contention: account.contention,
        source,
        channelCount: account.channels
          ? Object.keys(account.channels).length
          : (cache?.playlist.entries.length ?? 0),
        playlistFetchedAt: cache?.fetchedAt ?? null,
        playlistStale: cache ? this.#clock.now() - cache.fetchedAt > account.playlistTtlMs : false,
        playlistError: cache?.error ?? null,
        // Names only: an admin sees THAT the account carries a token, never the
        // token itself.
        credentialHeaders: Object.keys(account.headers),
      };
    });
  }

  async #playlist(account: MasterAccount, force: boolean): Promise<M3uPlaylist> {
    const cached = this.#playlists.get(account.id);
    const fresh = cached && this.#clock.now() - cached.fetchedAt < account.playlistTtlMs;
    if (cached && fresh && !force) return cached.playlist;

    return this.#flight.run(`${account.id}:${force ? "force" : "ttl"}`, async () => {
      const again = this.#playlists.get(account.id);
      if (again && !force && this.#clock.now() - again.fetchedAt < account.playlistTtlMs) {
        return again.playlist;
      }
      try {
        const body = await this.#fetch(account.playlistUrl as string, this.identity(account.id));
        const playlist = parseM3u(body);
        this.#playlists.set(account.id, {
          playlist,
          fetchedAt: this.#clock.now(),
          error: null,
        });
        return playlist;
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        if (cached) {
          // Stale beats empty: a failed refresh must not blank the channel map.
          this.#playlists.set(account.id, { ...cached, error: message });
          return cached.playlist;
        }
        throw new AccountError(`playlist fetch failed for ${account.id}: ${message}`);
      }
    });
  }
}
