import { describe, expect, it } from "vitest";
import { Broadcaster } from "../../server/edge/broadcast.ts";
import { RingBuffer, type StreamChunk } from "../../server/edge/ring-buffer.ts";
import { bytes, collect, text, tick } from "./mock-origin.ts";

function chunk(value: string, seq = 0): StreamChunk {
  return { seq, data: bytes(value), at: 0 };
}

describe("Broadcaster", () => {
  it("delivers the same bytes to every subscriber without copying", async () => {
    const bus = new Broadcaster();
    const a = bus.subscribe();
    const b = bus.subscribe();
    const payload = bytes("frame");

    bus.publish({ seq: 0, data: payload, at: 0 });
    bus.close();

    const [fromA, fromB] = await Promise.all([collect(a, 5), collect(b, 5)]);
    expect(fromA[0]).toBe(payload); // identity, not equality: zero-copy fan-out
    expect(fromB[0]).toBe(payload);
    expect(bus.publishedBytes).toBe(5);
    expect(bus.fanoutBytes).toBe(10); // 5B published once, served twice
  });

  it("replays a backlog before live data", async () => {
    const ring = new RingBuffer({ maxBytes: 1024, maxChunks: 8 });
    ring.push(bytes("old1"), 0);
    ring.push(bytes("old2"), 0);

    const bus = new Broadcaster();
    const sub = bus.subscribe({ backlog: ring.tail(1024) });
    bus.publish(chunk("live", 2));
    bus.close();

    expect(text(await collect(sub, 64))).toBe("old1old2live");
  });

  it("drops the oldest queued data for a slow subscriber and counts the loss", async () => {
    const bus = new Broadcaster();
    const slow = bus.subscribe({ maxQueueBytes: 8 });

    bus.publish(chunk("aaaa", 0));
    bus.publish(chunk("bbbb", 1));
    bus.publish(chunk("cccc", 2)); // pushes the queue over 8B → "aaaa" is dropped
    bus.close();

    expect(slow.droppedBytes).toBe(4);
    expect(slow.droppedChunks).toBe(1);
    expect(slow.lagEvents).toBe(1);
    expect(text(await collect(slow, 64))).toBe("bbbbcccc");
  });

  it("keeps a fast subscriber intact while a slow one drops", async () => {
    const bus = new Broadcaster();
    const slow = bus.subscribe({ maxQueueBytes: 4 });
    const fast = bus.subscribe({ maxQueueBytes: 1024 });

    for (let i = 0; i < 4; i += 1) bus.publish(chunk(`x${i}`, i));
    bus.close();

    expect(text(await collect(fast, 64))).toBe("x0x1x2x3");
    expect(slow.droppedBytes).toBeGreaterThan(0);
  });

  it("wakes a waiting consumer when data arrives", async () => {
    const bus = new Broadcaster();
    const sub = bus.subscribe();
    const received: string[] = [];

    const reader = (async () => {
      for await (const c of sub) received.push(new TextDecoder().decode(c.data));
    })();

    await tick();
    expect(received).toEqual([]);
    bus.publish(chunk("late", 0));
    await tick();
    expect(received).toEqual(["late"]);

    bus.close();
    await reader;
  });

  it("detaches a subscriber that closes, and stops queueing for it", async () => {
    const bus = new Broadcaster();
    const sub = bus.subscribe();
    expect(bus.subscriberCount).toBe(1);
    sub.close();
    expect(bus.subscriberCount).toBe(0);
    bus.publish(chunk("ignored", 0));
    expect(text(await collect(sub, 64))).toBe("");
  });

  it("closes subscriptions when the signal aborts", () => {
    const bus = new Broadcaster();
    const controller = new AbortController();
    const sub = bus.subscribe({ signal: controller.signal });
    expect(bus.subscriberCount).toBe(1);
    controller.abort();
    expect(sub.closed).toBe(true);
    expect(bus.subscriberCount).toBe(0);
  });

  it("propagates a publisher error to consumers", async () => {
    const bus = new Broadcaster();
    const sub = bus.subscribe();
    bus.close(new Error("upstream died"));
    await expect(collect(sub, 64)).rejects.toThrow("upstream died");
  });

  it("runs onClose exactly once", () => {
    const bus = new Broadcaster();
    let closes = 0;
    const sub = bus.subscribe({ onClose: () => (closes += 1) });
    sub.close();
    sub.close();
    expect(closes).toBe(1);
  });

  it("refuses a second iteration of the same subscription", async () => {
    const bus = new Broadcaster();
    const sub = bus.subscribe();
    bus.close();
    await collect(sub, 1);
    expect(() => sub[Symbol.asyncIterator]()).toThrow(/only be iterated once/);
  });

  it("serves 200 subscribers from one publish", async () => {
    const bus = new Broadcaster();
    const subs = Array.from({ length: 200 }, () => bus.subscribe());
    const payload = bytes("multicast");
    bus.publish({ seq: 0, data: payload, at: 0 });
    bus.close();

    const results = await Promise.all(subs.map((s) => collect(s, 9)));
    expect(results).toHaveLength(200);
    for (const result of results) expect(result[0]).toBe(payload);
    expect(bus.publishedBytes).toBe(9);
  });
});
