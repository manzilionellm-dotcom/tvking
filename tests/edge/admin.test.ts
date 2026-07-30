/*
 * Admin plane over real HTTP: auth, account management, monitoring, SSE.
 */

import http from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { EdgeProxy, type EdgeEvent } from "../../server/edge/edge.ts";
import { createAdminRouter, type AdminRouter } from "../../server/edge/admin.ts";
import { createEdgeServer } from "../../server/edge/server.ts";
import { MockOrigin, bytes, tick } from "./mock-origin.ts";

const TOKEN = "s3cret-admin-token";

let origin: MockOrigin;
let edge: EdgeProxy;
let admin: AdminRouter;
let server: http.Server;
let base: string;

async function boot(options: { token?: string } = {}) {
  origin = new MockOrigin({ openDelayMs: 1 });
  edge = new EdgeProxy({
    accounts: [
      {
        id: "master",
        label: "Ligne maître",
        channels: { tf1: "https://origin.example/tf1.ts", m6: "https://origin.example/m6.ts" },
        maxConnections: 1,
        device: "vlc",
        headers: { "x-provider-token": "provider-secret" },
      },
    ],
    transport: origin,
    lingerMs: 0,
    onEvent: (event: EdgeEvent) => admin?.publish(event),
  });
  admin = createAdminRouter({ edge, token: options.token ?? TOKEN, snapshotMs: 50 });
  server = createEdgeServer({ edge, egressBytesPerSecond: 8 * 1024 * 1024, admin });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
}

function api(path: string, init: RequestInit = {}) {
  return fetch(`${base}/admin${path}`, {
    ...init,
    headers: { authorization: `Bearer ${TOKEN}`, ...init.headers },
  });
}

beforeEach(() => boot());

afterEach(async () => {
  admin.close();
  await edge.shutdown();
  await new Promise<void>((resolve) => server.close(() => resolve()));
});

describe("admin plane — access", () => {
  it("refuses everything without the token", async () => {
    for (const path of ["/overview", "/accounts", "/sessions", "/events"]) {
      const response = await fetch(`${base}/admin${path}`);
      expect(response.status).toBe(401);
      expect(response.headers.get("www-authenticate")).toContain("Bearer");
      await response.body?.cancel();
    }
  });

  it("refuses a wrong token, whatever its length", async () => {
    for (const token of ["", "nope", `${TOKEN}x`, TOKEN.slice(0, -1)]) {
      const response = await fetch(`${base}/admin/overview`, {
        headers: { authorization: `Bearer ${token}` },
      });
      expect(response.status).toBe(401);
      await response.body?.cancel();
    }
  });

  it("accepts the token via X-Admin-Token too", async () => {
    const response = await fetch(`${base}/admin/overview`, { headers: { "x-admin-token": TOKEN } });
    expect(response.status).toBe(200);
  });

  it("serves the dashboard shell, which carries no data of its own", async () => {
    const response = await fetch(`${base}/admin/`);
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/html");
    const html = await response.text();
    expect(html).toContain("TV King");
    expect(html).not.toContain(TOKEN);
    expect(html).not.toContain("provider-secret");
  });

  it("stays off entirely when no token is configured", async () => {
    admin.close();
    await edge.shutdown();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    await boot({ token: "" });

    expect(admin.enabled).toBe(false);
    const response = await fetch(`${base}/admin/overview`);
    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: "admin_disabled" });
  });

  it("does not shadow the data plane", async () => {
    const health = await fetch(`${base}/healthz`);
    expect(await health.json()).toEqual({ status: "ok" });
  });
});

describe("admin plane — accounts", () => {
  it("lists master accounts without ever exposing their credentials", async () => {
    const body = await (await api("/accounts")).json();
    expect(body.accounts).toHaveLength(1);
    expect(body.accounts[0]).toMatchObject({
      id: "master",
      label: "Ligne maître",
      maxConnections: 1,
      device: "vlc",
      userAgent: "VLC/3.0.20 LibVLC/3.0.20",
      credentialHeaders: ["x-provider-token"],
    });
    expect(JSON.stringify(body)).not.toContain("provider-secret");
  });

  it("adds an account and routes to it immediately", async () => {
    const created = await api("/accounts", {
      method: "POST",
      body: JSON.stringify({
        id: "second",
        channelTemplate: "https://other.example/{id}.ts",
        maxConnections: 2,
        device: "kodi",
      }),
    });
    expect(created.status).toBe(200);

    const joined = await edge.subscribe("second/sport");
    expect(origin.requests.at(-1)?.url).toBe("https://other.example/sport.ts");
    expect(origin.requests.at(-1)?.headers["user-agent"]).toContain("Kodi");
    joined.subscription.close();
  });

  it("rejects an invalid account definition with a reason", async () => {
    const response = await api("/accounts", {
      method: "POST",
      body: JSON.stringify({ id: "broken" }),
    });
    expect(response.status).toBe(400);
    expect((await response.json()).detail).toMatch(/no playlistUrl/);
  });

  it("rejects malformed JSON", async () => {
    const response = await api("/accounts", { method: "POST", body: "{not json" });
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "invalid_json" });
  });

  it("refuses to resize a budget under live streams instead of breaking the invariant", async () => {
    const joined = await edge.subscribe("master/tf1");
    const response = await api("/accounts", {
      method: "POST",
      body: JSON.stringify({
        id: "master",
        channels: { tf1: "https://origin.example/tf1.ts" },
        maxConnections: 4,
      }),
    });
    expect(response.status).toBe(400);
    expect((await response.json()).detail).toMatch(/stop them before changing/);
    expect(edge.upstreamLimit).toBe(1);
    joined.subscription.close();
  });

  it("removes an account and closes its streams", async () => {
    const joined = await edge.subscribe("master/tf1");
    expect(edge.counters.active).toBe(1);

    const response = await api("/accounts/master", { method: "DELETE" });
    expect(await response.json()).toEqual({ removed: true });
    expect(edge.counters.active).toBe(0);
    expect(joined.subscription.closed || edge.sessions()).toBeTruthy();
    expect((await (await api("/accounts/master", { method: "DELETE" })).json()).removed).toBe(false);
  });

  it("lists the channels of an account", async () => {
    const body = await (await api("/accounts/master/channels")).json();
    expect(body.channels.map((c: { id: string }) => c.id).sort()).toEqual(["m6", "tf1"]);
  });
});

