import { describe, expect, it } from "vitest";
import { RingBuffer } from "../../server/edge/ring-buffer.ts";
import { bytes, text } from "./mock-origin.ts";

const at = 0;

describe("RingBuffer", () => {
  it("assigns gap-free sequence numbers and reports capacity", () => {
    const ring = new RingBuffer({ maxBytes: 64, maxChunks: 4 });
    expect(ring.oldestSeq).toBe(0);
    expect(ring.nextSeq).toBe(0);

    const a = ring.push(bytes("aa"), at);
    const b = ring.push(bytes("bb"), at);
    expect([a.seq, b.seq]).toEqual([0, 1]);
    expect(ring.size).toBe(2);
    expect(ring.bytes).toBe(4);
  });

  it("stores payloads by reference (zero-copy)", () => {
    const ring = new RingBuffer({ maxBytes: 64, maxChunks: 4 });
    const payload = bytes("shared");
    const stored = ring.push(payload, at);
    expect(stored.data).toBe(payload);
    expect(ring.since(0)[0].data).toBe(payload);
  });

  it("evicts oldest first past the chunk cap", () => {
    const ring = new RingBuffer({ maxBytes: 1024, maxChunks: 3 });
    for (const value of ["a", "b", "c", "d", "e"]) ring.push(bytes(value), at);
    expect(ring.size).toBe(3);
    expect(ring.oldestSeq).toBe(2);
    expect(text(ring.since(0).map((c) => c.data))).toBe("cde");
    expect(ring.evictedChunks).toBe(2);
  });

  it("evicts past the byte cap and keeps `bytes` exact", () => {
    const ring = new RingBuffer({ maxBytes: 6, maxChunks: 100 });
    ring.push(bytes("aaaa"), at);
    ring.push(bytes("bbbb"), at); // 8B > 6B → drops "aaaa"
    expect(ring.size).toBe(1);
    expect(ring.bytes).toBe(4);
    expect(text(ring.since(0).map((c) => c.data))).toBe("bbbb");
  });

  it("wraps around its slot array without losing order", () => {
    const ring = new RingBuffer({ maxBytes: 1024, maxChunks: 3 });
    for (let i = 0; i < 20; i += 1) ring.push(bytes(String(i % 10)), at);
    const seqs = ring.since(0).map((c) => c.seq);
    expect(seqs).toEqual([17, 18, 19]);
    expect(text(ring.since(0).map((c) => c.data))).toBe("789");
  });

  it("since() clamps to what survived eviction", () => {
    const ring = new RingBuffer({ maxBytes: 1024, maxChunks: 2 });
    ring.push(bytes("a"), at);
    ring.push(bytes("b"), at);
    ring.push(bytes("c"), at);
    const survived = ring.since(0);
    expect(survived[0].seq).toBe(1); // caller sees the gap: asked 0, got 1
    expect(ring.since(99)).toEqual([]);
  });

  it("tail() returns the newest bytes, oldest first, within budget", () => {
    const ring = new RingBuffer({ maxBytes: 1024, maxChunks: 10 });
    for (const value of ["11", "22", "33", "44"]) ring.push(bytes(value), at);
    expect(text(ring.tail(4).map((c) => c.data))).toBe("3344");
    expect(text(ring.tail(1000).map((c) => c.data))).toBe("11223344");
    expect(ring.tail(0)).toEqual([]);
    // A budget smaller than one chunk still yields the newest chunk, so a
    // joining client is never handed an empty start-up burst.
    expect(text(ring.tail(1).map((c) => c.data))).toBe("44");
  });

  it("rejects a chunk larger than the whole buffer", () => {
    const ring = new RingBuffer({ maxBytes: 4, maxChunks: 10 });
    expect(() => ring.push(bytes("aaaaaaaa"), at)).toThrow(/exceeds ring capacity/);
  });

  it("rejects nonsensical capacities", () => {
    expect(() => new RingBuffer({ maxBytes: 0, maxChunks: 1 })).toThrow(RangeError);
    expect(() => new RingBuffer({ maxBytes: 1, maxChunks: 0 })).toThrow(RangeError);
  });

  it("clear() empties the cache but keeps sequence continuity", () => {
    const ring = new RingBuffer({ maxBytes: 64, maxChunks: 4 });
    ring.push(bytes("a"), at);
    ring.clear();
    expect(ring.size).toBe(0);
    expect(ring.bytes).toBe(0);
    expect(ring.push(bytes("b"), at).seq).toBe(1);
  });
});
