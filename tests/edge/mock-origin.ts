/*
 * Test doubles for the origin side.
 *
 * `MockOrigin` deliberately puts an `await` between "open() was called" and
 * "a body exists": that gap is where a naive proxy opens a second connection,
 * so every concurrency test needs it to be real.
 */

import { Deferred } from "../../server/edge/sync.ts";
import type { OriginRequest, OriginResponse, OriginTransport } from "../../server/edge/origin.ts";

export function bytes(text: string): Uint8Array {
  return new TextEncoder().encode(text);
}

export function text(chunks: Uint8Array[]): string {
  const total = chunks.reduce((n, c) => n + c.byteLength, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(out);
}

class OriginChannel {
  #queue: Uint8Array[] = [];
  #waiter: Deferred | null = null;
  #done = false;
  #error: Error | null = null;

  push(data: Uint8Array): void {
    if (this.#done) return;
    this.#queue.push(data);
    this.#wake();
  }

  end(): void {
    this.#done = true;
    this.#wake();
  }

  fail(error: Error): void {
    this.#error = error;
    this.#done = true;
    this.#wake();
  }

  async *body(signal: AbortSignal): AsyncGenerator<Uint8Array> {
    const onAbort = () => this.end();
    signal.addEventListener("abort", onAbort, { once: true });
    try {
      for (;;) {
        while (this.#queue.length > 0) {
          if (signal.aborted) return;
          yield this.#queue.shift() as Uint8Array;
        }
        if (this.#error) throw this.#error;
        if (this.#done || signal.aborted) return;
        this.#waiter = new Deferred();
        await this.#waiter.promise;
      }
    } finally {
      signal.removeEventListener("abort", onAbort);
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

export interface MockOriginOptions {
  /** Latency between open() and the response — the interleaving window. */
  openDelayMs?: number;
  status?: number;
  contentType?: string;
  /** Fail this many opens before succeeding. */
  failOpens?: number;
}

export class MockOrigin implements OriginTransport {
  requests: Array<{ url: string; headers: Record<string, string> }> = [];
  opens = 0;
  active = 0;
  activeMax = 0;
  #channels = new Map<OriginChannel, string>();
  #options: MockOriginOptions;
  #failuresLeft: number;

  constructor(options: MockOriginOptions = {}) {
    this.#options = options;
    this.#failuresLeft = options.failOpens ?? 0;
  }

  get openChannels(): number {
    return this.#channels.size;
  }

  /** URLs of the upstream connections open right now. */
  get openUrls(): string[] {
    return [...this.#channels.values()];
  }

  async open(request: OriginRequest): Promise<OriginResponse> {
    this.opens += 1;
    this.active += 1;
    this.activeMax = Math.max(this.activeMax, this.active);
    this.requests.push({ url: request.url, headers: { ...request.headers } });

    const delay = this.#options.openDelayMs ?? 1;
    if (delay > 0) await new Promise((resolve) => setTimeout(resolve, delay));

    if (this.#failuresLeft > 0) {
      this.#failuresLeft -= 1;
      this.active -= 1;
      throw new Error("mock origin refused the connection");
    }

    const channel = new OriginChannel();
    this.#channels.set(channel, request.url);

    let closed = false;
    const release = () => {
      if (closed) return;
      closed = true;
      this.#channels.delete(channel);
      channel.end();
      this.active -= 1;
    };
    request.signal.addEventListener("abort", release, { once: true });

    const body = channel.body(request.signal);
    return {
      status: this.#options.status ?? 200,
      headers: { "content-type": this.#options.contentType ?? "video/mp2t" },
      body: (async function* tracked(): AsyncGenerator<Uint8Array> {
        try {
          yield* body;
        } finally {
          release();
        }
      })(),
      close: release,
    };
  }

  /** Publishes to every open upstream body, or only those whose URL matches. */
  push(data: Uint8Array, urlContains?: string): void {
    for (const [channel, url] of this.#channels) {
      if (urlContains === undefined || url.includes(urlContains)) channel.push(data);
    }
  }

  endAll(): void {
    for (const channel of [...this.#channels.keys()]) channel.end();
  }

  failAll(error: Error): void {
    for (const channel of [...this.#channels.keys()]) channel.fail(error);
  }
}

/** Reads at most `max` chunks (stops early when the subscription ends). */
export async function collect(
  source: AsyncIterable<{ data: Uint8Array }>,
  maxBytes: number
): Promise<Uint8Array[]> {
  const out: Uint8Array[] = [];
  let total = 0;
  for await (const chunk of source) {
    out.push(chunk.data);
    total += chunk.data.byteLength;
    if (total >= maxBytes) break;
  }
  return out;
}

/** Lets pending microtasks and timers run. */
export function tick(ms = 0): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
