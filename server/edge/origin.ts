/*
 * Upstream (origin) transport.
 *
 * Kept behind a one-method interface so the hub can be tested against a mock
 * origin with zero sockets, and so the counting wrapper can measure the
 * single-upstream invariant at the exact boundary that matters: a connection is
 * "active" from the instant `open()` is CALLED (not when it resolves) until its
 * body is fully consumed, aborted or closed. Counting from the call is what
 * catches the classic race where two joins both start connecting.
 */

import { redactUrl } from "./sanitize.ts";

export interface OriginRequest {
  url: string;
  /** Fully constructed by the edge — see sanitize.ts. */
  headers: Readonly<Record<string, string>>;
  signal: AbortSignal;
  method?: "GET" | "HEAD";
}

export interface OriginResponse {
  status: number;
  headers: Readonly<Record<string, string>>;
  body: AsyncIterable<Uint8Array>;
  /** Releases the connection without draining the body. Idempotent. */
  close(): void;
}

export interface OriginTransport {
  open(request: OriginRequest): Promise<OriginResponse>;
}

export class UpstreamError extends Error {
  name = "UpstreamError";
  status: number;

  constructor(message: string, status = 0) {
    super(message);
    this.status = status;
  }
}

export interface UpstreamCounters {
  /** Connections open right now. THE invariant gauge: must never exceed the cap. */
  active: number;
  /** High-water mark of `active` since process start. */
  activeMax: number;
  /** Total connections opened. */
  opens: number;
  /** Opens that failed before yielding a body. */
  failures: number;
  /** Bytes read from the origin. */
  bytes: number;
}

export function createCounters(): UpstreamCounters {
  return { active: 0, activeMax: 0, opens: 0, failures: 0, bytes: 0 };
}

/** Wraps a transport to track concurrent upstream connections. */
export function countingTransport(
  inner: OriginTransport,
  counters: UpstreamCounters
): OriginTransport {
  return {
    async open(request) {
      counters.opens += 1;
      counters.active += 1;
      counters.activeMax = Math.max(counters.activeMax, counters.active);

      let released = false;
      const release = () => {
        if (released) return;
        released = true;
        counters.active -= 1;
      };

      let response: OriginResponse;
      try {
        response = await inner.open(request);
      } catch (error) {
        counters.failures += 1;
        release();
        throw error;
      }

      const body = (async function* counted(): AsyncGenerator<Uint8Array> {
        try {
          for await (const chunk of response.body) {
            counters.bytes += chunk.byteLength;
            yield chunk;
          }
        } finally {
          release();
        }
      })();

      return {
        status: response.status,
        headers: response.headers,
        body,
        close() {
          response.close();
          void body.return(undefined);
          release();
        },
      };
    },
  };
}

export interface FetchTransportOptions {
  /** Hostnames the edge may connect to. Empty = no restriction. */
  allowedHosts?: readonly string[];
  /** Abort if the origin has not responded with headers within this budget. */
  openTimeoutMs?: number;
  /** Injected for tests; defaults to global fetch. */
  fetchImpl?: typeof fetch;
}

/** Rejects URLs outside the configured origin allowlist (SSRF guard). */
export function assertAllowedOrigin(url: string, allowedHosts: readonly string[] = []): URL {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new UpstreamError(`invalid origin URL`);
  }
  if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
    throw new UpstreamError(`unsupported origin scheme ${parsed.protocol}`);
  }
  if (allowedHosts.length > 0 && !allowedHosts.includes(parsed.hostname)) {
    throw new UpstreamError(`origin host not allowed: ${parsed.hostname}`);
  }
  return parsed;
}

/** Production transport: one HTTP request = one upstream connection. */
export class FetchOriginTransport implements OriginTransport {
  #allowedHosts: readonly string[];
  #openTimeoutMs: number;
  #fetch: typeof fetch;

  constructor(options: FetchTransportOptions = {}) {
    this.#allowedHosts = options.allowedHosts ?? [];
    this.#openTimeoutMs = options.openTimeoutMs ?? 10_000;
    this.#fetch = options.fetchImpl ?? globalThis.fetch;
  }

  async open(request: OriginRequest): Promise<OriginResponse> {
    assertAllowedOrigin(request.url, this.#allowedHosts);

    // Header timeout only: once the body flows, a live stream is long-lived by
    // design and must not be killed by an overall request deadline.
    const openTimer = new AbortController();
    const timer = setTimeout(() => openTimer.abort(), this.#openTimeoutMs);
    const signal = AbortSignal.any([request.signal, openTimer.signal]);

    let response: Response;
    try {
      response = await this.#fetch(request.url, {
        method: request.method ?? "GET",
        // `accept-language` is pinned to a constant because the runtime would
        // otherwise inject its own default. It is identical for every viewer,
        // so it cannot carry a locale. (`sec-fetch-mode` is forced by the fetch
        // implementation itself and is likewise a constant, not client data.)
        headers: { "accept-language": "*", ...request.headers },
        signal,
        redirect: "follow",
        // No cache, no cookie jar: the edge owns its cache, and cookies would
        // reintroduce cross-request identity.
        cache: "no-store",
        credentials: "omit",
      });
    } catch (error) {
      clearTimeout(timer);
      const reason = error instanceof Error ? error.message : String(error);
      throw new UpstreamError(`origin unreachable (${redactUrl(request.url)}): ${reason}`);
    }
    clearTimeout(timer);

    const headers: Record<string, string> = {};
    response.headers.forEach((value, name) => {
      headers[name.toLowerCase()] = value;
    });

    const stream = response.body;
    const body: AsyncIterable<Uint8Array> = stream
      ? readAll(stream)
      : (async function* empty(): AsyncGenerator<Uint8Array> {})();

    return {
      status: response.status,
      headers,
      body,
      close() {
        void stream?.cancel().catch(() => {});
      },
    };
  }
}

async function* readAll(stream: ReadableStream<Uint8Array>): AsyncGenerator<Uint8Array> {
  const reader = stream.getReader();
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) return;
      if (value && value.byteLength > 0) yield value;
    }
  } finally {
    reader.releaseLock();
    void stream.cancel().catch(() => {});
  }
}
