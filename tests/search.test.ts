import { describe, expect, it } from "vitest";
import { allItems } from "../app/lib/data";
import { normalize, score, searchItems } from "../app/lib/search";

describe("normalize", () => {
  it("folds case, accents and extra whitespace", () => {
    expect(normalize("  Athlétisme  ")).toBe("athletisme");
    expect(normalize("Préparation   MENTALE")).toBe("preparation mentale");
  });
});

describe("score", () => {
  const item = {
    id: "x",
    title: "Yoga du matin",
    art: { from: "#000", to: "#111" },
    instructor: "A. Roy",
    topics: ["forme"],
  };

  it("ranks a title prefix above a word prefix above metadata", () => {
    expect(score(item, "yoga")).toBeLessThan(score(item, "matin")!);
    expect(score(item, "matin")).toBeLessThan(score(item, "roy")!);
  });

  it("ignores accents and case in both directions", () => {
    const accented = { ...item, title: "Étirements & mobilité" };
    expect(score(accented, "etirements")).not.toBeNull();
    expect(score(accented, "ÉTIREMENTS")).not.toBeNull();
  });

  it("returns null for a non-match and for an empty query", () => {
    expect(score(item, "hockey")).toBeNull();
    expect(score(item, "   ")).toBeNull();
  });
});

describe("searchItems", () => {
  it("returns nothing for an empty query (never the whole catalogue)", () => {
    expect(searchItems(allItems, "")).toEqual([]);
    expect(searchItems(allItems, "   ")).toEqual([]);
  });

  it("finds real catalogue entries by title and by facet", () => {
    expect(searchItems(allItems, "yoga").map((i) => i.title)).toContain("Yoga du matin");
    expect(searchItems(allItems, "football").length).toBeGreaterThan(0);
  });

  it("finds an accented catalogue title from unaccented keys (a D-pad keyboard has none)", () => {
    const hits = searchItems(allItems, "athletisme");
    expect(hits.length).toBeGreaterThan(0);
  });

  it("puts the best match first", () => {
    const hits = searchItems(allItems, "hiit");
    expect(hits[0].title.toLowerCase().startsWith("hiit")).toBe(true);
  });

  it("returns each item at most once", () => {
    const ids = searchItems(allItems, "e").map((i) => i.id);
    expect(new Set(ids).size).toBe(ids.length);
  });
});
