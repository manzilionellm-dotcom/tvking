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
import { ManualWallClock } from "../../server/edge/clock.ts";
import { openDatabase, type Database } from "../../server/edge/db/database.ts";
import { PortalRepository } from "../../server/edge/portal/devices.ts";
import { ExpirationEnforcer } from "../../server/edge/portal/enforcer.ts";
import { VodLibrary } from "../../server/edge/vod/library.ts";
import { VodDownloader } from "../../server/edge/vod/downloader.ts";
import { masterDevice } from "../../server/edge/sanitize.ts";

const TOKEN = "s3cret-admin-token";

let origin: MockOrigin;
let edge: EdgeProxy;
let admin: AdminRouter;
let server: http.Server;
let base: string;
let db: Database;
let repo: PortalRepository;
let library: VodLibrary;
let downloader: VodDownloader;
let playlist: string;
let clock: ManualWallClock;

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
  db = openDatabase(":memory:");
  clock = new ManualWallClock("2026-06-01T12:00:00Z");
  repo = new PortalRepository(db, clock);
  library = new VodLibrary(db, clock);
  repo.upsertPackage({ name: "full", accountId: "master" });
  playlist =
    "#EXTM3U\n" +
    '#EXTINF:-1 group-title="VOD | SF",Dune (2021)\n' +
    "http://provider.example/movie/u/p/1.mkv\n" +
    '#EXTINF:-1 group-title="VOD | POLAR",Heat (1995)\n' +
    "http://provider.example/movie/u/p/2.mkv\n";
  downloader = new VodDownloader({
    library,
    transport: origin,
    dir: "/tmp/tvking-admin-vod",
    identityFor: () => masterDevice("vlc"),
    fetchPlaylist: async () => playlist,
  });

  admin = createAdminRouter({
    edge,
    token: options.token ?? TOKEN,
    snapshotMs: 50,
    portal: { repo, enforcer: new ExpirationEnforcer({ repo, edge, wallClock: clock }) },
    vod: { library, downloader },
  });
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
  db.close();
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

