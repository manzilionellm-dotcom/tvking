/*
 * Lightweight, privacy-first telemetry (Loi 11 — no PII in logs).
 *
 * This is deliberately small: a bounded in-memory ring of recent events plus a
 * pluggable sink, so the app has ONE place to record errors and notable UX
 * events (e.g. an error boundary tripping) without shipping a heavy analytics
 * SDK. Every value is scrubbed before it is stored or forwarded, so tokens,
 * emails and long id-like digit runs never reach a log or a remote endpoint.
 *
 * No network sink is wired by default: the app works with telemetry fully
 * local. A real backend can be attached later via `setSink`.
 */

export type Category =
  | "error" // uncaught render error caught by a boundary
  | "nav" // navigation / focus events
  | "player" // playback lifecycle (mock player today)
  | "app"; // generic app lifecycle

export interface TelemetryEvent {
  category: Category;
  name: string;
  /** Scrubbed, primitive-only payload. */
  data?: Record<string, string | number | boolean>;
}

const EMAIL = /[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/gi;
const BEARER = /\b(?:bearer|token|apikey|api_key|authorization)\b[=:\s]+\S+/gi;
// Long digit/hex runs look like ids/tokens/card numbers → redact defensively.
const LONG_ID = /\b[a-f0-9]{16,}\b|\b\d{10,}\b/gi;

/** Redact PII-shaped substrings from a string. Exported for tests. */
export function scrub(input: string): string {
  return input
    .replace(BEARER, "[redacted]")
    .replace(EMAIL, "[redacted-email]")
    .replace(LONG_ID, "[redacted-id]");
}

function scrubValue(v: unknown): string | number | boolean {
  if (typeof v === "number" || typeof v === "boolean") return v;
  return scrub(String(v));
}

/** Scrub every value of a flat payload. Exported for tests. */
export function scrubData(
  data?: Record<string, unknown>,
): Record<string, string | number | boolean> | undefined {
  if (!data) return undefined;
  const out: Record<string, string | number | boolean> = {};
  for (const [k, v] of Object.entries(data)) out[k] = scrubValue(v);
  return out;
}

export const RING_CAPACITY = 50;

class Ring {
  private buf: TelemetryEvent[] = [];
  push(e: TelemetryEvent) {
    this.buf.push(e);
    if (this.buf.length > RING_CAPACITY) this.buf.shift();
  }
  snapshot(): TelemetryEvent[] {
    return [...this.buf];
  }
  clear() {
    this.buf = [];
  }
}

const ring = new Ring();
let sink: ((e: TelemetryEvent) => void) | null = null;

/** Attach a forwarding sink (e.g. a real reporting backend). Values are already scrubbed. */
export function setSink(fn: ((e: TelemetryEvent) => void) | null) {
  sink = fn;
}

/** Recent (already scrubbed) events, oldest first. */
export function recentEvents(): TelemetryEvent[] {
  return ring.snapshot();
}

/** Test/reset helper. */
export function _reset() {
  ring.clear();
  sink = null;
}

export function logEvent(
  category: Category,
  name: string,
  data?: Record<string, unknown>,
): TelemetryEvent {
  const event: TelemetryEvent = {
    category,
    name: scrub(name),
    data: scrubData(data),
  };
  ring.push(event);
  if (sink) {
    try {
      sink(event);
    } catch {
      /* a broken sink must never break the app */
    }
  }
  return event;
}

/** Record an error without leaking its (potentially sensitive) message verbatim. */
export function logError(
  error: unknown,
  context?: Record<string, unknown>,
): TelemetryEvent {
  const message = error instanceof Error ? error.message : String(error);
  const digest =
    typeof error === "object" && error && "digest" in error
      ? String((error as { digest?: unknown }).digest ?? "")
      : "";
  return logEvent("error", "uncaught", {
    message,
    ...(digest ? { digest } : {}),
    ...context,
  });
}
