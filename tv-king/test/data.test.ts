import { describe, expect, it } from "vitest";
import {
  getById,
  getByUniverse,
  getContinueWatching,
  getHeroItems,
  getLiveNow,
  getUniverseMeta,
  MEDIA,
  searchMedia,
  UNIVERSES,
  type Universe,
} from "../app/lib/data";

describe("lookups de données", () => {
  it("getById retrouve un item connu et undefined sinon", () => {
    expect(getById("sp-derby-lumiere")?.title).toBe("Derby des Lumières");
    expect(getById("inconnu-xyz")).toBeUndefined();
  });

  it("tous les items ont un id unique", () => {
    const ids = new Set(MEDIA.map((m) => m.id));
    expect(ids.size).toBe(MEDIA.length);
  });

  it("getByUniverse ne renvoie que l'univers demandé, et chaque univers est peuplé", () => {
    const universes: Universe[] = [
      "sports",
      "chaines",
      "divertissement",
      "enfants",
      "journal",
    ];
    for (const u of universes) {
      const items = getByUniverse(u);
      expect(items.length).toBeGreaterThan(0);
      expect(items.every((m) => m.universe === u)).toBe(true);
    }
  });

  it("getContinueWatching ne renvoie que des contenus 0<progress<1", () => {
    const cw = getContinueWatching();
    expect(cw.length).toBeGreaterThan(0);
    expect(cw.every((m) => (m.progress ?? 0) > 0 && (m.progress ?? 0) < 1)).toBe(
      true,
    );
  });

  it("getLiveNow ne renvoie que des directs", () => {
    expect(getLiveNow().every((m) => m.live === true)).toBe(true);
  });

  it("getHeroItems renvoie des items existants", () => {
    const hero = getHeroItems();
    expect(hero.length).toBeGreaterThan(0);
    expect(hero.every((m) => getById(m.id) !== undefined)).toBe(true);
  });

  it("searchMedia : vide pour requête vide, sinon insensible à la casse", () => {
    expect(searchMedia("")).toEqual([]);
    const r = searchMedia("JOURNAL");
    expect(r.length).toBeGreaterThan(0);
  });

  it("UNIVERSES couvre les 5 univers, getUniverseMeta défini pour chacun", () => {
    expect(UNIVERSES).toHaveLength(5);
    for (const u of UNIVERSES) {
      const meta = getUniverseMeta(u.id);
      expect(meta.label).toBeTruthy();
      expect(meta.icon).toBeTruthy();
    }
  });
});
