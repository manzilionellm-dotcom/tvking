/*
 * Admin plane — master accounts, live routing, real-time monitoring.
 *
 * Kept strictly separate from the data plane: a different path prefix, a
 * required bearer token, and no-store on every response. Disabled outright when
 * no token is configured, because this API can add a master account (and thus
 * make the proxy connect somewhere new).
 *
 * The monitoring surface deliberately shows sessions, not people: an opaque id
 * per connection, the channel it is watching, its byte and lag counters. No IP,
 * no user agent, no cookie — the dashboard cannot show what the proxy refuses
 * to collect. Account credentials are reported by field NAME only.
 */

import { timingSafeEqual } from "node:crypto";
import type http from "node:http";
import { AccountError, type MasterAccountInput } from "./accounts.ts";
import { EdgeProxy, type EdgeEvent } from "./edge.ts";
import { DASHBOARD_HTML } from "./dashboard.ts";

export interface AdminOptions {
  edge: EdgeProxy;
  /** Required. Without it the admin plane stays off. */
  token?: string;
  prefix?: string;
  /** Snapshot push interval on the SSE stream. */
  snapshotMs?: number;
}

export interface AdminRouter {
  readonly enabled: boolean;
  readonly prefix: string;
  /** Returns true when the request was handled. */
  handle(req: http.IncomingMessage, res: http.ServerResponse, path: string, url: URL): boolean;
  /** Feed edge events to connected dashboards. */
  publish(event: EdgeEvent): void;
  close(): void;
}

const MAX_BODY_BYTES = 64 * 1024;

export function createAdminRouter(options: AdminOptions): AdminRouter {
  const prefix = (options.prefix ?? "/admin").replace(/\/$/, "");
  const token = options.token ?? "";
  const enabled = token.length > 0;
  const listeners = new Set<http.ServerResponse>();
  let heartbeat: ReturnType<typeof setInterval> | null = null;

  const edge = options.edge;

  function authorised(req: http.IncomingMessage): boolean {
    const header = req.headers.authorization ?? "";
    const bearer = header.startsWith("Bearer ") ? header.slice(7) : "";
    const provided = bearer || String(req.headers["x-admin-token"] ?? "");
    if (provided.length !== token.length) return false;
    return timingSafeEqual(Buffer.from(provided), Buffer.from(token));
  }

  function handle(
    req: http.IncomingMessage,
    res: http.ServerResponse,
    path: string,
    url: URL
  ): boolean {
    if (path !== prefix && !path.startsWith(`${prefix}/`)) return false;
    if (!enabled) {
      json(res, 404, { error: "admin_disabled" });
      return true;
    }

    const route = path.slice(prefix.length) || "/";

    // The shell is inert HTML: it holds no data and asks the operator for the
    // token before it can call anything below.
    if (route === "/" && req.method === "GET") {
      res.writeHead(200, {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "no-store",
        // Inline style/script only, and XHR only back to this origin — the page
        // must be able to reach /admin/events and nothing else.
        "content-security-policy":
          "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:",
      });
      res.end(DASHBOARD_HTML);
      return true;
    }

    if (!authorised(req)) {
      res.writeHead(401, {
        "content-type": "application/json; charset=utf-8",
        "www-authenticate": 'Bearer realm="tvking-edge"',
        "cache-control": "no-store",
      });
      res.end(JSON.stringify({ error: "unauthorized" }));
      return true;
    }

    void dispatch(req, res, route, url).catch((error) => {
      if (!res.headersSent) fail(res, error);
      else res.destroy();
    });
    return true;
  }

  async function dispatch(
    req: http.IncomingMessage,
    res: http.ServerResponse,
    route: string,
    url: URL
  ): Promise<void> {
    const method = req.method ?? "GET";

    if (route === "/overview" && method === "GET") {
      json(res, 200, edge.overview());
      return;
    }
    if (route === "/sessions" && method === "GET") {
      json(res, 200, { sessions: edge.sessions() });
      return;
    }
    if (route === "/accounts" && method === "GET") {
      json(res, 200, { accounts: edge.listAccounts() });
      return;
    }
    if (route === "/accounts" && method === "POST") {
      const body = await readJson(req);
      const account = edge.upsertAccount(body as MasterAccountInput);
      json(res, 200, { account: edge.listAccounts().find((a) => a.id === account.id) });
      return;
    }

    const accountMatch = /^\/accounts\/([^/]+)$/.exec(route);
    if (accountMatch && method === "DELETE") {
      const removed = await edge.removeAccount(decodeURIComponent(accountMatch[1]));
      json(res, removed ? 200 : 404, { removed });
      return;
    }

    const channelsMatch = /^\/accounts\/([^/]+)\/channels$/.exec(route);
    if (channelsMatch && method === "GET") {
      const channels = await edge.channels(decodeURIComponent(channelsMatch[1]), {
        refresh: url.searchParams.get("refresh") === "1",
      });
      json(res, 200, {
        channels: channels.map((entry) => ({
          id: entry.id,
          name: entry.name,
          group: entry.group ?? null,
          logo: entry.logo ?? null,
        })),
      });
      return;
    }

    const stopMatch = /^\/streams\/(.+)\/stop$/.exec(route);
    if (stopMatch && method === "POST") {
      const stopped = await edge.stopStream(decodeURIComponent(stopMatch[1]));
      json(res, stopped ? 200 : 404, { stopped });
      return;
    }

    if (route === "/events" && method === "GET") {
      subscribeEvents(res);
      return;
    }

    json(res, 404, { error: "not_found" });
  }

  /** Server-sent events: live edge activity plus a periodic full snapshot. */
  function subscribeEvents(res: http.ServerResponse): void {
    res.writeHead(200, {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-store",
      connection: "keep-alive",
      "x-accel-buffering": "no",
    });
    res.write(`event: overview\ndata: ${JSON.stringify(edge.overview())}\n\n`);
    listeners.add(res);
    res.on("close", () => listeners.delete(res));

    if (!heartbeat) {
      heartbeat = setInterval(() => {
        const snapshot = `event: overview\ndata: ${JSON.stringify(edge.overview())}\n\n`;
        for (const listener of listeners) listener.write(snapshot);
      }, options.snapshotMs ?? 2000);
      heartbeat.unref?.();
    }
  }

  function publish(event: EdgeEvent): void {
    if (listeners.size === 0) return;
    const frame = `event: activity\ndata: ${JSON.stringify(event)}\n\n`;
    for (const listener of listeners) listener.write(frame);
  }

  function close(): void {
    if (heartbeat) clearInterval(heartbeat);
    heartbeat = null;
    for (const listener of listeners) listener.end();
    listeners.clear();
  }

  return { enabled, prefix, handle, publish, close };
}

function json(res: http.ServerResponse, status: number, body: unknown): void {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(payload),
    "cache-control": "no-store",
  });
  res.end(payload);
}

function fail(res: http.ServerResponse, error: unknown): void {
  if (error instanceof AccountError) {
    json(res, 400, { error: "invalid_account", detail: error.message });
    return;
  }
  if (error instanceof SyntaxError) {
    json(res, 400, { error: "invalid_json" });
    return;
  }
  json(res, 500, { error: "internal_error" });
}

async function readJson(req: http.IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let total = 0;
  for await (const chunk of req) {
    const buffer = chunk as Buffer;
    total += buffer.byteLength;
    if (total > MAX_BODY_BYTES) throw new SyntaxError("body too large");
    chunks.push(buffer);
  }
  if (total === 0) return {};
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}
