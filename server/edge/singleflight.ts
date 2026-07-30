/*
 * Single-flight: N concurrent callers asking for the same key produce exactly
 * ONE execution of the work function; everyone else awaits that same promise.
 *
 * This is the classic thundering-herd guard (Go's `singleflight`, Varnish
 * request coalescing, nginx `proxy_cache_lock`). In this proxy it guarantees
 * that a burst of downstream joins on a cold stream opens one upstream
 * connection, not one per client.
 */

export class SingleFlight<T> {
  #inflight = new Map<string, Promise<T>>();
  #coalesced = 0;
  #executions = 0;

  /** Number of keys currently executing. */
  get inflight(): number {
    return this.#inflight.size;
  }

  /** How many callers rode along on someone else's execution. */
  get coalesced(): number {
    return this.#coalesced;
  }

  /** How many times the work function actually ran. */
  get executions(): number {
    return this.#executions;
  }

  has(key: string): boolean {
    return this.#inflight.has(key);
  }

  run(key: string, fn: () => Promise<T> | T): Promise<T> {
    const existing = this.#inflight.get(key);
    if (existing) {
      this.#coalesced += 1;
      return existing;
    }

    this.#executions += 1;
    // The slot is filled below, before the `finally` can run (the `await` yields
    // at least one microtask first). Clearing only our own entry matters: a
    // later call for the same key may already have installed a fresh promise.
    const slot: { promise?: Promise<T> } = {};
    const call = (async () => {
      try {
        return await fn();
      } finally {
        if (this.#inflight.get(key) === slot.promise) this.#inflight.delete(key);
      }
    })();
    slot.promise = call;
    this.#inflight.set(key, call);
    return call;
  }
}
