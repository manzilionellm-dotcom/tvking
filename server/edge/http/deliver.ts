/*
 * HTTP delivery helpers shared by the LAN routes and the subscriber portals.
 *
 * Live and VOD are delivered differently on purpose:
 *  - live is an endless shared stream, paced through a token bucket, no length,
 *    no ranges (see server.ts / hub.ts for why a per-client Range would break
 *    the collapse);
 *  - VOD is a file: it answers Range requests so players can seek, and it is
 *    NOT paced, because a file transfer is naturally throttled by the player's
 *    own buffering and TCP backpressure.
 */

import type http from "node:http";
import { TokenBucket, pace } from "../token-bucket.ts";
import { UnknownStreamError, type EdgeProxy } from "../edge.ts";
import { UpstreamError } from "../origin.ts";
import { VodError, type ChunkCache, type VodTarget } from "../vod/cache.ts";
import { systemClock, type Clock } from "../clock.ts";

export function sendJson(res: http.ServerResponse, status: number, body: unknown): void {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(payload),
    "cache-control": "no-store",
  });
  res.end(payload);
}

export function sendText(
  res: http.ServerResponse,
  status: number,
  body: string,
  contentType = "text/plain; charset=utf-8"
): void {
  res.writeHead(status, {
    "content-type": contentType,
    "content-length": Buffer.byteLength(body),
    "cache-control": "no-store",
  });
  res.end(body);
}

export function sendError(res: http.ServerResponse, error: unknown): void {
  if (res.headersSent) {
    res.destroy();
    return;
  }
  if (error instanceof UnknownStreamError) {
    sendJson(res, 404, { error: "unknown_stream" });
    return;
  }
  if (error instanceof VodError) {
    if (error.status === 503) res.setHeader("retry-after", "5");
    sendJson(res, error.status, { error: "vod_unavailable", detail: error.message });
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

export function drain(res: http.ServerResponse, signal: AbortSignal): Promise<void> {
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

export interface LiveDeliveryOptions {
  edge: EdgeProxy;
  streamId: string;
  req: http.IncomingMessage;
  res: http.ServerResponse;
  egressBytesPerSecond: number;
  burstBytes?: number;
  owner?: { deviceId: number; label?: string };
  clock?: Clock;
}

/** Joins a channel and streams it to one client until either side goes away. */
export async function deliverLive(options: LiveDeliveryOptions): Promise<void> {
  const { edge, streamId, req, res } = options;
  const controller = new AbortController();
  const detach = () => controller.abort();
  res.on("close", detach);
  req.on("aborted", detach);

  const joined = await edge.subscribe(streamId, {
    signal: controller.signal,
    owner: options.owner,
  });
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
    "x-accel-buffering": "no",
  });
  // Node holds headers back until the first write. A channel whose first byte
  // is a second away would look like a hung request to the player, so say "200,
  // connected" now and let the bytes follow.
  res.flushHeaders();

  const bucket = new TokenBucket({
    bytesPerSecond: options.egressBytesPerSecond,
    burstBytes: options.burstBytes,
    clock: options.clock ?? systemClock,
  });

  const payload = async function* payload(): AsyncGenerator<Uint8Array> {
    for await (const chunk of joined.subscription) yield chunk.data;
  };

  try {
    for await (const slice of pace(payload(), bucket, { signal: controller.signal })) {
      if (controller.signal.aborted) break;
      if (!res.write(slice)) await drain(res, controller.signal);
    }
  } finally {
    joined.subscription.close();
    if (!res.writableEnded) res.end();
  }
}

export interface VodDeliveryOptions {
  cache: ChunkCache;
  target: VodTarget;
  req: http.IncomingMessage;
  res: http.ServerResponse;
  contentType?: string;
}

/** RFC 9110 §14.1 — a single range; multipart ranges are not worth it here. */
export function parseRange(
  header: string | undefined,
  size: number | null
): { start: number; end: number | null } | "invalid" | null {
  if (!header) return null;
  const match = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
  if (!match) return "invalid";
  const [, rawStart, rawEnd] = match;

  if (rawStart === "" && rawEnd === "") return "invalid";
  if (rawStart === "") {
    // Suffix range ("last N bytes") needs the size to mean anything.
    if (size === null) return "invalid";
    const length = Number(rawEnd);
    if (length <= 0) return "invalid";
    return { start: Math.max(0, size - length), end: size - 1 };
  }
  const start = Number(rawStart);
  const end = rawEnd === "" ? null : Number(rawEnd);
  if (end !== null && end < start) return "invalid";
  if (size !== null && start >= size) return "invalid";
  return { start, end: end === null ? null : end };
}

/** Serves a VOD file from the chunk cache, honouring Range. */
export async function deliverVod(options: VodDeliveryOptions): Promise<void> {
  const { cache, target, req, res } = options;
  const controller = new AbortController();
  const detach = () => controller.abort();
  res.on("close", detach);
  req.on("aborted", detach);

  const size = await cache.probeSize(target, controller.signal);
  const range = parseRange(req.headers.range, size);
  if (range === "invalid") {
    res.writeHead(416, {
      "content-range": size === null ? "bytes */*" : `bytes */${size}`,
      "accept-ranges": "bytes",
    });
    res.end();
    return;
  }

  const start = range?.start ?? 0;
  const end = range?.end ?? (size === null ? Number.MAX_SAFE_INTEGER : size - 1);
  const headers: Record<string, string> = {
    "content-type": options.contentType ?? "video/mp4",
    "accept-ranges": "bytes",
    "cache-control": "no-store",
  };
  if (size !== null) headers["content-length"] = String(Math.min(end, size - 1) - start + 1);
  if (range && size !== null) {
    headers["content-range"] = `bytes ${start}-${Math.min(end, size - 1)}/${size}`;
  }

  res.writeHead(range ? 206 : 200, headers);
  if (req.method === "HEAD") {
    res.end();
    return;
  }

  try {
    for await (const piece of cache.read(target, start, end, controller.signal)) {
      if (controller.signal.aborted) break;
      if (!res.write(piece)) await drain(res, controller.signal);
    }
  } finally {
    if (!res.writableEnded) res.end();
  }
}
