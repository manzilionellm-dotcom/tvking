/*
 * The local VOD library — a manual, operator-owned collection.
 *
 * What this deliberately is NOT any more: an aggregate refreshed by a
 * background worker. Merging the same film from four providers into one entry
 * makes sense for an automatic catalogue and makes no sense for a curated one —
 * once an operator renames or re-files an entry, there is no honest answer to
 * "which of the four titles wins?". So the library is flat: one row per
 * imported line, edited by hand, and nothing changes unless someone asks.
 *
 * Visibility is explicit too. An item nobody assigned is visible to nobody:
 * when the whole point is choosing exactly who gets what, silence must mean
 * "not shared", never "shared with everyone".
 */

import type { Database } from "../db/database.ts";
import { systemWallClock, type WallClock } from "../clock.ts";
import { classify, normalizeTitle, type VodKind } from "./classify.ts";

export type VodState = "pending" | "downloading" | "ready" | "failed";
export type AssignmentTarget = "package" | "device";

export interface VodSource {
  id: number;
  name: string;
  url: string;
  accountId: string;
  enabled: boolean;
  lastImportAt: number | null;
  lastError: string | null;
  lastImportItems: number;
  createdAt: number;
  /** Items currently in the library that came from this source. */
  items: number;
}

export interface VodCategory {
  id: number;
  kind: VodKind;
  name: string;
  enabled: boolean;
  items: number;
}

export interface VodItem {
  id: number;
  sourceId: number | null;
  sourceName: string | null;
  kind: VodKind;
  title: string;
  year: number;
  categoryId: number | null;
  category: string | null;
  season: number | null;
  episode: number | null;
  poster: string | null;
  sourceUrl: string;
  container: string | null;
  quality: string | null;
  state: VodState;
  filePath: string | null;
  bytesTotal: number;
  bytesDone: number;
  error: string | null;
  importedAt: number;
  updatedAt: number;
  downloadedAt: number | null;
  assignments: Assignment[];
}

export interface Assignment {
  type: AssignmentTarget;
  id: number;
}

export interface ImportEntry {
  name: string;
  url: string;
  group?: string;
  logo?: string;
  attributes?: Readonly<Record<string, string>>;
}

export interface ItemQuery {
  kind?: VodKind;
  categoryId?: number | null;
  sourceId?: number;
  state?: VodState;
  search?: string;
  limit?: number;
  offset?: number;
}

export interface ItemPatch {
  title?: string;
  categoryId?: number | null;
  kind?: VodKind;
  poster?: string | null;
  year?: number;
}

export class LibraryError extends Error {
  name = "LibraryError";
}

const KINDS: readonly VodKind[] = ["movie", "series"];

export class VodLibrary {
  #db: Database;
  #clock: WallClock;

  constructor(db: Database, clock: WallClock = systemWallClock) {
    this.#db = db;
    this.#clock = clock;
  }

  // ------------------------------------------------------------- sources

  /**
   * Registers a source WITHOUT importing anything: adding a provider line and
   * pulling its catalogue are two separate decisions now, and the second one is
   * a button.
   */
  addSource(input: { name: string; url: string; accountId: string }): VodSource {
    const name = input.name?.trim();
    const url = input.url?.trim();
    if (!name) throw new LibraryError("a source needs a name");
    if (!/^https?:\/\//i.test(url ?? "")) throw new LibraryError("a source needs an http(s) URL");
    if (!input.accountId?.trim()) throw new LibraryError("a source needs a master account");

    this.#db.run(
      `INSERT INTO vod_sources(name, url, account_id, enabled, created_at)
       VALUES(?, ?, ?, 1, ?)
       ON CONFLICT(name) DO UPDATE SET url = excluded.url, account_id = excluded.account_id`,
      name,
      url,
      input.accountId.trim(),
      this.#clock.now()
    );
    return this.sourceByName(name) as VodSource;
  }

  removeSource(id: number): boolean {
    return this.#db.run("DELETE FROM vod_sources WHERE id = ?", id).changes > 0;
  }

  setSourceEnabled(id: number, enabled: boolean): boolean {
    return (
      this.#db.run("UPDATE vod_sources SET enabled = ? WHERE id = ?", enabled ? 1 : 0, id).changes > 0
    );
  }

