/*
 * Dynamic channel switching on a single master slot.
 *
 * The property under test is not just "never two upstream connections" — it is
 * "never two upstream connections AND nobody's HTTP socket is dropped". A proxy
 * that satisfies the first by killing the other viewers is not what was asked
 * for, so every test here checks the swapped-out clients too.
 */

import { describe, expect, it } from "vitest";
import { EdgeProxy, type EdgeConfig } from "../../server/edge/edge.ts";
import { ManualClock } from "../../server/edge/clock.ts";
import { MockOrigin, bytes, collect, text, tick } from "./mock-origin.ts";

function makeEdge(overrides: Partial<EdgeConfig> = {}) {
  const origin = new MockOrigin({ openDelayMs: 1 });
  const clock = new ManualClock();
  const edge = new EdgeProxy({
    accounts: [
      {
        id: "master",
        label: "Ligne maître",
        channelTemplate: "https://origin.example/live/{id}.ts",
        maxConnections: 1,
        device: "vlc",
      },
    ],
    transport: origin,
    ring: { maxBytes: 512 * 1024, maxChunks: 256 },
    backlogBytes: 32 * 1024,
    subscriberQueueBytes: 128 * 1024,
    lingerMs: 0,
    starveGraceMs: 20_000,
    swapSettleMs: 0, // the e2e covers the real settle gap over sockets
    slotWaitMs: 5_000,
    clock,
    reconnect: { attempts: 0, baseDelayMs: 10, maxDelayMs: 10 },
    ...overrides,
  });
  return { edge, origin, clock };
}

function stream(edge: EdgeProxy, key: string) {
  return edge.stats().streams.find((s) => s.key === key);
}

