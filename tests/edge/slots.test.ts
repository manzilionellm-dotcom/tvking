/*
 * Slot pool in isolation, with fake holders — the arbitration logic without a
 * hub, a socket or a clock in the way.
 */

import { describe, expect, it } from "vitest";
import { ManualClock } from "../../server/edge/clock.ts";
import { SlotPool, type SlotHolder, type SlotLease } from "../../server/edge/slots.ts";
import { tick } from "./mock-origin.ts";

class FakeHolder implements SlotHolder {
  key: string;
  viewers: number;
  lastActiveAt: number;
  lease: SlotLease | null = null;
  yields: string[] = [];
  #pool: SlotPool;
  #refuse: boolean;

  constructor(pool: SlotPool, key: string, viewers = 1, lastActiveAt = 0, refuse = false) {
    this.#pool = pool;
    this.key = key;
    this.viewers = viewers;
    this.lastActiveAt = lastActiveAt;
    this.#refuse = refuse;
    pool.register(this);
  }

  get holdsSlot(): boolean {
    return this.lease !== null;
  }

  async take(): Promise<void> {
    this.lease = await this.#pool.acquire(this.key);
  }

  async yieldSlot(reason: string): Promise<boolean> {
    if (this.#refuse || !this.lease) return false;
    this.yields.push(reason);
    const lease = this.lease;
    this.lease = null;
    lease.release();
    return true;
  }
}

function makePool(overrides: Partial<ConstructorParameters<typeof SlotPool>[0]> = {}) {
  const clock = new ManualClock();
  const events: string[] = [];
  const pool = new SlotPool({
    id: "master",
    capacity: 1,
    clock,
    onEvent: (event) => events.push(event.type),
    ...overrides,
  });
  return { pool, clock, events };
}

describe("SlotPool", () => {
  it("hands out its capacity and no more", async () => {
    const { pool } = makePool({ capacity: 2, policy: "reject" });
    const a = await pool.acquire("a");
    const b = await pool.acquire("b");
    expect(pool.available).toBe(0);
    await expect(pool.acquire("c")).rejects.toThrow(/no free slot/);

    a.release();
    expect(pool.available).toBe(1);
    b.release();
    expect(pool.available).toBe(2);
  });

  it("ignores a double release", async () => {
    const { pool } = makePool();
    const lease = await pool.acquire("a");
    lease.release();
    lease.release();
    expect(pool.available).toBe(1);
  });

  it("rejects a nonsensical capacity", () => {
    expect(() => new SlotPool({ id: "x", capacity: 0 })).toThrow(RangeError);
  });

  it("swaps the current holder out for the newcomer", async () => {
    const { pool } = makePool();
    const holder = new FakeHolder(pool, "tf1");
    await holder.take();

    const lease = await pool.acquire("m6");
    expect(holder.yields).toEqual(["swapped for m6"]);
    expect(holder.holdsSlot).toBe(false);
    expect(pool.swaps).toBe(1);
    lease.release();
  });

  it("gives the freed permit to the requester, not back to the holder", async () => {
    // The bug this guards: a channel that starves to make room immediately
    // re-acquires its own permit, and the swap never happens.
    const { pool } = makePool();
    const greedy = new FakeHolder(pool, "tf1");
    await greedy.take();

    let reacquired: SlotLease | null = null;
    const original = greedy.yieldSlot.bind(greedy);
    greedy.yieldSlot = async (reason: string) => {
      const result = await original(reason);
      // Exactly what StreamHub does when it starves: queue for the slot again.
      void pool.acquire(greedy.key, { allowSwap: false, waitMs: 0 }).then((lease) => {
        reacquired = lease;
      });
      return result;
    };

    const lease = await pool.acquire("m6");
    expect(lease).toBeTruthy();
    expect(reacquired).toBeNull(); // the starved channel is queued, not served
    expect(pool.available).toBe(0);

    lease.release(); // now it is the starved channel's turn
    await tick();
    expect(reacquired).not.toBeNull();
  });

  it("evicts holders with no viewers before disturbing anyone", async () => {
    const { pool } = makePool({ capacity: 2 });
    const watched = new FakeHolder(pool, "watched", 5, 100);
    const abandoned = new FakeHolder(pool, "abandoned", 0, 0);
    await watched.take();
    await abandoned.take();

    const lease = await pool.acquire("newcomer");
    expect(abandoned.yields).toHaveLength(1);
    expect(watched.yields).toHaveLength(0);
    expect(pool.swaps).toBe(0); // dropping an unwatched stream is not a swap
    lease.release();
  });

  it("picks the least-recently-active holder among watched ones", async () => {
    const { pool } = makePool({ capacity: 2 });
    const old = new FakeHolder(pool, "old", 2, 10);
    const recent = new FakeHolder(pool, "recent", 2, 900);
    await old.take();
    await recent.take();

    const lease = await pool.acquire("newcomer");
    expect(old.yields).toHaveLength(1);
    expect(recent.yields).toHaveLength(0);
    lease.release();
  });

  it("queues when every holder refuses to yield, then times out honestly", async () => {
    const { pool, clock } = makePool({ waitMs: 1000 });
    const stubborn = new FakeHolder(pool, "stubborn", 1, 0, true);
    await stubborn.take();

    // Caught eagerly: the rejection lands while the clock advances below.
    const pending = pool.acquire("newcomer").then(
      () => null,
      (error: unknown) => error
    );
    await tick();
    expect(pool.waiting).toBe(1);

    await clock.advance(1001);
    expect(String(await pending)).toMatch(/no free slot/);
    expect(pool.denials).toBe(1);
    expect(pool.waiting).toBe(0);
  });

  it("grants a queued waiter as soon as a lease is released", async () => {
    const { pool, clock } = makePool({ waitMs: 5000 });
    const stubborn = new FakeHolder(pool, "stubborn", 1, 0, true);
    await stubborn.take();

    const pending = pool.acquire("newcomer");
    await tick();
    stubborn.lease?.release();

    const lease = await pending;
    expect(lease).toBeTruthy();
    expect(pool.available).toBe(0);
    await clock.advance(10_000); // the deadline must not fire on a granted waiter
    lease.release();
    expect(pool.available).toBe(1);
  });

  it("serves waiters first-come, first-served", async () => {
    const { pool } = makePool({ waitMs: 5000 });
    const stubborn = new FakeHolder(pool, "stubborn", 1, 0, true);
    await stubborn.take();

    const order: string[] = [];
    const first = pool.acquire("first", { allowSwap: false }).then((l) => {
      order.push("first");
      return l;
    });
    await tick();
    const second = pool.acquire("second", { allowSwap: false }).then((l) => {
      order.push("second");
      return l;
    });
    await tick();

    stubborn.lease?.release();
    (await first).release();
    await second;
    expect(order).toEqual(["first", "second"]);
  });

  it("stops tracking holders that unregister", async () => {
    const { pool } = makePool();
    const holder = new FakeHolder(pool, "tf1");
    await holder.take();
    expect(pool.activeHolders().map((h) => h.key)).toEqual(["tf1"]);

    pool.unregister("tf1");
    expect(pool.activeHolders()).toEqual([]);
  });

  it("reports counters for the dashboard", async () => {
    const { pool, events } = makePool();
    const holder = new FakeHolder(pool, "tf1");
    await holder.take();
    const lease = await pool.acquire("m6");
    lease.release();

    expect(pool.grants).toBe(2);
    expect(pool.swaps).toBe(1);
    expect(events).toContain("slot-granted");
    expect(events).toContain("slot-swap");
    expect(events).toContain("slot-released");
  });
});
