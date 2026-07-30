/*
 * The manual VOD library: import on demand, curate by hand, share explicitly.
 *
 * The behaviour that changed is worth stating as tests, not just as a comment:
 * two providers carrying the same film now produce TWO entries, because the
 * operator — not a merge heuristic — decides what the library looks like.
 */

import { describe, expect, it } from "vitest";
import { ManualWallClock } from "../../server/edge/clock.ts";
import { openDatabase } from "../../server/edge/db/database.ts";
import { LibraryError, VodLibrary } from "../../server/edge/vod/library.ts";

function harness() {
  const db = openDatabase(":memory:");
  const clock = new ManualWallClock("2026-07-01T09:00:00Z");
  const library = new VodLibrary(db, clock);
  return { db, clock, library };
}

const GRAND_BLEU = {
  name: "FR - Le Grand Bleu (1988) [MULTI 1080p]",
  url: "http://a.example/movie/u/p/501.mkv",
  group: "VOD | ACTION",
  logo: "http://img/gb.jpg",
};

describe("sources", () => {
  it("registers a source without importing anything", () => {
    const { library } = harness();
    const source = library.addSource({
      name: "provider-a",
      url: "http://a.example/vod.m3u",
      accountId: "master",
    });

    expect(source.enabled).toBe(true);
    expect(source.lastImportAt).toBeNull(); // nothing was pulled
    expect(source.items).toBe(0);
    expect(library.counts().items).toBe(0);
  });

  it("validates what it is given", () => {
    const { library } = harness();
    expect(() => library.addSource({ name: "", url: "http://a", accountId: "m" })).toThrow(LibraryError);
    expect(() => library.addSource({ name: "a", url: "ftp://a", accountId: "m" })).toThrow(/http/);
    expect(() => library.addSource({ name: "a", url: "http://a", accountId: "" })).toThrow(/account/);
  });

  it("counts the entries each source contributed", () => {
    const { library } = harness();
    const source = library.addSource({ name: "a", url: "http://a", accountId: "master" });
    library.registerItem(source.id, GRAND_BLEU);
    expect(library.source(source.id)?.items).toBe(1);
  });
});

describe("items", () => {
  it("files one entry per imported line, parsed but not merged", () => {
    const { library } = harness();
    const a = library.addSource({ name: "a", url: "http://a", accountId: "master" });
    const b = library.addSource({ name: "b", url: "http://b", accountId: "master" });

    library.registerItem(a.id, GRAND_BLEU);
    library.registerItem(b.id, {
      name: "Le Grand Bleu (1988)",
      url: "http://b.example/movie/x/77.mp4",
      group: "Films Action",
    });

    // Two providers, two entries: the operator decides, not a merge rule.
    const items = library.items({ kind: "movie" });
    expect(items).toHaveLength(2);
    expect(items.map((item) => item.sourceName).sort()).toEqual(["a", "b"]);
    expect(items[0]).toMatchObject({ title: "Le Grand Bleu", year: 1988, state: "pending" });
  });

  it("re-importing a source updates its lines instead of doubling them", () => {
    const { library } = harness();
    const source = library.addSource({ name: "a", url: "http://a", accountId: "master" });

    const first = library.registerItem(source.id, GRAND_BLEU);
    const second = library.registerItem(source.id, GRAND_BLEU);

    expect(first.created).toBe(true);
    expect(second.created).toBe(false);
    expect(second.item.id).toBe(first.item.id);
    expect(library.counts().items).toBe(1);
  });

  it("keeps an operator's rename when the source is re-imported", () => {
    const { library } = harness();
    const source = library.addSource({ name: "a", url: "http://a", accountId: "master" });
    const { item } = library.registerItem(source.id, GRAND_BLEU);

    library.updateItem(item.id, { title: "Le Grand Bleu — édition longue" });
    library.registerItem(source.id, GRAND_BLEU);

    expect(library.item(item.id)?.title).toBe("Le Grand Bleu — édition longue");
  });

  it("renames, re-files and re-types by hand", () => {
    const { library } = harness();
    const source = library.addSource({ name: "a", url: "http://a", accountId: "master" });
    const { item } = library.registerItem(source.id, GRAND_BLEU);
    const folder = library.createCategory({ kind: "movie", name: "Cinéma français" });

    const renamed = library.updateItem(item.id, { title: "Le Grand Bleu", categoryId: folder.id });
    expect(renamed.title).toBe("Le Grand Bleu");
    expect(renamed.category).toBe("Cinéma français");

    library.updateItem(item.id, { categoryId: null });
    expect(library.item(item.id)?.categoryId).toBeNull();

    expect(() => library.updateItem(item.id, { title: "   " })).toThrow(/cannot be empty/);
    expect(() => library.updateItem(item.id, { categoryId: 9999 })).toThrow(/unknown category/);
    expect(() => library.updateItem(9999, { title: "x" })).toThrow(/unknown item/);
  });

  it("searches without caring about accents or case", () => {
    const { library } = harness();
    const source = library.addSource({ name: "a", url: "http://a", accountId: "master" });
    library.registerItem(source.id, { name: "L'Été dernier (2023)", url: "http://a/movie/1.mkv" });

    expect(library.items({ search: "ete" })).toHaveLength(1);
    expect(library.items({ search: "ÉTÉ" })).toHaveLength(1);
    expect(library.items({ search: "hiver" })).toHaveLength(0);
  });

  it("filters by kind, state, source and folder", () => {
    const { library } = harness();
    const source = library.addSource({ name: "a", url: "http://a", accountId: "master" });
    const movie = library.registerItem(source.id, GRAND_BLEU).item;
    library.registerItem(source.id, {
      name: "Breaking Bad S05E14",
      url: "http://a/series/1.mkv",
      group: "SERIES",
    });
    library.setState(movie.id, "ready", { filePath: "/tmp/1.mkv", bytesDone: 10 });

    expect(library.items({ kind: "series" })).toHaveLength(1);
    expect(library.items({ state: "ready" }).map((i) => i.id)).toEqual([movie.id]);
    expect(library.items({ sourceId: source.id })).toHaveLength(2);
    expect(library.items({ categoryId: movie.categoryId as number })).toHaveLength(1);
  });

  it("deletes an entry", () => {
    const { library } = harness();
    const source = library.addSource({ name: "a", url: "http://a", accountId: "master" });
    const { item } = library.registerItem(source.id, GRAND_BLEU);

    expect(library.removeItem(item.id)?.id).toBe(item.id);
    expect(library.item(item.id)).toBeNull();
    expect(library.removeItem(item.id)).toBeNull();
  });
});

