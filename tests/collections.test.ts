import { describe, expect, it } from "vitest";
import {
  MAX_IDS,
  addId,
  emptySet,
  hasId,
  parseSet,
  removeId,
  toggleId,
} from "../app/lib/collections";

describe("parseSet (defensive)", () => {
  it("returns an empty set for null, junk, bad JSON or a foreign version", () => {
    expect(parseSet(null)).toEqual(emptySet());
    expect(parseSet("not json")).toEqual(emptySet());
    expect(parseSet('"a string"')).toEqual(emptySet());
    expect(parseSet(JSON.stringify({ v: 2, ids: ["a"] }))).toEqual(emptySet());
    expect(parseSet(JSON.stringify({ v: 1, ids: "nope" }))).toEqual(emptySet());
  });

  it("keeps only non-empty unique strings, in order", () => {
    const store = parseSet(JSON.stringify({ v: 1, ids: ["a", 4, "", "b", "a", null] }));
    expect(store.ids).toEqual(["a", "b"]);
  });

  it("round-trips what it wrote", () => {
    const store = addId(addId(emptySet(), "a"), "b");
    expect(parseSet(JSON.stringify(store))).toEqual(store);
  });

  it("caps a hostile oversized payload", () => {
    const ids = Array.from({ length: MAX_IDS + 50 }, (_, i) => `id-${i}`);
    expect(parseSet(JSON.stringify({ v: 1, ids })).ids).toHaveLength(MAX_IDS);
  });
});

describe("add / remove / toggle", () => {
  it("adds most-recent-first and never duplicates", () => {
    const store = addId(addId(addId(emptySet(), "a"), "b"), "a");
    expect(store.ids).toEqual(["a", "b"]);
  });

  it("removes without touching the rest, and ignores unknown ids", () => {
    const store = addId(addId(emptySet(), "a"), "b");
    expect(removeId(store, "a").ids).toEqual(["b"]);
    expect(removeId(store, "zzz").ids).toEqual(["b", "a"]);
  });

  it("toggles in and back out", () => {
    const once = toggleId(emptySet(), "a");
    expect(hasId(once, "a")).toBe(true);
    expect(hasId(toggleId(once, "a"), "a")).toBe(false);
  });

  it("evicts the oldest past the cap", () => {
    let store = emptySet();
    for (let i = 0; i < MAX_IDS + 10; i++) store = addId(store, `id-${i}`);
    expect(store.ids).toHaveLength(MAX_IDS);
    expect(hasId(store, `id-${MAX_IDS + 9}`)).toBe(true); // newest kept
    expect(hasId(store, "id-0")).toBe(false); // oldest dropped
  });

  it("never mutates the input store", () => {
    const store = addId(emptySet(), "a");
    const snapshot = JSON.stringify(store);
    addId(store, "b");
    removeId(store, "a");
    toggleId(store, "c");
    expect(JSON.stringify(store)).toBe(snapshot);
  });
});
