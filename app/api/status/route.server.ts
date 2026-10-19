/**
 * app/api/status/route.server.ts — real-time status over Server-Sent Events. REAL DATA ONLY.
 *
 * The `.server.ts` suffix is a page extension that next.config.ts enables only for the
 * Vercel build. The GitHub Pages static export (GITHUB_PAGES=true) cannot contain a dynamic
 * route, so there this file is not a route at all and the widget simply gets a 404.
 *
 * GET  → one `status` SSE event, then the stream closes with `retry: 60000` so EventSource
 *        reconnects every 60 s (cheap polling with SSE semantics; no long-lived function time).
 * POST → anonymous heartbeat. Counted ONLY when a Redis-compatible REST store is configured
 *        (KV_REST_API_URL + KV_REST_API_TOKEN — the variable names Vercel KV / Upstash inject).
 *
 * Nothing here is estimated. When a value cannot be observed it is `null`, never a guess.
 */
import { NextRequest, NextResponse } from "next/server";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

const WINDOW_SECONDS = 120; // a session is "active" if it sent a heartbeat in the last 2 minutes
const ZSET_KEY = "live:sessions";

type StatusPayload = {
  ok: true;
  time: string; // ISO-8601 server time
  region: string | null; // VERCEL_REGION (e.g. "iad1"), null outside Vercel
  deployment: string | null; // VERCEL_DEPLOYMENT_ID
  commit: string | null; // short VERCEL_GIT_COMMIT_SHA
  activeSessions: number | null; // null = NOT MEASURED (no store configured)
  windowSeconds: number;
  sessionsSource: "kv" | null;
};

function kvConfig(): { url: string; token: string } | null {
  const url = process.env.KV_REST_API_URL;
  const token = process.env.KV_REST_API_TOKEN;
  return url && token ? { url, token } : null;
}

/** Upstash/Vercel KV REST pipeline: POST /pipeline with [[cmd, ...args], ...]. */
async function kvPipeline(cmds: (string | number)[][]): Promise<unknown[] | null> {
  const cfg = kvConfig();
  if (!cfg) return null;
  try {
    const res = await fetch(`${cfg.url}/pipeline`, {
      method: "POST",
      headers: { Authorization: `Bearer ${cfg.token}`, "Content-Type": "application/json" },
      body: JSON.stringify(cmds),
      cache: "no-store",
      signal: AbortSignal.timeout(1500),
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { result?: unknown; error?: string }[];
    return data.map((d) => d.result);
  } catch {
    return null;
  }
}

async function countActiveSessions(): Promise<number | null> {
  const now = Math.floor(Date.now() / 1000);
  const out = await kvPipeline([
    ["ZREMRANGEBYSCORE", ZSET_KEY, "-inf", now - WINDOW_SECONDS],
    ["ZCARD", ZSET_KEY],
  ]);
  const card = out?.[1];
  return typeof card === "number" ? card : null;
}

function sse(payload: StatusPayload): Response {
  const body =
    `retry: 60000\n` +
    `event: status\n` +
    `id: ${Date.now()}\n` +
    `data: ${JSON.stringify(payload)}\n\n`;
  return new Response(body, {
    status: 200,
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-store, no-transform",
      "X-Accel-Buffering": "no",
      Connection: "keep-alive",
      "X-Robots-Tag": "noindex, nofollow",
    },
  });
}

export async function GET() {
  const sha = process.env.VERCEL_GIT_COMMIT_SHA ?? null;
  const payload: StatusPayload = {
    ok: true,
    time: new Date().toISOString(),
    region: process.env.VERCEL_REGION ?? null,
    deployment: process.env.VERCEL_DEPLOYMENT_ID ?? null,
    commit: sha ? sha.slice(0, 7) : null,
    activeSessions: await countActiveSessions(),
    windowSeconds: WINDOW_SECONDS,
    sessionsSource: kvConfig() ? "kv" : null,
  };
  return sse(payload);
}

/** Heartbeat. Body: { id: string } — an opaque random id generated in memory by the browser. */
export async function POST(req: NextRequest) {
  if (!kvConfig()) return new NextResponse(null, { status: 204 });
  let id = "";
  try {
    const json = (await req.json()) as { id?: unknown };
    if (typeof json.id === "string" && /^[A-Za-z0-9_-]{8,64}$/.test(json.id)) id = json.id;
  } catch {
    /* ignore malformed bodies */
  }
  if (!id) return new NextResponse(null, { status: 400 });
  const now = Math.floor(Date.now() / 1000);
  await kvPipeline([
    ["ZADD", ZSET_KEY, now, id],
    ["ZREMRANGEBYSCORE", ZSET_KEY, "-inf", now - WINDOW_SECONDS],
    ["EXPIRE", ZSET_KEY, WINDOW_SECONDS * 2],
  ]);
  return new NextResponse(null, { status: 204, headers: { "Cache-Control": "no-store" } });
}
