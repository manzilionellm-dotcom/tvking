/*
 * StreamHub — one logical stream, at most one upstream connection.
 *
 * Lifecycle:
 *
 *   idle ──join()──▶ [slot] ──open()──▶ live ──pump──▶ ring ──▶ broadcaster ──▶ N clients
 *    ▲                                    │
 *    └────── stop (linger expired / EOF / fatal error) ◀──── last client leaves
 *
 * The invariant "at most one upstream connection per hub" is held by a mutex
 * around the whole lifecycle, not by a bare boolean: `await` inside `#start()`
 * (slot acquisition, TCP + TLS, response headers) is precisely where a second
 * join would otherwise slip through the check-then-act window.
 *
 * When the last client leaves, the upstream is kept open for `lingerMs`. That
 * is what makes zapping free: a client that switches away and back within the
 * linger window rejoins the live buffer with no new TCP/TLS handshake and no
 * re-negotiation with the origin.
 *
 * Note what this class does NOT accept: downstream request headers. It cannot
 * forward client metadata upstream because it is never given any — the privacy
 * boundary is structural, not a filter someone can forget to call.
 */

import { Broadcaster, type Subscription } from "./broadcast.ts";
import { RingBuffer, type RingBufferOptions } from "./ring-buffer.ts";
import { systemClock, type Clock } from "./clock.ts";
import { Mutex } from "./sync.ts";
import { UpstreamError, type OriginResponse, type OriginTransport } from "./origin.ts";
import {
  assertMirrorsMasterSignature,
  buildUpstreamHeaders,
  type UpstreamIdentity,
} from "./sanitize.ts";
import type { SlotLease } from "./slots.ts";

export type HubEvent =
  | { type: "upstream-open"; key: string; attempt: number }
  | { type: "upstream-live"; key: string; status: number; contentType: string | null }
  | { type: "upstream-close"; key: string; reason: string; bytes: number }
  | { type: "upstream-error"; key: string; message: string }
  | { type: "reconnect"; key: string; attempt: number; delayMs: number }
  | { type: "starve"; key: string; reason: string; subscribers: number }
  | { type: "resume"; key: string; subscribers: number }
  | { type: "join"; key: string; subscribers: number }
  | { type: "leave"; key: string; subscribers: number }
  | { type: "linger"; key: string; ms: number };

export interface ReconnectPolicy {
  /** Reconnect attempts after an upstream EOF/error while clients remain. */
  attempts: number;
  baseDelayMs: number;
  maxDelayMs: number;
}

export interface StreamHubOptions {
  key: string;
  url: string;
  transport: OriginTransport;
  identity: UpstreamIdentity;
  ring: RingBufferOptions;
  /** Bytes of buffered stream handed to a joining client for instant start. */
  backlogBytes: number;
  /** Per-client queue cap before drop-oldest kicks in. */
  subscriberQueueBytes: number;
  /** How long the upstream stays open with zero clients (zapping window). */
  lingerMs: number;
  reconnect: ReconnectPolicy;
  /**
   * Virtual slot admission for the master account. The hub holds the lease for
   * its whole live period, across reconnects, and gives it back when it stops
   * or is swapped out. `allowSwap: false` means "queue, do not evict anyone" —
   * used when a starved channel is waiting to come back.
   */
  acquireSlot?: (options: { signal?: AbortSignal; allowSwap?: boolean; waitMs?: number }) => Promise<SlotLease>;
  /**
   * How long a swapped-out channel keeps its clients attached while waiting for
   * the slot to come back. After that they are ended honestly rather than left
   * staring at a stalled socket.
   */
  starveGraceMs?: number;
  /** Upper bound on waiting for a closing upstream socket to unwind. */
  quiesceMs?: number;
  /**
   * Pause between giving an upstream socket up and letting the next channel
   * connect. Closing a socket locally is not the same as the ORIGIN seeing it
   * closed: without this gap the provider can observe the old and the new
   * connection overlapping for a round trip, and count two.
   */
  swapSettleMs?: number;
  clock?: Clock;
  onEvent?: (event: HubEvent) => void;
}

export interface JoinOptions {
  signal?: AbortSignal;
  maxQueueBytes?: number;
}