  source(id: number): VodSource | null {
    return this.#toSource(
      this.#db.get(`${SOURCE_SELECT} WHERE s.id = ? GROUP BY s.id`, id)
    );
  }

  sourceByName(name: string): VodSource | null {
    return this.#toSource(
      this.#db.get(`${SOURCE_SELECT} WHERE s.name = ? GROUP BY s.id`, name)
    );
  }

  listSources(): VodSource[] {
    return this.#db
      .all(`${SOURCE_SELECT} GROUP BY s.id ORDER BY s.name`)
      .map((row) => this.#toSource(row) as VodSource);
  }

  markImport(sourceId: number, result: { items: number; error?: string | null }): void {
    this.#db.run(
      "UPDATE vod_sources SET last_import_at = ?, last_import_items = ?, last_error = ? WHERE id = ?",
      this.#clock.now(),
      result.items,
      result.error ?? null,
      sourceId
    );
  }

  // ------------------------------------------------------ categories (folders)

  createCategory(input: { kind: VodKind; name: string }): VodCategory {
    const name = input.name?.trim();
    if (!name) throw new LibraryError("a category needs a name");
    if (!KINDS.includes(input.kind)) throw new LibraryError(`unknown kind: ${String(input.kind)}`);
    this.#db.run(
      "INSERT INTO vod_categories(kind, name, enabled) VALUES(?, ?, 1) ON CONFLICT(kind, name) DO NOTHING",
      input.kind,
      name
    );
    return this.categoryByName(input.kind, name) as VodCategory;
  }

  renameCategory(id: number, name: string): VodCategory {
    const trimmed = name?.trim();
    if (!trimmed) throw new LibraryError("a category needs a name");
    const existing = this.category(id);
    if (!existing) throw new LibraryError(`unknown category ${id}`);
    const clash = this.categoryByName(existing.kind, trimmed);
    if (clash && clash.id !== id) throw new LibraryError(`category "${trimmed}" already exists`);
    this.#db.run("UPDATE vod_categories SET name = ? WHERE id = ?", trimmed, id);
    return this.category(id) as VodCategory;
  }

  setCategoryEnabled(id: number, enabled: boolean): boolean {
    return (
      this.#db.run("UPDATE vod_categories SET enabled = ? WHERE id = ?", enabled ? 1 : 0, id)
        .changes > 0
    );
  }

  /** Items keep their place in the library; they just lose the folder. */
  removeCategory(id: number): boolean {
    return this.#db.run("DELETE FROM vod_categories WHERE id = ?", id).changes > 0;
  }

  category(id: number): VodCategory | null {
    return this.#toCategory(this.#db.get(`${CATEGORY_SELECT} WHERE c.id = ? GROUP BY c.id`, id));
  }

  categoryByName(kind: VodKind, name: string): VodCategory | null {
    return this.#toCategory(
      this.#db.get(`${CATEGORY_SELECT} WHERE c.kind = ? AND c.name = ? GROUP BY c.id`, kind, name)
    );
  }

  listCategories(kind?: VodKind): VodCategory[] {
    const rows = kind
      ? this.#db.all(`${CATEGORY_SELECT} WHERE c.kind = ? GROUP BY c.id ORDER BY c.name`, kind)
      : this.#db.all(`${CATEGORY_SELECT} GROUP BY c.id ORDER BY c.kind, c.name`);
    return rows.map((row) => this.#toCategory(row) as VodCategory);
  }

  // --------------------------------------------------------------- items

  /**
   * Files one imported playlist line. Re-importing the same source updates the
   * line in place — and leaves the operator's edits alone: a title someone
   * renamed is not overwritten by the provider's decorated filename.
   */
  registerItem(sourceId: number, entry: ImportEntry): { item: VodItem; created: boolean } {
    const parsed = classify(entry);
    const now = this.#clock.now();
    const existing = this.#db.get<{ id: number }>(
      "SELECT id FROM vod_items WHERE source_id = ? AND source_url = ?",
      sourceId,
      entry.url
    );

    if (existing) {
      this.#db.run(
        `UPDATE vod_items SET container = ?, quality = ?, poster = COALESCE(poster, ?), updated_at = ?
         WHERE id = ?`,
        parsed.container,
        parsed.quality,
        entry.logo ?? null,
        now,
        existing.id
      );
      return { item: this.item(existing.id) as VodItem, created: false };
    }

    const category = this.#ensureCategory(parsed.kind, parsed.category);
    const created = this.#db.run(
      `INSERT INTO vod_items(source_id, kind, title, search_key, year, category_id, season, episode,
                             poster, source_url, container, quality, state, imported_at, updated_at)
       VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)`,
      sourceId,
      parsed.kind,
      parsed.title,
      normalizeTitle(parsed.title),
      parsed.year,
      category.id,
      parsed.season,
      parsed.episode,
      entry.logo ?? null,
      entry.url,
      parsed.container,
      parsed.quality,
      now,
      now
    );
    return { item: this.item(created.lastInsertRowid) as VodItem, created: true };
  }

  item(id: number): VodItem | null {
    const row = this.#db.get(`${ITEM_SELECT} WHERE i.id = ?`, id);
    return row ? this.#toItem(row) : null;
  }

  items(query: ItemQuery = {}): VodItem[] {
    const where: string[] = [];
    const params: unknown[] = [];
    if (query.kind) {
      where.push("i.kind = ?");
      params.push(query.kind);
    }
    if (query.state) {
      where.push("i.state = ?");
      params.push(query.state);
    }
    if (query.sourceId !== undefined) {
      where.push("i.source_id = ?");
      params.push(query.sourceId);
    }
    if (query.categoryId !== undefined) {
      if (query.categoryId === null) where.push("i.category_id IS NULL");
      else {
        where.push("i.category_id = ?");
        params.push(query.categoryId);
      }
    }
    if (query.search) {
      // Search on the accent-free copy so "ete" finds "Été".
      where.push("i.search_key LIKE ?");
      params.push(`%${normalizeTitle(query.search)}%`);
    }
    params.push(Math.min(query.limit ?? 200, 1000), query.offset ?? 0);

    return this.#db
      .all(
        `${ITEM_SELECT} ${where.length ? `WHERE ${where.join(" AND ")}` : ""}
         ORDER BY i.kind, i.title LIMIT ? OFFSET ?`,
        ...params
      )
      .map((row) => this.#toItem(row));
  }

  updateItem(id: number, patch: ItemPatch): VodItem {
    const existing = this.item(id);
    if (!existing) throw new LibraryError(`unknown item ${id}`);

    const title = patch.title === undefined ? existing.title : patch.title.trim();
    if (!title) throw new LibraryError("a title cannot be empty");
    if (patch.kind !== undefined && !KINDS.includes(patch.kind)) {
      throw new LibraryError(`unknown kind: ${String(patch.kind)}`);
    }
    if (patch.categoryId !== undefined && patch.categoryId !== null && !this.category(patch.categoryId)) {
      throw new LibraryError(`unknown category ${patch.categoryId}`);
    }

    this.#db.run(
      `UPDATE vod_items SET title = ?, search_key = ?, kind = ?, category_id = ?, poster = ?, year = ?,
                            updated_at = ?
       WHERE id = ?`,
      title,
      normalizeTitle(title),
      patch.kind ?? existing.kind,
      patch.categoryId === undefined ? existing.categoryId : patch.categoryId,
      patch.poster === undefined ? existing.poster : patch.poster,
      patch.year ?? existing.year,
      this.#clock.now(),
      id
    );
    return this.item(id) as VodItem;
  }

  /** @internal — used by the downloader to record progress and outcome. */
  setState(
    id: number,
    state: VodState,
    patch: {
      filePath?: string | null;
      bytesTotal?: number;
      bytesDone?: number;
      error?: string | null;
      downloadedAt?: number | null;
    } = {}
  ): void {
    const existing = this.item(id);
    if (!existing) return;
    this.#db.run(
      `UPDATE vod_items SET state = ?, file_path = ?, bytes_total = ?, bytes_done = ?, error = ?,
                            downloaded_at = ?, updated_at = ?
       WHERE id = ?`,
      state,
      patch.filePath === undefined ? existing.filePath : patch.filePath,
      patch.bytesTotal ?? existing.bytesTotal,
      patch.bytesDone ?? existing.bytesDone,
      patch.error === undefined ? existing.error : patch.error,
      patch.downloadedAt === undefined ? existing.downloadedAt : patch.downloadedAt,
      this.#clock.now(),
      id
    );
  }

  removeItem(id: number): VodItem | null {
    const existing = this.item(id);
    if (!existing) return null;
    this.#db.run("DELETE FROM vod_items WHERE id = ?", id);
    // The row is gone; the caller deletes the file it points at.
    return existing;
  }

  // --------------------------------------------------------- assignments

  /** Grants access to one item for packages and/or devices. */
  assign(itemId: number, targets: readonly Assignment[]): VodItem {
    if (!this.item(itemId)) throw new LibraryError(`unknown item ${itemId}`);
    const now = this.#clock.now();
    this.#db.transaction(() => {
      for (const target of targets) {
        if (target.type !== "package" && target.type !== "device") {
          throw new LibraryError(`unknown assignment target: ${String(target.type)}`);
        }
        this.#db.run(
          `INSERT INTO vod_assignments(item_id, target_type, target_id, created_at)
           VALUES(?, ?, ?, ?) ON CONFLICT DO NOTHING`,
          itemId,
          target.type,
          target.id,
          now
        );
      }
    });
    return this.item(itemId) as VodItem;
  }

  unassign(itemId: number, target: Assignment): boolean {
    return (
      this.#db.run(
        "DELETE FROM vod_assignments WHERE item_id = ? AND target_type = ? AND target_id = ?",
        itemId,
        target.type,
        target.id
      ).changes > 0
    );
  }

  /** Replaces the whole assignment set of an item in one call. */
  setAssignments(itemId: number, targets: readonly Assignment[]): VodItem {
    if (!this.item(itemId)) throw new LibraryError(`unknown item ${itemId}`);
    this.#db.transaction(() => {
      this.#db.run("DELETE FROM vod_assignments WHERE item_id = ?", itemId);
    });
    return this.assign(itemId, targets);
  }

  /**
   * What a subscriber may actually watch: downloaded, and assigned either to
   * their package or to their device.
   */
  visibleItems(
    subscriber: { packageId: number | null; deviceId: number },
    query: { kind?: VodKind; categoryId?: number; limit?: number } = {}
  ): VodItem[] {
    const params: unknown[] = [subscriber.deviceId, subscriber.packageId ?? -1];
    let where = "";
    if (query.kind) {
      where += " AND i.kind = ?";
      params.push(query.kind);
    }
    if (query.categoryId !== undefined) {
      where += " AND i.category_id = ?";
      params.push(query.categoryId);
    }
    params.push(Math.min(query.limit ?? 500, 1000));

    return this.#db
      .all(
        `${ITEM_SELECT}
          WHERE i.state = 'ready'
            AND (c.enabled IS NULL OR c.enabled = 1)
            AND EXISTS (
              SELECT 1 FROM vod_assignments a
               WHERE a.item_id = i.id
                 AND ((a.target_type = 'device' AND a.target_id = ?)
                   OR (a.target_type = 'package' AND a.target_id = ?))
            )
            ${where}
          ORDER BY i.kind, i.title LIMIT ?`,
        ...params
      )
      .map((row) => this.#toItem(row));
  }

  /** Categories that actually hold something this subscriber can watch. */
  visibleCategories(
    subscriber: { packageId: number | null; deviceId: number },
    kind?: VodKind
  ): VodCategory[] {
    const visible = this.visibleItems(subscriber, { kind, limit: 1000 });
    const counts = new Map<number, number>();
    for (const item of visible) {
      if (item.categoryId === null) continue;
      counts.set(item.categoryId, (counts.get(item.categoryId) ?? 0) + 1);
    }
    return [...counts.entries()]
      .map(([id, items]) => ({ ...(this.category(id) as VodCategory), items }))
      .sort((a, b) => a.name.localeCompare(b.name));
  }

  counts(): {
    items: number;
    movies: number;
    series: number;
    ready: number;
    pending: number;
    failed: number;
    downloading: number;
    bytesOnDisk: number;
    assigned: number;
  } {
    const one = (sql: string, ...params: unknown[]) =>
      Number((this.#db.get<{ n: number }>(sql, ...params) as { n: number } | undefined)?.n ?? 0);
    return {
      items: one("SELECT COUNT(*) AS n FROM vod_items"),
      movies: one("SELECT COUNT(*) AS n FROM vod_items WHERE kind = 'movie'"),
      series: one("SELECT COUNT(*) AS n FROM vod_items WHERE kind = 'series'"),
      ready: one("SELECT COUNT(*) AS n FROM vod_items WHERE state = 'ready'"),
      pending: one("SELECT COUNT(*) AS n FROM vod_items WHERE state = 'pending'"),
      failed: one("SELECT COUNT(*) AS n FROM vod_items WHERE state = 'failed'"),
      downloading: one("SELECT COUNT(*) AS n FROM vod_items WHERE state = 'downloading'"),
      bytesOnDisk: one("SELECT COALESCE(SUM(bytes_done), 0) AS n FROM vod_items WHERE state = 'ready'"),
      assigned: one("SELECT COUNT(DISTINCT item_id) AS n FROM vod_assignments"),
    };
  }

  // ----------------------------------------------------------- internals

  #ensureCategory(kind: VodKind, name: string): VodCategory {
    return this.categoryByName(kind, name) ?? this.createCategory({ kind, name });
  }

  #assignments(itemId: number): Assignment[] {
    return this.#db
      .all<{ target_type: string; target_id: number }>(
        "SELECT target_type, target_id FROM vod_assignments WHERE item_id = ? ORDER BY target_type, target_id",
        itemId
      )
      .map((row) => ({ type: row.target_type as AssignmentTarget, id: Number(row.target_id) }));
  }

  #toSource(row: Record<string, unknown> | undefined): VodSource | null {
    if (!row) return null;
    return {
      id: Number(row.id),
      name: String(row.name),
      url: String(row.url),
      accountId: String(row.account_id),
      enabled: Number(row.enabled) === 1,
      lastImportAt: row.last_import_at === null ? null : Number(row.last_import_at),
      lastError: (row.last_error as string | null) ?? null,
      lastImportItems: Number(row.last_import_items ?? 0),
      createdAt: Number(row.created_at),
      items: Number(row.items ?? 0),
    };
  }

  #toCategory(row: Record<string, unknown> | undefined): VodCategory | null {
    if (!row) return null;
    return {
      id: Number(row.id),
      kind: String(row.kind) as VodKind,
      name: String(row.name),
      enabled: Number(row.enabled) === 1,
      items: Number(row.items ?? 0),
    };
  }

  #toItem(row: Record<string, unknown>): VodItem {
    const id = Number(row.id);
    return {
      id,
      sourceId: row.source_id === null ? null : Number(row.source_id),
      sourceName: (row.source_name as string | null) ?? null,
      kind: String(row.kind) as VodKind,
      title: String(row.title),
      year: Number(row.year),
      categoryId: row.category_id === null ? null : Number(row.category_id),
      category: (row.category_name as string | null) ?? null,
      season: row.season === null ? null : Number(row.season),
      episode: row.episode === null ? null : Number(row.episode),
      poster: (row.poster as string | null) ?? null,
      sourceUrl: String(row.source_url),
      container: (row.container as string | null) ?? null,
      quality: (row.quality as string | null) ?? null,
      state: String(row.state) as VodState,
      filePath: (row.file_path as string | null) ?? null,
      bytesTotal: Number(row.bytes_total ?? 0),
      bytesDone: Number(row.bytes_done ?? 0),
      error: (row.error as string | null) ?? null,
      importedAt: Number(row.imported_at),
      updatedAt: Number(row.updated_at),
      downloadedAt: row.downloaded_at === null ? null : Number(row.downloaded_at),
      assignments: this.#assignments(id),
    };
  }
}

const SOURCE_SELECT = `
  SELECT s.*, COUNT(i.id) AS items
    FROM vod_sources s
    LEFT JOIN vod_items i ON i.source_id = s.id`;

const CATEGORY_SELECT = `
  SELECT c.*, COUNT(i.id) AS items
    FROM vod_categories c
    LEFT JOIN vod_items i ON i.category_id = c.id`;

const ITEM_SELECT = `
  SELECT i.*, c.name AS category_name, c.enabled AS category_enabled, s.name AS source_name
    FROM vod_items i
    LEFT JOIN vod_categories c ON c.id = i.category_id
    LEFT JOIN vod_sources s ON s.id = i.source_id`;
