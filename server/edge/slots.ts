/*
 * Virtual slot allocation for a master subscription line.
 *
 * A provider account permits N simultaneous connections (almost always 1). That
 * budget is the scarce resource this proxy manages, so it is modelled
 * explicitly: one `SlotPool` per account, `capacity` leases, and a policy for
 * what happens when a client asks for a channel while the budget is spent.
 *
 * Contention policies:
 *   - "swap"   (default) the pool asks the current holder to give the slot up.
 *              A holder with no viewers is dropped outright; a holder that
 *              still has viewers STARVES: its upstream closes, its downstream
 *              sockets stay open on the buffered tail, and it queues for the
 *              slot again. That is the dynamic channel switch.
 *   - "wait"   queue for the slot and fail with 503 on timeout.
 *   - "reject" fail immediately (503) — useful when zapping must never
 *              interrupt whoever is already watching.
 *
 * Eviction order among holders: no-viewer holders first (nobody notices), then
 * least-recently-active, then fewest viewers — the classic LRU choice, biased
 * so the channel most people are watching is the last to be taken away.
 */

import { AbortedError, Deferred } from "./sync.ts";
import { systemClock, type Clock } from "./clock.ts";
import { UpstreamError } from "./origin.ts";

export type ContentionPolicy = "swap" | "wait" | "reject";

/** What the pool needs to know about a hub to arbitrate between hubs. */
export interface SlotHolder {
  readonly key: string;
  readonly viewers: number;
  readonly lastActiveAt: number;
  /** True while this holder owns a lease. */
  readonly holdsSlot: boolean;
  /**
   * Give the lease back. Implementations keep downstream clients attached when
   * `viewers > 0` (starve) and shut down entirely when nobody is watching.
   * Resolves true when a lease was actually released.
   */
  yieldSlot(reason: string): Promise<boolean>;
}

export interface SlotLease {
  release(): void;
}

export type SlotEvent =
  | { type: "slot-granted"; pool: string; key: string; available: number }
  | { type: "slot-released"; pool: string; key: string; available: number }
  | { type: "slot-swap"; pool: string; from: string; to: string }
  | { type: "slot-wait"; pool: string; key: string }
  | { type: "slot-denied"; pool: string; key: string; reason: string };

export interface SlotPoolOptions {
  /** Account id — pools are per master subscription. */
  id: string;
  capacity: number;
  policy?: ContentionPolicy;
  /** How long to queue for a lease before giving up (ms). */
  waitMs?: number;
  clock?: Clock;
  onEvent?: (event: SlotEvent) => void;
}

interface Waiter {
  key: string;
  deferred: Deferred;
  granted: boolean;
}

export class SlotPool {
  #id: string;
  #capacity: number;
  #used = 0;
  /**
   * Explicit queue rather than a plain semaphore, because WHO gets a freed
   * permit matters here: a channel that starves to make room must not be able
   * to grab its own permit back before the channel it made room for takes it.
   * A swap requester queues at the FRONT, a returning starved channel at the
   * back, and the release path grants strictly in queue order.
   */
  #queue: Waiter[] = [];
  #policy: ContentionPolicy;
  #waitMs: number;
  #clock: Clock;
  #onEvent: ((event: SlotEvent) => void) | undefined;
  #holders = new Map<string, SlotHolder>();
  #grants = 0;
  #swaps = 0;
  #denials = 0;

  constructor(options: SlotPoolOptions) {
    this.#id = options.id;
    if (!Number.isInteger(options.capacity) || options.capacity < 1) {
      throw new RangeError(`slot pool needs >= 1 connection, got ${options.capacity}`);
    }
    this.#capacity = options.capacity;
    this.#policy = options.policy ?? "swap";
    this.#waitMs = options.waitMs ?? 10_000;
    this.#clock = options.clock ?? systemClock;
    this.#onEvent = options.onEvent;
  }

  get id(): string {
    return this.#id;
  }

  get capacity(): number {
    return this.#capacity;
  }

  get available(): number {
    return this.#capacity - this.#used;
  }

  get waiting(): number {
    return this.#queue.length;
  }

  get policy(): ContentionPolicy {
    return this.#policy;
  }

  get grants(): number {
    return this.#grants;
  }

  /** Number of times a live channel was swapped out for another. */
  get swaps(): number {
    return this.#swaps;
  }

  get denials(): number {
    return this.#denials;
  }

  register(holder: SlotHolder): void {
    this.#holders.set(holder.key, holder);
  }

  unregister(key: string): void {
    this.#holders.delete(key);
  }