describe("folders", () => {
  it("creates, renames and deletes without losing items", () => {
    const { library } = harness();
    const source = library.addSource({ name: "a", url: "http://a", accountId: "master" });
    const { item } = library.registerItem(source.id, GRAND_BLEU);
    const folder = library.category(item.categoryId as number);

    expect(folder?.name).toBe("Action");
    expect(library.renameCategory(folder!.id, "Action & aventure").name).toBe("Action & aventure");

    library.removeCategory(folder!.id);
    // The film stays in the library, just without a folder.
    expect(library.item(item.id)?.categoryId).toBeNull();
    expect(library.counts().items).toBe(1);
  });

  it("refuses a duplicate folder name within a kind", () => {
    const { library } = harness();
    library.createCategory({ kind: "movie", name: "Action" });
    const other = library.createCategory({ kind: "movie", name: "Polar" });
    expect(() => library.renameCategory(other.id, "Action")).toThrow(/already exists/);
    // The same name under another kind is a different folder.
    expect(library.createCategory({ kind: "series", name: "Action" }).id).not.toBe(other.id);
  });

  it("rejects an empty name or an unknown kind", () => {
    const { library } = harness();
    expect(() => library.createCategory({ kind: "movie", name: "  " })).toThrow(LibraryError);
    // @ts-expect-error deliberately invalid kind
    expect(() => library.createCategory({ kind: "podcast", name: "x" })).toThrow(/unknown kind/);
  });
});

