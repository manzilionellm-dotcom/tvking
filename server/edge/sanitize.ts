/*
 * Privacy boundary between the LAN and the origin.
 *
 * The rule enforced here is deny-by-default: the upstream request is
 * CONSTRUCTED from the edge's own static identity, never forwarded from the
 * downstream request. Nothing a client sends can reach the origin unless it is
 * explicitly allowlisted, so a new client hint or tracking header added by some
 * future player cannot leak by omission.
 *
 * What the origin therefore observes: the edge's IP (it is the only TCP peer),
 * one stable User-Agent, and no cookies, no Referer, no XFF/Forwarded chain, no
 * trace IDs, no client hints — i.e. no personal data about downstream viewers
 * (GDPR art. 5(1)(c), data minimisation).
 *
 * Standards notes:
 *  - Hop-by-hop headers and the extra field-names listed in `Connection` are
 *    dropped in both directions (RFC 9110 §7.6.1).
 *  - RFC 7239 `Forwarded` is deliberately NOT added. That RFC exists to reveal
 *    the client chain; disclosing it is exactly what this proxy must not do.
 *  - A `Via` field is added instead: it identifies the intermediary without
 *    identifying the client (RFC 9110 §7.6.3).
 */

export type HeaderBag = Record<string, string | string[] | number | undefined>;

/** RFC 9110 §7.6.1 — connection-specific, never forwarded by an intermediary. */
export const HOP_BY_HOP_HEADERS: ReadonlySet<string> = new Set([
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "proxy-connection",
  "te",
  "trailer",
  "transfer-encoding",
  "upgrade",
]);

/**
 * Request headers that identify, fingerprint or track the downstream client.
 * Kept explicit (rather than implied by the allowlist) so the intent is
 * auditable and testable.
 */
export const CLIENT_IDENTITY_HEADERS: ReadonlySet<string> = new Set([
  // Network identity
  "x-forwarded-for",
  "x-forwarded-host",
  "x-forwarded-proto",
  "x-forwarded-port",
  "x-forwarded-server",
  "forwarded",
  "x-real-ip",
  "x-client-ip",
  "x-cluster-client-ip",
  "client-ip",
  "true-client-ip",
  "cf-connecting-ip",
  "cf-ipcountry",
  "cf-ray",
  "fastly-client-ip",
  "x-appengine-user-ip",
  "x-azure-clientip",
  // Device / agent fingerprint
  "user-agent",
  "sec-ch-ua",
  "sec-ch-ua-arch",
  "sec-ch-ua-bitness",
  "sec-ch-ua-full-version",
  "sec-ch-ua-full-version-list",
  "sec-ch-ua-mobile",
  "sec-ch-ua-model",
  "sec-ch-ua-platform",
  "sec-ch-ua-platform-version",
  "device-memory",
  "downlink",
  "dpr",
  "ect",
  "rtt",
  "save-data",
  "viewport-width",
  "width",
  // Session / credentials — the edge presents its own, never the client's
  "cookie",
  "cookie2",
  "authorization",
  "referer",
  "origin",
  "from",
  "x-csrf-token",
  // Correlation and tracing
  "traceparent",
  "tracestate",
  "baggage",
  "x-request-id",
  "x-correlation-id",
  "x-amzn-trace-id",
  "x-datadog-trace-id",
  "x-b3-traceid",
  "x-b3-spanid",
  "x-device-id",
  "x-session-id",
  // Fetch metadata / preferences that describe the user
  "sec-fetch-site",
  "sec-fetch-mode",
  "sec-fetch-dest",
  "sec-fetch-user",
  "sec-gpc",
  "dnt",
  "early-data",
  "accept-language",
]);

/** Response headers stripped before data goes back to LAN clients. */
export const DOWNSTREAM_STRIPPED_HEADERS: ReadonlySet<string> = new Set([
  "set-cookie",
  "set-cookie2",
  "server",
  "x-powered-by",
  "p3p",
  "x-amz-cf-id",
  "x-amz-request-id",
  "cf-ray",
  "x-served-by",
  "x-cache-hits",
  "report-to",
  "nel",
]);

/**
 * The only downstream request headers that may be forwarded. Range is
 * intentionally absent: a collapsed stream is shared, so a per-client Range
 * would either poison the shared buffer or force a second upstream connection.
 */
export const UPSTREAM_FORWARD_ALLOWLIST: ReadonlySet<string> = new Set(["accept"]);

