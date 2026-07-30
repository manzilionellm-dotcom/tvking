/*
 * VOD catalogue store.
 *
 * The aggregation rule lives in `ingest()`: one row per WORK, N rows per
 * source that carries it. Four providers offering the same film produce one
 * catalogue entry with four playable streams — the subscriber sees a library,
 * not four copies of it, and the edge gets a fallback URL for free when one
 * provider stalls.
 */

import type { Database } from "../db/database.ts";
import { systemWallClock, type WallClock } from "../clock.ts";
import { classify, type ClassifiedItem, type VodKind } from "./classify.ts";

export interface VodSource {
  id: number;
  name: string;
  url: string;
  accountId: string;
  enabled: boolean;
  lastIngestAt: number | null;
  lastError: string | null;
  lastItems: number;
  createdAt: number;
}

export interface VodCategory {
  id: number;
  kind: VodKind;
  name: string;
  enabled: boolean;
  titles: number;
}

export interface VodTitle {
  id: number;
  kind: VodKind;
  title: string;
  year: number;
  category: string | null;
  categoryId: number | null;
  poster: string | null;
  plot: string | null;
  rating: number | null;
  streams: number;
  updatedAt: number;
}

export interface VodStream {
  id: number;
  titleId: number;
  sourceId: number;
  sourceName: string;
  url: string;
  container: string | null;
  quality: string | null;
  season: number | null;
  episode: number | null;
}

export interface IngestEntry {
  name: string;
  url: string;
  group?: string;
  logo?: string;
  attributes?: Readonly<Record<string, string>>;
}

export interface IngestOutcome {
  seen: number;
  titlesCreated: number;
  titlesUpdated: number;
  streamsCreated: number;
  duplicatesMerged: number;
  categories: number;
}

export interface CatalogQuery {
  kind?: VodKind;
  categoryId?: number;
  search?: string;
  limit?: number;
  offset?: number;
  /** Hide titles whose category is switched off (what subscribers see). */
  enabledOnly?: boolean;
}

export class VodCatalog {
  #db: Database;
  #clock: WallClock;

  constructor(db: Database, clock: WallClock = systemWallClock) {
    this.#db = db;
    this.#clock = clock;
  }

  // ------------------------------------------------------------- sources

