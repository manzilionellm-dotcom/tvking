/*
 * Environment → configuration. Pure and total: it never reads process state on
 * its own, so it is unit-testable and the failure modes are explicit errors
 * rather than a proxy that starts up pointing nowhere.
 */

import type { EdgeConfig, OriginTarget } from "./edge.ts";
import type { MasterAccountInput } from "./accounts.ts";
import { isMasterDeviceName, type UpstreamIdentity } from "./sanitize.ts";

/** Just the parts of an environment this module reads. */
export type Env = Readonly<Record<string, string | undefined>>;

export interface EdgeRuntimeConfig {
  host: string;
  port: number;
  pathPrefix: string;
  egressBytesPerSecond: number;
  maxClients: number;
  allowedHosts: string[];
  /** Empty string = admin plane disabled. */
  adminToken: string;
  adminPrefix: string;
  /** SQLite file for subscribers, VOD catalogue and cache index. */
  databasePath: string;
  /** Subscriber portals (MAC / Xtream). Off unless a database is configured. */
  portalEnabled: boolean;
  publicBase: string | undefined;
  enforcerIntervalMs: number;
  vod: {
    enabled: boolean;
    /** Where downloaded media lives, one file per library item. */
    filesDir: string;
    /** Refuse a single file bigger than this (0 = no limit). */
    maxFileBytes: number;
  };
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

/**
 * `EDGE_ACCOUNTS` holds the master subscription lines, e.g.
 *   [{"id":"master","playlistUrl":"https://provider/get.php?...","maxConnections":1,
 *     "device":"vlc","headers":{"x-token":"..."}}]
 * Validated here rather than at first use, so a typo fails at boot.
 */
export function parseAccounts(raw: string | undefined): MasterAccountInput[] {
  if (!raw) return [];
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new ConfigError("EDGE_ACCOUNTS must be valid JSON");
  }
  if (!Array.isArray(parsed)) throw new ConfigError("EDGE_ACCOUNTS must be a JSON array");

  return parsed.map((entry, index) => {
    if (!entry || typeof entry !== "object") {
      throw new ConfigError(`EDGE_ACCOUNTS[${index}] must be an object`);
    }
    const account = entry as Record<string, unknown>;
    if (typeof account.id !== "string" || account.id === "") {
      throw new ConfigError(`EDGE_ACCOUNTS[${index}].id is required`);
    }
    if (account.device !== undefined && !isMasterDeviceName(String(account.device))) {
      throw new ConfigError(`EDGE_ACCOUNTS[${index}].device is unknown: ${String(account.device)}`);
    }
    const contention = account.contention;
    if (contention !== undefined && !["swap", "wait", "reject"].includes(String(contention))) {
      throw new ConfigError(`EDGE_ACCOUNTS[${index}].contention must be swap, wait or reject`);
    }
    return account as unknown as MasterAccountInput;
  });
}

export function loadConfig(env: Env): EdgeRuntimeConfig {
  const map = json(env, "EDGE_STREAM_MAP");
  const template = env.EDGE_ORIGIN_TEMPLATE;
  const accounts = parseAccounts(env.EDGE_ACCOUNTS);
  if (!map && !template && accounts.length === 0) {
    throw new ConfigError("set EDGE_ACCOUNTS, EDGE_STREAM_MAP or EDGE_ORIGIN_TEMPLATE");
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

  const contention = env.EDGE_CONTENTION || "swap";
  if (!["swap", "wait", "reject"].includes(contention)) {
    throw new ConfigError("EDGE_CONTENTION must be swap, wait or reject");
  }

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
    // No token, no admin plane: this API can point the proxy at a new origin.
    adminToken: env.EDGE_ADMIN_TOKEN ?? "",
    adminPrefix: env.EDGE_ADMIN_PREFIX || "/admin",
    databasePath: env.EDGE_DB || "",
    // The portals need somewhere to keep subscribers; without a database they
    // would authorise from thin air, so they stay off.
    portalEnabled: Boolean(env.EDGE_DB) && env.EDGE_PORTAL !== "0",
    publicBase: env.EDGE_PUBLIC_BASE || undefined,
    enforcerIntervalMs: num(env, "EDGE_ENFORCE_INTERVAL_MS", 15_000),
    vod: {
      enabled: Boolean(env.EDGE_DB) && env.EDGE_VOD !== "0",
      filesDir: env.EDGE_VOD_DIR || "./.edge-cache/vod",
      maxFileBytes: Number(env.EDGE_VOD_MAX_FILE_BYTES ?? 0),
    },
    edge: {
      accounts,
      resolveOrigin:
        map || template ? buildResolver(map, template, json(env, "EDGE_UPSTREAM_HEADERS")) : undefined,
      identity,
      contention: contention as EdgeConfig["contention"],
      starveGraceMs: num(env, "EDGE_STARVE_GRACE_MS", 30_000),
      swapSettleMs: Number(env.EDGE_SWAP_SETTLE_MS ?? 100),
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
