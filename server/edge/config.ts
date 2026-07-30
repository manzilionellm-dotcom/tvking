/*
 * Environment → configuration. Pure and total: it never reads process state on
 * its own, so it is unit-testable and the failure modes are explicit errors
 * rather than a proxy that starts up pointing nowhere.
 */

import type { EdgeConfig, OriginTarget } from "./edge.ts";
import type { UpstreamIdentity } from "./sanitize.ts";

/** Just the parts of an environment this module reads. */
export type Env = Readonly<Record<string, string | undefined>>;

export interface EdgeRuntimeConfig {
  host: string;
  port: number;
  pathPrefix: string;
  egressBytesPerSecond: number;
  maxClients: number;
  allowedHosts: string[];
  edge: Omit<EdgeConfig, "transport">;
}

export class ConfigError extends Error {
  name = "ConfigError";
}

const DEFAULT_USER_AGENT = "tvking-edge/1.0";

function num(env: Env, key: string, fallback: number): number {
  const raw = env[key];
  if (raw === undefined || raw === "") return fallback;
  const value = Number(raw);
  if (!Number.isFinite(value) || value <= 0) {
    throw new ConfigError(`${key} must be a positive number, got ${JSON.stringify(raw)}`);
  }
  return value;
}

function json(env: Env, key: string): Record<string, string> | null {
  const raw = env[key];
  if (!raw) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new ConfigError(`${key} must be valid JSON`);
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new ConfigError(`${key} must be a JSON object`);
  }
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(parsed as Record<string, unknown>)) {
    if (typeof v !== "string") throw new ConfigError(`${key}.${k} must be a string`);
    out[k] = v;
  }
  return out;
}

/**
 * Builds the origin resolver from either an explicit id→URL map
 * (`EDGE_STREAM_MAP`) or a template (`EDGE_ORIGIN_TEMPLATE`, `{id}` placeholder).
 * The map wins; unknown ids resolve to null (→ 404), never to a guessed URL.
 */
export function buildResolver(
  map: Record<string, string> | null,
  template: string | undefined,
  extra: Record<string, string> | null
): (streamId: string) => OriginTarget | null {
  const perStream: Readonly<Record<string, string>> | undefined = extra ?? undefined;
  return (streamId: string): OriginTarget | null => {
    if (map) {
      const url = map[streamId];
      return url ? { url, extra: perStream } : null;
    }
    if (template) {
      return { url: template.replaceAll("{id}", encodeURIComponent(streamId)), extra: perStream };
    }
    return null;
  };
}

export function loadConfig(env: Env): EdgeRuntimeConfig {
  const map = json(env, "EDGE_STREAM_MAP");
  const template = env.EDGE_ORIGIN_TEMPLATE;
  if (!map && !template) {
    throw new ConfigError("set EDGE_STREAM_MAP or EDGE_ORIGIN_TEMPLATE");
  }
  if (template && !template.includes("{id}")) {
    throw new ConfigError("EDGE_ORIGIN_TEMPLATE must contain the {id} placeholder");
  }

  const identity: UpstreamIdentity = {
    userAgent: env.EDGE_USER_AGENT || DEFAULT_USER_AGENT,
    accept: env.EDGE_ACCEPT || "*/*",
    extra: json(env, "EDGE_UPSTREAM_HEADERS") ?? undefined,
    via: env.EDGE_VIA || "1.1 tvking-edge",
  };

  const allowedHosts = (env.EDGE_ALLOWED_HOSTS ?? "")
    .split(",")
    .map((host) => host.trim())
    .filter(Boolean);

  return {
    // Loopback by default: a proxy holding origin credentials must be opted
    // into LAN exposure, not exposed by accident.
    host: env.EDGE_HOST || "127.0.0.1",
    port: num(env, "EDGE_PORT", 8787),
    pathPrefix: env.EDGE_PATH_PREFIX || "/edge/",
    egressBytesPerSecond: num(env, "EDGE_EGRESS_BPS", 3 * 1024 * 1024),
    maxClients: num(env, "EDGE_MAX_CLIENTS", 200),
    allowedHosts,
    edge: {
      resolveOrigin: buildResolver(map, template, json(env, "EDGE_UPSTREAM_HEADERS")),
      identity,
      maxUpstreamConnections: num(env, "EDGE_MAX_UPSTREAM", 1),
      slotWaitMs: num(env, "EDGE_SLOT_WAIT_MS", 10_000),
      ring: {
        maxBytes: num(env, "EDGE_RING_BYTES", 16 * 1024 * 1024),
        maxChunks: num(env, "EDGE_RING_CHUNKS", 4096),
      },
      backlogBytes: num(env, "EDGE_BACKLOG_BYTES", 512 * 1024),
      subscriberQueueBytes: num(env, "EDGE_CLIENT_QUEUE_BYTES", 4 * 1024 * 1024),
      lingerMs: num(env, "EDGE_LINGER_MS", 15_000),
      reconnect: {
        attempts: num(env, "EDGE_RECONNECT_ATTEMPTS", 5),
        baseDelayMs: num(env, "EDGE_RECONNECT_BASE_MS", 250),
        maxDelayMs: num(env, "EDGE_RECONNECT_MAX_MS", 5_000),
      },
    },
  };
}
