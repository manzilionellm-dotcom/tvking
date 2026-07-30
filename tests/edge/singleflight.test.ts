import { describe, expect, it } from "vitest";
import { SingleFlight } from "../../server/edge/singleflight.ts";
import { AbortedError, Mutex, Semaphore } from "../../server/edge/sync.ts";
import { tick } from "./mock-origin.ts";

describe("SingleFlight", () => {
  it("runs the work once for N concurrent callers of the same key", async () => {
    const flight = new SingleFlight<number>();
    let runs = 0;

    const callers = Array.from({ length: 500 }, () =>
      flight.run("channel-1", async () => {
        runs += 1;
        await tick(5);
        return 42;
      })
    );
    const results = await Promise.all(callers);

    expect(runs).toBe(1);
    expect(flight.executions).toBe(1);
    expect(flight.coalesced).toBe(499);
    expect(new Set(results)).toEqual(new Set([42]));
  });

  it("keys are independent", async () => {
    const flight = new SingleFlight<string>();
    const [a, b] = await Promise.all([
      flight.run("a", async () => "a"),
      flight.run("b", async () => "b"),
    ]);
    expect([a, b]).toEqual(["a", "b"]);
    expect(flight.executions).toBe(2);
  });

  it("clears the key once settled, so a later call re-runs", async () => {
    const flight = new SingleFlight<number>();
    let runs = 0;
    const work = async () => {
      runs += 1;
      return runs;
    };
    expect(await flight.run("k", work)).toBe(1);
    expect(flight.inflight).toBe(0);
    expect(await flight.run("k", work)).toBe(2);
  });

  it("shares the rejection with every coalesced caller and does not poison the key", async () => {
    const flight = new SingleFlight<number>();
    const boom = () => flight.run("k", async () => {
      await tick(1);
      throw new Error("origin down");
    });
    const results = await Promise.allSettled([boom(), boom(), boom()]);
    expect(results.every((r) => r.status === "rejected")).toBe(true);
    expect(flight.executions).toBe(1);

    expect(await flight.run("k", async () => 7)).toBe(7);
  });
});

describe("Mutex", () => {
  it("serialises critical sections across await points", async () => {
    const mutex = new Mutex();
    let concurrent = 0;
    let maxConcurrent = 0;

    await Promise.all(
      Array.from({ length: 50 }, () =>
        mutex.runExclusive(async () => {
          concurrent += 1;
          maxConcurrent = Math.max(maxConcurrent, concurrent);
          await tick(1);
          concurrent -= 1;
        })
      )
    );

    expect(maxConcurrent).toBe(1);
    expect(mutex.locked).toBe(false);
  });

  it("is FIFO", async () => {
    const mutex = new Mutex();
    const order: number[] = [];
    await Promise.all(
      Array.from({ length: 10 }, (_, i) =>
        mutex.runExclusive(async () => {
          order.push(i);
          await tick(0);
        })
      )
    );
    expect(order).toEqual([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
  });

  it("releases even when the section throws", async () => {
    const mutex = new Mutex();
    await expect(
      mutex.runExclusive(async () => {
        throw new Error("nope");
      })
    ).rejects.toThrow("nope");
    expect(mutex.locked).toBe(false);
  });

  it("ignores a double release", async () => {
    const mutex = new Mutex();
    const release = await mutex.lock();
    release();
    release();
    const second = await mutex.lock();
    expect(mutex.locked).toBe(true);
    second();
  });
});

describe("Semaphore", () => {
  it("never lets more than `permits` holders through", async () => {
    const semaphore = new Semaphore(1);
    let held = 0;
    let maxHeld = 0;

    await Promise.all(
      Array.from({ length: 100 }, async () => {
        await semaphore.acquire();
        held += 1;
        maxHeld = Math.max(maxHeld, held);
        await tick(1);
        held -= 1;
        semaphore.release();
      })
    );

    expect(maxHeld).toBe(1);
    expect(semaphore.available).toBe(1);
  });

  it("tryAcquire fails instead of waiting", async () => {
    const semaphore = new Semaphore(1);
    expect(semaphore.tryAcquire()).toBe(true);
    expect(semaphore.tryAcquire()).toBe(false);
    semaphore.release();
    expect(semaphore.tryAcquire()).toBe(true);
  });

  it("aborts a queued acquisition without leaking the permit", async () => {
    const semaphore = new Semaphore(1);
    await semaphore.acquire();

    const controller = new AbortController();
    const queued = semaphore.acquire(controller.signal);
    await tick();
    expect(semaphore.waiting).toBe(1);

    controller.abort();
    await expect(queued).rejects.toBeInstanceOf(AbortedError);
    expect(semaphore.waiting).toBe(0);

    semaphore.release();
    expect(semaphore.available).toBe(1);
  });

  it("never exceeds its capacity on over-release", () => {
    const semaphore = new Semaphore(1);
    semaphore.release();
    semaphore.release();
    expect(semaphore.available).toBe(1);
  });
});
