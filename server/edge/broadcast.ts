/*
 * Asynchronous fan-out (pub/sub) over the edge cache.
 *
 * One publisher (the upstream pump) feeds N independent subscribers. Each
 * subscriber owns a bounded queue of chunk REFERENCES — the payload bytes stay
 * shared with the ring buffer, so fan-out is O(1) memory per client, not O(bytes).
 *
 * Overflow policy is drop-oldest, the correct choice for live media: a client
 * whose socket stalls should resume near the live edge rather than accumulate a
 * growing backlog (and unbounded memory). Drops are counted, never silent.
 * This mirrors `tokio::sync::broadcast`'s lag behaviour.
 */

import { Deferred } from "./sync.ts";
import type { StreamChunk } from "./ring-buffer.ts";

export interface SubscribeOptions {
  /** Bytes this subscriber may buffer before the oldest queued chunk is dropped. */
  maxQueueBytes?: number;
  /** Chunks delivered before live data (typically `ring.tail(n)`). */
  backlog?: readonly StreamChunk[];
  /** Invoked exactly once when the subscription ends, whatever the reason. */
  onClose?: () => void;
  /** Ends the subscription when aborted (client disconnect). */
  signal?: AbortSignal;
}

const DEFAULT_QUEUE_BYTES = 4 * 1024 * 1024;

export class Subscription implements AsyncIterable<StreamChunk> {
  #queue: StreamChunk[] = [];
  #head = 0; // read cursor into #queue, avoids O(n) shift()
  #queuedBytes = 0;
  #maxQueueBytes: number;
  #waiter: Deferred | null = null;
  #ended = false; // publisher finished
  #closed = false; // consumer left
  #error: Error | null = null;
  #iterated = false;
  #deliveredBytes = 0;
  #droppedBytes = 0;
  #droppedChunks = 0;
  #lagEvents = 0;
  #onClose: (() => void) | undefined;
  #signal: AbortSignal | undefined;
  #onAbort: (() => void) | undefined;
  #detach: (sub: Subscription) => void;

  constructor(options: SubscribeOptions, detach: (sub: Subscription) => void) {
    this.#maxQueueBytes = options.maxQueueBytes ?? DEFAULT_QUEUE_BYTES;
    this.#onClose = options.onClose;
    this.#detach = detach;

    for (const chunk of options.backlog ?? []) this.push(chunk);

    this.#signal = options.signal;
    if (this.#signal) {
      this.#onAbort = () => this.close();
      if (this.#signal.aborted) this.close();
      else this.#signal.addEventListener("abort", this.#onAbort, { once: true });
    }
  }

  get deliveredBytes(): number {
    return this.#deliveredBytes;
  }

  /** Bytes skipped because this client could not keep up. */
  get droppedBytes(): number {
    return this.#droppedBytes;
  }

  get droppedChunks(): number {
    return this.#droppedChunks;
  }

  /** Number of distinct times the subscriber went into overflow. */
  get lagEvents(): number {
    return this.#lagEvents;
  }

  get queuedBytes(): number {
    return this.#queuedBytes;
  }

  get closed(): boolean {
    return this.#closed;
  }

  /** @internal — called by the Broadcaster. */
  push(chunk: StreamChunk): void {
    if (this.#closed || this.#ended) return;

    let lagged = false;
    while (
      this.#queuedBytes + chunk.data.byteLength > this.#maxQueueBytes &&
      this.#head < this.#queue.length
    ) {
      const dropped = this.#queue[this.#head];
      this.#head += 1;
      this.#queuedBytes -= dropped.data.byteLength;
      this.#droppedBytes += dropped.data.byteLength;
      this.#droppedChunks += 1;
      lagged = true;
    }
    if (lagged) this.#lagEvents += 1;

    this.#queue.push(chunk);
    this.#queuedBytes += chunk.data.byteLength;
    this.#compact();
    this.#wake();
  }

  /** @internal — publisher is done; the queue still drains. */
  end(error?: Error): void {
    if (this.#ended) return;
    this.#ended = true;
    if (error) this.#error = error;
    this.#wake();
  }

  /** Consumer side: stop receiving and release the slot. Idempotent. */
  close(): void {
    if (this.#closed) return;
    this.#closed = true;
    this.#queue = [];
    this.#head = 0;
    this.#queuedBytes = 0;
    if (this.#signal && this.#onAbort) this.#signal.removeEventListener("abort", this.#onAbort);
    this.#detach(this);
    this.#wake();
    this.#onClose?.();
  }

  [Symbol.asyncIterator](): AsyncIterator<StreamChunk> {
    if (this.#iterated) {
      throw new Error("a Subscription can only be iterated once");
    }
    this.#iterated = true;
    return this.#iterate();
  }

  async *#iterate(): AsyncGenerator<StreamChunk> {
    try {
      for (;;) {
        while (this.#head < this.#queue.length && !this.#closed) {
          const chunk = this.#queue[this.#head];
          this.#head += 1;
          this.#queuedBytes -= chunk.data.byteLength;
          this.#deliveredBytes += chunk.data.byteLength;
          this.#compact();
          yield chunk;
        }
        if (this.#closed) return;
        if (this.#error) throw this.#error;
        if (this.#ended) return;
        this.#waiter = new Deferred();
        await this.#waiter.promise;
      }
    } finally {
      // Covers `break`, `return` and exceptions in the consumer loop.
      this.close();
    }
  }

  #compact(): void {
    if (this.#head > 32 && this.#head * 2 >= this.#queue.length) {
      this.#queue = this.#queue.slice(this.#head);
      this.#head = 0;
    }
  }

  #wake(): void {
    const waiter = this.#waiter;
    if (waiter) {
      this.#waiter = null;
      waiter.resolve();
    }
  }
}

export class Broadcaster {
  #subscribers = new Set<Subscription>();
  #closed = false;
  #publishedBytes = 0;
  #fanoutBytes = 0;

  get subscriberCount(): number {
    return this.#subscribers.size;
  }

  get closed(): boolean {
    return this.#closed;
  }

  /** Bytes published once by the upstream pump. */
  get publishedBytes(): number {
    return this.#publishedBytes;
  }

  /** Bytes handed to subscribers — `fanout - published` is the WAN saving. */
  get fanoutBytes(): number {
    return this.#fanoutBytes;
  }

  subscribe(options: SubscribeOptions = {}): Subscription {
    // Replayed backlog is fan-out too — in fact it is the purest form of it:
    // bytes served from the cache that the WAN never carried again.
    for (const chunk of options.backlog ?? []) this.#fanoutBytes += chunk.data.byteLength;
    const sub = new Subscription(options, (s) => this.#subscribers.delete(s));
    if (this.#closed) {
      sub.end();
      return sub;
    }
    if (!sub.closed) this.#subscribers.add(sub);
    return sub;
  }

  publish(chunk: StreamChunk): void {
    if (this.#closed) return;
    this.#publishedBytes += chunk.data.byteLength;
    for (const sub of this.#subscribers) {
      this.#fanoutBytes += chunk.data.byteLength;
      sub.push(chunk);
    }
  }

  /** Ends every subscription. Queued data still drains unless `error` is set. */
  close(error?: Error): void {
    if (this.#closed) return;
    this.#closed = true;
    for (const sub of [...this.#subscribers]) sub.end(error);
    this.#subscribers.clear();
  }

  /** Largest per-subscriber backlog — the "slowest client" gauge. */
  slowestQueueBytes(): number {
    let worst = 0;
    for (const sub of this.#subscribers) worst = Math.max(worst, sub.queuedBytes);
    return worst;
  }
}
