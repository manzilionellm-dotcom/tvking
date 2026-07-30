/*
 * EdgeProxy — the stream router.
 *
 * Owns master accounts (subscription lines), their slot pools (connection
 * budgets), the per-channel hubs, and the downstream session book.
 *
 * Two levels of collapsing:
 *   1. Per channel: one StreamHub = one upstream connection, however many
 *      clients are watching (see hub.ts).
 *   2. Per account: a SlotPool caps concurrent upstream connections at the
 *      provider's limit — 1 by default. When a client asks for a channel while
 *      the budget is spent, the pool swaps: the least valuable live channel
 *      gives its slot up and, if it still has viewers, keeps them attached on
 *      the buffered tail while it queues to come back (see slots.ts).
 *
 * A stream reference is `<account>/<channel>`; a bare `<channel>` targets the
 * default account.
 */

import { SingleFlight } from "./singleflight.ts";
import { systemClock, type Clock } from "./clock.ts";
import { StreamHub, type HubEvent, type HubStats, type ReconnectPolicy } from "./hub.ts";
import { SlotPool, type ContentionPolicy, type SlotEvent, type SlotLease } from "./slots.ts";
import {
  AccountError,
  AccountRegistry,
  type AccountSnapshot,
  type MasterAccount,
  type MasterAccountInput,
} from "./accounts.ts";
import type { M3uEntry } from "./m3u.ts";
import type { Subscription } from "./broadcast.ts";
import type { RingBufferOptions } from "./ring-buffer.ts";
import {
  FetchOriginTransport,
  UpstreamError,
  countingTransport,
  createCounters,
  type OriginTransport,
  type UpstreamCounters,
} from "./origin.ts";
import { buildUpstreamHeaders, type UpstreamIdentity } from "./sanitize.ts";

export interface OriginTarget {
  url: string;
  /** Per-channel additions to the master signature (e.g. an origin token). */
  extra?: Readonly<Record<string, string>>;
}

export type OriginResolver = (
  channelId: string
) => OriginTarget | null | Promise<OriginTarget | null>;

export interface EdgeConfig {
  /** Master subscription lines. */
  accounts?: MasterAccountInput[];
  /** Single-origin shortcut: becomes the `default` account's resolver. */
  resolveOrigin?: OriginResolver;
  /** Master device signature for the `default` account. */
  identity?: UpstreamIdentity;
  transport?: OriginTransport;
  /** Connection budget of the `default` account. Default 1. */
  maxUpstreamConnections?: number;
  /** What the `default` account does when its budget is spent. */
  contention?: ContentionPolicy;
  /** How long a cold channel waits for a slot before failing with 503. */
  slotWaitMs?: number;
  ring?: RingBufferOptions;
  /** Bytes replayed to a joining client for instant start. */
  backlogBytes?: number;
  /**
   * Per-client buffer. Also the cover a client has while its channel is swapped
   * out: at the egress rate, this many bytes is how long playback survives a
   * switch without stalling.
   */
  subscriberQueueBytes?: number;
  /** Zapping window: upstream stays open this long with zero viewers. */
  lingerMs?: number;
  /** How long a swapped-out channel keeps its clients before ending them. */
  starveGraceMs?: number;
  /** Settle gap between releasing an upstream socket and opening the next. */
  swapSettleMs?: number;
  reconnect?: ReconnectPolicy;
  /** Cap on a playlist download. */
  maxPlaylistBytes?: number;
  clock?: Clock;
  onEvent?: (event: EdgeEvent) => void;
}

export type EdgeEvent =
  | HubEvent
  | SlotEvent
  | { type: "session-open"; session: string; account: string; channel: string; clients: number }
  | { type: "session-close"; session: string; account: string; channel: string; clients: number }
  | { type: "session-dropped"; session: string; account: string; channel: string; reason: string }
  | { type: "account-upsert"; account: string }
  | { type: "account-remove"; account: string }
  | { type: "reject"; key: string; reason: string };

export interface EdgeStats {
  upstream: UpstreamCounters & { limit: number; slotsAvailable: number; waiting: number };
  downstreamClients: number;
  bytesFromOrigin: number;
  bytesToClients: number;
  /** Bytes served from the edge cache instead of the WAN. */
  bytesSaved: number;
  streams: HubStats[];
}

