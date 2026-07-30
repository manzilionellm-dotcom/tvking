/*
 * Schema migrations.
 *
 * Forward-only, numbered, and applied inside a transaction each: the version
 * table is the single source of truth about what a given database contains, so
 * an interrupted upgrade leaves either the old schema or the new one, never a
 * half-applied mixture. Migrations are append-only — edit one that has shipped
 * and every existing install silently disagrees with the code.
 */

export interface Migration {
  version: number;
  name: string;
  sql: string;
}

export const MIGRATIONS: readonly Migration[] = [
  {
    version: 1,
    name: "portal-and-vod",
    sql: `
      -- ---------------------------------------------------------------- portal
      -- A package is what a device is allowed to watch: one master account, and
      -- optionally a restriction to some groups or channels ([] = everything).
      CREATE TABLE packages (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        name         TEXT    NOT NULL UNIQUE,
        account_id   TEXT    NOT NULL,
        groups_json  TEXT    NOT NULL DEFAULT '[]',
        channels_json TEXT   NOT NULL DEFAULT '[]',
        vod_enabled  INTEGER NOT NULL DEFAULT 1,
        created_at   INTEGER NOT NULL
      );

      -- A device is a subscriber identity: a MAG box (MAC) or an Xtream login.
      -- Both may be set; either one authenticates the same package.
      CREATE TABLE devices (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        mac           TEXT    UNIQUE,
        username      TEXT    UNIQUE,
        password_hash TEXT,
        label         TEXT    NOT NULL DEFAULT '',
        package_id    INTEGER REFERENCES packages(id) ON DELETE SET NULL,
        max_connections INTEGER NOT NULL DEFAULT 1,
        disabled      INTEGER NOT NULL DEFAULT 0,
        note          TEXT    NOT NULL DEFAULT '',
        created_at    INTEGER NOT NULL,
        updated_at    INTEGER NOT NULL,
        CHECK (mac IS NOT NULL OR username IS NOT NULL)
      );

      -- Grants are append-only history: "when did this device get what, and who
      -- revoked it" is an answer an operator eventually needs.
      CREATE TABLE subscriptions (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id  INTEGER NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
        plan       TEXT    NOT NULL,
        starts_at  INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        revoked_at INTEGER,
        note       TEXT    NOT NULL DEFAULT ''
      );
      CREATE INDEX subscriptions_device_idx ON subscriptions(device_id, expires_at DESC);

      -- ------------------------------------------------------------------ vod
      CREATE TABLE vod_sources (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL UNIQUE,
        url         TEXT    NOT NULL,
        account_id  TEXT    NOT NULL,
        enabled     INTEGER NOT NULL DEFAULT 1,
        last_ingest_at INTEGER,
        last_error  TEXT,
        last_items  INTEGER NOT NULL DEFAULT 0,
        created_at  INTEGER NOT NULL
      );

      CREATE TABLE vod_categories (
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        kind    TEXT    NOT NULL,
        name    TEXT    NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        UNIQUE (kind, name)
      );

      -- One row per WORK, not per playlist line: the same film present in four
      -- source playlists is one title with four streams. year defaults to 0
      -- rather than NULL because SQLite treats NULLs as distinct in a UNIQUE
      -- index, which would defeat the dedup key.
      CREATE TABLE vod_titles (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        kind        TEXT    NOT NULL,
        title       TEXT    NOT NULL,
        normalized  TEXT    NOT NULL,
        year        INTEGER NOT NULL DEFAULT 0,
        category_id INTEGER REFERENCES vod_categories(id) ON DELETE SET NULL,
        poster      TEXT,
        plot        TEXT,
        rating      REAL,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL,
        UNIQUE (kind, normalized, year)
      );
      CREATE INDEX vod_titles_category_idx ON vod_titles(category_id);
      CREATE INDEX vod_titles_kind_idx ON vod_titles(kind, title);

      CREATE TABLE vod_streams (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        title_id  INTEGER NOT NULL REFERENCES vod_titles(id) ON DELETE CASCADE,
        source_id INTEGER NOT NULL REFERENCES vod_sources(id) ON DELETE CASCADE,
        url       TEXT    NOT NULL,
        container TEXT,
        quality   TEXT,
        season    INTEGER,
        episode   INTEGER,
        added_at  INTEGER NOT NULL,
        UNIQUE (source_id, url)
      );
      CREATE INDEX vod_streams_title_idx ON vod_streams(title_id);

      -- Disk cache index. Kept in the database so eviction order survives a
      -- restart: an LRU that forgets what was recently used is not an LRU.
      CREATE TABLE vod_chunks (
        key          TEXT    NOT NULL,
        idx          INTEGER NOT NULL,
        bytes        INTEGER NOT NULL,
        created_at   INTEGER NOT NULL,
        last_used_at INTEGER NOT NULL,
        hits         INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (key, idx)
      );
      CREATE INDEX vod_chunks_lru_idx ON vod_chunks(last_used_at);
    `,
  },
];
