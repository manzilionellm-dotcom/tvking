/*
 * Subscriber portals over real HTTP: an Xtream player and a MAG box, both
 * authenticating against the same device book, both cut off when the clock says
 * the subscription is over.
 */

import http from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { ManualWallClock } from "../../server/edge/clock.ts";
import { openDatabase, type Database } from "../../server/edge/db/database.ts";
import { EdgeProxy } from "../../server/edge/edge.ts";
import { createEdgeServer } from "../../server/edge/server.ts";
import { PortalRepository } from "../../server/edge/portal/devices.ts";
import { ExpirationEnforcer } from "../../server/edge/portal/enforcer.ts";
import { createXtreamRouter } from "../../server/edge/portal/xtream.ts";
import { createStalkerRouter, macFromCookie } from "../../server/edge/portal/stalker.ts";
import { numericId } from "../../server/edge/portal/context.ts";
import { VodLibrary } from "../../server/edge/vod/library.ts";
import { MockOrigin, bytes, tick } from "./mock-origin.ts";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

const PLAYLIST = `#EXTM3U
#EXTINF:-1 tvg-id="tf1" group-title="Généralistes",TF1
http://origin.example/live/tf1.ts
#EXTINF:-1 tvg-id="bein1" group-title="Sport",beIN SPORTS 1
http://origin.example/live/bein1.ts
`;

const MAC = "00:1A:79:AA:BB:CC";

let db: Database;
let clock: ManualWallClock;
let repo: PortalRepository;
let library: VodLibrary;
let vodFile: string;
let vodDir: string;
let edge: EdgeProxy;
let origin: MockOrigin;
let server: http.Server;
let base: string;
let enforcer: ExpirationEnforcer;
let deviceId: number;

