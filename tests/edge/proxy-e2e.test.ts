/*
 * End-to-end over real sockets: a real origin HTTP server, the real edge
 * server, and 120 real HTTP clients.
 *
 * This is the test that actually proves the product claim, because it counts
 * TCP connections accepted by the origin process rather than anything the proxy
 * reports about itself.
 */

import http from "node:http";
import type { AddressInfo } from "node:net";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { EdgeProxy } from "../../server/edge/edge.ts";
import { FetchOriginTransport } from "../../server/edge/origin.ts";
import { createEdgeServer } from "../../server/edge/server.ts";

interface OriginProbe {
  requests: Array<Record<string, string | string[] | undefined>>;
  sockets: number;
  maxSockets: number;
  maxConcurrentRequests: number;
  /**
   * Sockets the origin already had open at the instant each request arrived —
   * the moment a provider would count connections against the account. TCP
   * close is asynchronous, so this (rather than a cumulative socket peak) is
   * what says whether the edge ever presented itself twice.
   */
  socketsOnArrival: number[];
}

let origin: http.Server;
let edgeServer: http.Server;
let edge: EdgeProxy;
let edgeUrl: string;
const probe: OriginProbe = {
  requests: [],
  sockets: 0,
  maxSockets: 0,
  maxConcurrentRequests: 0,
  socketsOnArrival: [],
};
let liveRequests = 0;

/** Bytes the origin emits: a fixed pattern, so corruption is detectable. */
const FRAME = Buffer.alloc(8 * 1024, 0x41);

beforeAll(async () => {
  origin = http.createServer((req, res) => {
    probe.requests.push({ ...req.headers });
    probe.socketsOnArrival.push(probe.sockets);
    liveRequests += 1;
    probe.maxConcurrentRequests = Math.max(probe.maxConcurrentRequests, liveRequests);

    res.writeHead(200, {
      "content-type": "video/mp2t",
      // The origin tries to set a cookie; it must not reach LAN clients.
      "set-cookie": "origin_session=abc123",
      server: "test-origin/1.0",
    });
    const timer = setInterval(() => {
      if (!res.write(FRAME)) return;
    }, 5);
    const stop = () => {
      clearInterval(timer);
      liveRequests -= 1;
    };
    res.on("close", stop);
  });

  origin.on("connection", (socket) => {
    probe.sockets += 1;
    probe.maxSockets = Math.max(probe.maxSockets, probe.sockets);
    socket.on("close", () => {
      probe.sockets -= 1;
    });
  });

  await new Promise<void>((resolve) => origin.listen(0, "127.0.0.1", resolve));
  const originPort = (origin.address() as AddressInfo).port;

  edge = new EdgeProxy({
    resolveOrigin: (id) => ({ url: `http://127.0.0.1:${originPort}/live/${id}.ts` }),
    identity: { userAgent: "tvking-edge/1.0", via: "1.1 tvking-edge" },
    transport: new FetchOriginTransport({ allowedHosts: ["127.0.0.1"] }),
    maxUpstreamConnections: 1,
    lingerMs: 0,
    ring: { maxBytes: 4 * 1024 * 1024, maxChunks: 512 },
    backlogBytes: 64 * 1024,
    subscriberQueueBytes: 1024 * 1024,
    reconnect: { attempts: 0, baseDelayMs: 10, maxDelayMs: 10 },
  });

  edgeServer = createEdgeServer({
    edge,
    egressBytesPerSecond: 64 * 1024 * 1024,
    maxClients: 500,
  });
  await new Promise<void>((resolve) => edgeServer.listen(0, "127.0.0.1", resolve));
  edgeUrl = `http://127.0.0.1:${(edgeServer.address() as AddressInfo).port}`;
});

afterAll(async () => {
  await edge.shutdown();
  await new Promise<void>((resolve) => edgeServer.close(() => resolve()));
  await new Promise<void>((resolve) => origin.close(() => resolve()));
});

