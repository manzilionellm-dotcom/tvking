/*
 * Entry point: `npm run edge` (Node ≥ 22 runs TypeScript directly).
 *
 * Deliberately a standalone long-lived process rather than a Next.js route
 * handler: connection collapsing only works if all clients share ONE process
 * holding ONE ring buffer. Serverless route handlers are per-invocation and
 * horizontally replicated, so the same code behind a serverless function would
 * silently open one upstream per instance — the exact thing this proxy exists
 * to prevent. The TV app talks to this service over the LAN.
 *
 * Planes are opt-in and degrade independently: no admin token → no admin plane;
 * no database → no subscriber portal and no VOD. The streaming core runs either
 * way, so a misconfigured panel can never take the picture down.
 */

import process from "node:process";
import { EdgeProxy, type EdgeEvent } from "./edge.ts";
import { FetchOriginTransport } from "./origin.ts";
import { createEdgeServer, type PortalRouter } from "./server.ts";
import { createAdminRouter, type AdminOptions } from "./admin.ts";
import { ConfigError, loadConfig } from "./config.ts";
import { openDatabase } from "./db/database.ts";
import { PortalRepository } from "./portal/devices.ts";
import { ExpirationEnforcer } from "./portal/enforcer.ts";
import { createXtreamRouter } from "./portal/xtream.ts";
import { createStalkerRouter } from "./portal/stalker.ts";
import { VodCatalog } from "./vod/catalog.ts";
import { VodIngestWorker } from "./vod/ingest.ts";
import { ChunkCache } from "./vod/cache.ts";
import { systemWallClock } from "./clock.ts";
import type { PortalContext } from "./portal/context.ts";

function main(): void {
  let config;
  try {
    config = loadConfig(process.env);
  } catch (error) {
    if (error instanceof ConfigError) {
      console.error(`[edge] configuration error: ${error.message}`);
      process.exit(2);
    }
    throw error;
  }

  const log = (line: string) => console.log(`[edge] ${line}`);
  const listeners: Array<(event: EdgeEvent) => void> = [];

  const transport = new FetchOriginTransport({ allowedHosts: config.allowedHosts });
  const edge = new EdgeProxy({
    ...config.edge,
    transport,
    onEvent: (event: EdgeEvent) => {
      log(describe(event));
      for (const listener of listeners) listener(event);
    },
  });

  // ------------------------------------------------------- optional planes
  const db = config.databasePath ? openDatabase(config.databasePath) : null;
  const portals: PortalRouter[] = [];
  let adminPortal: AdminOptions["portal"];
  let adminVod: AdminOptions["vod"];
  let enforcer: ExpirationEnforcer | null = null;
  let worker: VodIngestWorker | null = null;

  if (db) {
    const repo = new PortalRepository(db, systemWallClock);
    const catalog = new VodCatalog(db, systemWallClock);
    const cache = new ChunkCache({
      db,
      dir: config.vod.cacheDir,
      transport,
      chunkBytes: config.vod.chunkBytes,
      maxBytes: config.vod.cacheMaxBytes,
    });

    enforcer = new ExpirationEnforcer({
      repo,
      edge,
      intervalMs: config.enforcerIntervalMs,
      onEvent: (event) =>
        log(`enforce device=${event.device} reason=${event.reason} sessions=${event.sessions}`),
    });
    enforcer.start();
    adminPortal = { repo, enforcer };

    if (config.vod.enabled) {
      worker = new VodIngestWorker({
        catalog,
        intervalMs: config.vod.ingestIntervalMs,
        fetchPlaylist: (accountId, url, signal) => edge.fetchText(accountId, url, { signal }),
        onEvent: (event) => log(describe(event as unknown as { type: string })),
      });
      worker.start();
      adminVod = { catalog, cache, worker };
    }

    if (config.portalEnabled) {
      const context: PortalContext = {
        repo,
        catalog,
        cache,
        edge,
        wallClock: systemWallClock,
        egressBytesPerSecond: config.egressBytesPerSecond,
        publicBase: config.publicBase,
        onEvent: (event) => log(describe(event as unknown as { type: string })),
      };
      portals.push(createXtreamRouter(context), createStalkerRouter(context));
    }
  }

  const admin = createAdminRouter({
    edge,
    token: config.adminToken,
    prefix: config.adminPrefix,
    portal: adminPortal,
    vod: adminVod,
  });
  listeners.push((event) => admin.publish(event));

  const server = createEdgeServer({
    edge,
    egressBytesPerSecond: config.egressBytesPerSecond,
    maxClients: config.maxClients,
    pathPrefix: config.pathPrefix,
    admin,
    portals,
    log,
  });

  server.listen(config.port, config.host, () => {
    const base = `http://${config.host}:${config.port}`;
    log(
      `listening on ${base}${config.pathPrefix}<account>/<channel> ` +
        `(${edge.upstreamLimit} upstream connection(s) across ` +
        `${edge.listAccounts().length} master account(s), ` +
        `${Math.round(config.egressBytesPerSecond / 1024)} KiB/s per client)`
    );
    log(
      admin.enabled
        ? `admin dashboard on ${base}${config.adminPrefix}/`
        : "admin plane disabled (set EDGE_ADMIN_TOKEN to enable it)"
    );
    log(
      portals.length > 0
        ? `subscriber portals on ${base}/player_api.php (Xtream) and ${base}/portal.php (MAG)`
        : "subscriber portals disabled (set EDGE_DB to enable them)"
    );
    log(worker ? "VOD ingestion worker started" : "VOD plane disabled");
  });

  let stopping = false;
  const shutdown = (signal: string) => {
    if (stopping) return;
    stopping = true;
    log(`${signal} received, draining`);
    admin.close();
    server.close();
    void Promise.all([enforcer?.stop(), worker?.stop()])
      .then(() => edge.shutdown())
      .then(() => {
        db?.close();
        process.exit(0);
      });
  };
  process.on("SIGINT", () => shutdown("SIGINT"));
  process.on("SIGTERM", () => shutdown("SIGTERM"));
}

function describe(event: { type: string } & Record<string, unknown>): string {
  const parts = Object.entries(event)
    .filter(([key]) => key !== "type")
    .map(([key, value]) => `${key}=${String(value)}`);
  return [event.type, ...parts].join(" ");
}

main();