  /** Holders currently owning a lease. */
  activeHolders(): SlotHolder[] {
    return [...this.#holders.values()].filter((holder) => holder.holdsSlot);
  }

  /**
   * Acquires a lease for `key`. The returned lease IS the permission to open an
   * upstream connection — nothing else in the edge may open one.
   */
  async acquire(
    key: string,
    options: { signal?: AbortSignal; allowSwap?: boolean; waitMs?: number } = {}
  ): Promise<SlotLease> {
    const { signal, allowSwap = true } = options;
    if (this.#queue.length === 0 && this.#take()) return this.#lease(key);

    if (this.#policy === "reject") {
      this.#denials += 1;
      this.#emit({ type: "slot-denied", pool: this.#id, key, reason: "no-slot" });
      throw new UpstreamError(`no free slot on master account ${this.#id}`, 503);
    }

    const waiter: Waiter = { key, deferred: new Deferred(), granted: false };
    const swapping = allowSwap && this.#policy === "swap";
    // Front of the queue: the permit freed by the swap below belongs to us.
    if (swapping) this.#queue.unshift(waiter);
    else this.#queue.push(waiter);

    if (swapping) {
      for (const victim of this.#evictionOrder(key)) {
        if (waiter.granted) break;
        const hadViewers = victim.viewers > 0;
        const yielded = await victim.yieldSlot(`swapped for ${key}`);
        if (!yielded) continue;
        if (hadViewers) {
          this.#swaps += 1;
          this.#emit({ type: "slot-swap", pool: this.#id, from: victim.key, to: key });
        }
      }
    }

    if (!waiter.granted) {
      this.#emit({ type: "slot-wait", pool: this.#id, key });
      const waitMs = options.waitMs ?? this.#waitMs;
      const deadline = new AbortController();
      if (waitMs > 0) {
        void this.#clock.sleep(waitMs, deadline.signal).then(() => deadline.abort());
      }
      const stopped = new Deferred<"timeout" | "cancelled">();
      const onTimeout = () => stopped.resolve("timeout");
      const onCancel = () => stopped.resolve("cancelled");
      deadline.signal.addEventListener("abort", onTimeout, { once: true });
      signal?.addEventListener("abort", onCancel, { once: true });

      const outcome = await Promise.race([
        waiter.deferred.promise.then(() => "granted" as const),
        stopped.promise,
      ]);
      deadline.abort();
      signal?.removeEventListener("abort", onCancel);

      // A grant that landed in the same tick as the deadline still counts —
      // dropping it here would leak the permit for good.
      if (outcome !== "granted" && !waiter.granted) {
        this.#drop(waiter);
        // A caller that walked away (its last viewer left) is not a denial:
        // counting it would inflate the "refused" figure on the dashboard.
        if (outcome === "cancelled") {
          throw new AbortedError(`slot wait cancelled for ${key}`);
        }
        this.#denials += 1;
        this.#emit({ type: "slot-denied", pool: this.#id, key, reason: "timeout" });
        throw new UpstreamError(`no free slot on master account ${this.#id}`, 503);
      }
    }

    return this.#lease(key);
  }

  /**
   * Opportunistic lease for control-plane work (catalogue refreshes, VOD
   * ingestion): takes a free permit, or reclaims one from a stream NOBODY is
   * watching, and otherwise gives up. A background download must never
   * interrupt a viewer — and must never become the second connection either.
   */
  async tryAcquireIdle(key: string): Promise<SlotLease | null> {
    if (this.#queue.length === 0 && this.#take()) return this.#lease(key);

    for (const holder of this.activeHolders()) {
      if (holder.key === key || holder.viewers > 0) continue;
      if (!(await holder.yieldSlot(`released for ${key}`))) continue;
      if (this.#queue.length === 0 && this.#take()) return this.#lease(key);
    }
    return null;
  }

  #take(): boolean {
    if (this.#used >= this.#capacity) return false;
    this.#used += 1;
    return true;
  }

  #free(): void {
    this.#used = Math.max(0, this.#used - 1);
    while (this.#used < this.#capacity && this.#queue.length > 0) {
      const waiter = this.#queue.shift() as Waiter;
      waiter.granted = true;
      this.#used += 1;
      waiter.deferred.resolve();
    }
  }

  #drop(waiter: Waiter): void {
    const index = this.#queue.indexOf(waiter);
    if (index >= 0) this.#queue.splice(index, 1);
  }

  #lease(key: string): SlotLease {
    this.#grants += 1;
    this.#emit({ type: "slot-granted", pool: this.#id, key, available: this.available });
    let released = false;
    return {
      release: () => {
        if (released) return;
        released = true;
        this.#free();
        this.#emit({
          type: "slot-released",
          pool: this.#id,
          key,
          available: this.available,
        });
      },
    };
  }

  /** Idle holders first, then least-recently-active, then fewest viewers. */
  #evictionOrder(requester: string): SlotHolder[] {
    return this.activeHolders()
      .filter((holder) => holder.key !== requester)
      .sort((a, b) => {
        const idle = Number(a.viewers === 0) - Number(b.viewers === 0);
        if (idle !== 0) return -idle;
        if (a.lastActiveAt !== b.lastActiveAt) return a.lastActiveAt - b.lastActiveAt;
        return a.viewers - b.viewers;
      });
  }

  #emit(event: SlotEvent): void {
    this.#onEvent?.(event);
  }
}