/** The static identity every upstream request is built from. */
export interface UpstreamIdentity {
  userAgent: string;
  accept?: string;
  /**
   * Fixed language token. Pinned because an HTTP runtime that finds the field
   * missing will insert its own default; the value is identical for every
   * viewer, so it carries no locale.
   */
  acceptLanguage?: string;
  /** Origin-side credentials owned by the edge (never the client's). */
  extra?: Readonly<Record<string, string>>;
  /** `Via` pseudonym; RFC 9110 §7.6.3 allows a made-up name for the host. */
  via?: string;
}

/**
 * Master device signatures.
 *
 * Every request made on behalf of one master subscription mirrors ONE of these,
 * byte for byte. The origin therefore sees a single device, not a fleet: no
 * per-client variation to correlate, count or fingerprint. Which signature to
 * present is a deployment choice — an origin that only speaks to known player
 * software gets the matching profile.
 */
export const MASTER_DEVICE_PROFILES = {
  edge: { userAgent: "tvking-edge/1.0", accept: "*/*" },
  vlc: { userAgent: "VLC/3.0.20 LibVLC/3.0.20", accept: "*/*" },
  kodi: { userAgent: "Kodi/20.5 (Linux; Android 12) inputstream.adaptive", accept: "*/*" },
  tivimate: { userAgent: "TiviMate/4.7.0 (Android)", accept: "*/*" },
  exoplayer: { userAgent: "ExoPlayerLib/2.19.1", accept: "*/*" },
} as const satisfies Record<string, { userAgent: string; accept: string }>;

export type MasterDeviceName = keyof typeof MASTER_DEVICE_PROFILES;

export function isMasterDeviceName(value: string): value is MasterDeviceName {
  return Object.prototype.hasOwnProperty.call(MASTER_DEVICE_PROFILES, value);
}

/** Builds a complete, self-consistent identity from a named device profile. */
export function masterDevice(
  name: MasterDeviceName = "edge",
  overrides: Partial<UpstreamIdentity> = {}
): UpstreamIdentity {
  const profile = MASTER_DEVICE_PROFILES[name];
  return {
    userAgent: profile.userAgent,
    accept: profile.accept,
    acceptLanguage: "*",
    via: "1.1 tvking-edge",
    ...overrides,
  };
}

export interface SanitizeResult {
  headers: Record<string, string>;
  /** Field NAMES that were dropped — values are never retained or logged. */
  dropped: string[];
  /** Field names that survived the allowlist. */
  forwarded: string[];
}

function firstValue(value: string | string[] | number | undefined): string | undefined {
  if (value === undefined) return undefined;
  if (Array.isArray(value)) return value[0];
  return String(value);
}

/** Lower-cases field names (HTTP field names are case-insensitive). */
function normalize(bag: HeaderBag): Map<string, string> {
  const out = new Map<string, string>();
  for (const rawName of Object.keys(bag)) {
    const value = firstValue(bag[rawName]);
    if (value !== undefined) out.set(rawName.toLowerCase(), value);
  }
  return out;
}

/** Field names named by `Connection`, which are hop-by-hop for this message. */
export function connectionListedHeaders(bag: HeaderBag): Set<string> {
  const listed = new Set<string>();
  const raw = bag["connection"] ?? bag["Connection"];
  const values = Array.isArray(raw) ? raw : raw === undefined ? [] : [String(raw)];
  for (const value of values) {
    for (const token of value.split(",")) {
      const name = token.trim().toLowerCase();
      if (name && name !== "close" && name !== "keep-alive") listed.add(name);
    }
  }
  return listed;
}

/**
 * Builds the upstream request headers. `incoming` is inspected only to report
 * what was dropped and to pass the narrow allowlist through — it is never the
 * base of the result.
 */
export function buildUpstreamHeaders(
  identity: UpstreamIdentity,
  incoming: HeaderBag = {},
  allowlist: ReadonlySet<string> = UPSTREAM_FORWARD_ALLOWLIST
): SanitizeResult {
  const hopByHop = connectionListedHeaders(incoming);
  const forwarded: string[] = [];
  const dropped: string[] = [];
  const headers: Record<string, string> = {};

  for (const [name, value] of normalize(incoming)) {
    const forwardable =
      allowlist.has(name) &&
      !HOP_BY_HOP_HEADERS.has(name) &&
      !hopByHop.has(name) &&
      !CLIENT_IDENTITY_HEADERS.has(name);
    if (!forwardable) {
      dropped.push(name);
      continue;
    }
    headers[name] = value;
    forwarded.push(name);
  }

  // The master device signature always wins over anything forwarded.
  headers["user-agent"] = identity.userAgent;
  headers["accept"] = identity.accept ?? headers["accept"] ?? "*/*";
  headers["accept-encoding"] = "identity"; // media is already compressed
  headers["accept-language"] = identity.acceptLanguage ?? "*";
  headers["via"] = identity.via ?? "1.1 tvking-edge";
  for (const [name, value] of Object.entries(identity.extra ?? {})) {
    headers[name.toLowerCase()] = value;
  }

  return { headers, dropped, forwarded };
}

