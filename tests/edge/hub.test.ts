/*
 * The single-upstream invariant, at the hub level.
 *
 * Every test here measures the invariant at the transport boundary
 * (`countingTransport`), i.e. the number of connections the origin could
 * actually observe — not an internal flag the implementation controls.
 */

import { describe, expect, it } from "vitest";
import { ManualClock } from "../../server/edge/clock.ts";
import { StreamHub, type StreamHubOptions } from "../../server/edge/hub.ts";
import { countingTransport, createCounters, type UpstreamCounters } from "../../server/edge/origin.ts";
import type { Subscription } from "../../server/edge/broadcast.ts";
import { MockOrigin, bytes, collect, text, tick } from "./mock-origin.ts";

interface Harness {
  hub: StreamHub;
  origin: MockOrigin;
  counters: UpstreamCounters;
  clock: ManualClock;
}

function makeHub(overrides: Partial<StreamHubOptions> = {}, originDelayMs = 2): Harness {
  const origin = new MockOrigin({ openDelayMs: originDelayMs });
  const counters = createCounters();
  const clock = new ManualClock();
  const hub = new StreamHub({
    key: "sport-live",
    url: "https://origin.example/live/sport.ts",
    transport: countingTransport(origin, counters),
    identity: { userAgent: "tvking-edge/1.0" },
    ring: { maxBytes: 1024 * 1024, maxChunks: 512 },
    backlogBytes: 64 * 1024,
    subscriberQueueBytes: 256 * 1024,
    lingerMs: 10_000,
    reconnect: { attempts: 3, baseDelayMs: 100, maxDelayMs: 1000 },
    clock,
    ...overrides,
  });
  return { hub, origin, counters, clock };
}

describe("StreamHub — single upstream connection", () => {
  it("opens exactly ONE upstream for 150 clients joining at once", async () => {
    const { hub, origin, counters } = makeHub();

    const subs = await Promise.all(Array.from({ length: 150 }, () => hub.join()));

    expect(subs).toHaveLength(150);
    expect(hub.subscribers).toBe(150);
    expect(origin.opens).toBe(1);
    expect(origin.requests).toHaveLength(1);
    expect(counters.opens).toBe(1);
    expect(counters.activeMax).toBe(1); // the invariant
    expect(counters.active).toBe(1);

    await hub.close();
  });

  it("fans the same bytes out to all of them", async () => {
    const { hub, origin, counters } = makeHub();
    const subs = await Promise.all(Array.from({ length: 120 }, () => hub.join()));
    const readers = subs.map((sub) => collect(sub, 6));

    origin.push(bytes("abc"));
    origin.push(bytes("def"));
    await tick(5);

    const results = await Promise.all(readers);
    for (const chunks of results) expect(text(chunks)).toBe("abcdef");

    // 6 bytes crossed the WAN; 720 were served on the LAN.
    expect(counters.bytes).toBe(6);
    expect(hub.stats().bytesFannedOut).toBe(720);

    await hub.close();
  });

  it("stays at one upstream when clients trickle in over time", async () => {
    const { hub, origin, counters } = makeHub();
    const subs: Subscription[] = [];
    for (let i = 0; i < 40; i += 1) {
      subs.push(await hub.join());
      if (i % 5 === 0) origin.push(bytes(`chunk${i}`));
      await tick(1);
    }
    expect(counters.opens).toBe(1);
    expect(counters.activeMax).toBe(1);
    await hub.close();
  });

  it("holds the invariant through random join/leave churn", async () => {
    // linger 0: every empty moment tears the upstream down, so this hammers the
    // start/stop transitions — the window where a second connection would slip in.
    const { hub, origin, counters } = makeHub({ lingerMs: 0 }, 1);

    let seed = 42;
    const random = () => {
      seed = (seed * 1103515245 + 12345) % 2147483648;
      return seed / 2147483648;
    };

    await Promise.all(
      Array.from({ length: 200 }, async (_, i) => {
        await tick(Math.floor(random() * 8));
        const sub = await hub.join();
        origin.push(bytes(`x${i}`));
        await tick(Math.floor(random() * 8));
        sub.close();
      })
    );
    await tick(20);

    expect(counters.activeMax).toBe(1); // the invariant, under race
    expect(counters.opens).toBeGreaterThan(0);
    await hub.close();
  });

  it("hands a joining client the buffered tail for an instant start", async () => {
    const { hub, origin } = makeHub();
    const first = await hub.join();
    origin.push(bytes("already-playing"));
    await tick(5);

    const late = await hub.join();
    const seen = text(await collect(late, "already-playing".length));
    expect(seen).toBe("already-playing"); // no upstream re-request needed
    expect(origin.opens).toBe(1);

    first.close();
    await hub.close();
  });
});

