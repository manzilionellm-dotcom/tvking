import { describe, expect, it } from "vitest";
import {
  emptyDownloads,
  isDownloaded,
  MAX_DOWNLOADS,
  parseDownloads,
  withDownloaded,
} from "../app/lib/downloads";

describe("parseDownloads", () => {
  it("yields a clean store from null, junk, bad JSON or wrong version", () => {
    expect(parseDownloads(null)).toEqual(emptyDownloads());
    expect(parseDownloads("not json {")).toEqual(emptyDownloads());
    expect(parseDownloads(JSON.stringify({ v: 2, entries: {} }))).toEqual(emptyDownloads());
    expect(parseDownloads(JSON.stringify([1]))).toEqual(emptyDownloads());
  });

  it("drops malformed entries but keeps valid ones", () => {
    const raw = JSON.stringify({
      v: 1,
      entries: { good: { at: 100 }, bad1: { at: "x" }, bad2: null, bad3: { at: Infinity } },
    });
    const store = parseDownloads(raw);
    expect(Object.keys(store.entries)).toEqual(["good"]);
  });

  it("round-trips through JSON", () => {
    const store = withDownloaded(emptyDownloads(), "mv1", 42);
    expect(parseDownloads(JSON.stringify(store))).toEqual(store);
  });
});

describe("withDownloaded / isDownloaded", () => {
  it("marks a film as downloaded", () => {
    const store = withDownloaded(emptyDownloads(), "mv1", 1);
    expect(isDownloaded(store, "mv1")).toBe(true);
    expect(isDownloaded(store, "mv2")).toBe(false);
  });

  it("evicts the oldest entries past the cap", () => {
    let store = emptyDownloads();
    for (let i = 0; i < MAX_DOWNLOADS + 3; i++) {
      store = withDownloaded(store, `f${i}`, i);
    }
    expect(Object.keys(store.entries)).toHaveLength(MAX_DOWNLOADS);
    expect(isDownloaded(store, "f0")).toBe(false);
    expect(isDownloaded(store, `f${MAX_DOWNLOADS + 2}`)).toBe(true);
  });
});
