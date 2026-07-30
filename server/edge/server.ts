/*
 * HTTP front-end for the edge proxy (LAN side).
 *
 * Responsibilities kept deliberately thin: validate the stream id, join the
 * hub, shape the egress, honour backpressure, and detach on disconnect. All the
 * collapsing logic lives in edge.ts / hub.ts.
 *
 * Privacy note: this server never logs a client IP, User-Agent or any other
 * downstream identifier — logging them here would recreate, on disk, exactly
 * the data the proxy strips on the wire.
 */

import http from "node:http";
import { EdgeProxy, UnknownStreamError } from "./edge.ts";
import { TokenBucket, pace } from "./token-bucket.ts";
import { UpstreamError } from "./origin.ts";
import { systemClock, type Clock } from "./clock.ts";

export interface EdgeServerOptions {
  edge: EdgeProxy;
  /** Per-client egress rate. Should exceed the stream bitrate (e.g. 1.5x). */
  egressBytesPerSecond: number;
  /** Bucket depth; defaults to 100 ms of rate (near-CBR). */
  burstBytes?: number;
  /** Refuse further clients past this count (memory guard). */
  maxClients?: number;
  /** URL prefix for stream requests. */
  pathPrefix?: string;
  clock?: Clock;
  log?: (line: string) => void;
}

/** Conservative id charset: no traversal, no scheme smuggling, no query. */
const STREAM_ID = /^[A-Za-z0-9._~-]{1,128}$/;

export function createEdgeServer(options: EdgeServerOptions): http.Server {
  const prefix = options.pathPrefix ?? "/edge/";
  const maxClients = options.maxClients ?? 200;
  const clock = options.clock ?? systemClock;
  const log = options.log ?? (() => {});
  let clients = 0;

  const server = http.createServer((req, res) => {
    const url = new URL(req.url ?? "/", "http://edge.local");
    const path = url.pathname;

    if (path === "/healthz") {
      sendJson(res, 200, { status: "ok" });
      return;
    }
    if (path === "/metrics") {
      sendJson(res, 200, options.edge.stats());
      return;
    }
    if (!path.startsWith(prefix)) {
      sendJson(res, 404, { error: "not_found" });
      return;
    }
    if (req.method !== "GET" && req.method !== "HEAD") {
      res.writeHead(405, { allow: "GET, HEAD", "content-type": "application/json" });
      res.end(JSON.stringify({ error: "method_not_allowed" }));
      return;
    }

    const streamId = decodeURIComponent(path.slice(prefix.length));
    if (!STREAM_ID.test(streamId)) {
      sendJson(res, 400, { error: "invalid_stream_id" });
      return;
    }

    // A HEAD probe must not be able to open a WAN connection: answer it from
    // what the edge already knows.
    if (req.method === "HEAD") {
      const known = options.edge.stats().streams.find((s) => s.key === streamId);
      res.writeHead(200, {
        "content-type": known?.contentType ?? "video/mp2t",
        "cache-control": "no-store",
      });
      res.end();
      return;
    }

    if (clients >= maxClients) {
      res.writeHead(503, { "retry-after": "5", "content-type": "application/json" });
      res.end(JSON.stringify({ error: "too_many_clients" }));
      return;
    }

    clients += 1;
    void stream(streamId, req, res)
      .catch((error) => {
        log(`stream ${streamId} failed: ${describe(error)}`);
        if (!res.headersSent) sendError(res, error);
        else res.destroy();
      })
      .finally(() => {
        clients -= 1;
      });
  });

  async function stream(
    streamId: string,
    req: http.IncomingMessage,
    res: http.ServerResponse
  ): Promise<void> {
    const controller = new AbortController();
    const detach = () => controller.abort();
    res.on("close", detach);
    req.on("aborted", detach);

    const joined = await options.edge.subscribe(streamId, { signal: controller.signal });
    if (controller.signal.aborted) {
      joined.subscription.close();
      return;
    }

    res.writeHead(200, {
      "content-type": joined.contentType ?? "video/mp2t",
      // The edge cache is the cache. Nothing downstream should store a live
      // stream, and no intermediary should try to (RFC 9111 §5.2.2.5).
      "cache-control": "no-store",
      pragma: "no-cache",
      connection: "keep-alive",
      // Disables proxy buffering in front of the edge (nginx et al.).
      "x-accel-buffering": "no",
    });

    const bucket = new TokenBucket({
      bytesPerSecond: options.egressBytesPerSecond,
      burstBytes: options.burstBytes,
      clock,
    });

    const payload = async function* payload(): AsyncGenerator<Uint8Array> {
      for await (const chunk of joined.subscription) yield chunk.data;
    };

    try {
      for await (const slice of pace(payload(), bucket, { signal: controller.signal })) {
        if (controller.signal.aborted) break;
        // Zero-copy hand-off; Node copies into the socket buffer itself.
        if (!res.write(slice)) await drain(res, controller.signal);
      }
    } finally {
      joined.subscription.close();
      if (!res.writableEnded) res.end();
    }
  }

  return server;
}

function drain(res: http.ServerResponse, signal: AbortSignal): Promise<void> {
  if (signal.aborted) return Promise.resolve();
  return new Promise<void>((resolve) => {
    const done = () => {
      res.off("drain", done);
      res.off("close", done);
      signal.removeEventListener("abort", done);
      resolve();
    };
    res.once("drain", done);
    res.once("close", done);
    signal.addEventListener("abort", done, { once: true });
  });
}

function sendJson(res: http.ServerResponse, status: number, body: unknown): void {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(payload),
    "cache-control": "no-store",
  });
  res.end(payload);
}

function sendError(res: http.ServerResponse, error: unknown): void {
  if (error instanceof UnknownStreamError) {
    sendJson(res, 404, { error: "unknown_stream" });
    return;
  }
  if (error instanceof UpstreamError) {
    const status = error.status === 503 ? 503 : 502;
    if (status === 503) res.setHeader("retry-after", "5");
    sendJson(res, status, { error: "upstream_unavailable" });
    return;
  }
  sendJson(res, 500, { error: "internal_error" });
}

function describe(error: unknown): string {
  return error instanceof Error ? `${error.name}: ${error.message}` : String(error);
}