describe("assignments", () => {
  function seeded() {
    const { library, clock, db } = harness();
    const source = library.addSource({ name: "a", url: "http://a", accountId: "master" });
    const ready = library.registerItem(source.id, GRAND_BLEU).item;
    const pending = library.registerItem(source.id, {
      name: "Dune (2021)",
      url: "http://a/movie/2.mkv",
      group: "VOD | SF",
    }).item;
    library.setState(ready.id, "ready", { filePath: "/tmp/1.mkv", bytesDone: 42 });
    return { library, clock, db, ready, pending };
  }

  it("shows nothing to a subscriber until something is assigned", () => {
    const { library, ready } = seeded();
    expect(library.visibleItems({ packageId: 1, deviceId: 7 })).toEqual([]);

    library.assign(ready.id, [{ type: "package", id: 1 }]);
    expect(library.visibleItems({ packageId: 1, deviceId: 7 }).map((i) => i.id)).toEqual([ready.id]);
  });

  it("keeps an undownloaded title invisible even when assigned", () => {
    const { library, pending } = seeded();
    library.assign(pending.id, [{ type: "package", id: 1 }]);
    expect(library.visibleItems({ packageId: 1, deviceId: 7 })).toEqual([]);
  });

  it("grants per device as well as per package", () => {
    const { library, ready } = seeded();
    library.assign(ready.id, [{ type: "device", id: 42 }]);

    expect(library.visibleItems({ packageId: 1, deviceId: 42 })).toHaveLength(1);
    expect(library.visibleItems({ packageId: 1, deviceId: 43 })).toHaveLength(0);
  });

  it("does not leak a package's titles to a device on another package", () => {
    const { library, ready } = seeded();
    library.assign(ready.id, [{ type: "package", id: 1 }]);
    expect(library.visibleItems({ packageId: 2, deviceId: 7 })).toHaveLength(0);
    expect(library.visibleItems({ packageId: null, deviceId: 7 })).toHaveLength(0);
  });

  it("replaces the whole set with setAssignments, and unassigns one target", () => {
    const { library, ready } = seeded();
    library.assign(ready.id, [
      { type: "package", id: 1 },
      { type: "device", id: 42 },
    ]);
    expect(library.item(ready.id)?.assignments).toHaveLength(2);

    library.setAssignments(ready.id, [{ type: "device", id: 42 }]);
    expect(library.item(ready.id)?.assignments).toEqual([{ type: "device", id: 42 }]);

    expect(library.unassign(ready.id, { type: "device", id: 42 })).toBe(true);
    expect(library.item(ready.id)?.assignments).toEqual([]);
  });

  it("is idempotent and validates its targets", () => {
    const { library, ready } = seeded();
    library.assign(ready.id, [{ type: "package", id: 1 }]);
    library.assign(ready.id, [{ type: "package", id: 1 }]);
    expect(library.item(ready.id)?.assignments).toHaveLength(1);

    // @ts-expect-error deliberately invalid target type
    expect(() => library.assign(ready.id, [{ type: "user", id: 1 }])).toThrow(/unknown assignment/);
    expect(() => library.assign(9999, [{ type: "package", id: 1 }])).toThrow(/unknown item/);
  });

  it("hides a whole folder when it is switched off", () => {
    const { library, ready } = seeded();
    library.assign(ready.id, [{ type: "package", id: 1 }]);
    library.setCategoryEnabled(library.item(ready.id)?.categoryId as number, false);
    expect(library.visibleItems({ packageId: 1, deviceId: 7 })).toHaveLength(0);
  });

  it("lists only folders holding something the subscriber can watch", () => {
    const { library, ready, pending } = seeded();
    library.assign(ready.id, [{ type: "package", id: 1 }]);
    library.assign(pending.id, [{ type: "package", id: 1 }]); // not downloaded

    const folders = library.visibleCategories({ packageId: 1, deviceId: 7 });
    expect(folders.map((folder) => folder.name)).toEqual(["Action"]);
    expect(folders[0].items).toBe(1);
  });

  it("drops assignments with the item", () => {
    const { library, db, ready } = seeded();
    library.assign(ready.id, [{ type: "package", id: 1 }]);
    library.removeItem(ready.id);
    expect(db.all("SELECT * FROM vod_assignments")).toEqual([]);
  });
});

describe("counts", () => {
  it("summarises the library for the panel", () => {
    const { library } = harness();
    const source = library.addSource({ name: "a", url: "http://a", accountId: "master" });
    const movie = library.registerItem(source.id, GRAND_BLEU).item;
    library.registerItem(source.id, {
      name: "Breaking Bad S05E14",
      url: "http://a/series/1.mkv",
      group: "SERIES",
    });
    library.setState(movie.id, "ready", { filePath: "/tmp/1.mkv", bytesDone: 1024 });
    library.assign(movie.id, [{ type: "package", id: 1 }]);

    expect(library.counts()).toMatchObject({
      items: 2,
      movies: 1,
      series: 1,
      ready: 1,
      pending: 1,
      bytesOnDisk: 1024,
      assigned: 1,
    });
  });
});
