/*
 * EdgeProxy — the registry of stream hubs and the process-wide upstream cap.
 *
 * Two levels of collapsing:
 *   1. Per stream: StreamHub guarantees one upstream connection however many
 *      clients join (see hub.ts).
 *   2. Process-wide: a semaphore caps TOTAL concurrent upstream connections,
 *      `maxUpstreamConnections`, which defaults to 1. With the default, the
 *      origin observes a single connection from a single IP at any instant, no
 *      matter how many players, test streams or zapping loops run on the LAN.
 *
 * When the cap is reached and a new stream is requested, the edge first drops
 * upstreams nobody is watching any more (LRU among lingering hubs) and only
 * then waits for a slot — so zapping never blocks on a stream the viewer left,
 * while a genuinely contended cap produces an honest 503 instead of a silent
 * second connection.
 */

import { SingleFlight } from "./singleflight.ts";
import { Semaphore } from "./sync.ts";
import { systemClock, type Clock } from "./clock.ts";
import { StreamHub, type HubEvent, type HubStats, type ReconnectPolicy } from "./hub.ts";
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
import type { UpstreamIdentity } from "./sanitize.ts";

export interface OriginTarget {
  url: string;
  /** Per-stream additions to the edge identity (e.g. an origin token). */
  extra?: Readonly<Record<string, string>>;
}

export type OriginResolver = (
  streamId: string
) => OriginTarget | null | Promise<OriginTarget | null>;

export interface EdgeConfig {
  /** Maps a public stream id to an origin URL. May be async (token minting). */
  resolveOrigin: OriginResolver;
  /** The single identity every upstream request is made under. */
  identity: UpstreamIdentity;
  transport?: OriginTransport;
  /** Hard cap on concurrent upstream connections. Default 1. */
  maxUpstreamConnections?: number;
  /** How long a cold stream waits for a slot before failing with 503. */
  slotWaitMs?: number;
  ring?: RingBufferOptions;
  /** Bytes replayed to a joining client for instant start. */
  backlogBytes?: number;
  subscriberQueueBytes?: number;
  /** Zapping window: upstream stays open this long with zero viewers. */
  lingerMs?: number;
  reconnect?: ReconnectPolicy;
  clock?: Clock;
  onEvent?: (event: EdgeEvent) => void;
}

export type EdgeEvent =
  | HubEvent
  | { type: "evict"; key: string }
  | { type: "slot-wait"; key: string }
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

export interface EdgeSubscription {
  subscription: Subscription;
  contentType: string | null;
  streamId: string;
}

const DEFAULTS = {
  maxUpstreamConnections: 1,
  slotWaitMs: 10_000,
  ring: { maxBytes: 16 * 1024 * 1024, maxChunks: 4096 } satisfies RingBufferOptions,
  backlogBytes: 512 * 1024,
  subscriberQueueBytes: 4 * 1024 * 1024,
  lingerMs: 15_000,
  reconnect: { attempts: 5, baseDelayMs: 250, maxDelayMs: 5_000 } satisfies ReconnectPolicy,
};

export class UnknownStreamError extends Error {
  name = "UnknownStreamError";
}

export class EdgeProxy {
  #config: EdgeConfig;
  #clock: Clock;
  #hubs = new Map<string, StreamHub>();
  #hubFlight = new SingleFlight<StreamHub>();
  #slots: Semaphore;
  #counters: UpstreamCounters = createCounters();
  #transport: OriginTransport;
  #closed = false;

  constructor(config: EdgeConfig) {
    this.#config = config;
    this.#clock = config.clock ?? systemClock;
    this.#slots = new Semaphore(config.maxUpstreamConnections ?? DEFAULTS.maxUpstreamConnections);
    // Every upstream open goes through the counter, so the invariant is
    // measured at the transport boundary rather than inferred from bookkeeping.
    this.#transport = countingTransport(config.transport ?? new FetchOriginTransport(), this.#counters);
  }

  get counters(): Readonly<UpstreamCounters> {
    return this.#counters;
  }

  get upstreamLimit(): number {
    return this.#slots.capacity;
  }