describe("admin plane — subscriber devices", () => {
  async function addDevice(body: Record<string, unknown>) {
    const response = await api("/devices", { method: "POST", body: JSON.stringify(body) });
    return { status: response.status, body: await response.json() };
  }

  it("creates a device with a plan in one call", async () => {
    const packages = (await (await api("/packages")).json()).packages;
    const created = await addDevice({
      label: "Salon",
      mac: "00:1a:79:aa:bb:cc",
      packageId: packages[0].id,
      plan: "trial-24h",
    });

    expect(created.status).toBe(200);
    expect(created.body.device.state).toBe("active");
    expect(created.body.device.subscription.plan).toBe("trial-24h");

    const listed = (await (await api("/devices")).json()).devices;
    expect(listed).toHaveLength(1);
    expect(listed[0]).toMatchObject({ mac: "00:1A:79:AA:BB:CC", label: "Salon", state: "active" });
    expect(listed[0].remainingMs).toBe(24 * 3_600_000);
  });

  it("generates Xtream credentials on demand and shows them exactly once", async () => {
    const packages = (await (await api("/packages")).json()).packages;
    const created = await addDevice({ label: "Mobile", username: "auto", packageId: packages[0].id });

    expect(created.body.credentials.username).toMatch(/^tv[0-9a-f]{8}$/);
    expect(created.body.credentials.password).toMatch(/^[0-9a-f]{12}$/);
    // Not recoverable afterwards: only the hash is stored.
    const listed = (await (await api("/devices")).json()).devices;
    expect(JSON.stringify(listed)).not.toContain(created.body.credentials.password);
  });

  it("offers exactly the five documented durations", async () => {
    const plans = (await (await api("/devices")).json()).plans;
    expect(plans.map((p: { id: string }) => p.id)).toEqual(["trial-24h", "1m", "3m", "6m", "12m"]);
    expect(plans.find((p: { id: string }) => p.id === "trial-24h").trial).toBe(true);
  });

  it("grants, extends and revokes", async () => {
    const packages = (await (await api("/packages")).json()).packages;
    const created = await addDevice({ mac: "00:1a:79:aa:bb:cc", packageId: packages[0].id });
    const id = created.body.device.device.id;

    const granted = await (
      await api(`/devices/${id}/grant`, { method: "POST", body: JSON.stringify({ plan: "3m" }) })
    ).json();
    expect(granted.device.state).toBe("active");
    expect(new Date(granted.subscription.expiresAt).toISOString()).toBe("2026-09-01T12:00:00.000Z");

    const revoked = await (await api(`/devices/${id}/revoke`, { method: "POST" })).json();
    expect(revoked.revoked).toBe(1);
    const listed = (await (await api("/devices")).json()).devices;
    expect(listed[0].state).toBe("revoked");
  });

  it("rejects an unknown plan with the list of valid ones", async () => {
    const packages = (await (await api("/packages")).json()).packages;
    const created = await addDevice({ mac: "00:1a:79:aa:bb:cc", packageId: packages[0].id });
    const id = created.body.device.device.id;

    const response = await api(`/devices/${id}/grant`, {
      method: "POST",
      body: JSON.stringify({ plan: "forever" }),
    });
    expect(response.status).toBe(400);
    expect((await response.json()).plans).toContain("12m");
  });

  it("rejects a malformed MAC with a readable reason", async () => {
    const response = await api("/devices", {
      method: "POST",
      body: JSON.stringify({ mac: "not-a-mac" }),
    });
    expect(response.status).toBe(400);
    expect((await response.json()).detail).toMatch(/invalid MAC/);
  });

  it("cuts live streams when a device is revoked or deleted", async () => {
    const packages = (await (await api("/packages")).json()).packages;
    const created = await addDevice({
      mac: "00:1a:79:aa:bb:cc",
      packageId: packages[0].id,
      plan: "12m",
    });
    const id = created.body.device.device.id;

    const joined = await edge.subscribe("master/tf1", { owner: { deviceId: id } });
    expect(edge.sessionsForDevice(id)).toHaveLength(1);

    const revoked = await (await api(`/devices/${id}/revoke`, { method: "POST" })).json();
    expect(revoked.droppedSessions).toBe(1);
    expect(joined.subscription.closed).toBe(true);

    const again = await edge.subscribe("master/tf1", { owner: { deviceId: id } });
    await api(`/devices/${id}`, { method: "DELETE" });
    expect(again.subscription.closed).toBe(true);
  });

  it("reports devices and the enforcer in the overview", async () => {
    const packages = (await (await api("/packages")).json()).packages;
    await addDevice({ mac: "00:1a:79:aa:bb:cc", packageId: packages[0].id, plan: "1m" });

    const overview = await (await api("/overview")).json();
    expect(overview.portal.configured).toBe(true);
    expect(overview.portal.devices).toHaveLength(1);
    expect(overview.portal.plans).toHaveLength(5);
    expect(overview.portal.enforcer).toMatchObject({ running: false, sweeps: 0 });
  });
});

