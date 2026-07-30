/*
 * EdgeProxy: the process-wide upstream cap, on top of the per-stream hub.
 */

import { describe, expect, it } from "vitest";
import { EdgeProxy, UnknownStreamError, type EdgeConfig } from "../../server/edge/edge.ts";
import { ManualClock } from "../../server/edge/clock.ts";
import { MockOrigin, bytes, collect, text, tick } from "./mock-origin.ts";

function makeEdge(overrides: Partial<EdgeConfig> = {}, origin = new MockOrigin({ openDelayMs: 2 })) {
  const edge = new EdgeProxy({
    resolveOrigin: (id) => ({ url: `https://origin.example/live/${id}.ts` }),
    identity: { userAgent: "tvking-edge/1.0" },
    transport: origin,
    maxUpstreamConnections: 1,
    slotWaitMs: 80,
    ring: { maxBytes: 512 * 1024, maxChunks: 256 },
    backlogBytes: 32 * 1024,
    subscriberQueueBytes: 128 * 1024,
    lingerMs: 0,
    reconnect: { attempts: 2, baseDelayMs: 10, maxDelayMs: 20 },
    ...overrides,
  });
  return { edge, origin };
}

describe("EdgeProxy — collapsing", () => {
  it("serves 200 concurrent clients of one stream from a single connection", async () => {
    const { edge, origin } = makeEdge();

    const joined = await Promise.all(
      Array.from({ length: 200 }, () => edge.subscribe("sport-live"))
    );
    expect(edge.stats().downstreamClients).toBe(200);

    const readers = joined.map((j) => collect(j.subscription, 5));
    origin.push(bytes("HELLO"));
    await tick(5);

    for (const chunks of await Promise.all(readers)) expect(text(chunks)).toBe("HELLO");
    expect(edge.counters.opens).toBe(1);
    expect(edge.counters.activeMax).toBe(1);
    expect(origin.requests).toHaveLength(1);

    // Read after the clients have taken their bytes and detached.
    const stats = edge.stats();
    expect(stats.bytesFromOrigin).toBe(5);
    expect(stats.bytesToClients).toBe(1000);
    expect(stats.bytesSaved).toBe(995); // 995 B that never crossed the WAN

    await edge.shutdown();
  });

  it("resolves the origin once for a herd of cold joins", async () => {
    let resolves = 0;
    const { edge } = makeEdge({
      // Async on purpose: real deployments mint a token or fetch a playlist here.
      resolveOrigin: async (id) => {
        resolves += 1;
        await tick(3);
        return { url: `https://origin.example/live/${id}.ts` };
      },
    });

    await Promise.all(Array.from({ length: 100 }, () => edge.subscribe("formation-1")));
    expect(resolves).toBe(1);
    expect(edge.counters.opens).toBe(1);

    await edge.shutdown();
  });

  it("rejects an unknown stream without touching the WAN", async () => {
    const { edge } = makeEdge({ resolveOrigin: () => null });
    await expect(edge.subscribe("nope")).rejects.toBeInstanceOf(UnknownStreamError);
    expect(edge.counters.opens).toBe(0);
    await edge.shutdown();
  });
});

describe("EdgeProxy — process-wide upstream cap", () => {
  it("never exceeds one connection while zapping across channels", async () => {
    const { edge, origin } = makeEdge();
    const channels = ["sport-live", "formation-1", "sport-replay", "formation-2", "sport-live"];

    for (const channel of channels) {
      const { subscription } = await edge.subscribe(channel);
      origin.push(bytes("frame"));
      await tick(2);
      subscription.close();
      await tick(4); // lingerMs 0 → upstream released on the way out
      expect(edge.counters.active).toBeLessThanOrEqual(1);
    }

    expect(edge.counters.activeMax).toBe(1);
    await edge.shutdown();
  });

  it("evicts an unwatched lingering stream instead of opening a second connection", async () => {
    const clock = new ManualClock();
    const { edge, origin } = makeEdge({ lingerMs: 60_000, clock });

    const first = await edge.subscribe("sport-live");
    first.subscription.close();
    await tick(4);
    expect(edge.counters.active).toBe(1); // lingering, nobody watching

    const second = await edge.subscribe("formation-1");
    origin.push(bytes("x"));
    await tick(4);

    expect(edge.counters.active).toBe(1);
    expect(edge.counters.activeMax).toBe(1); // evicted, not stacked
    expect(edge.counters.opens).toBe(2);
    expect(edge.stats().streams.find((s) => s.key === "sport-live")?.state).toBe("idle");

    second.subscription.close();
    await edge.shutdown();
  });

  it("refuses a second live stream rather than opening a second connection", async () => {
    const { edge } = makeEdge({ lingerMs: 60_000 });
    const watched = await edge.subscribe("sport-live"); // held open by a viewer

    await expect(edge.subscribe("formation-1")).rejects.toThrow(/upstream connection limit/);
    expect(edge.counters.activeMax).toBe(1);

    watched.subscription.close();
    await edge.shutdown();
  });

  it("honours a higher cap when the deployment asks for one", async () => {
    const { edge, origin } = makeEdge({ maxUpstreamConnections: 2, lingerMs: 60_000 });

    const a = await edge.subscribe("sport-live");
    const b = await edge.subscribe("formation-1");
    origin.push(bytes("y"));
    await tick(4);

    expect(edge.counters.activeMax).toBe(2);
    expect(edge.upstreamLimit).toBe(2);

    a.subscription.close();
    b.subscription.close();
    await edge.shutdown();
  });

  it("frees the slot again after a stream is released", async () => {
    const { edge } = makeEdge({ lingerMs: 0 });
    const a = await edge.subscribe("sport-live");
    a.subscription.close();
    await tick(6);

    const b = await edge.subscribe("formation-1"); // must not need to wait
    expect(edge.counters.activeMax).toBe(1);
    b.subscription.close();
    await edge.shutdown();
  });

  it("holds the cap under 150 concurrent joins spread over 6 channels", async () => {
    // Deliberately over-subscribed: with one slot, most of these must fail
    // rather than quietly opening a second WAN connection.
    const { edge, origin } = makeEdge({ lingerMs: 0, slotWaitMs: 40 });
    const channels = ["a", "b", "c", "d", "e", "f"];

    const outcomes = await Promise.allSettled(
      Array.from({ length: 150 }, async (_, i) => {
        const joined = await edge.subscribe(channels[i % channels.length]);
        origin.push(bytes("z"));
        await tick(3);
        joined.subscription.close();
      })
    );
    await tick(20);

    expect(edge.counters.activeMax).toBe(1); // the invariant, under contention
    expect(outcomes.some((o) => o.status === "fulfilled")).toBe(true);
    for (const outcome of outcomes) {
      if (outcome.status === "rejected") {
        expect(String(outcome.reason)).toMatch(/upstream connection limit/);
      }
    }

    await edge.shutdown();
  });
});

describe("EdgeProxy — lifecycle", () => {
  it("shutdown ends subscriptions and refuses new ones", async () => {
    const { edge } = makeEdge();
    const joined = await edge.subscribe("sport-live");
    const reader = collect(joined.subscription, 1024);

    await edge.shutdown();
    await reader;

    expect(edge.counters.active).toBe(0);
    await expect(edge.subscribe("sport-live")).rejects.toThrow(/shutting down/);
  });
});
