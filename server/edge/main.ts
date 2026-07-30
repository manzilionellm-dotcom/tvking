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

  const edge = new EdgeProxy({
    ...config.edge,
    transport: new FetchOriginTransport({ allowedHosts: config.allowedHosts }),
    onEvent: (event: EdgeEvent) => log(describe(event)),
  });

  const server = createEdgeServer({
    edge,
    egressBytesPerSecond: config.egressBytesPerSecond,
    maxClients: config.maxClients,
    pathPrefix: config.pathPrefix,
    log,
  });

  server.listen(config.port, config.host, () => {
    log(
      `listening on http://${config.host}:${config.port}${config.pathPrefix}<id> ` +
        `(max ${config.edge.maxUpstreamConnections} upstream connection(s), ` +
        `${Math.round(config.egressBytesPerSecond / 1024)} KiB/s per client)`
    );
  });

  let stopping = false;
  const shutdown = (signal: string) => {
    if (stopping) return;
    stopping = true;
    log(`${signal} received, draining`);
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
