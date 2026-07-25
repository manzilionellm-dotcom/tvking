import { describe, expect, it } from "vitest";
import {
  allItems,
  formationRows,
  getItem,
  heroSlides,
  homeRows,
  kindOf,
  relatedTo,
  sportRows,
} from "../app/lib/data";

const everyRowItem = [...homeRows, ...sportRows, ...formationRows].flatMap((r) => r.items);

describe("catalogue invariants", () => {
  it("indexes every hero and row item by id", () => {
    for (const item of [...heroSlides, ...everyRowItem]) {
      expect(getItem(item.id), `id ${item.id} must resolve`).toBeDefined();
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
