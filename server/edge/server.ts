/*
 * HTTP front-end (LAN side).
 *
 * Three planes share one port, in this order:
 *   1. admin   — /admin, token-gated, operator only;
 *   2. portals — Xtream and Stalker, authenticated per subscriber device;
 *   3. edge    — /edge/<account>/<channel>, the raw route with no subscriber
 *                model, for the TV app on a trusted LAN.
 *
 * Privacy note: this server never logs a client IP, User-Agent or any other
 * downstream identifier — logging them here would recreate, on disk, exactly
 * the data the proxy strips on the wire. The subscriber identifiers the portals
 * DO use (MAC, Xtream login) are the operator's own records, not telemetry.
 */

import http from "node:http";
import { EdgeProxy } from "./edge.ts";
import { deliverLive, sendError, sendJson } from "./http/deliver.ts";
import { systemClock, type Clock } from "./clock.ts";
import type { AdminRouter } from "./admin.ts";

export interface PortalRouter {
  handle(req: http.IncomingMessage, res: http.ServerResponse, url: URL): Promise<boolean>;
}

export interface EdgeServerOptions {
  edge: EdgeProxy;
  /** Per-client egress rate. Should exceed the stream bitrate (e.g. 1.5x). */
  egressBytesPerSecond: number;
  /** Bucket depth; defaults to 100 ms of rate (near-CBR). */
  burstBytes?: number;
  /** Refuse further clients past this count (memory guard). */
  maxClients?: number;
  /** URL prefix for raw stream requests. */
  pathPrefix?: string;
  /** Admin plane, when configured. Mounted on its own prefix. */
  admin?: AdminRouter;
  /** Subscriber portals (Xtream, Stalker), tried in order. */
  portals?: readonly PortalRouter[];
  clock?: Clock;
  log?: (line: string) => void;
}

/**
 * Conservative id charset: no traversal, no scheme smuggling, no query.
 * A reference is `<channel>` (default account) or `<account>/<channel>`.
 */
const ID_PART = /^[A-Za-z0-9._~-]{1,128}$/;

function validStreamRef(ref: string): boolean {
  const parts = ref.split("/");
  if (parts.length > 2) return false;
  // "." and ".." match the charset but are path traversal, not identifiers.
  return parts.every((part) => ID_PART.test(part) && part !== "." && part !== "..");
}

export function createEdgeServer(options: EdgeServerOptions): http.Server {
  const prefix = options.pathPrefix ?? "/edge/";
  const maxClients = options.maxClients ?? 200;
  const clock = options.clock ?? systemClock;
  const log = options.log ?? (() => {});
  let clients = 0;

  const server = http.createServer((req, res) => {
    void route(req, res).catch((error) => {
      log(`request failed: ${describe(error)}`);
      sendError(res, error);
    });
  });

  async function route(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
    const url = new URL(req.url ?? "/", "http://edge.local");
    const path = url.pathname;

    if (options.admin?.handle(req, res, path, url)) return;

    for (const portal of options.portals ?? []) {
      if (await portal.handle(req, res, url)) return;
    }

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

    const streamId = path
      .slice(prefix.length)
      .split("/")
      .map((part) => decodeURIComponent(part))
      .join("/");
    if (!validStreamRef(streamId)) {
      sendJson(res, 400, { error: "invalid_stream_id" });
      return;
    }

    // A HEAD probe must not be able to open a WAN connection: answer it from
    // what the edge already knows.
    if (req.method === "HEAD") {
      const known = options.edge
        .stats()
        .streams.find((s) => s.key === streamId || s.key === `default/${streamId}`);
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
    try {
      await deliverLive({
        edge: options.edge,
        streamId,
        req,
        res,
        egressBytesPerSecond: options.egressBytesPerSecond,
        burstBytes: options.burstBytes,
        clock,
      });
    } catch (error) {
      log(`stream ${streamId} failed: ${describe(error)}`);
      sendError(res, error);
    } finally {
      clients -= 1;
    }
  }

  // A swapped-out channel keeps its clients attached with no bytes flowing;
  // an idle-socket timeout would undo exactly that. Request-level timeouts
  // (headers, body) still apply.
  server.timeout = 0;
  return server;
}

function describe(error: unknown): string {
  return error instanceof Error ? `${error.name}: ${error.message}` : String(error);
}
