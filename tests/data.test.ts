import { describe, it, expect } from "vitest";
import {
  allItems,
  getItem,
  kindOf,
  relatedTo,
  heroSlides,
  homeRows,
  sportRows,
  formationRows,
} from "../app/lib/data";

describe("allItems", () => {
  it("has no duplicate ids", () => {
    const ids = allItems.map((i) => i.id);
    expect(new Set(ids).size).toBe(ids.length);
  });
  it("includes hero + every row item", () => {
    const sampled = [
      heroSlides[0].id,
      homeRows[0].items[0].id,
      sportRows[0].items[0].id,
      formationRows[0].items[0].id,
    ];
    for (const id of sampled) expect(getItem(id)).toBeDefined();
  });
});

describe("getItem", () => {
  it("returns the item for a known id", () => {
    expect(getItem("hero-ucl")?.title).toContain("Champions League");
  });
  it("returns undefined for an unknown id", () => {
    expect(getItem("does-not-exist")).toBeUndefined();
  });
});

describe("kindOf", () => {
  it("classifies sport by live/score/clock/startsIn", () => {
    expect(kindOf({ id: "x", title: "t", art: { from: "#000", to: "#111" }, live: "live" })).toBe(
      "sport",
    );
  });
  it("classifies formation otherwise", () => {
    expect(
      kindOf({ id: "y", title: "t", art: { from: "#000", to: "#111" }, level: "Débutant" }),
    ).toBe("formation");
  });
});

describe("relatedTo", () => {
  const sport = getItem("l1")!; // a live sport item
  it("excludes the item itself", () => {
    expect(relatedTo(sport).some((r) => r.id === sport.id)).toBe(false);
  });
  it("excludes 1:1 logo/topic cards", () => {
    expect(relatedTo(sport).every((r) => r.shape !== "1:1")).toBe(true);
  });
  it("keeps the same kind", () => {
    expect(relatedTo(sport).every((r) => kindOf(r) === "sport")).toBe(true);
  });
  it("returns at most 8", () => {
    expect(relatedTo(sport).length).toBeLessThanOrEqual(8);
  });
});
