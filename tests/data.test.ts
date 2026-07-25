import { describe, expect, it } from "vitest";
import {
  allFacets,
  allItems,
  facetHref,
  formationFacets,
  formationRows,
  getFacet,
  getItem,
  heroSlides,
  homeRows,
  itemsInFacet,
  kindOf,
  relatedTo,
  sportFacets,
  sportRows,
  untaggedItems,
} from "../app/lib/data";

const everyRowItem = [...homeRows, ...sportRows, ...formationRows].flatMap((r) => r.items);
/* Facet tiles are navigation (they carry their own href), not content. */
const everyContentItem = [...heroSlides, ...everyRowItem].filter((it) => !it.href);

describe("catalogue invariants", () => {
  it("indexes every hero and row content item by id", () => {
    for (const item of everyContentItem) {
      expect(getItem(item.id), `id ${item.id} must resolve`).toBeDefined();
    }
  });

  it("gives no detail page to a facet tile", () => {
    for (const tile of everyRowItem.filter((it) => it.href)) {
      expect(getItem(tile.id), `facet tile ${tile.id} must not be content`).toBeUndefined();
    }
  });

  it("has no duplicate ids inside allItems", () => {
    const ids = allItems.map((it) => it.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("returns undefined for an unknown slug (drives the 404 path)", () => {
    expect(getItem("does-not-exist")).toBeUndefined();
  });
});

describe("kindOf", () => {
  it("classifies live/score/clock/startsIn as sport", () => {
    expect(kindOf({ id: "x", title: "x", art: { from: "#000", to: "#111" }, live: "live" })).toBe("sport");
    expect(kindOf({ id: "x", title: "x", art: { from: "#000", to: "#111" }, startsIn: "demain" })).toBe("sport");
  });

  it("classifies everything else as formation", () => {
    expect(kindOf({ id: "x", title: "x", art: { from: "#000", to: "#111" }, level: "Débutant" })).toBe("formation");
  });
});

describe("relatedTo", () => {
  it("never includes the item itself, logo tiles, or the other kind", () => {
    for (const item of allItems.filter((it) => it.shape !== "1:1")) {
      const related = relatedTo(item);
      expect(related.every((r) => r.id !== item.id)).toBe(true);
      expect(related.every((r) => r.shape !== "1:1")).toBe(true);
      expect(related.every((r) => kindOf(r) === kindOf(item))).toBe(true);
      expect(related.length).toBeLessThanOrEqual(8);
    }
  });
});

describe("facets", () => {
  it("resolves every facet by kind + key, and nowhere else", () => {
    for (const f of allFacets) {
      expect(getFacet(f.kind, f.key)).toBe(f);
    }
    expect(getFacet("sport", "communication")).toBeUndefined();
    expect(getFacet("formation", "football")).toBeUndefined();
  });

  it("uses distinct keys and routes them under their category", () => {
    const keys = allFacets.map((f) => f.key);
    expect(new Set(keys).size).toBe(keys.length);
    for (const f of sportFacets) expect(facetHref(f)).toBe(`/sport/${f.key}`);
    for (const f of formationFacets) expect(facetHref(f)).toBe(`/formation/${f.key}`);
  });

  it("tags every content item with at least one facet", () => {
    expect(untaggedItems().map((it) => it.id)).toEqual([]);
  });

  it("fills every facet page with content of the matching kind", () => {
    for (const f of allFacets) {
      const items = itemsInFacet(f);
      expect(items.length, `facet ${f.key} must not be an empty page`).toBeGreaterThan(0);
      expect(items.every((it) => kindOf(it) === f.kind)).toBe(true);
    }
  });

  it("puts every tagged item on the facet page of each of its tags", () => {
    for (const item of allItems) {
      for (const key of item.topics ?? []) {
        const facet = allFacets.find((f) => f.key === key);
        expect(facet, `unknown topic ${key} on ${item.id}`).toBeDefined();
        expect(itemsInFacet(facet!).map((i) => i.id)).toContain(item.id);
      }
    }
  });
});
