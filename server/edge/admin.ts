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
import { PLANS, PLAN_IDS, isPlanId, type PlanId } from "./portal/plans.ts";
import { PortalError, generateCredentials, type PortalRepository } from "./portal/devices.ts";
import type { VodCatalog } from "./vod/catalog.ts";
import type { VodIngestWorker } from "./vod/ingest.ts";
import type { ChunkCache } from "./vod/cache.ts";
import type { ExpirationEnforcer } from "./portal/enforcer.ts";

export interface AdminOptions {
  edge: EdgeProxy;
  /** Required. Without it the admin plane stays off. */
  token?: string;
  prefix?: string;
  /** Snapshot push interval on the SSE stream. */
  snapshotMs?: number;
  /** Subscriber plane, when the portal is configured. */
  portal?: {
    repo: PortalRepository;
    enforcer?: ExpirationEnforcer;
  };
  /** VOD plane, when the catalogue is configured. */
  vod?: {
    catalog: VodCatalog;
    cache: ChunkCache;
    worker?: VodIngestWorker;
  };
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
      json(res, 200, overview());
      return;
    }

    // ------------------------------------------------------------- devices
    if (route === "/devices" && method === "GET") {
      requirePortal();
      json(res, 200, { devices: devices(), plans: planCatalogue() });
      return;
    }
    if (route === "/devices" && method === "POST") {
      const repo = requirePortal();
      const body = (await readJson(req)) as Record<string, unknown>;
      const generated =
        body.username === "auto" ? generateCredentials() : { username: undefined, password: undefined };
      const device = repo.createDevice({
        mac: typeof body.mac === "string" && body.mac ? body.mac : null,
        username: generated.username ?? (typeof body.username === "string" ? body.username : null),
        password: generated.password ?? (typeof body.password === "string" ? body.password : null),
        label: typeof body.label === "string" ? body.label : "",
        packageId: typeof body.packageId === "number" ? body.packageId : null,
        maxConnections: typeof body.maxConnections === "number" ? body.maxConnections : 1,
        note: typeof body.note === "string" ? body.note : "",
      });
      // A plan may be granted in the same call — that is the "add a client and
      // give them 24 h" flow the panel is built around.
      if (typeof body.plan === "string" && isPlanId(body.plan)) {
        repo.grant(device.id, body.plan);
      }
      json(res, 200, {
        device: repo.status(repo.device(device.id) as never),
        // Only place a generated password is ever shown: it is not recoverable.
        credentials: generated.username ? generated : undefined,
      });
      return;
    }

    const deviceMatch = /^\/devices\/(\d+)$/.exec(route);
    if (deviceMatch && (method === "PATCH" || method === "POST")) {
      const repo = requirePortal();
      const body = (await readJson(req)) as Record<string, unknown>;
      const device = repo.updateDevice(Number(deviceMatch[1]), body as never);
      json(res, 200, { device: repo.status(device) });
      return;
    }
    if (deviceMatch && method === "DELETE") {
      const repo = requirePortal();
      const id = Number(deviceMatch[1]);
      // Cut anything the device is watching before the record disappears,
      // otherwise the enforcer would have nothing left to match against.
      edge.dropSessions((session) => session.deviceId === id, "device-deleted");
      json(res, 200, { removed: repo.removeDevice(id) });
      return;
    }

    const grantMatch = /^\/devices\/(\d+)\/grant$/.exec(route);
    if (grantMatch && method === "POST") {
      const repo = requirePortal();
      const body = (await readJson(req)) as Record<string, unknown>;
      const plan = String(body.plan ?? "");
      if (!isPlanId(plan)) {
        json(res, 400, { error: "unknown_plan", plans: PLAN_IDS });
        return;
      }
      const device = repo.device(Number(grantMatch[1]));
      if (!device) {
        json(res, 404, { error: "unknown_device" });
        return;
      }
      const subscription = repo.grant(device.id, plan as PlanId, {
        note: typeof body.note === "string" ? body.note : undefined,
      });
      json(res, 200, { subscription, device: repo.status(device) });
      return;
    }

    const revokeMatch = /^\/devices\/(\d+)\/revoke$/.exec(route);
    if (revokeMatch && method === "POST") {
      const repo = requirePortal();
      const id = Number(revokeMatch[1]);
      const revoked = repo.revoke(id);
      // Revoking has to bite immediately, not at the next enforcer tick.
      const dropped = edge.dropSessions((session) => session.deviceId === id, "revoked");
      json(res, 200, { revoked, droppedSessions: dropped });
      return;
    }

    // ------------------------------------------------------------ packages
    if (route === "/packages" && method === "GET") {
      json(res, 200, { packages: requirePortal().listPackages() });
      return;
    }
    if (route === "/packages" && method === "POST") {
      const repo = requirePortal();
      const body = (await readJson(req)) as Record<string, unknown>;
      json(res, 200, { package: repo.upsertPackage(body as never) });
      return;
    }
    const packageMatch = /^\/packages\/(\d+)$/.exec(route);
    if (packageMatch && method === "DELETE") {
      json(res, 200, { removed: requirePortal().removePackage(Number(packageMatch[1])) });
      return;
    }

    // ----------------------------------------------------------------- vod
    if (route === "/vod" && method === "GET") {
      json(res, 200, vodOverview());
      return;
    }
    if (route === "/vod/sources" && method === "POST") {
      const vod = requireVod();
      const body = (await readJson(req)) as Record<string, unknown>;
      json(res, 200, {
        source: vod.catalog.upsertSource({
          name: String(body.name ?? ""),
          url: String(body.url ?? ""),
          accountId: String(body.accountId ?? ""),
          enabled: body.enabled !== false,
        }),
      });
      return;
    }
    const sourceMatch = /^\/vod\/sources\/(\d+)$/.exec(route);
    if (sourceMatch && method === "PATCH") {
      const vod = requireVod();
      const body = (await readJson(req)) as Record<string, unknown>;
      json(res, 200, {
        updated: vod.catalog.setSourceEnabled(Number(sourceMatch[1]), body.enabled !== false),
      });
      return;
    }
    if (sourceMatch && method === "DELETE") {
      json(res, 200, { removed: requireVod().catalog.removeSource(Number(sourceMatch[1])) });
      return;
    }
    const categoryMatch = /^\/vod\/categories\/(\d+)$/.exec(route);
    if (categoryMatch && method === "PATCH") {
      const vod = requireVod();
      const body = (await readJson(req)) as Record<string, unknown>;
      json(res, 200, {
        updated: vod.catalog.setCategoryEnabled(Number(categoryMatch[1]), body.enabled !== false),
      });
      return;
    }
    if (route === "/vod/ingest" && method === "POST") {
      const vod = requireVod();
      if (!vod.worker) {
        json(res, 400, { error: "no_ingest_worker" });
        return;
      }
      const body = (await readJson(req)) as Record<string, unknown>;
      const reports = await vod.worker.runOnce({
        sourceId: typeof body.sourceId === "number" ? body.sourceId : undefined,
      });
      json(res, 200, { reports });
      return;
    }
    if (route === "/vod/titles" && method === "GET") {
      const vod = requireVod();
      json(res, 200, {
        titles: vod.catalog.titles({
          kind: (url.searchParams.get("kind") as "movie" | "series" | null) ?? undefined,
          search: url.searchParams.get("search") ?? undefined,
          limit: Number(url.searchParams.get("limit") ?? 100),
        }),
      });
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

  function requirePortal(): PortalRepository {
    if (!options.portal) throw new PortalError("portal plane is not configured");
    return options.portal.repo;
  }

  function requireVod() {
    if (!options.vod) throw new PortalError("VOD plane is not configured");
    return options.vod;
  }

  function planCatalogue() {
    return PLAN_IDS.map((id) => ({ id, label: PLANS[id].label, trial: PLANS[id].trial }));
  }

  /** Device rows with their live session count — the panel's main table. */
  function devices() {
    if (!options.portal) return [];
    const now = Date.now();
    return options.portal.repo.listDevices().map((status) => ({
      id: status.device.id,
      mac: status.device.mac,
      username: status.device.username,
      label: status.device.label,
      packageId: status.device.packageId,
      packageName: status.package?.name ?? null,
      accountId: status.package?.accountId ?? null,
      maxConnections: status.device.maxConnections,
      disabled: status.device.disabled,
      note: status.device.note,
      state: status.state,
      plan: status.subscription?.plan ?? null,
      startsAt: status.subscription?.startsAt ?? null,
      expiresAt: status.subscription?.expiresAt ?? null,
      remainingMs: status.remainingMs,
      activeSessions: edge.sessionsForDevice(status.device.id).length,
      createdAt: status.device.createdAt,
      now,
    }));
  }

  function vodOverview() {
    if (!options.vod) return { configured: false };
    const { catalog, cache, worker } = options.vod;
    return {
      configured: true,
      counts: catalog.counts(),
      sources: catalog.listSources(),
      categories: catalog.listCategories(),
      cache: cache.stats(),
      worker: worker ? { running: worker.running, runs: worker.runs, lastRunAt: worker.lastRunAt } : null,
    };
  }

  function overview() {
    const base = edge.overview();
    return {
      ...base,
      portal: options.portal
        ? {
            configured: true,
            devices: devices(),
            plans: planCatalogue(),
            packages: options.portal.repo.listPackages(),
            enforcer: options.portal.enforcer
              ? {
                  running: options.portal.enforcer.running,
                  sweeps: options.portal.enforcer.sweeps,
                  droppedSessions: options.portal.enforcer.droppedSessions,
                }
              : null,
          }
        : { configured: false },
      vod: vodOverview(),
    };
  }

  /** Server-sent events: live edge activity plus a periodic full snapshot. */
  function subscribeEvents(res: http.ServerResponse): void {
    res.writeHead(200, {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-store",
      connection: "keep-alive",
      "x-accel-buffering": "no",
    });
    res.write(`event: overview\ndata: ${JSON.stringify(overview())}\n\n`);
    listeners.add(res);
    res.on("close", () => listeners.delete(res));

    if (!heartbeat) {
      heartbeat = setInterval(() => {
        const snapshot = `event: overview\ndata: ${JSON.stringify(overview())}\n\n`;
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
  if (error instanceof PortalError) {
    json(res, 400, { error: "invalid_request", detail: error.message });
    return;
  }
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