/** A downstream player that leaks everything a real client would leak. */
async function watch(streamId: string, wantBytes: number) {
  const controller = new AbortController();
  const response = await fetch(`${edgeUrl}/edge/${streamId}`, {
    signal: controller.signal,
    headers: {
      "user-agent": "Mozilla/5.0 (Linux; Android 12; BRAVIA 4K)",
      "x-forwarded-for": "192.168.1.44",
      cookie: "sid=6f2e1c9a",
      referer: "http://tv.lan/watch/psg-om",
      "accept-language": "fr-FR",
    },
  });

  const reader = response.body?.getReader();
  let received = 0;
  const first: number[] = [];
  if (reader) {
    while (received < wantBytes) {
      const { done, value } = await reader.read();
      if (done || !value) break;
      if (first.length === 0 && value.byteLength > 0) first.push(value[0]);
      received += value.byteLength;
    }
  }
  controller.abort();
  return { status: response.status, headers: response.headers, received, firstByte: first[0] };
}

describe("edge proxy end to end", () => {
  it(
    "serves 120 concurrent clients from ONE origin connection",
    async () => {
      const clients = await Promise.all(
        Array.from({ length: 120 }, () => watch("sport-live", 32 * 1024))
      );

      for (const client of clients) {
        expect(client.status).toBe(200);
        expect(client.received).toBeGreaterThanOrEqual(32 * 1024);
        expect(client.firstByte).toBe(0x41); // payload intact through the fan-out
      }

      // Counted by the origin process itself.
      expect(probe.requests).toHaveLength(1);
      expect(probe.maxConcurrentRequests).toBe(1);
      expect(probe.maxSockets).toBe(1);
      expect(edge.counters.activeMax).toBe(1);

      // 120 clients × 32 KiB served from one stream pulled once: the LAN moves
      // an order of magnitude more bytes than the WAN.
      const stats = edge.stats();
      expect(stats.bytesToClients).toBeGreaterThanOrEqual(120 * 32 * 1024);
      expect(stats.bytesToClients).toBeGreaterThan(stats.bytesFromOrigin * 10);
      expect(stats.bytesSaved).toBeGreaterThan(0);
    },
    30_000
  );

  it("shows the origin nothing about the clients", () => {
    const seen = probe.requests[0];

    // The whole wire, pinned: every value is a constant of the edge, so two
    // different viewers produce byte-identical upstream requests.
    expect(Object.keys(seen).sort()).toEqual(
      [
        "accept",
        "accept-encoding",
        "accept-language",
        "cache-control",
        "connection",
        "host",
        "pragma",
        "sec-fetch-mode",
        "user-agent",
        "via",
      ].sort()
    );
    expect(seen["user-agent"]).toBe("tvking-edge/1.0");
    expect(seen.via).toBe("1.1 tvking-edge");
    expect(seen["accept-encoding"]).toBe("identity");
    expect(seen["accept-language"]).toBe("*"); // constant, never the client's fr-FR

    for (const leak of ["x-forwarded-for", "forwarded", "cookie", "referer", "x-real-ip"]) {
      expect(seen[leak]).toBeUndefined();
    }
    // No client value appears anywhere in the request, under any field name.
    const wire = JSON.stringify(seen);
    for (const value of ["192.168.1.44", "6f2e1c9a", "BRAVIA", "psg-om", "fr-FR"]) {
      expect(wire).not.toContain(value);
    }
  });

  it("does not leak origin cookies or fingerprints back to clients", async () => {
    const client = await watch("sport-live", 8 * 1024);
    expect(client.headers.get("set-cookie")).toBeNull();
    expect(client.headers.get("server")).toBeNull();
    expect(client.headers.get("content-type")).toBe("video/mp2t");
    expect(client.headers.get("cache-control")).toBe("no-store");
  });

  it("reuses the live upstream when a second client joins mid-stream", async () => {
    const before = probe.requests.length;
    const controller = new AbortController();
    const first = fetch(`${edgeUrl}/edge/zap-test`, { signal: controller.signal });
    const response = await first;
    const reader = response.body?.getReader();
    await reader?.read();

    const second = await watch("zap-test", 8 * 1024);
    expect(second.received).toBeGreaterThan(0);
    expect(probe.requests.length).toBe(before + 1); // one new upstream, shared

    controller.abort();
    await reader?.cancel().catch(() => {});
  }, 20_000);

  it("exposes health and metrics without opening anything upstream", async () => {
    const before = probe.requests.length;
    const health = await fetch(`${edgeUrl}/healthz`);
    expect(await health.json()).toEqual({ status: "ok" });

    const metrics = await (await fetch(`${edgeUrl}/metrics`)).json();
    expect(metrics.upstream.limit).toBe(1);
    expect(metrics.upstream.activeMax).toBeLessThanOrEqual(1);
    expect(probe.requests.length).toBe(before);
  });

  it("validates the request line", async () => {
    // Percent-encoded traversal survives client-side path normalisation and
    // reaches the edge as "../secret" — the id charset is what rejects it.
    expect((await fetch(`${edgeUrl}/edge/%2e%2e%2fsecret`)).status).toBe(400);
    expect((await fetch(`${edgeUrl}/edge/sport live`)).status).toBe(400);
    expect((await fetch(`${edgeUrl}/nope`)).status).toBe(404);

    const post = await fetch(`${edgeUrl}/edge/sport-live`, { method: "POST" });
    expect(post.status).toBe(405);
    expect(post.headers.get("allow")).toBe("GET, HEAD");
  });

  it("answers HEAD without opening an upstream connection", async () => {
    const before = probe.requests.length;
    const head = await fetch(`${edgeUrl}/edge/never-watched`, { method: "HEAD" });
    expect(head.status).toBe(200);
    expect(probe.requests.length).toBe(before);
  });

  it("swaps channels on the single slot without closing either socket", async () => {
    // Two different channels, one master slot, real sockets on both sides.
    const first = new AbortController();
    const a = await fetch(`${edgeUrl}/edge/swap-a`, { signal: first.signal });
    const readerA = a.body?.getReader();
    expect((await readerA?.read())?.value?.byteLength).toBeGreaterThan(0);

    const second = new AbortController();
    const b = await fetch(`${edgeUrl}/edge/swap-b`, { signal: second.signal });
    const readerB = b.body?.getReader();
    const fromB = await readerB?.read();
    expect(fromB?.value?.byteLength).toBeGreaterThan(0); // the newcomer is live

    // Across the whole file: never two requests at once, and every request
    // arrived on an origin that held exactly one socket — the previous one was
    // already gone, thanks to the settle gap in the slot hand-off.
    expect(probe.maxConcurrentRequests).toBe(1);
    expect(Math.max(...probe.socketsOnArrival)).toBe(1);

    // Client A was swapped out, yet its response is neither ended nor errored:
    // it is simply quiet until the slot comes back.
    const idle = await Promise.race([
      readerA?.read().then((r) => (r.done ? "ended" : "data")),
      new Promise((resolve) => setTimeout(() => resolve("still-open"), 400)),
    ]);
    expect(idle).not.toBe("ended");

    const swapped = edge.stats().streams.find((s) => s.key === "default/swap-a");
    expect(swapped?.state).toBe("starved");
    expect(swapped?.subscribers).toBe(1);

    first.abort();
    second.abort();
    await readerA?.cancel().catch(() => {});
    await readerB?.cancel().catch(() => {});
  }, 20_000);

  it("404s an unknown stream", async () => {
    const unknown = new EdgeProxy({
      resolveOrigin: () => null,
      identity: { userAgent: "tvking-edge/1.0" },
      transport: new FetchOriginTransport({ allowedHosts: ["127.0.0.1"] }),
    });
    const server = createEdgeServer({ edge: unknown, egressBytesPerSecond: 1024 * 1024 });
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}/edge/ghost`;

    const response = await fetch(url);
    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: "unknown_stream" });

    await unknown.shutdown();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  });
});