  upsertSource(input: {
    name: string;
    url: string;
    accountId: string;
    enabled?: boolean;
  }): VodSource {
    this.#db.run(
      `INSERT INTO vod_sources(name, url, account_id, enabled, created_at)
       VALUES(?, ?, ?, ?, ?)
       ON CONFLICT(name) DO UPDATE SET
         url = excluded.url, account_id = excluded.account_id, enabled = excluded.enabled`,
      input.name,
      input.url,
      input.accountId,
      input.enabled === false ? 0 : 1,
      this.#clock.now()
    );
    return this.sourceByName(input.name) as VodSource;
  }

  setSourceEnabled(id: number, enabled: boolean): boolean {
    return this.#db.run("UPDATE vod_sources SET enabled = ? WHERE id = ?", enabled ? 1 : 0, id)
      .changes > 0;
  }

  removeSource(id: number): boolean {
    return this.#db.run("DELETE FROM vod_sources WHERE id = ?", id).changes > 0;
  }

  sourceByName(name: string): VodSource | null {
    return this.#toSource(this.#db.get("SELECT * FROM vod_sources WHERE name = ?", name));
  }

  source(id: number): VodSource | null {
    return this.#toSource(this.#db.get("SELECT * FROM vod_sources WHERE id = ?", id));
  }

  listSources(): VodSource[] {
    return this.#db
      .all("SELECT * FROM vod_sources ORDER BY name")
      .map((row) => this.#toSource(row) as VodSource);
  }

  // ---------------------------------------------------------- categories

  listCategories(kind?: VodKind): VodCategory[] {
    const rows = kind
      ? this.#db.all(
          `SELECT c.*, COUNT(t.id) AS titles FROM vod_categories c
             LEFT JOIN vod_titles t ON t.category_id = c.id
            WHERE c.kind = ? GROUP BY c.id ORDER BY c.name`,
          kind
        )
      : this.#db.all(
          `SELECT c.*, COUNT(t.id) AS titles FROM vod_categories c
             LEFT JOIN vod_titles t ON t.category_id = c.id
            GROUP BY c.id ORDER BY c.kind, c.name`
        );
    return rows.map((row) => ({
      id: Number(row.id),
      kind: String(row.kind) as VodKind,
      name: String(row.name),
      enabled: Number(row.enabled) === 1,
      titles: Number(row.titles ?? 0),
    }));
  }

  setCategoryEnabled(id: number, enabled: boolean): boolean {
    return this.#db.run("UPDATE vod_categories SET enabled = ? WHERE id = ?", enabled ? 1 : 0, id)
      .changes > 0;
  }

  // -------------------------------------------------------------- titles

  titles(query: CatalogQuery = {}): VodTitle[] {
    const where: string[] = [];
    const params: unknown[] = [];
    if (query.kind) {
      where.push("t.kind = ?");
      params.push(query.kind);
    }
    if (query.categoryId !== undefined) {
      where.push("t.category_id = ?");
      params.push(query.categoryId);
    }
    if (query.search) {
      where.push("t.title LIKE ?");
      params.push(`%${query.search}%`);
    }
    if (query.enabledOnly) {
      where.push("(c.enabled IS NULL OR c.enabled = 1)");
    }
    const limit = Math.min(query.limit ?? 200, 1000);
    params.push(limit, query.offset ?? 0);

    return this.#db
      .all(
        `SELECT t.*, c.name AS category_name, COUNT(s.id) AS streams
           FROM vod_titles t
           LEFT JOIN vod_categories c ON c.id = t.category_id
           LEFT JOIN vod_streams s ON s.title_id = t.id
          ${where.length ? `WHERE ${where.join(" AND ")}` : ""}
          GROUP BY t.id
          ORDER BY t.title
          LIMIT ? OFFSET ?`,
        ...params
      )
      .map((row) => this.#toTitle(row));
  }

  title(id: number): VodTitle | null {
    const row = this.#db.get(
      `SELECT t.*, c.name AS category_name, COUNT(s.id) AS streams
         FROM vod_titles t
         LEFT JOIN vod_categories c ON c.id = t.category_id
         LEFT JOIN vod_streams s ON s.title_id = t.id
        WHERE t.id = ? GROUP BY t.id`,
      id
    );
    return row ? this.#toTitle(row) : null;
  }

  streams(titleId: number): VodStream[] {
    return this.#db
      .all(
        `SELECT s.*, src.name AS source_name FROM vod_streams s
           JOIN vod_sources src ON src.id = s.source_id
          WHERE s.title_id = ?
          ORDER BY s.season, s.episode, s.id`,
        titleId
      )
      .map((row) => ({
        id: Number(row.id),
        titleId: Number(row.title_id),
        sourceId: Number(row.source_id),
        sourceName: String(row.source_name),
        url: String(row.url),
        container: (row.container as string | null) ?? null,
        quality: (row.quality as string | null) ?? null,
        season: row.season === null ? null : Number(row.season),
        episode: row.episode === null ? null : Number(row.episode),
      }));
  }

  /** The stream a player should get: enabled source, best quality first. */
  preferredStream(titleId: number): VodStream | null {
    const streams = this.streams(titleId).filter((stream) => {
      const source = this.source(stream.sourceId);
      return source?.enabled !== false;
    });
    if (streams.length === 0) return null;
    const rank = (quality: string | null) =>
      quality === null ? 0 : ["SD", "HD", "FHD", "1080P", "UHD", "4K", "2160P"].indexOf(quality) + 1;
    return [...streams].sort((a, b) => rank(b.quality) - rank(a.quality))[0];
  }

  counts(): { movies: number; series: number; streams: number; categories: number } {
    const one = (sql: string, ...params: unknown[]) =>
      Number((this.#db.get<{ n: number }>(sql, ...params) as { n: number } | undefined)?.n ?? 0);
    return {
      movies: one("SELECT COUNT(*) AS n FROM vod_titles WHERE kind = 'movie'"),
      series: one("SELECT COUNT(*) AS n FROM vod_titles WHERE kind = 'series'"),
      streams: one("SELECT COUNT(*) AS n FROM vod_streams"),
      categories: one("SELECT COUNT(*) AS n FROM vod_categories"),
    };
  }

  // ------------------------------------------------------------- ingest

  /**
   * Folds a batch of playlist entries into the catalogue. One transaction for
   * the whole batch: a partially ingested source is worse than a stale one.
   */
  ingest(sourceId: number, entries: readonly IngestEntry[]): IngestOutcome {
    const now = this.#clock.now();
    const outcome: IngestOutcome = {
      seen: entries.length,
      titlesCreated: 0,
      titlesUpdated: 0,
      streamsCreated: 0,
      duplicatesMerged: 0,
      categories: 0,
    };
    const categoryCache = new Map<string, number>();

    this.#db.transaction(() => {
      for (const entry of entries) {
        const item = classify(entry);
        const categoryId = this.#categoryId(item.kind, item.category, categoryCache, outcome);
        const titleId = this.#titleId(item, categoryId, entry, now, outcome);

        const inserted = this.#db.run(
          `INSERT INTO vod_streams(title_id, source_id, url, container, quality, season, episode, added_at)
           VALUES(?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(source_id, url) DO NOTHING`,
          titleId,
          sourceId,
          entry.url,
          item.container,
          item.quality,
          item.season,
          item.episode,
          now
        );
        if (inserted.changes > 0) outcome.streamsCreated += 1;
      }
    });
    return outcome;
  }

  markIngest(sourceId: number, result: { items: number; error?: string | null }): void {
    this.#db.run(
      "UPDATE vod_sources SET last_ingest_at = ?, last_items = ?, last_error = ? WHERE id = ?",
      this.#clock.now(),
      result.items,
      result.error ?? null,
      sourceId
    );
  }

  // ----------------------------------------------------------- internals

  #categoryId(
    kind: VodKind,
    name: string,
    cache: Map<string, number>,
    outcome: IngestOutcome
  ): number {
    const key = `${kind}:${name}`;
    const cached = cache.get(key);
    if (cached !== undefined) return cached;

    const existing = this.#db.get<{ id: number }>(
      "SELECT id FROM vod_categories WHERE kind = ? AND name = ?",
      kind,
      name
    );
    if (existing) {
      cache.set(key, existing.id);
      return existing.id;
    }
    const created = this.#db.run(
      "INSERT INTO vod_categories(kind, name, enabled) VALUES(?, ?, 1)",
      kind,
      name
    );
    outcome.categories += 1;
    cache.set(key, created.lastInsertRowid);
    return created.lastInsertRowid;
  }

  #titleId(
    item: ClassifiedItem,
    categoryId: number,
    entry: IngestEntry,
    now: number,
    outcome: IngestOutcome
  ): number {
    const existing = this.#db.get<{ id: number; poster: string | null }>(
      "SELECT id, poster FROM vod_titles WHERE kind = ? AND normalized = ? AND year = ?",
      item.kind,
      item.normalized,
      item.year
    );

    if (existing) {
      outcome.duplicatesMerged += 1;
      // Only fill gaps: a later source must not overwrite metadata that a
      // better-curated one already provided.
      const poster = existing.poster ?? entry.logo ?? null;
      this.#db.run(
        "UPDATE vod_titles SET poster = ?, category_id = COALESCE(category_id, ?), updated_at = ? WHERE id = ?",
        poster,
        categoryId,
        now,
        existing.id
      );
      outcome.titlesUpdated += 1;
      return existing.id;
    }

    const created = this.#db.run(
      `INSERT INTO vod_titles(kind, title, normalized, year, category_id, poster, plot, rating, created_at, updated_at)
       VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      item.kind,
      item.title,
      item.normalized,
      item.year,
      categoryId,
      entry.logo ?? null,
      entry.attributes?.["plot"] ?? null,
      entry.attributes?.["rating"] ? Number(entry.attributes["rating"]) : null,
      now,
      now
    );
    outcome.titlesCreated += 1;
    return created.lastInsertRowid;
  }

  #toSource(row: Record<string, unknown> | undefined): VodSource | null {
    if (!row) return null;
    return {
      id: Number(row.id),
      name: String(row.name),
      url: String(row.url),
      accountId: String(row.account_id),
      enabled: Number(row.enabled) === 1,
      lastIngestAt: row.last_ingest_at === null ? null : Number(row.last_ingest_at),
      lastError: (row.last_error as string | null) ?? null,
      lastItems: Number(row.last_items ?? 0),
      createdAt: Number(row.created_at),
    };
  }

  #toTitle(row: Record<string, unknown>): VodTitle {
    return {
      id: Number(row.id),
      kind: String(row.kind) as VodKind,
      title: String(row.title),
      year: Number(row.year),
      category: (row.category_name as string | null) ?? null,
      categoryId: row.category_id === null ? null : Number(row.category_id),
      poster: (row.poster as string | null) ?? null,
      plot: (row.plot as string | null) ?? null,
      rating: row.rating === null ? null : Number(row.rating),
      streams: Number(row.streams ?? 0),
      updatedAt: Number(row.updated_at),
    };
  }
}