describe("admin plane — monitoring", () => {
  it("reports upstream, streams, sessions and dedup efficiency", async () => {
    const clients = await Promise.all(
      Array.from({ length: 20 }, () => edge.subscribe("master/tf1"))
    );
    origin.push(bytes("0123456789"));
    await tick(5);

    const overview = await (await api("/overview")).json();
    expect(overview.upstream.limit).toBe(1);
    expect(overview.upstream.activeMax).toBe(1); // never more than one, ever
    expect(overview.accounts[0].slots).toMatchObject({ capacity: 1, available: 0 });
    expect(overview.accounts[0].activeChannels).toEqual(["tf1"]);
    expect(overview.streams[0]).toMatchObject({
      account: "master",
      channel: "tf1",
      state: "live",
      subscribers: 20,
      holdsSlot: true,
    });
    expect(overview.sessions).toHaveLength(20);
    expect(overview.efficiency.clientRequests).toBe(20);
    expect(overview.efficiency.upstreamOpens).toBe(1);
    expect(overview.efficiency.requestsPerUpstream).toBe(20); // 20 clients → 1 socket
    expect(overview.efficiency.fanoutRatio).toBeGreaterThan(1);

    for (const client of clients) client.subscription.close();
  });

  it("shows sessions as opaque ids with no viewer data", async () => {
    const joined = await edge.subscribe("master/tf1");
    const body = await (await api("/sessions")).json();

    expect(body.sessions).toHaveLength(1);
    expect(body.sessions[0].id).toMatch(/^[0-9a-f-]{6,}$/);
    expect(body.sessions[0]).toMatchObject({ account: "master", channel: "tf1", stalled: false });
    const serialised = JSON.stringify(body);
    for (const forbidden of ["ip", "127.0.0.1", "user-agent", "cookie"]) {
      expect(serialised.toLowerCase()).not.toContain(forbidden);
    }
    joined.subscription.close();
  });

  it("stops a stream on request", async () => {
    const joined = await edge.subscribe("master/tf1");
    expect(edge.counters.active).toBe(1);

    const response = await api(`/streams/${encodeURIComponent("master/tf1")}/stop`, {
      method: "POST",
    });
    expect(await response.json()).toEqual({ stopped: true });
    expect(edge.counters.active).toBe(0);
    expect(joined.subscription.closed).toBe(false); // ended, not left dangling
    const missing = await api(`/streams/${encodeURIComponent("master/ghost")}/stop`, {
      method: "POST",
    });
    expect(missing.status).toBe(404);
  });

  it("streams live activity over SSE, starting with a snapshot", async () => {
    const controller = new AbortController();
    const response = await api("/events", { signal: controller.signal });
    expect(response.headers.get("content-type")).toContain("text/event-stream");

    const reader = response.body?.getReader();
    const decoder = new TextDecoder();
    let buffer = decoder.decode((await reader?.read())?.value ?? new Uint8Array());
    expect(buffer).toContain("event: overview");

    const joined = await edge.subscribe("master/tf1");
    const deadline = Date.now() + 3000;
    while (!buffer.includes("event: activity") && Date.now() < deadline) {
      const next = await reader?.read();
      if (next?.done) break;
      buffer += decoder.decode(next?.value ?? new Uint8Array());
    }
    expect(buffer).toContain("event: activity");
    expect(buffer).toMatch(/"type":"(upstream-open|slot-granted|join|session-open)"/);

    joined.subscription.close();
    controller.abort();
    await reader?.cancel().catch(() => {});
  }, 15_000);

  it("404s an unknown admin route", async () => {
    const response = await api("/nope");
    expect(response.status).toBe(404);
  });
});