export interface HubStats {
  key: string;
  state: HubState;
  holdsSlot: boolean;
  /** Times this channel was swapped out to free its slot. */
  starves: number;
  /** Milliseconds spent swapped out with clients still attached. */
  starvedMs: number;
  subscribers: number;
  bufferedBytes: number;
  bufferedChunks: number;
  bytesFromOrigin: number;
  bytesFannedOut: number;
  upstreamOpens: number;
  slowestQueueBytes: number;
  contentType: string | null;
  lingering: boolean;
}

/**
 * `starved` is the interesting one: no upstream connection, no slot, but the
 * downstream sockets are still open and draining their buffers while the hub
 * queues for the slot to come back. That is what makes a channel switch look
 * instant to the client that caused it and survivable to the ones that did not.
 */
export type HubState = "idle" | "live" | "starved" | "stopping";

export class StreamHub {
  #options: StreamHubOptions;
  #clock: Clock;
  #lifecycle = new Mutex();
  #ring: RingBuffer;
  #broadcaster = new Broadcaster();
  #state: HubState = "idle";
  #subscribers = 0;
  #abort: AbortController | null = null;
  #pump: Promise<void> | null = null;
  #lease: SlotLease | null = null;
  #starveAbort: AbortController | null = null;
  #starvedAt = 0;
  #starvedMs = 0;
  #starves = 0;
  #lingerTimer: AbortController | null = null;
  #generation = 0;
  #contentType: string | null = null;
  #bytesFromOrigin = 0;
  #fanoutBase = 0; // fan-out from previous broadcasters, kept across restarts
  #upstreamOpens = 0;
  #closed = false;
  #lastActiveAt = 0;

  constructor(options: StreamHubOptions) {
    this.#options = options;
    this.#clock = options.clock ?? systemClock;
    this.#ring = new RingBuffer(options.ring);
    this.#lastActiveAt = this.#clock.now();
  }

  get key(): string {
    return this.#options.key;
  }

  get state(): HubState {
    return this.#state;
  }

  get subscribers(): number {
    return this.#subscribers;
  }

  get contentType(): string | null {
    return this.#contentType;
  }

  /** True when the upstream is open but nobody is watching (evictable). */
  get idleLive(): boolean {
    return this.#state === "live" && this.#subscribers === 0;
  }

  /** SlotHolder view: this hub owns a lease on its account's slot pool. */
  get holdsSlot(): boolean {
    return this.#lease !== null;
  }

  /** SlotHolder view: how many downstream clients would notice a swap. */
  get viewers(): number {
    return this.#subscribers;
  }

  /** Clock time of the last join/leave — LRU key for eviction. */
  get lastActiveAt(): number {
    return this.#lastActiveAt;
  }