/**
 * The exact field set a master signature produces, with no request to sanitise.
 * Two different viewers must yield this same object.
 */
export function masterSignature(identity: UpstreamIdentity): Record<string, string> {
  return buildUpstreamHeaders(identity).headers;
}

/**
 * Throws unless `headers` mirrors the master signature exactly: same field
 * names, same values. Any per-client variation — an extra field, a different
 * value — is a correlation handle for the origin, so it is treated as a fault.
 */
export function assertMirrorsMasterSignature(
  headers: HeaderBag,
  identity: UpstreamIdentity,
  options: { allow?: readonly string[] } = {}
): void {
  const expected = masterSignature(identity);
  const actual = normalize(headers);
  // `allow` exists for exactly one case: VOD range requests, whose value comes
  // from the cache's chunk grid (a multiple of the chunk size) and is therefore
  // identical whichever viewer asked. Anything client-derived stays forbidden.
  const allowed = new Set(options.allow ?? []);
  const problems: string[] = [];

  for (const [name, value] of Object.entries(expected)) {
    if (actual.get(name) !== value) problems.push(`${name} differs from the master signature`);
  }
  for (const name of actual.keys()) {
    if (!(name in expected) && !allowed.has(name)) {
      problems.push(`${name} is not part of the master signature`);
    }
  }
  if (problems.length > 0) {
    throw new Error(`upstream request does not mirror the master device: ${problems.join(", ")}`);
  }
}

/**
 * Names in `headers` that would identify a downstream client. Empty means the
 * request is clean.
 *
 * A field whose value is exactly what the master signature prescribes is not
 * client metadata — `User-Agent: <master device>` and `Accept-Language: *` are
 * constants of the proxy. Anything else from the identity list is a leak.
 */
export function inspectClientMetadata(
  headers: HeaderBag,
  identity?: UpstreamIdentity | string
): string[] {
  const expected =
    typeof identity === "string"
      ? { "user-agent": identity }
      : identity
        ? masterSignature(identity)
        : {};
  const leaks: string[] = [];
  for (const [name, value] of normalize(headers)) {
    if (!CLIENT_IDENTITY_HEADERS.has(name)) continue;
    if (expected[name] === value) continue;
    leaks.push(name);
  }
  return leaks;
}

export function assertNoClientMetadata(
  headers: HeaderBag,
  identity?: UpstreamIdentity | string
): void {
  const leaks = inspectClientMetadata(headers, identity);
  if (leaks.length > 0) {
    throw new Error(`upstream request would leak client metadata: ${leaks.join(", ")}`);
  }
}

/** Filters origin response headers before they reach LAN clients. */
export function sanitizeDownstreamHeaders(upstream: HeaderBag): Record<string, string> {
  const hopByHop = connectionListedHeaders(upstream);
  const out: Record<string, string> = {};
  for (const rawName of Object.keys(upstream)) {
    const name = rawName.toLowerCase();
    if (HOP_BY_HOP_HEADERS.has(name) || hopByHop.has(name)) continue;
    if (DOWNSTREAM_STRIPPED_HEADERS.has(name)) continue;
    // Length/ranges describe the origin response, not the collapsed LAN stream.
    if (name === "content-length" || name === "content-range" || name === "accept-ranges") continue;
    const value = firstValue(upstream[rawName]);
    if (value !== undefined) out[name] = value;
  }
  return out;
}

/**
 * Log-safe URL: keeps scheme/host/path, replaces every query value with `***`.
 * Origin stream URLs routinely carry subscription tokens.
 */
export function redactUrl(url: string): string {
  try {
    const parsed = new URL(url);
    for (const key of [...parsed.searchParams.keys()]) parsed.searchParams.set(key, "***");
    if (parsed.username || parsed.password) {
      parsed.username = "***";
      parsed.password = "***";
    }
    return parsed.toString();
  } catch {
    return "<unparseable-url>";
  }
}
