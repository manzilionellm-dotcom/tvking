import { describe, expect, it } from "vitest";
import {
  emptyStore,
  FINISHED_AT,
  MAX_ENTRIES,
  parseStore,
  positionOf,
  withPosition,
  type ResumeStore,
} from "../app/lib/resume";

describe("parseStore", () => {
  it("yields a clean store from null, junk, bad JSON or wrong version", () => {
    expect(parseStore(null)).toEqual(emptyStore());
    expect(parseStore("not json {")).toEqual(emptyStore());
    expect(parseStore(JSON.stringify({ v: 2, entries: {} }))).toEqual(emptyStore());
    expect(parseStore(JSON.stringify([1, 2, 3]))).toEqual(emptyStore());
    expect(parseStore(JSON.stringify(null))).toEqual(emptyStore());
  });

  it("drops malformed entries but keeps valid ones", () => {
    const raw = JSON.stringify({
      v: 1,
      entries: {
        good: { pos: 12, dur: 40, at: 1000 },
        bad1: { pos: "12", dur: 40, at: 1000 },
        bad2: { pos: Infinity, dur: 40, at: 1000 },
        bad3: null,
      },
    });
    const store = parseStore(raw);
    expect(Object.keys(store.entries)).toEqual(["good"]);
    expect(positionOf(store, "good")).toBe(12);
  });

  it("round-trips through JSON", () => {
    const store = withPosition(emptyStore(), "a", 10, 40, 5);
    expect(parseStore(JSON.stringify(store))).toEqual(store);
  });
});

describe("withPosition", () => {
  it("records and updates a position without mutating the input", () => {
    const s0 = emptyStore();
    const s1 = withPosition(s0, "a", 10, 40, 1);
    const s2 = withPosition(s1, "a", 20, 40, 2);
    expect(positionOf(s0, "a")).toBeNull();
    expect(positionOf(s1, "a")).toBe(10);
    expect(positionOf(s2, "a")).toBe(20);
  });

  it("clamps negative positions to 0", () => {
    expect(positionOf(withPosition(emptyStore(), "a", -5, 40, 1), "a")).toBe(0);
  });

  it("removes an entry once the item is effectively finished", () => {
    const s1 = withPosition(emptyStore(), "a", 10, 40, 1);
    const s2 = withPosition(s1, "a", 40 * FINISHED_AT, 40, 2);
    expect(positionOf(s2, "a")).toBeNull();
  });

  it("evicts the oldest entries past MAX_ENTRIES", () => {
    let store: ResumeStore = emptyStore();
    for (let i = 0; i < MAX_ENTRIES + 10; i++) {
      store = withPosition(store, `item-${i}`, 5, 40, i);
    }
    expect(Object.keys(store.entries)).toHaveLength(MAX_ENTRIES);
    expect(positionOf(store, "item-0")).toBeNull(); // oldest gone
    expect(positionOf(store, `item-${MAX_ENTRIES + 9}`)).toBe(5); // newest kept
  });
});