export interface SessionSnapshot {
  /** Opaque per-connection id. Deliberately NOT derived from anything about
   *  the viewer: no IP, no user agent, no cookie. */
  id: string;
  /** Subscriber device this session belongs to, when the portal authorised it. */
  deviceId: number | null;
  deviceLabel: string | null;
  account: string;
  channel: string;
  startedAt: number;
  bytesDelivered: number;
  droppedBytes: number;
  lagEvents: number;
  queuedBytes: number;
  /** True while the channel is swapped out — the socket is alive, data is not. */
  stalled: boolean;
}

export interface AccountOverview extends AccountSnapshot {
  slots: {
    capacity: number;
    available: number;
    waiting: number;
    grants: number;
    swaps: number;
    denials: number;
    policy: ContentionPolicy;
  };
  activeChannels: string[];
  clients: number;
}

export interface EdgeOverview {
  upstream: EdgeStats["upstream"];
  accounts: AccountOverview[];
  streams: Array<HubStats & { account: string; channel: string }>;
  sessions: SessionSnapshot[];
  efficiency: {
    clientRequests: number;
    upstreamOpens: number;
    /** Client requests served per upstream connection opened. */
    requestsPerUpstream: number;
    bytesFromOrigin: number;
    bytesToClients: number;
    bytesSaved: number;
    /** LAN bytes per WAN byte. */
    fanoutRatio: number;
  };
}

export interface EdgeSubscription {
  subscription: Subscription;
  contentType: string | null;
  /** Canonical `<account>/<channel>` key. */
  streamId: string;
  account: string;
  channel: string;
  sessionId: string;
}

const DEFAULTS = {
  maxUpstreamConnections: 1,
  slotWaitMs: 10_000,
  ring: { maxBytes: 16 * 1024 * 1024, maxChunks: 4096 } satisfies RingBufferOptions,
  backlogBytes: 512 * 1024,
  subscriberQueueBytes: 4 * 1024 * 1024,
  lingerMs: 15_000,
  starveGraceMs: 30_000,
  swapSettleMs: 100,
  maxPlaylistBytes: 16 * 1024 * 1024,
  reconnect: { attempts: 5, baseDelayMs: 250, maxDelayMs: 5_000 } satisfies ReconnectPolicy,
};

export const DEFAULT_ACCOUNT = "default";

export class UnknownStreamError extends Error {
  name = "UnknownStreamError";
}

/** Splits `<account>/<channel>`; a bare id targets the default account. */
export function parseStreamId(streamId: string): { account: string; channel: string } {
  const slash = streamId.indexOf("/");
  if (slash < 0) return { account: DEFAULT_ACCOUNT, channel: streamId };
  return { account: streamId.slice(0, slash), channel: streamId.slice(slash + 1) };
}

interface Session {
  id: string;
  account: string;
  channel: string;
  startedAt: number;
  subscription: Subscription;
  hub: StreamHub;
  deviceId: number | null;
  deviceLabel: string | null;
}

export class EdgeProxy {
  #config: EdgeConfig;
  #clock: Clock;
  #hubs = new Map<string, StreamHub>();
  #hubFlight = new SingleFlight<StreamHub>();
  #pools = new Map<string, SlotPool>();
  #sessions = new Map<string, Session>();
  #accounts: AccountRegistry;
  #counters: UpstreamCounters = createCounters();
  #transport: OriginTransport;
  #clientRequests = 0;
  #closed = false;

