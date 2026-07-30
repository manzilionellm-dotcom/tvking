/*
 * Async primitives.
 *
 * Node runs one event loop per process, but "single-threaded" does NOT mean
 * "race-free": every `await` is a yield point, so two joins can interleave
 * between the check "is the upstream open?" and the act "open the upstream".
 * That interleaving is exactly how a proxy ends up with two upstream
 * connections. The Mutex below closes those windows; the Semaphore caps the
 * number of upstream connections process-wide.
 */

/** Rejection used when a wait is cancelled through an AbortSignal. */
export class AbortedError extends Error {
  name = "AbortedError";

  constructor(message = "operation aborted") {
    super(message);
  }
}

export class Deferred<T = void> {
  promise: Promise<T>;
  resolve: (value: T | PromiseLike<T>) => void = () => {};
  reject: (reason?: unknown) => void = () => {};

  constructor() {
    this.promise = new Promise<T>((resolve, reject) => {
      this.resolve = resolve;
      this.reject = reject;
    });
  }
}

/** Fair (FIFO) non-reentrant mutex. */
export class Mutex {
  #locked = false;
  #queue: Deferred[] = [];

  get locked(): boolean {
    return this.#locked;
  }

  get waiting(): number {
    return this.#queue.length;
  }

  /** Acquires the lock, resolving to its release function (idempotent). */
  async lock(): Promise<() => void> {
    if (this.#locked) {
      const waiter = new Deferred();
      this.#queue.push(waiter);
      await waiter.promise;
    }
    this.#locked = true;

    let released = false;
    return () => {
      if (released) return;
      released = true;
      const next = this.#queue.shift();
      // Hand the lock straight to the next waiter — never unlock in between,
      // or a late arrival could jump the queue and break FIFO fairness.
      if (next) next.resolve();
      else this.#locked = false;
    };
  }

  async runExclusive<T>(fn: () => Promise<T> | T): Promise<T> {
    const release = await this.lock();
    try {
      return await fn();
    } finally {
      release();
    }
  }
}

/** Counting semaphore with FIFO waiters and abortable acquisition. */
export class Semaphore {
  #permits: number;
  #max: number;
  #queue: Deferred[] = [];

  constructor(permits: number) {
    if (!Number.isInteger(permits) || permits < 1) {
      throw new RangeError(`semaphore needs >= 1 permit, got ${permits}`);
    }
    this.#permits = permits;
    this.#max = permits;
  }

  get available(): number {
    return this.#permits;
  }

  get capacity(): number {
    return this.#max;
  }

  get waiting(): number {
    return this.#queue.length;
  }

  tryAcquire(): boolean {
    if (this.#permits <= 0) return false;
    this.#permits -= 1;
    return true;
  }

  async acquire(signal?: AbortSignal): Promise<void> {
    if (this.tryAcquire()) return;
    if (signal?.aborted) throw new AbortedError();

    const waiter = new Deferred();
    this.#queue.push(waiter);

    const onAbort = () => {
      const i = this.#queue.indexOf(waiter);
      if (i >= 0) {
        this.#queue.splice(i, 1);
        waiter.reject(new AbortedError());
      }
    };
    signal?.addEventListener("abort", onAbort, { once: true });

    try {
      await waiter.promise;
    } finally {
      signal?.removeEventListener("abort", onAbort);
    }
  }

  release(): void {
    const next = this.#queue.shift();
    // Same hand-off rule as Mutex: the permit goes to the waiter directly.
    if (next) next.resolve();
    else this.#permits = Math.min(this.#permits + 1, this.#max);
  }
}

/** Awaits `promise`, rejecting with AbortedError if `signal` fires first. */
export function withAbort<T>(promise: Promise<T>, signal?: AbortSignal): Promise<T> {
  if (!signal) return promise;
  if (signal.aborted) return Promise.reject(new AbortedError());
  return new Promise<T>((resolve, reject) => {
    const onAbort = () => reject(new AbortedError());
    signal.addEventListener("abort", onAbort, { once: true });
    promise.then(resolve, reject).finally(() => signal.removeEventListener("abort", onAbort));
  });
}
