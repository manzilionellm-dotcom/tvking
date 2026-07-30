/*
 * Egress traffic shaping.
 *
 * Upstream media arrives in bursts (TCP recv windows, origin buffering). Handed
 * straight to N clients, those bursts turn into synchronised spikes: the LAN
 * link saturates, players see jitter, and one slow client drags the rest.
 *
 * `TokenBucket` meters egress at a configured byte rate; `pace()` wraps a chunk
 * stream and slices it so no single write can exceed the bucket depth. Depth
 * (`burstBytes`) is the whole trade-off knob: it equals the amount of burst
 * tolerated, so `rate / 10` gives ~100 ms of smoothing — close to CBR while
 * still letting a client that just joined drain its start-up backlog.
 */

import { systemClock, type Clock } from "./clock.ts";

export interface TokenBucketOptions {
  /** Sustained egress rate. */
  bytesPerSecond: number;
  /** Bucket depth = maximum instantaneous burst. Defaults to 100 ms of rate. */
  burstBytes?: number;
  clock?: Clock;
}

export class TokenBucket {
  #rate: number;
  #burst: number;
  #tokens: number;
  #last: number;
  #clock: Clock;
  #waitedMs = 0;

  constructor(options: TokenBucketOptions) {
    const { bytesPerSecond, burstBytes, clock } = options;
    if (!(bytesPerSecond > 0)) {
      throw new RangeError(`bytesPerSecond must be > 0, got ${bytesPerSecond}`);
    }
    this.#rate = bytesPerSecond;
    this.#burst = Math.max(1, Math.floor(burstBytes ?? bytesPerSecond / 10));
    this.#tokens = this.#burst;
    this.#clock = clock ?? systemClock;
    this.#last = this.#clock.now();
  }

  get bytesPerSecond(): number {
    return this.#rate;
  }

  get burstBytes(): number {
    return this.#burst;
  }

  get available(): number {
    this.#refill();
    return this.#tokens;
  }

  /** Total time this bucket has held data back — the shaping cost. */
  get waitedMs(): number {
    return this.#waitedMs;
  }

  tryTake(bytes: number): boolean {
    this.#assertFits(bytes);
    this.#refill();
    if (this.#tokens < bytes) return false;
    this.#tokens -= bytes;
    return true;
  }

  /** Waits until `bytes` tokens are available, then consumes them. */
  async take(bytes: number, signal?: AbortSignal): Promise<void> {
    this.#assertFits(bytes);
    for (;;) {
      if (signal?.aborted) return;
      if (this.tryTake(bytes)) return;
      const missing = bytes - this.#tokens;
      const waitMs = Math.max(1, Math.ceil((missing / this.#rate) * 1000));
      this.#waitedMs += waitMs;
      await this.#clock.sleep(waitMs, signal);
    }
  }

  #assertFits(bytes: number): void {
    if (bytes > this.#burst) {
      throw new RangeError(
        `cannot take ${bytes}B from a bucket of depth ${this.#burst}B — slice the write first`
      );
    }
  }

  #refill(): void {
    const now = this.#clock.now();
    const elapsed = now - this.#last;
    if (elapsed <= 0) return;
    this.#last = now;
    this.#tokens = Math.min(this.#burst, this.#tokens + (elapsed / 1000) * this.#rate);
  }
}

export interface PaceOptions {
  /** Upper bound on a single yielded write; also capped by the bucket depth. */
  maxSliceBytes?: number;
  signal?: AbortSignal;
}

/**
 * Meters `source` through `bucket`, yielding zero-copy `subarray` views — the
 * payload is never copied, only re-sliced.
 */
export async function* pace(
  source: AsyncIterable<Uint8Array>,
  bucket: TokenBucket,
  options: PaceOptions = {}
): AsyncGenerator<Uint8Array> {
  const sliceCap = Math.max(1, Math.min(options.maxSliceBytes ?? 64 * 1024, bucket.burstBytes));
  const { signal } = options;

  for await (const chunk of source) {
    let offset = 0;
    while (offset < chunk.byteLength) {
      if (signal?.aborted) return;
      const end = Math.min(offset + sliceCap, chunk.byteLength);
      const slice = chunk.subarray(offset, end);
      await bucket.take(slice.byteLength, signal);
      if (signal?.aborted) return;
      yield slice;
      offset = end;
    }
  }
}
