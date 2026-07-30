/*
 * Entry point: `npm run edge` (Node ≥ 22 runs TypeScript directly).
 *
 * Deliberately a standalone long-lived process rather than a Next.js route
 * handler: connection collapsing only works if all clients share ONE process
 * holding ONE ring buffer. Serverless route handlers are per-invocation and
 * horizontally replicated, so the same code behind a serverless function would
 * silently open one upstream per instance — the exact thing this proxy exists
 * to prevent. The TV app talks to this service over the LAN.
 */

import process from "node:process";
import { EdgeProxy, type EdgeEvent } from "./edge.ts";
import { FetchOriginTransport } from "./origin.ts";
import { createEdgeServer } from "./server.ts";
import { createAdminRouter } from "./admin.ts";
import { ConfigError, loadConfig } from "./config.ts";

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

  // The edge emits events before the admin router exists, hence the indirection.
  const listeners: Array<(event: EdgeEvent) => void> = [];
  const edge = new EdgeProxy({
    ...config.edge,
    transport: new FetchOriginTransport({ allowedHosts: config.allowedHosts }),
    onEvent: (event: EdgeEvent) => {
      log(describe(event));
      for (const listener of listeners) listener(event);
    },
  });

  const admin = createAdminRouter({
    edge,
    token: config.adminToken,
    prefix: config.adminPrefix,
  });
  listeners.push((event) => admin.publish(event));

  const server = createEdgeServer({
    edge,
    egressBytesPerSecond: config.egressBytesPerSecond,
    maxClients: config.maxClients,
    pathPrefix: config.pathPrefix,
    admin,
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
  });

  let stopping = false;
  const shutdown = (signal: string) => {
    if (stopping) return;
    stopping = true;
    log(`${signal} received, draining`);
    admin.close();
    server.close();
    void edge.shutdown().then(() => process.exit(0));
  };
  process.on("SIGINT", () => shutdown("SIGINT"));
  process.on("SIGTERM", () => shutdown("SIGTERM"));
}

function describe(event: EdgeEvent): string {
  const parts = Object.entries(event)
    .filter(([key]) => key !== "type")
    .map(([key, value]) => `${key}=${String(value)}`);
  return [event.type, ...parts].join(" ");
}

main();