  /**
   * Attaches a client to `streamId`, opening the upstream only if this edge is
   * not already pulling it. Aborting `signal` detaches the client and, once the
   * last one is gone, starts the linger countdown.
   */
  async subscribe(
    streamId: string,
    options: { signal?: AbortSignal; maxQueueBytes?: number } = {}
  ): Promise<EdgeSubscription> {
    if (this.#closed) throw new UpstreamError("edge is shutting down", 503);
    const hub = await this.#hub(streamId);
    const subscription = await hub.join(options);
    return { subscription, contentType: hub.contentType, streamId };
  }

  stats(): EdgeStats {
    const streams = [...this.#hubs.values()].map((hub) => hub.stats());
    const bytesFromOrigin = streams.reduce((sum, s) => sum + s.bytesFromOrigin, 0);
    const bytesToClients = streams.reduce((sum, s) => sum + s.bytesFannedOut, 0);
    return {
      upstream: {
        ...this.#counters,
        limit: this.#slots.capacity,
        slotsAvailable: this.#slots.available,
        waiting: this.#slots.waiting,
      },
      downstreamClients: streams.reduce((sum, s) => sum + s.subscribers, 0),
      bytesFromOrigin,
      bytesToClients,
      bytesSaved: Math.max(0, bytesToClients - bytesFromOrigin),
      streams,
    };
  }

  async shutdown(): Promise<void> {
    this.#closed = true;
    await Promise.all([...this.#hubs.values()].map((hub) => hub.close("shutdown")));
    this.#hubs.clear();
  }

  // ---------------------------------------------------------------- internals

  /** One hub per stream id; concurrent cold joins resolve the origin once. */
  async #hub(streamId: string): Promise<StreamHub> {
    const existing = this.#hubs.get(streamId);
    if (existing) return existing;

    return this.#hubFlight.run(streamId, async () => {
      const cached = this.#hubs.get(streamId);
      if (cached) return cached;

      const target = await this.#config.resolveOrigin(streamId);
      if (!target) {
        this.#emit({ type: "reject", key: streamId, reason: "unknown-stream" });
        throw new UnknownStreamError(`unknown stream: ${streamId}`);
      }

      const hub = new StreamHub({
        key: streamId,
        url: target.url,
        transport: this.#transport,
        identity: {
          ...this.#config.identity,
          extra: { ...this.#config.identity.extra, ...target.extra },
        },
        ring: this.#config.ring ?? DEFAULTS.ring,
        backlogBytes: this.#config.backlogBytes ?? DEFAULTS.backlogBytes,
        subscriberQueueBytes: this.#config.subscriberQueueBytes ?? DEFAULTS.subscriberQueueBytes,
        lingerMs: this.#config.lingerMs ?? DEFAULTS.lingerMs,
        reconnect: this.#config.reconnect ?? DEFAULTS.reconnect,
        acquireSlot: () => this.#acquireSlot(streamId),
        clock: this.#clock,
        onEvent: (event) => this.#emit(event),
      });
      this.#hubs.set(streamId, hub);
      return hub;
    });
  }

  /** Global upstream admission: try, then evict idle streams, then wait. */
  async #acquireSlot(streamId: string): Promise<() => void> {
    let released = false;
    const release = () => {
      if (released) return;
      released = true;
      this.#slots.release();
    };

    if (this.#slots.tryAcquire()) return release;

    // Nobody is watching those upstreams any more — drop them before queueing.
    while (await this.#evictOneIdle()) {
      if (this.#slots.tryAcquire()) return release;
    }

    this.#emit({ type: "slot-wait", key: streamId });
    const timeout = new AbortController();
    const timer = setTimeout(() => timeout.abort(), this.#config.slotWaitMs ?? DEFAULTS.slotWaitMs);
    try {
      await this.#slots.acquire(timeout.signal);
    } catch {
      this.#emit({ type: "reject", key: streamId, reason: "upstream-limit" });
      throw new UpstreamError(
        `upstream connection limit reached (${this.#slots.capacity})`,
        503
      );
    } finally {
      clearTimeout(timer);
    }
    return release;
  }

  /** Stops the least-recently-used hub that is live with zero viewers. */
  async #evictOneIdle(): Promise<boolean> {
    let victim: StreamHub | null = null;
    for (const hub of this.#hubs.values()) {
      if (!hub.idleLive) continue;
      if (!victim || hub.lastActiveAt < victim.lastActiveAt) victim = hub;
    }
    if (!victim) return false;
    this.#emit({ type: "evict", key: victim.key });
    return victim.stopIfIdle();
  }

  #emit(event: EdgeEvent): void {
    this.#config.onEvent?.(event);
  }
}