  /**
   * Attaches a downstream client. Opens the upstream only if this hub does not
   * already have one; concurrent joins are serialised and share it.
   */
  async join(options: JoinOptions = {}): Promise<Subscription> {
    return this.#lifecycle.runExclusive(async () => {
      if (this.#closed) throw new UpstreamError("edge stream closed");
      this.#cancelLinger();
      // Joining a starved channel attaches to the buffer and waits for the slot
      // to come back rather than swapping someone else out — otherwise two
      // populated channels would take turns evicting each other.
      if (this.#state !== "live" && this.#state !== "starved") await this.#start();

      this.#subscribers += 1;
      this.#lastActiveAt = this.#clock.now();
      const subscription = this.#broadcaster.subscribe({
        maxQueueBytes: options.maxQueueBytes ?? this.#options.subscriberQueueBytes,
        // Instant start: replay the tail of the edge cache before live data.
        backlog: this.#ring.tail(this.#options.backlogBytes),
        signal: options.signal,
        onClose: () => this.#leave(),
      });
      this.#emit({ type: "join", key: this.key, subscribers: this.#subscribers });
      return subscription;
    });
  }

  stats(): HubStats {
    return {
      key: this.key,
      state: this.#state,
      holdsSlot: this.holdsSlot,
      starves: this.#starves,
      starvedMs: this.#starvedMs + (this.#state === "starved" ? this.#clock.now() - this.#starvedAt : 0),
      subscribers: this.#subscribers,
      bufferedBytes: this.#ring.bytes,
      bufferedChunks: this.#ring.size,
      bytesFromOrigin: this.#bytesFromOrigin,
      bytesFannedOut: this.#fanoutBase + this.#broadcaster.fanoutBytes,
      upstreamOpens: this.#upstreamOpens,
      slowestQueueBytes: this.#broadcaster.slowestQueueBytes(),
      contentType: this.#contentType,
      lingering: this.#lingerTimer !== null,
    };
  }

  /**
   * Gives the account slot back so another channel can use it (SlotHolder).
   *
   * With no viewers the hub simply stops. With viewers it STARVES: the upstream
   * connection closes, the lease is released, but the broadcaster, the ring and
   * every downstream socket stay exactly as they are. Clients keep playing out
   * of their buffers while the hub queues for the slot to come back, so a
   * channel switch never drops anyone else's HTTP connection.
   */
  async yieldSlot(reason: string): Promise<boolean> {
    return this.#lifecycle.runExclusive(async () => {
      if (!this.#lease || this.#state !== "live") return false;
      if (this.#subscribers === 0) {
        await this.#stop(reason);
        return true;
      }
      await this.#starveNow(reason);
      return true;
    });
  }

  /** Stops the upstream if no client is attached. Used by the LRU evictor. */
  async stopIfIdle(): Promise<boolean> {
    return this.#lifecycle.runExclusive(async () => {
      if (this.#state !== "live" || this.#subscribers > 0) return false;
      await this.#stop("evicted");
      return true;
    });
  }

  /** Tears the hub down for good and ends every subscription. */
  async close(reason = "shutdown"): Promise<void> {
    this.#closed = true;
    await this.#lifecycle.runExclusive(async () => {
      await this.#stop(reason);
    });
  }

  // ---------------------------------------------------------------- internals

  /** Caller MUST hold #lifecycle. */
  async #start(): Promise<void> {
    const lease = this.#options.acquireSlot
      ? await this.#options.acquireSlot({ allowSwap: true })
      : { release: () => {} };
    await this.#launch(lease);
  }

  /**
   * Opens the upstream under an already-granted lease and starts the pump.
   * Caller MUST hold #lifecycle.
   */
  async #launch(lease: SlotLease): Promise<void> {
    const controller = new AbortController();
    try {
      const response = await this.#open(controller.signal, 1);
      this.#applyResponse(response);
      this.#abort = controller;
      this.#lease = lease;
      this.#state = "live";
      this.#generation += 1;
      const generation = this.#generation;
      // Detached on purpose: the pump outlives this join.
      this.#pump = this.#run(response, controller, generation);
    } catch (error) {
      controller.abort();
      lease.release();
      this.#emit({
        type: "upstream-error",
        key: this.key,
        message: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  }

  async #open(signal: AbortSignal, attempt: number): Promise<OriginResponse> {
    // Built from the master signature alone — no downstream input reaches here.
    const headers = buildUpstreamHeaders(this.#options.identity);
    // Belt and braces: the request must be byte-identical whoever asked for it.
    assertMirrorsMasterSignature(headers.headers, this.#options.identity);

    this.#upstreamOpens += 1;
    this.#emit({ type: "upstream-open", key: this.key, attempt });

    const response = await this.#options.transport.open({
      url: this.#options.url,
      headers: headers.headers,
      signal,
    });

    if (response.status < 200 || response.status >= 300) {
      response.close();
      throw new UpstreamError(`origin refused the stream (HTTP ${response.status})`, response.status);
    }
    return response;
  }

  #applyResponse(response: OriginResponse): void {
    this.#contentType = response.headers["content-type"] ?? this.#contentType;
    this.#emit({
      type: "upstream-live",
      key: this.key,
      status: response.status,
      contentType: this.#contentType,
    });
  }

  /** The single upstream pump. Exactly one runs per live generation. */
  async #run(
    first: OriginResponse,
    controller: AbortController,
    generation: number
  ): Promise<void> {
    let response = first;
    let attempt = 0;
    let failure: Error | null = null;
    let reason = "eof";

    try {
      for (;;) {
        await this.#drain(response, controller.signal, generation);
        if (controller.signal.aborted) {
          reason = "aborted";
          break;
        }
        if (this.#subscribers === 0) {
          reason = "eof";
          break;
        }
        attempt += 1;
        if (attempt > this.#options.reconnect.attempts) {
          failure = new UpstreamError("upstream ended and the reconnect budget is exhausted");
          break;
        }
        const delayMs = this.#backoff(attempt);
        this.#emit({ type: "reconnect", key: this.key, attempt, delayMs });
        await this.#clock.sleep(delayMs, controller.signal);
        if (controller.signal.aborted) {
          reason = "aborted";
          break;
        }
        response = await this.#open(controller.signal, attempt + 1);
        this.#applyResponse(response);
      }
    } catch (error) {
      if (controller.signal.aborted) reason = "aborted";
      else failure = error instanceof Error ? error : new Error(String(error));
    }

    if (failure) {
      this.#emit({ type: "upstream-error", key: this.key, message: failure.message });
    }
    // Detached: #finish takes the lifecycle mutex, which a concurrent #stop()
    // may be holding while it awaits this very pump.
    if (!controller.signal.aborted) {
      void this.#finish(generation, failure ?? undefined, reason);
    }
  }

  async #drain(response: OriginResponse, signal: AbortSignal, generation: number): Promise<void> {
    const cap = this.#ring.capacityBytes;
    for await (const chunk of response.body) {
      // A superseded pump must never write into the current generation's
      // buffer, even if its transport ignores the abort signal.
      if (signal.aborted || generation !== this.#generation) return;
      if (chunk.byteLength === 0) continue;
      // Zero-copy in the common case; only an absurdly large chunk is sliced.
      for (let offset = 0; offset < chunk.byteLength; offset += cap) {
        const slice =
          chunk.byteLength <= cap ? chunk : chunk.subarray(offset, Math.min(offset + cap, chunk.byteLength));
        this.#bytesFromOrigin += slice.byteLength;
        this.#broadcaster.publish(this.#ring.push(slice, this.#clock.now()));
      }
    }
  }

  async #finish(generation: number, error: Error | undefined, reason: string): Promise<void> {
    await this.#lifecycle.runExclusive(async () => {
      if (generation !== this.#generation || this.#state !== "live") return;
      await this.#stop(reason, error);
    });
  }

  /**
   * Live → starved. Caller MUST hold #lifecycle.
   * Everything downstream is deliberately left untouched.
   */
  async #starveNow(reason: string): Promise<void> {
    this.#generation += 1; // retire the pump before anything else
    this.#abort?.abort();
    this.#abort = null;
    const pump = this.#pump;
    this.#pump = null;

    // The lease is only handed back once the socket is really gone: releasing
    // it earlier would let the next channel connect while the provider still
    // counts this one, which is precisely the overlap the budget forbids.
    await this.#quiesce(pump);
    await this.#releaseLease();
    this.#state = "starved";
    this.#starvedAt = this.#clock.now();
    this.#starves += 1;
    this.#emit({ type: "starve", key: this.key, reason, subscribers: this.#subscribers });
    this.#queueResume();
  }

  /** Queues for the slot to come back, under a bounded grace period. */
  #queueResume(): void {
    const pending = new AbortController();
    this.#starveAbort = pending;

    const graceMs = this.#options.starveGraceMs ?? 30_000;
    void this.#clock.sleep(graceMs, pending.signal).then(async () => {
      if (pending.signal.aborted) return;
      // The slot never came back. Ending the subscriptions is the honest
      // outcome: better a clean end than a socket that stalls forever.
      await this.#lifecycle.runExclusive(async () => {
        if (this.#state !== "starved" || this.#starveAbort !== pending) return;
        await this.#stop(
          "starve-timeout",
          new UpstreamError("channel lost its slot on the master account", 503)
        );
      });
    });

    void this.#awaitSlot(pending);
  }

  async #awaitSlot(pending: AbortController): Promise<void> {
    if (!this.#options.acquireSlot) return;
    let lease: SlotLease;
    try {
      // allowSwap:false — a starved channel waits its turn, it does not evict
      // the channel that just took the slot. waitMs:0 — the grace timer above
      // owns the deadline.
      lease = await this.#options.acquireSlot({
        signal: pending.signal,
        allowSwap: false,
        waitMs: 0,
      });
    } catch {
      return; // denied or cancelled; the grace timer or #leave() ends the hub
    }

    await this.#lifecycle.runExclusive(async () => {
      if (this.#state !== "starved" || pending.signal.aborted || this.#starveAbort !== pending) {
        lease.release();
        return;
      }
      this.#cancelStarve();
      try {
        await this.#launch(lease);
        this.#starvedMs += this.#clock.now() - this.#starvedAt;
        this.#emit({ type: "resume", key: this.key, subscribers: this.#subscribers });
      } catch (error) {
        await this.#stop(
          "resume-failed",
          error instanceof Error ? error : new Error(String(error))
        );
      }
    });
  }

  #cancelStarve(): void {
    if (this.#starveAbort) {
      this.#starveAbort.abort();
      this.#starveAbort = null;
    }
  }

  #leave(): void {
    this.#subscribers = Math.max(0, this.#subscribers - 1);
    this.#lastActiveAt = this.#clock.now();
    this.#emit({ type: "leave", key: this.key, subscribers: this.#subscribers });
    if (this.#subscribers > 0) return;
    if (this.#state === "live") this.#scheduleLinger();
    // The last client of a swapped-out channel left: stop queueing for a slot
    // nobody is waiting for any more.
    if (this.#state === "starved") {
      void this.#lifecycle.runExclusive(async () => {
        if (this.#state !== "starved" || this.#subscribers > 0) return;
        await this.#stop("starved-abandoned");
      });
    }
  }

  #scheduleLinger(): void {
    this.#cancelLinger();
    const ms = this.#options.lingerMs;
    this.#emit({ type: "linger", key: this.key, ms });
    if (ms <= 0) {
      void this.stopIfIdle();
      return;
    }
    // The linger window is what makes channel switching free; it is bounded so
    // an abandoned stream cannot hold a WAN connection open forever.
    const countdown = new AbortController();
    this.#lingerTimer = countdown;
    void this.#clock.sleep(ms, countdown.signal).then(() => {
      if (countdown.signal.aborted) return;
      this.#lingerTimer = null;
      void this.stopIfIdle();
    });
  }

  #cancelLinger(): void {
    if (this.#lingerTimer) {
      this.#lingerTimer.abort();
      this.#lingerTimer = null;
    }
  }

  /** Caller MUST hold #lifecycle. */
  async #stop(reason: string, error?: Error): Promise<void> {
    if (this.#state === "idle") return;
    this.#state = "stopping";
    this.#cancelLinger();
    // Retire the generation immediately: from here on, the old pump is a ghost.
    this.#generation += 1;

    this.#abort?.abort();
    this.#abort = null;
    const pump = this.#pump;
    this.#pump = null;

    this.#broadcaster.close(error);
    // A fresh broadcaster and an empty ring: replaying seconds-old live data to
    // the next viewer would be worse than a clean start.
    this.#fanoutBase += this.#broadcaster.fanoutBytes;
    this.#broadcaster = new Broadcaster();
    this.#ring.clear();
    this.#subscribers = 0;

    if (this.#starveAbort) {
      this.#starvedMs += this.#clock.now() - this.#starvedAt;
      this.#cancelStarve();
    }

    await this.#quiesce(pump);
    await this.#releaseLease();
    this.#state = "idle";

    this.#emit({
      type: "upstream-close",
      key: this.key,
      reason,
      bytes: this.#bytesFromOrigin,
    });
  }

  /**
   * Waits for the pump to finish unwinding — i.e. for the upstream socket to be
   * closed — but never for longer than `quiesceMs`. The cap uses real time on
   * purpose: it exists to survive a transport that ignores its abort signal,
   * and a bounded wait is better than a lifecycle mutex held forever. The
   * generation check in #drain already prevents a late pump from publishing.
   */
  async #quiesce(pump: Promise<void> | null): Promise<void> {
    if (!pump) return;
    const capMs = this.#options.quiesceMs ?? 2_000;
    await Promise.race([pump.catch(() => {}), systemClock.sleep(capMs)]);
  }

  /**
   * Hands the lease back after letting the origin notice the socket closing.
   * Real time again: this models a network round trip, not logical time.
   */
  async #releaseLease(): Promise<void> {
    if (!this.#lease) return;
    const settleMs = this.#options.swapSettleMs ?? 100;
    if (settleMs > 0) await systemClock.sleep(settleMs);
    this.#lease.release();
    this.#lease = null;
  }

  #backoff(attempt: number): number {
    const { baseDelayMs, maxDelayMs } = this.#options.reconnect;
    return Math.min(maxDelayMs, baseDelayMs * 2 ** (attempt - 1));
  }

  #emit(event: HubEvent): void {
    this.#options.onEvent?.(event);
  }
}