describe("admin plane — VOD library", () => {
  async function addSource() {
    const response = await api("/vod/sources", {
      method: "POST",
      body: JSON.stringify({
        name: "provider-a",
        url: "http://provider.example/vod.m3u",
        accountId: "master",
      }),
    });
    return (await response.json()).source;
  }

  it("adds a source without importing anything", async () => {
    const source = await addSource();
    expect(source.lastImportAt).toBeNull();

    const vod = await (await api("/vod")).json();
    expect(vod.configured).toBe(true);
    expect(vod.sources).toHaveLength(1);
    expect(vod.counts.items).toBe(0); // nothing was scraped on the way in
    expect(vod.items).toEqual([]);
  });

  it("imports the catalogue when Télécharger is pressed", async () => {
    const source = await addSource();
    const report = (await (await api(`/vod/sources/${source.id}/import`, { method: "POST" })).json())
      .report;

    expect(report.ok).toBe(true);
    expect(report.created).toBe(2);

    const vod = await (await api("/vod")).json();
    expect(vod.counts.items).toBe(2);
    expect(vod.items.map((item: { title: string }) => item.title).sort()).toEqual(["Dune", "Heat"]);
    expect(vod.items.every((item: { state: string }) => item.state === "pending")).toBe(true);
    // Folder names come from the provider's group, tidied: short words stay
    // upper-case ("SF"), longer ones are capitalised ("Polar").
    expect(vod.categories.map((c: { name: string }) => c.name).sort()).toEqual(["Polar", "SF"]);
  });

  it("renames a title and moves it between folders", async () => {
    const source = await addSource();
    await api(`/vod/sources/${source.id}/import`, { method: "POST" });
    const items = (await (await api("/vod/items")).json()).items;
    const dune = items.find((item: { title: string }) => item.title === "Dune");

    const folder = (
      await (
        await api("/vod/categories", {
          method: "POST",
          body: JSON.stringify({ kind: "movie", name: "Science-fiction" }),
        })
      ).json()
    ).category;

    const renamed = (
      await (
        await api(`/vod/items/${dune.id}`, {
          method: "PATCH",
          body: JSON.stringify({ title: "Dune — partie 1", categoryId: folder.id }),
        })
      ).json()
    ).item;

    expect(renamed.title).toBe("Dune — partie 1");
    expect(renamed.category).toBe("Science-fiction");
  });

  it("renames and deletes a folder without losing its titles", async () => {
    const source = await addSource();
    await api(`/vod/sources/${source.id}/import`, { method: "POST" });
    const categories = (await (await api("/vod")).json()).categories;
    const sf = categories.find((c: { name: string }) => c.name === "SF");

    const renamed = (
      await (
        await api(`/vod/categories/${sf.id}`, {
          method: "PATCH",
          body: JSON.stringify({ name: "Science-fiction" }),
        })
      ).json()
    ).category;
    expect(renamed.name).toBe("Science-fiction");

    await api(`/vod/categories/${sf.id}`, { method: "DELETE" });
    const vod = await (await api("/vod")).json();
    expect(vod.counts.items).toBe(2);
    expect(vod.items.some((item: { category: string | null }) => item.category === null)).toBe(true);
  });

  it("assigns a title to packages and devices, and replaces the set", async () => {
    const source = await addSource();
    await api(`/vod/sources/${source.id}/import`, { method: "POST" });
    const item = (await (await api("/vod/items")).json()).items[0];
    const pack = (await (await api("/packages")).json()).packages[0];
    const device = (
      await (
        await api("/devices", {
          method: "POST",
          body: JSON.stringify({ mac: "00:1a:79:aa:bb:cc", packageId: pack.id, plan: "1m" }),
        })
      ).json()
    ).device.device;

    const assigned = (
      await (
        await api(`/vod/items/${item.id}/assignments`, {
          method: "PUT",
          body: JSON.stringify({
            targets: [
              { type: "package", id: pack.id },
              { type: "device", id: device.id },
            ],
          }),
        })
      ).json()
    ).item;
    expect(assigned.assignments).toHaveLength(2);

    const replaced = (
      await (
        await api(`/vod/items/${item.id}/assignments`, {
          method: "PUT",
          body: JSON.stringify({ targets: [{ type: "device", id: device.id }] }),
        })
      ).json()
    ).item;
    expect(replaced.assignments).toEqual([{ type: "device", id: device.id }]);
  });

  it("downloads a title on demand and can free it again", async () => {
    const source = await addSource();
    await api(`/vod/sources/${source.id}/import`, { method: "POST" });
    const item = (await (await api("/vod/items")).json()).items[0];

    // The mock origin ends its body straight away: a zero-byte download still
    // exercises the whole path from button to "ready".
    setTimeout(() => origin.endAll(), 5);
    const report = (await (await api(`/vod/items/${item.id}/download`, { method: "POST" })).json())
      .report;
    expect(report.ok).toBe(true);
    expect(library.item(item.id)?.state).toBe("ready");

    const freed = await (await api(`/vod/items/${item.id}/file`, { method: "DELETE" })).json();
    expect(freed.removed).toBe(true);
    expect(library.item(item.id)?.state).toBe("pending");
  });

  it("deletes an entry entirely", async () => {
    const source = await addSource();
    await api(`/vod/sources/${source.id}/import`, { method: "POST" });
    const item = (await (await api("/vod/items")).json()).items[0];

    const removed = await (await api(`/vod/items/${item.id}`, { method: "DELETE" })).json();
    expect(removed.removed).toBe(true);
    expect(library.item(item.id)).toBeNull();
  });

  it("filters the library for the panel", async () => {
    const source = await addSource();
    await api(`/vod/sources/${source.id}/import`, { method: "POST" });

    const search = await (await api("/vod/items?search=heat")).json();
    expect(search.items.map((item: { title: string }) => item.title)).toEqual(["Heat"]);

    const pending = await (await api("/vod/items?state=pending")).json();
    expect(pending.items).toHaveLength(2);
  });

  it("reports a bad request with a reason", async () => {
    const response = await api("/vod/sources", {
      method: "POST",
      body: JSON.stringify({ name: "x", url: "ftp://nope", accountId: "master" }),
    });
    expect(response.status).toBe(400);
    expect((await response.json()).detail).toMatch(/http/);
  });

  it("still refuses everything without the admin token", async () => {
    const response = await fetch(`${base}/admin/vod`);
    expect(response.status).toBe(401);
    await response.body?.cancel();
  });
});
