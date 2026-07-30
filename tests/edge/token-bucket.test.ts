import { describe, expect, it } from "vitest";
import { ManualClock } from "../../server/edge/clock.ts";
import { TokenBucket, pace } from "../../server/edge/token-bucket.ts";
import { bytes, text } from "./mock-origin.ts";

describe("TokenBucket", () => {
  it("starts full and refills at the configured rate", async () => {
    const clock = new ManualClock();
    const bucket = new TokenBucket({ bytesPerSecond: 1000, burstBytes: 100, clock });

    expect(bucket.available).toBe(100);
    expect(bucket.tryTake(100)).toBe(true);
    expect(bucket.tryTake(1)).toBe(false);

    await clock.advance(50); // 50 ms at 1000 B/s = 50 B
    expect(bucket.available).toBeCloseTo(50, 6);
    expect(bucket.tryTake(50)).toBe(true);
  });

  it("never refills past the burst depth", async () => {
    const clock = new ManualClock();
    const bucket = new TokenBucket({ bytesPerSecond: 1000, burstBytes: 100, clock });
    bucket.tryTake(100);
    await clock.advance(10_000);
    expect(bucket.available).toBe(100);
  });

  it("take() waits for tokens instead of bursting", async () => {
    const clock = new ManualClock();
    const bucket = new TokenBucket({ bytesPerSecond: 1000, burstBytes: 100, clock });
    bucket.tryTake(100);

    let done = false;
    const pending = bucket.take(100).then(() => (done = true));

    await clock.advance(50);
    expect(done).toBe(false); // only 50 of the 100 bytes have accrued
    await clock.advance(60);
    await pending;
    expect(done).toBe(true);
    expect(bucket.waitedMs).toBeGreaterThan(0);
  });

  it("refuses a request larger than the bucket depth", () => {
    const bucket = new TokenBucket({ bytesPerSecond: 1000, burstBytes: 100 });
    expect(() => bucket.tryTake(101)).toThrow(/slice the write first/);
  });

  it("rejects a non-positive rate", () => {
    expect(() => new TokenBucket({ bytesPerSecond: 0 })).toThrow(RangeError);
  });

  it("defaults the depth to 100 ms of rate", () => {
    expect(new TokenBucket({ bytesPerSecond: 2000 }).burstBytes).toBe(200);
  });
});

describe("pace", () => {
  it("slices oversized chunks into zero-copy views and preserves the bytes", async () => {
    const clock = new ManualClock();
    const bucket = new TokenBucket({ bytesPerSecond: 1_000_000, burstBytes: 4, clock });
    const source = (async function* source() {
      yield bytes("abcdefghij"); // 10 B through a 4 B bucket
    })();

    const out: Uint8Array[] = [];
    const drain = (async () => {
      for await (const slice of pace(source, bucket, { maxSliceBytes: 4 })) out.push(slice);
    })();

    // 1 MB/s refills 4 B in well under a millisecond; a few ticks suffice.
    for (let i = 0; i < 10; i += 1) await clock.advance(1);
    await drain;

    expect(out.map((s) => s.byteLength)).toEqual([4, 4, 2]);
    expect(text(out)).toBe("abcdefghij");
    expect(out[0].buffer).toBe(out[1].buffer); // views over the same payload
  });

  it("shapes a burst into a constant rate", async () => {
    const clock = new ManualClock();
    // 1000 B/s, 100 B depth: a 1000 B burst must take ~900 ms to drain.
    const bucket = new TokenBucket({ bytesPerSecond: 1000, burstBytes: 100, clock });
    const source = (async function* source() {
      yield new Uint8Array(1000);
    })();

    let delivered = 0;
    const drain = (async () => {
      for await (const slice of pace(source, bucket, { maxSliceBytes: 100 })) {
        delivered += slice.byteLength;
      }
    })();

    await clock.advance(0);
    expect(delivered).toBe(100); // the depth, and not one byte more

    for (let i = 0; i < 9; i += 1) await clock.advance(100);
    await drain;
    expect(delivered).toBe(1000);
  });

  it("stops promptly when the client goes away", async () => {
    const clock = new ManualClock();
    const bucket = new TokenBucket({ bytesPerSecond: 100, burstBytes: 10, clock });
    const controller = new AbortController();
    const source = (async function* source() {
      for (;;) yield new Uint8Array(10);
    })();

    let delivered = 0;
    const drain = (async () => {
      for await (const slice of pace(source, bucket, { signal: controller.signal, maxSliceBytes: 10 })) {
        delivered += slice.byteLength;
        controller.abort();
      }
    })();

    await clock.advance(1000);
    await drain;
    expect(delivered).toBe(10);
  });
});