describe("dynamic channel switching on one slot", () => {
  it("swaps the upstream without dropping the other client's socket", async () => {
    const { edge, origin } = makeEdge();

    const one = await edge.subscribe("master/tf1");
    origin.push(bytes("tf1-buffered"), "tf1");
    await tick(3);

    // A second client asks for another channel while the only slot is busy.
    const two = await edge.subscribe("master/m6");
    await tick(3);

    expect(edge.counters.activeMax).toBe(1); // the invariant holds through the swap
    expect(edge.counters.active).toBe(1);
    expect(origin.openUrls).toEqual([expect.stringContaining("m6")]);

    // The swapped-out client is still attached: socket alive, hub starved.
    expect(one.subscription.closed).toBe(false);
    expect(stream(edge, "master/tf1")?.state).toBe("starved");
    expect(stream(edge, "master/tf1")?.subscribers).toBe(1);
    expect(stream(edge, "master/m6")?.state).toBe("live");

    // ...and it can still play what the edge buffered before the switch.
    expect(text(await collect(one.subscription, "tf1-buffered".length))).toBe("tf1-buffered");

    two.subscription.close();
    await edge.shutdown();
  });

  it("brings the swapped-out channel back when the slot frees", async () => {
    const { edge, origin } = makeEdge();

    const one = await edge.subscribe("master/tf1");
    const two = await edge.subscribe("master/m6");
    await tick(3);
    expect(stream(edge, "master/tf1")?.state).toBe("starved");

    two.subscription.close(); // lingerMs 0 → the slot comes free
    await tick(10);

    expect(stream(edge, "master/tf1")?.state).toBe("live");
    expect(edge.counters.activeMax).toBe(1);
    expect(one.subscription.closed).toBe(false);

    // Fresh upstream data reaches the client that never disconnected.
    origin.push(bytes("back-on-air"), "tf1");
    await tick(3);
    expect(text(await collect(one.subscription, 11))).toBe("back-on-air");

    await edge.shutdown();
  });

  it("reports the swap in the account's slot metrics", async () => {
    const { edge } = makeEdge();
    const one = await edge.subscribe("master/tf1");
    const two = await edge.subscribe("master/m6");
    await tick(3);

    const account = edge.overview().accounts.find((a) => a.id === "master");
    expect(account?.slots.capacity).toBe(1);
    expect(account?.slots.available).toBe(0);
    expect(account?.slots.swaps).toBe(1);
    expect(account?.activeChannels).toEqual(["m6"]);
    expect(stream(edge, "master/tf1")?.starves).toBe(1);

    one.subscription.close();
    two.subscription.close();
    await edge.shutdown();
  });

  it("marks the stalled session as such without naming the viewer", async () => {
    const { edge } = makeEdge();
    const one = await edge.subscribe("master/tf1");
    const two = await edge.subscribe("master/m6");
    await tick(3);

    const sessions = edge.sessions();
    expect(sessions).toHaveLength(2);
    const stalled = sessions.find((s) => s.channel === "tf1");
    expect(stalled?.stalled).toBe(true);
    expect(sessions.find((s) => s.channel === "m6")?.stalled).toBe(false);
    // The session record carries nothing that identifies a person.
    expect(Object.keys(sessions[0]).sort()).toEqual(
      [
        "account",
        "bytesDelivered",
        "channel",
        "droppedBytes",
        "id",
        "lagEvents",
        "queuedBytes",
        "stalled",
        "startedAt",
      ].sort()
    );

    one.subscription.close();
    two.subscription.close();
    await edge.shutdown();
  });

  it("ends a starved client honestly once the grace period expires", async () => {
    const { edge, clock } = makeEdge({ starveGraceMs: 5_000 });

    const one = await edge.subscribe("master/tf1");
    const ended = collect(one.subscription, 1024).then(
      () => "ended-clean",
      (error: unknown) => String(error)
    );
    const two = await edge.subscribe("master/m6"); // holds the slot for good
    await tick(3);

    await clock.advance(5_001);
    await tick(5);

    expect(await ended).toMatch(/lost its slot/);
    expect(stream(edge, "master/tf1")?.state).toBe("idle");
    expect(edge.counters.activeMax).toBe(1);

    two.subscription.close();
    await edge.shutdown();
  });

  it("stops queueing for a slot once the last starved client leaves", async () => {
    const { edge } = makeEdge();
    const one = await edge.subscribe("master/tf1");
    const two = await edge.subscribe("master/m6");
    await tick(3);
    expect(stream(edge, "master/tf1")?.state).toBe("starved");

    one.subscription.close();
    await tick(5);
    expect(stream(edge, "master/tf1")?.state).toBe("idle");

    // The abandoned channel must not steal the slot back from the live one.
    await tick(10);
    expect(stream(edge, "master/m6")?.state).toBe("live");
    expect(edge.counters.activeMax).toBe(1);

    two.subscription.close();
    await edge.shutdown();
  });

  it("does not swap when several clients share the SAME channel", async () => {
    const { edge, origin } = makeEdge();
    const clients = await Promise.all(
      Array.from({ length: 50 }, () => edge.subscribe("master/tf1"))
    );
    await tick(3);

    expect(origin.opens).toBe(1);
    expect(edge.counters.activeMax).toBe(1);
    expect(edge.overview().accounts[0].slots.swaps).toBe(0);
    expect(stream(edge, "master/tf1")?.subscribers).toBe(50);

    for (const client of clients) client.subscription.close();
    await edge.shutdown();
  });

  it("keeps 60 zapping clients connected across 6 channels on one slot", async () => {
    // Zapping is sequential by nature: each new request swaps the upstream.
    // What must never happen is a client already watching losing its socket.
    const { edge, origin } = makeEdge({ starveGraceMs: 120_000 });
    const channels = ["tf1", "m6", "canal", "arte", "bein1", "rmc"];
    const clients = [];

    for (let i = 0; i < 60; i += 1) {
      clients.push(await edge.subscribe(`master/${channels[i % channels.length]}`));
      origin.push(bytes("frame"));
      await tick(1);
      expect(edge.counters.active).toBeLessThanOrEqual(1);
      expect(clients.every((client) => !client.subscription.closed)).toBe(true);
    }

    expect(edge.counters.activeMax).toBe(1); // one connection, the whole time
    expect(origin.activeMax).toBe(1);
    expect(edge.sessions()).toHaveLength(60);
    // Exactly one channel live; the rest starved with their viewers attached.
    expect(edge.stats().streams.filter((s) => s.state === "live")).toHaveLength(1);
    expect(edge.stats().streams.filter((s) => s.state === "starved").length).toBe(5);

    for (const client of clients) client.subscription.close();
    await edge.shutdown();
  }, 20_000);

  it("never interrupts a viewer under the reject policy", async () => {
    const { edge } = makeEdge({
      accounts: [
        {
          id: "master",
          channelTemplate: "https://origin.example/live/{id}.ts",
          maxConnections: 1,
          contention: "reject",
        },
      ],
    });

    const one = await edge.subscribe("master/tf1");
    await expect(edge.subscribe("master/m6")).rejects.toThrow(/no free slot/);
    expect(one.subscription.closed).toBe(false);
    expect(stream(edge, "master/tf1")?.state).toBe("live");

    one.subscription.close();
    await edge.shutdown();
  });

  it("keeps accounts independent: one slot each, no cross-eviction", async () => {
    const { edge, origin } = makeEdge({
      accounts: [
        { id: "a", channelTemplate: "https://a.example/{id}.ts", maxConnections: 1 },
        { id: "b", channelTemplate: "https://b.example/{id}.ts", maxConnections: 1 },
      ],
    });

    const one = await edge.subscribe("a/tf1");
    const two = await edge.subscribe("b/tf1");
    await tick(3);

    expect(edge.counters.activeMax).toBe(2); // one per master line, as configured
    expect(edge.upstreamLimit).toBe(2);
    expect(stream(edge, "a/tf1")?.state).toBe("live");
    expect(stream(edge, "b/tf1")?.state).toBe("live");
    expect(origin.openUrls.sort()).toEqual([
      "https://a.example/tf1.ts",
      "https://b.example/tf1.ts",
    ]);

    one.subscription.close();
    two.subscription.close();
    await edge.shutdown();
  });
});