beforeEach(async () => {
  db = openDatabase(":memory:");
  clock = new ManualWallClock("2026-06-01T12:00:00Z");
  repo = new PortalRepository(db, clock);
  library = new VodLibrary(db, clock);
  origin = new MockOrigin({ openDelayMs: 1 });
  vodDir = await mkdtemp(path.join(tmpdir(), "tvking-portal-vod-"));

  edge = new EdgeProxy({
    accounts: [
      {
        id: "master",
        label: "Ligne maître",
        playlistUrl: "http://origin.example/playlist.m3u",
        maxConnections: 4,
        device: "vlc",
      },
    ],
    transport: origin,
    lingerMs: 0,
    swapSettleMs: 0,
  });
  // Feed the channel map: the registry fetches it through the slot budget.
  const feed = setInterval(() => {
    origin.push(new TextEncoder().encode(PLAYLIST), "playlist");
    origin.endAll();
  }, 2);

  const pack = repo.upsertPackage({ name: "full", accountId: "master" });
  const device = repo.createDevice({
    mac: MAC,
    username: "client01",
    password: "s3cret",
    label: "Salon",
    packageId: pack.id,
    maxConnections: 1,
  });
  deviceId = device.id;
  repo.grant(device.id, "trial-24h");

  // A manually curated library: imported, downloaded, then explicitly shared.
  const source = library.addSource({
    name: "vod",
    url: "http://o/vod.m3u",
    accountId: "master",
  });
  const imported = library.registerItem(source.id, {
    name: "Le Grand Bleu (1988)",
    url: "http://origin.example/movie/u/p/1.mkv",
    group: "VOD | ACTION",
  }).item;
  vodFile = path.join(vodDir, `${imported.id}.mkv`);
  await writeFile(vodFile, Buffer.alloc(2048, 0x42));
  library.setState(imported.id, "ready", {
    filePath: vodFile,
    bytesTotal: 2048,
    bytesDone: 2048,
    downloadedAt: clock.now(),
  });
  library.assign(imported.id, [{ type: "package", id: pack.id }]);

  const context = {
    repo,
    library,
    edge,
    wallClock: clock,
    egressBytesPerSecond: 16 * 1024 * 1024,
  };
  enforcer = new ExpirationEnforcer({ repo, edge, wallClock: clock });

  server = createEdgeServer({
    edge,
    egressBytesPerSecond: 16 * 1024 * 1024,
    portals: [createXtreamRouter(context), createStalkerRouter(context)],
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;

  // Warm the channel map once so each test starts from a known catalogue.
  await edge.channels("master").catch(() => []);
  clearInterval(feed);
});

afterEach(async () => {
  await edge.shutdown();
  await new Promise<void>((resolve) => server.close(() => resolve()));
  db.close();
  await rm(vodDir, { recursive: true, force: true });
});

async function watch(url: string, wantBytes = 4): Promise<{ status: number; received: number }> {
  const controller = new AbortController();
  // The mock origin only delivers to connections that are already open, so the
  // feed has to run across the whole exchange.
  const feed = setInterval(() => origin.push(bytes("data")), 3);
  try {
    const response = await fetch(url, { signal: controller.signal });
    let received = 0;
    if (!response.ok || !response.body) {
      await response.body?.cancel().catch(() => {});
      return { status: response.status, received };
    }
    const reader = response.body.getReader();
    const pump = (async () => {
      while (received < wantBytes) {
        const { done, value } = await reader.read();
        if (done || !value) break;
        received += value.byteLength;
      }
    })();
    await Promise.race([pump, tick(1000)]);
    controller.abort();
    await reader.cancel().catch(() => {});
    return { status: response.status, received };
  } finally {
    clearInterval(feed);
  }
}

describe("Xtream Codes API", () => {
  it("authenticates and reports the subscription", async () => {
    const info = await (
      await fetch(`${base}/player_api.php?username=client01&password=s3cret`)
    ).json();

    expect(info.user_info.auth).toBe(1);
    expect(info.user_info.status).toBe("Active");
    expect(info.user_info.is_trial).toBe("1");
    expect(info.user_info.max_connections).toBe("1");
    expect(Number(info.user_info.exp_date) * 1000).toBe(
      Date.parse("2026-06-02T12:00:00Z") // exactly 24 h
    );
    expect(info.server_info.timezone).toBe("UTC");
  });

  it("refuses a wrong password without leaking whether the user exists", async () => {
    const bad = await (
      await fetch(`${base}/player_api.php?username=client01&password=nope`)
    ).json();
    const missing = await (
      await fetch(`${base}/player_api.php?username=ghost&password=nope`)
    ).json();
    expect(bad.user_info.auth).toBe(0);
    expect(missing.user_info.auth).toBe(0);
  });

  it("lists live categories and streams from the package", async () => {
    const categories = await (
      await fetch(`${base}/player_api.php?username=client01&password=s3cret&action=get_live_categories`)
    ).json();
    expect(categories.map((c: { category_name: string }) => c.category_name).sort()).toEqual([
      "Généralistes",
      "Sport",
    ]);

    const streams = await (
      await fetch(`${base}/player_api.php?username=client01&password=s3cret&action=get_live_streams`)
    ).json();
    expect(streams.map((s: { name: string }) => s.name)).toEqual(["TF1", "beIN SPORTS 1"]);
    expect(streams[0].stream_id).toBe(numericId("tf1"));
  });

  it("lists the local VOD library", async () => {
    const movies = await (
      await fetch(`${base}/player_api.php?username=client01&password=s3cret&action=get_vod_streams`)
    ).json();
    expect(movies).toHaveLength(1);
    expect(movies[0].name).toBe("Le Grand Bleu (1988)");
    expect(movies[0].container_extension).toBe("mkv");
  });

  it("serves a downloaded film from disk, with Range", async () => {
    const id = library.items()[0].id;
    const response = await fetch(`${base}/movie/client01/s3cret/${id}.mkv`, {
      headers: { range: "bytes=0-99" },
    });
    expect(response.status).toBe(206);
    expect(response.headers.get("content-range")).toBe("bytes 0-99/2048");
    expect(new Uint8Array(await response.arrayBuffer())[0]).toBe(0x42);
  });

  it("hides a title that is not assigned to the subscriber", async () => {
    const id = library.items()[0].id;
    library.setAssignments(id, []);

    const movies = await (
      await fetch(`${base}/player_api.php?username=client01&password=s3cret&action=get_vod_streams`)
    ).json();
    expect(movies).toEqual([]);

    const response = await fetch(`${base}/movie/client01/s3cret/${id}.mkv`);
    expect(response.status).toBe(404);
  });

  it("hides a title that has not been downloaded", async () => {
    const id = library.items()[0].id;
    library.setState(id, "pending", { filePath: null, bytesDone: 0 });

    const movies = await (
      await fetch(`${base}/player_api.php?username=client01&password=s3cret&action=get_vod_streams`)
    ).json();
    expect(movies).toEqual([]);
  });

  it("generates an m3u_plus playlist pointing back at the edge", async () => {
    const playlist = await (
      await fetch(`${base}/get.php?username=client01&password=s3cret&type=m3u_plus`)
    ).text();

    expect(playlist.startsWith("#EXTM3U")).toBe(true);
    expect(playlist).toContain(`/live/client01/s3cret/${numericId("tf1")}.ts`);
    expect(playlist).toContain("/movie/client01/s3cret/");
    // The provider's own URLs must never appear in what a client receives.
    expect(playlist).not.toContain("origin.example");
  });

  it("streams a live channel for a valid subscriber", async () => {
    const result = await watch(`${base}/live/client01/s3cret/${numericId("tf1")}.ts`);
    expect(result.status).toBe(200);
    expect(result.received).toBeGreaterThan(0);
    expect(edge.counters.activeMax).toBe(1);
  });

  it("refuses the stream once the subscription has expired", async () => {
    clock.advance(25 * 3_600_000);
    const response = await fetch(`${base}/live/client01/s3cret/${numericId("tf1")}.ts`);
    expect(response.status).toBe(403);
    expect((await response.json()).detail).toMatch(/expired/);
    // The only upstream connection ever opened was the channel-map refresh.
    expect(edge.stats().streams).toHaveLength(0);
  });

  it("enforces the per-device connection limit", async () => {
    const controller = new AbortController();
    const first = await fetch(`${base}/live/client01/s3cret/${numericId("tf1")}.ts`, {
      signal: controller.signal,
    });
    expect(first.status).toBe(200);
    const reader = first.body?.getReader();
    origin.push(bytes("x"));
    await reader?.read();

    const second = await fetch(`${base}/live/client01/s3cret/${numericId("bein1")}.ts`);
    expect(second.status).toBe(429); // maxConnections is 1
    await second.body?.cancel();

    controller.abort();
    await reader?.cancel().catch(() => {});
  }, 20_000);

  it("404s a channel that is not in the package", async () => {
    const response = await fetch(`${base}/live/client01/s3cret/999999.ts`);
    expect(response.status).toBe(404);
  });
});

describe("Stalker / MAG portal", () => {
  const cookie = `mac=${encodeURIComponent(MAC)}; stb_lang=fr`;

  async function portal(query: string, token?: string) {
    const response = await fetch(`${base}/portal.php?${query}`, {
      headers: {
        cookie,
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
    });
    return response.json();
  }

  it("reads the MAC out of the cookie", () => {
    expect(macFromCookie("mac=00%3A1A%3A79%3AAA%3ABB%3ACC; stb_lang=fr")).toBe(MAC);
    expect(macFromCookie("mac=001A79AABBCC")).toBe(MAC);
    expect(macFromCookie("stb_lang=fr")).toBeNull();
    expect(macFromCookie(undefined)).toBeNull();
  });

  it("hands out a token then a profile carrying the expiry", async () => {
    const handshake = await portal("type=stb&action=handshake");
    expect(handshake.js.token).toMatch(/^[0-9a-f]{32}$/);

    const profile = await portal("type=stb&action=get_profile", handshake.js.token);
    expect(profile.js.status).toBe(0); // 0 = allowed
    expect(profile.js.mac).toBe(MAC);
    expect(profile.js.phone).toBe("2026-06-02 12:00:00"); // the trial's end
  });

  it("tells an expired box why it is blocked", async () => {
    clock.advance(25 * 3_600_000);
    const profile = await portal("type=stb&action=get_profile");
    expect(profile.js.status).toBe(1);
    expect(profile.js.block_reason).toMatch(/expired/);
  });

  it("refuses an unregistered MAC", async () => {
    const response = await fetch(`${base}/portal.php?type=stb&action=get_profile`, {
      headers: { cookie: "mac=00%3A11%3A22%3A33%3A44%3A55" },
    });
    const body = await response.json();
    expect(body.js.status).toBe(1);
  });

  it("lists channels with playable ffmpeg links", async () => {
    const handshake = await portal("type=stb&action=handshake");
    const list = await portal("type=itv&action=get_all_channels", handshake.js.token);

    expect(list.js.total_items).toBe(2);
    expect(list.js.data[0].name).toBe("TF1");
    expect(list.js.data[0].cmd).toMatch(/^ffmpeg http:\/\/.*\/stalker\/stream\/[0-9a-f]{32}\/live\/\d+$/);
    // The provider URL is never handed to the box.
    expect(JSON.stringify(list.js.data)).not.toContain("origin.example");
  });

  it("streams through the link it issued", async () => {
    const handshake = await portal("type=stb&action=handshake");
    const list = await portal("type=itv&action=get_all_channels", handshake.js.token);
    const url = String(list.js.data[0].cmd).replace("ffmpeg ", "");

    const result = await watch(url);
    expect(result.status).toBe(200);
    expect(result.received).toBeGreaterThan(0);
  });

  it("refuses a link whose token was issued for nobody", async () => {
    const response = await fetch(`${base}/stalker/stream/deadbeef/live/1`);
    expect(response.status).toBe(403);
  });

  it("stops honouring issued links once the subscription expires", async () => {
    const handshake = await portal("type=stb&action=handshake");
    const list = await portal("type=itv&action=get_all_channels", handshake.js.token);
    const url = String(list.js.data[0].cmd).replace("ffmpeg ", "");

    clock.advance(25 * 3_600_000);
    const response = await fetch(url);
    expect(response.status).toBe(403);
    await response.body?.cancel();
  });

  it("exposes the local library to a MAG box", async () => {
    const handshake = await portal("type=stb&action=handshake");
    const categories = await portal("type=vod&action=get_categories", handshake.js.token);
    expect(categories.js[0].title).toBe("Action");

    const list = await portal("type=vod&action=get_ordered_list", handshake.js.token);
    expect(list.js.data[0].name).toBe("Le Grand Bleu");
    expect(list.js.data[0].cmd).toMatch(/\/stalker\/stream\/[0-9a-f]{32}\/movie\/\d+$/);
  });

  it("plays a downloaded film through the link it issued", async () => {
    const handshake = await portal("type=stb&action=handshake");
    const list = await portal("type=vod&action=get_ordered_list", handshake.js.token);
    const response = await fetch(String(list.js.data[0].cmd), { headers: { range: "bytes=0-9" } });

    expect(response.status).toBe(206);
    expect((await response.arrayBuffer()).byteLength).toBe(10);
  });

  it("answers unknown actions with an empty payload instead of an error", async () => {
    const response = await portal("type=stb&action=nonsense");
    expect(response.js).toEqual({});
  });
});

describe("expiration cuts live portal streams", () => {
  it("drops a MAG stream mid-playback when the trial runs out", async () => {
    const handshake = await fetch(`${base}/portal.php?type=stb&action=handshake`, {
      headers: { cookie: `mac=${encodeURIComponent(MAC)}` },
    }).then((r) => r.json());
    const list = await fetch(`${base}/portal.php?type=itv&action=get_all_channels`, {
      headers: { cookie: `mac=${encodeURIComponent(MAC)}`, authorization: `Bearer ${handshake.js.token}` },
    }).then((r) => r.json());

    const controller = new AbortController();
    const response = await fetch(String(list.js.data[0].cmd).replace("ffmpeg ", ""), {
      signal: controller.signal,
    });
    const reader = response.body?.getReader();
    origin.push(bytes("frame"));
    await reader?.read();
    expect(edge.sessionsForDevice(deviceId)).toHaveLength(1);

    // The clock moves past the end of the trial while the box is watching.
    clock.advance(24 * 3_600_000 + 1000);
    const swept = enforcer.sweep();

    expect(swept.droppedSessions).toBe(1);
    expect(swept.devices[0].reason).toBe("expired");
    expect(edge.sessionsForDevice(deviceId)).toHaveLength(0);

    // The socket ends rather than hanging: the reader sees EOF.
    const tail = await Promise.race([
      reader?.read().then(() => "data-or-eof"),
      tick(500).then(() => "still-open"),
    ]);
    expect(tail).toBe("data-or-eof");

    controller.abort();
    await reader?.cancel().catch(() => {});
  }, 20_000);
});