describe("StreamHub — zapping and linger", () => {
  it("keeps the upstream open while lingering, and reuses it on return", async () => {
    const { hub, origin, counters, clock } = makeHub({ lingerMs: 5_000 });

    const first = await hub.join();
    first.close();
    await tick(2);

    expect(hub.stats().lingering).toBe(true);
    expect(counters.active).toBe(1); // still connected: zapping window

    await clock.advance(1_000);
    const back = await hub.join();
    expect(origin.opens).toBe(1); // no new TCP/TLS handshake
    expect(counters.opens).toBe(1);
    expect(hub.stats().lingering).toBe(false);

    back.close();
    await hub.close();
  });

  it("closes the upstream once the linger window expires", async () => {
    const { hub, counters, clock } = makeHub({ lingerMs: 5_000 });

    const sub = await hub.join();
    sub.close();
    await tick(2);
    expect(counters.active).toBe(1);

    await clock.advance(5_001);
    await tick(5);

    expect(counters.active).toBe(0);
    expect(hub.state).toBe("idle");
  });

  it("tears down immediately when lingerMs is 0", async () => {
    const { hub, counters } = makeHub({ lingerMs: 0 });
    const sub = await hub.join();
    sub.close();
    await tick(10);
    expect(counters.active).toBe(0);
    expect(hub.state).toBe("idle");
  });

  it("a client that aborts during the join does not leave a phantom viewer", async () => {
    const { hub, counters } = makeHub({ lingerMs: 0 });
    const controller = new AbortController();
    controller.abort();

    const sub = await hub.join({ signal: controller.signal });
    expect(sub.closed).toBe(true);
    await tick(10);
    expect(hub.subscribers).toBe(0);
    expect(counters.active).toBe(0);
  });
});

describe("StreamHub — upstream failures", () => {
  it("propagates a failed open and leaves nothing running", async () => {
    const origin = new MockOrigin({ openDelayMs: 1, failOpens: 1 });
    const counters = createCounters();
    let slots = 0;
    const { hub } = makeHub({
      transport: countingTransport(origin, counters),
      acquireSlot: async () => {
        slots += 1;
        return () => {
          slots -= 1;
        };
      },
    });

    await expect(hub.join()).rejects.toThrow(/refused the connection/);
    expect(hub.state).toBe("idle");
    expect(counters.active).toBe(0);
    expect(slots).toBe(0); // the global slot was handed back
  });

  it("rejects a non-2xx origin response", async () => {
    const origin = new MockOrigin({ openDelayMs: 1, status: 403 });
    const counters = createCounters();
    const { hub } = makeHub({ transport: countingTransport(origin, counters) });

    await expect(hub.join()).rejects.toThrow(/HTTP 403/);
    expect(counters.active).toBe(0);
  });

  it("reconnects once, and only once at a time, when the origin drops", async () => {
    const { hub, origin, counters, clock } = makeHub();
    const sub = await hub.join();

    origin.endAll(); // upstream EOF with a viewer still attached
    await tick(5);
    await clock.advance(200); // backoff
    await tick(5);

    expect(counters.opens).toBe(2);
    expect(counters.activeMax).toBe(1); // never two at the same time
    expect(hub.state).toBe("live");

    origin.push(bytes("resumed"));
    await tick(2);
    expect(text(await collect(sub, 7))).toBe("resumed");

    await hub.close();
  });

  it("gives up after the reconnect budget and ends the subscriptions", async () => {
    const { hub, origin, clock } = makeHub({
      reconnect: { attempts: 1, baseDelayMs: 10, maxDelayMs: 10 },
    });
    const sub = await hub.join();
    // Caught eagerly: the subscription rejects well before the assertion below.
    const reader = collect(sub, 1024).then(
      () => null,
      (error: unknown) => error
    );

    origin.endAll();
    await tick(5);
    await clock.advance(20);
    await tick(5);
    origin.endAll(); // the retry dies too
    await tick(5);
    await clock.advance(20);
    await tick(5);

    expect(String(await reader)).toMatch(/reconnect budget/);
    expect(hub.state).toBe("idle");
  });

  it("does not reconnect when nobody is watching", async () => {
    const { hub, origin, counters } = makeHub({ lingerMs: 60_000 });
    const sub = await hub.join();
    sub.close();
    await tick(2);

    origin.endAll();
    await tick(10);

    expect(counters.opens).toBe(1);
    expect(hub.state).toBe("idle"); // EOF while idle just closes the hub
  });
});

describe("StreamHub — teardown", () => {
  it("close() ends every subscription and releases the upstream", async () => {
    const { hub, counters } = makeHub();
    const subs = await Promise.all(Array.from({ length: 10 }, () => hub.join()));
    const readers = subs.map((sub) => collect(sub, 1024));

    await hub.close();
    await Promise.all(readers);

    expect(counters.active).toBe(0);
    expect(hub.state).toBe("idle");
    await expect(hub.join()).rejects.toThrow(/closed/);
  });

  it("stopIfIdle() refuses to cut a stream that still has viewers", async () => {
    const { hub, counters } = makeHub();
    const sub = await hub.join();

    expect(await hub.stopIfIdle()).toBe(false);
    expect(counters.active).toBe(1);

    sub.close();
    await tick(2);
    expect(await hub.stopIfIdle()).toBe(true);
    expect(counters.active).toBe(0);
  });

  it("reports coherent stats", async () => {
    const { hub, origin } = makeHub();
    const sub = await hub.join();
    origin.push(bytes("0123456789"));
    await tick(2);

    const stats = hub.stats();
    expect(stats.key).toBe("sport-live");
    expect(stats.state).toBe("live");
    expect(stats.subscribers).toBe(1);
    expect(stats.bytesFromOrigin).toBe(10);
    expect(stats.bufferedBytes).toBe(10);
    expect(stats.contentType).toBe("video/mp2t");
    expect(stats.upstreamOpens).toBe(1);

    sub.close();
    await hub.close();
  });
});

describe("StreamHub — privacy boundary", () => {
  it("sends only the edge identity upstream", async () => {
    const { hub, origin } = makeHub();
    const sub = await hub.join();

    expect(origin.requests[0].headers).toEqual({
      "user-agent": "tvking-edge/1.0",
      accept: "*/*",
      "accept-encoding": "identity",
      via: "1.1 tvking-edge",
    });

    sub.close();
    await hub.close();
  });
});
