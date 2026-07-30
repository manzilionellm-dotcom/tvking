/*
 * Injectable monotonic clock.
 *
 * Every time-dependent part of the edge (token-bucket pacing, linger timers,
 * reconnect backoff) takes a Clock so tests can drive time deterministically
 * instead of sleeping. Production uses `performance.now()`, which is monotonic
 * and immune to wall-clock jumps (NTP steps, DST) — `Date.now()` is not.
 */

export interface Clock {
  /** Milliseconds since an arbitrary origin. Monotonic, non-decreasing. */
  now(): number;
  /**
   * Resolves after `ms` have elapsed, or early if `signal` aborts.
   * Never rejects: callers re-check `signal.aborted` after awaiting.
   */
  sleep(ms: number, signal?: AbortSignal): Promise<void>;
}

export const systemClock: Clock = {
  now() {
    return performance.now();
  },
  sleep(ms, signal) {
    if (ms <= 0 || signal?.aborted) return Promise.resolve();
    return new Promise<void>((resolve) => {
      const done = () => {
        clearTimeout(timer);
        signal?.removeEventListener("abort", done);
        resolve();
      };
      const timer = setTimeout(done, ms);
      // A pending sleep (linger countdown, pacing gap) must not by itself keep
      // the process alive on shutdown.
      timer.unref?.();
      signal?.addEventListener("abort", done, { once: true });
    });
  },
};

interface Waiter {
  at: number;
  resolve: () => void;
  onAbort?: () => void;
  signal?: AbortSignal;
}

/**
 * Clock whose time only moves when the test says so. `advance()` fires every
 * waiter that came due and then yields to the macrotask queue, so the code
 * under test has actually run by the time `advance()` resolves.
 */
export class ManualClock implements Clock {
  #t = 0;
  #waiters: Waiter[] = [];

  now(): number {
    return this.#t;
  }

  sleep(ms: number, signal?: AbortSignal): Promise<void> {
    if (ms <= 0 || signal?.aborted) return Promise.resolve();
    return new Promise<void>((resolve) => {
      const waiter: Waiter = { at: this.#t + ms, resolve, signal };
      if (signal) {
        waiter.onAbort = () => {
          this.#drop(waiter);
          resolve();
        };
        signal.addEventListener("abort", waiter.onAbort, { once: true });
      }
      this.#waiters.push(waiter);
    });
  }

  /** Moves time forward by `ms` and lets everything it woke up run. */
  async advance(ms: number): Promise<void> {
    this.#t += ms;
    const due = this.#waiters.filter((w) => w.at <= this.#t);
    this.#waiters = this.#waiters.filter((w) => w.at > this.#t);
    for (const waiter of due) {
      if (waiter.onAbort && waiter.signal) waiter.signal.removeEventListener("abort", waiter.onAbort);
      waiter.resolve();
    }
    await new Promise<void>((resolve) => setImmediate(resolve));
  }

  get pending(): number {
    return this.#waiters.length;
  }

  #drop(waiter: Waiter): void {
    const i = this.#waiters.indexOf(waiter);
    if (i >= 0) this.#waiters.splice(i, 1);
  }
}