  constructor(config: EdgeConfig) {
    this.#config = config;
    this.#clock = config.clock ?? systemClock;
    // Every upstream open goes through the counter, so the invariant is
    // measured at the transport boundary rather than inferred from bookkeeping.
    this.#transport = countingTransport(
      config.transport ?? new FetchOriginTransport(),
      this.#counters
    );
    this.#accounts = new AccountRegistry({
      clock: this.#clock,
      // Routed through the slot budget: a channel-map refresh is an upstream
      // connection like any other.
      fetchPlaylist: async (url, identity, signal) => {
        const accountId = this.#accountIdForIdentity(identity);
        if (!accountId) return this.#fetchPlaylist(url, identity, signal);
        return this.fetchText(accountId, url, { signal });
      },
    });

    if (config.resolveOrigin) {
      this.upsertAccount({
        id: DEFAULT_ACCOUNT,
        label: "default",
        resolver: config.resolveOrigin,
        maxConnections: config.maxUpstreamConnections ?? DEFAULTS.maxUpstreamConnections,
        contention: config.contention ?? "swap",
        identity: config.identity,
      });
    }
    for (const account of config.accounts ?? []) this.upsertAccount(account);
  }

  get counters(): Readonly<UpstreamCounters> {
    return this.#counters;
  }

  /** Total connection budget across every master account. */
  get upstreamLimit(): number {
    return [...this.#pools.values()].reduce((sum, pool) => sum + pool.capacity, 0);
  }

  get accounts(): AccountRegistry {
    return this.#accounts;
  }

  // ------------------------------------------------------------- admin plane

  upsertAccount(input: MasterAccountInput): MasterAccount {
    const account = this.#accounts.upsert(input);
    const existing = this.#pools.get(account.id);
    if (existing) {
      const changed =
        existing.capacity !== account.maxConnections || existing.policy !== account.contention;
      if (changed && existing.activeHolders().length > 0) {
        throw new AccountError(
          `account ${account.id} has live streams; stop them before changing its connection budget`
        );
      }
      if (changed) this.#pools.delete(account.id);
    }
    this.#poolFor(account);
    this.#emit({ type: "account-upsert", account: account.id });
    return account;
  }

  async removeAccount(id: string): Promise<boolean> {
    const existed = this.#accounts.remove(id);
    if (!existed) return false;
    for (const [key, hub] of [...this.#hubs.entries()]) {
      if (parseStreamId(key).account !== id) continue;
      await hub.close("account-removed");
      this.#hubs.delete(key);
    }
    this.#pools.delete(id);
    this.#emit({ type: "account-remove", account: id });
    return true;
  }

  listAccounts(): AccountSnapshot[] {
    return this.#accounts.snapshot();
  }

  channels(accountId: string, options: { refresh?: boolean } = {}): Promise<M3uEntry[]> {
    return this.#accounts.channels(accountId, options);
  }

  /** Ends a stream and every client on it. Returns false if it was not live. */
  async stopStream(streamId: string): Promise<boolean> {
    const { account, channel } = parseStreamId(streamId);
    const hub = this.#hubs.get(`${account}/${channel}`);
    if (!hub) return false;
    await hub.close("admin-stop");
    return true;
  }

  // ------------------------------------------------------------- data plane

  /**
   * Attaches a client to a channel. Opens an upstream connection only if this
   * edge is not already pulling that channel, and only within the account's
   * connection budget.
   */
  async subscribe(
    streamId: string,
    options: {
      signal?: AbortSignal;
      maxQueueBytes?: number;
      /** Subscriber this session belongs to; lets the enforcer cut it later. */
      owner?: { deviceId: number; label?: string };
    } = {}
  ): Promise<EdgeSubscription> {
    if (this.#closed) throw new UpstreamError("edge is shutting down", 503);
    const { account, channel } = parseStreamId(streamId);
    const key = `${account}/${channel}`;
    this.#clientRequests += 1;

    const hub = await this.#hub(account, channel, key);
    const subscription = await hub.join(options);
    const session = this.#openSession(account, channel, subscription, hub, options.owner);

    return {
      subscription,
      contentType: hub.contentType,
      streamId: key,
      account,
      channel,
      sessionId: session.id,
    };
  }

  stats(): EdgeStats {
    const streams = [...this.#hubs.values()].map((hub) => hub.stats());
    const bytesFromOrigin = streams.reduce((sum, s) => sum + s.bytesFromOrigin, 0);
    const bytesToClients = streams.reduce((sum, s) => sum + s.bytesFannedOut, 0);
    const pools = [...this.#pools.values()];
    return {
      upstream: {
        ...this.#counters,
        limit: this.upstreamLimit,
        slotsAvailable: pools.reduce((sum, pool) => sum + pool.available, 0),
        waiting: pools.reduce((sum, pool) => sum + pool.waiting, 0),
      },
      downstreamClients: streams.reduce((sum, s) => sum + s.subscribers, 0),
      bytesFromOrigin,
      bytesToClients,
      bytesSaved: Math.max(0, bytesToClients - bytesFromOrigin),
      streams,
    };
  }

  sessions(): SessionSnapshot[] {
    return [...this.#sessions.values()].map((session) => ({
      id: session.id,
      deviceId: session.deviceId,
      deviceLabel: session.deviceLabel,
      account: session.account,
      channel: session.channel,
      startedAt: session.startedAt,
      bytesDelivered: session.subscription.deliveredBytes,
      droppedBytes: session.subscription.droppedBytes,
      lagEvents: session.subscription.lagEvents,
      queuedBytes: session.subscription.queuedBytes,
      stalled: session.hub.state === "starved",
    }));
  }

  /** Everything the dashboard needs, in one consistent snapshot. */
  overview(): EdgeOverview {
    const base = this.stats();
    const sessions = this.sessions();

    const accounts: AccountOverview[] = this.#accounts.snapshot().map((snapshot) => {
      const pool = this.#pools.get(snapshot.id);
      const holders = pool?.activeHolders() ?? [];
      return {
        ...snapshot,
        slots: {
          capacity: pool?.capacity ?? 0,
          available: pool?.available ?? 0,
          waiting: pool?.waiting ?? 0,
          grants: pool?.grants ?? 0,
          swaps: pool?.swaps ?? 0,
          denials: pool?.denials ?? 0,
          policy: pool?.policy ?? "swap",
        },
        activeChannels: holders.map((holder) => parseStreamId(holder.key).channel),
        clients: sessions.filter((session) => session.account === snapshot.id).length,
      };
    });

    return {
      upstream: base.upstream,
      accounts,
      streams: base.streams.map((stream) => ({
        ...stream,
        ...parseStreamId(stream.key),
      })),
      sessions,
      efficiency: {
        clientRequests: this.#clientRequests,
        upstreamOpens: this.#counters.opens,
        requestsPerUpstream:
          this.#counters.opens === 0 ? this.#clientRequests : this.#clientRequests / this.#counters.opens,
        bytesFromOrigin: base.bytesFromOrigin,
        bytesToClients: base.bytesToClients,
        bytesSaved: base.bytesSaved,
        fanoutRatio:
          base.bytesFromOrigin === 0 ? 0 : base.bytesToClients / base.bytesFromOrigin,
      },
    };
  }

  async shutdown(): Promise<void> {
    this.#closed = true;
    await Promise.all([...this.#hubs.values()].map((hub) => hub.close("shutdown")));
    this.#hubs.clear();
    this.#sessions.clear();
  }

  // ---------------------------------------------------------------- internals

  #poolFor(account: MasterAccount): SlotPool {
    const existing = this.#pools.get(account.id);
    if (existing) return existing;
    const pool = new SlotPool({
      id: account.id,
      capacity: account.maxConnections,
      policy: account.contention,
      waitMs: this.#config.slotWaitMs ?? DEFAULTS.slotWaitMs,
      clock: this.#clock,
      onEvent: (event) => this.#emit(event),
    });
    this.#pools.set(account.id, pool);
    return pool;
  }

  /** One hub per channel; concurrent cold joins resolve the origin once. */
  async #hub(accountId: string, channel: string, key: string): Promise<StreamHub> {
    const existing = this.#hubs.get(key);
    if (existing) return existing;

    return this.#hubFlight.run(key, async () => {
      const cached = this.#hubs.get(key);
      if (cached) return cached;

      const account = this.#accounts.get(accountId);
      if (!account) {
        this.#emit({ type: "reject", key, reason: "unknown-account" });
        throw new UnknownStreamError(`unknown account: ${accountId}`);
      }
      const target = await this.#accounts.resolve(accountId, channel);
      if (!target) {
        this.#emit({ type: "reject", key, reason: "unknown-channel" });
        throw new UnknownStreamError(`unknown stream: ${key}`);
      }

      const pool = this.#poolFor(account);
      const hub = new StreamHub({
        key,
        url: target.url,
        transport: this.#transport,
        identity: {
          ...this.#accounts.identity(accountId),
          extra: { ...this.#accounts.identity(accountId).extra, ...target.extra },
        },
        ring: this.#config.ring ?? DEFAULTS.ring,
        backlogBytes: this.#config.backlogBytes ?? DEFAULTS.backlogBytes,
        subscriberQueueBytes:
          this.#config.subscriberQueueBytes ?? DEFAULTS.subscriberQueueBytes,
        lingerMs: this.#config.lingerMs ?? DEFAULTS.lingerMs,
        starveGraceMs: this.#config.starveGraceMs ?? DEFAULTS.starveGraceMs,
        swapSettleMs: this.#config.swapSettleMs ?? DEFAULTS.swapSettleMs,
        reconnect: this.#config.reconnect ?? DEFAULTS.reconnect,
        acquireSlot: (slotOptions) => pool.acquire(key, slotOptions),
        clock: this.#clock,
        onEvent: (event) => this.#emit(event),
      });
      pool.register(hub);
      this.#hubs.set(key, hub);
      return hub;
    });
  }

  /** Ends every session matching `predicate`. Used by the expiry enforcer. */
  dropSessions(predicate: (session: SessionSnapshot) => boolean, reason = "revoked"): number {
    let dropped = 0;
    for (const session of [...this.#sessions.values()]) {
      const snapshot = this.sessions().find((s) => s.id === session.id);
      if (!snapshot || !predicate(snapshot)) continue;
      session.subscription.close();
      this.#sessions.delete(session.id);
      dropped += 1;
      this.#emit({
        type: "session-dropped",
        session: session.id,
        account: session.account,
        channel: session.channel,
        reason,
      });
    }
    return dropped;
  }

  /** Live sessions belonging to one subscriber device. */
  sessionsForDevice(deviceId: number): SessionSnapshot[] {
    return this.sessions().filter((session) => session.deviceId === deviceId);
  }

  #openSession(
    account: string,
    channel: string,
    subscription: Subscription,
    hub: StreamHub,
    owner?: { deviceId: number; label?: string }
  ): Session {
    const session: Session = {
      id: randomSessionId(),
      account,
      channel,
      startedAt: this.#clock.now(),
      subscription,
      hub,
      deviceId: owner?.deviceId ?? null,
      deviceLabel: owner?.label ?? null,
    };
    this.#sessions.set(session.id, session);
    this.#emit({
      type: "session-open",
      session: session.id,
      account,
      channel,
      clients: this.#sessions.size,
    });
    subscription.addCloseListener(() => {
      this.#sessions.delete(session.id);
      this.#emit({
        type: "session-close",
        session: session.id,
        account,
        channel,
        clients: this.#sessions.size,
      });
    });
    return session;
  }

  /**
   * Lease for a VOD byte fetch. It takes a free slot, or one held by a stream
   * nobody is watching, and otherwise returns null — a film must not knock a
   * live viewer off the account it shares with them.
   */
  async acquireVodLease(accountId: string): Promise<SlotLease | null> {
    const account = this.#accounts.get(accountId);
    if (!account) return null;
    return this.#poolFor(account).tryAcquireIdle(`${accountId}:vod`);
  }

  /**
   * Control-plane download (channel map, VOD catalogue). It takes a slot only
   * if one is free or held by a stream nobody is watching: a background refresh
   * must never interrupt a viewer, and must never become the second connection
   * the provider counts. No slot → the caller keeps its stale copy.
   */
  async fetchText(
    accountId: string,
    url: string,
    options: { signal?: AbortSignal; maxBytes?: number } = {}
  ): Promise<string> {
    const account = this.#accounts.get(accountId);
    if (!account) throw new UnknownStreamError(`unknown account: ${accountId}`);
    const pool = this.#poolFor(account);
    const lease = await pool.tryAcquireIdle(`${accountId}:control`);
    if (!lease) {
      throw new UpstreamError(`master account ${accountId} is busy streaming`, 503);
    }
    try {
      return await this.#fetchPlaylist(url, this.#accounts.identity(accountId), options.signal, options.maxBytes);
    } finally {
      lease.release();
    }
  }

  async #fetchPlaylist(
    url: string,
    identity: UpstreamIdentity,
    signal?: AbortSignal,
    maxBytes?: number
  ): Promise<string> {
    const controller = new AbortController();
    const onAbort = () => controller.abort();
    signal?.addEventListener("abort", onAbort, { once: true });

    const response = await this.#transport.open({
      url,
      headers: buildUpstreamHeaders(identity).headers,
      signal: controller.signal,
    });
    try {
      if (response.status < 200 || response.status >= 300) {
        throw new UpstreamError(`playlist request failed (HTTP ${response.status})`, response.status);
      }
      const cap = maxBytes ?? this.#config.maxPlaylistBytes ?? DEFAULTS.maxPlaylistBytes;
      const chunks: Uint8Array[] = [];
      let total = 0;
      for await (const chunk of response.body) {
        total += chunk.byteLength;
        if (total > cap) throw new UpstreamError(`playlist exceeds ${cap} bytes`);
        chunks.push(chunk);
      }
      const buffer = new Uint8Array(total);
      let offset = 0;
      for (const chunk of chunks) {
        buffer.set(chunk, offset);
        offset += chunk.byteLength;
      }
      return new TextDecoder().decode(buffer);
    } finally {
      response.close();
      signal?.removeEventListener("abort", onAbort);
    }
  }

  /** Maps an identity back to its account so control fetches find their pool. */
  #accountIdForIdentity(identity: UpstreamIdentity): string | null {
    for (const account of this.#accounts.list()) {
      if (this.#accounts.identity(account.id).userAgent === identity.userAgent) return account.id;
    }
    return null;
  }

  #emit(event: EdgeEvent): void {
    this.#config.onEvent?.(event);
  }
}

function randomSessionId(): string {
  return globalThis.crypto.randomUUID().slice(0, 12);
}
