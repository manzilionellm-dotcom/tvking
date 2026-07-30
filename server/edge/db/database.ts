/*
 * SQLite access layer.
 *
 * Uses Node's built-in `node:sqlite` — no dependency, no native build step, and
 * the file is a single artefact an operator can copy or back up. The proxy's
 * hot path never touches it: the database holds subscribers, the VOD catalogue
 * and the cache index, none of which sit between a client and its bytes.
 *
 * WAL is on so a long ingestion run cannot block a subscriber lookup.
 */

import { DatabaseSync, type StatementSync } from "node:sqlite";
import { MIGRATIONS, type Migration } from "./schema.ts";

export type Row = Record<string, unknown>;

export interface MigrationResult {
  applied: number[];
  version: number;
}

export class Database {
  #db: DatabaseSync;
  #statements = new Map<string, StatementSync>();

  constructor(location = ":memory:") {
    this.#db = new DatabaseSync(location);
    this.#db.exec("PRAGMA journal_mode = WAL");
    this.#db.exec("PRAGMA foreign_keys = ON");
    this.#db.exec("PRAGMA busy_timeout = 5000");
  }

  get handle(): DatabaseSync {
    return this.#db;
  }

  /** Prepared statements are cached: the same SQL is compiled once. */
  prepare(sql: string): StatementSync {
    let statement = this.#statements.get(sql);
    if (!statement) {
      statement = this.#db.prepare(sql);
      this.#statements.set(sql, statement);
    }
    return statement;
  }

  all<T extends object = Row>(sql: string, ...params: unknown[]): T[] {
    return this.prepare(sql).all(...(params as never[])) as T[];
  }

  get<T extends object = Row>(sql: string, ...params: unknown[]): T | undefined {
    return this.prepare(sql).get(...(params as never[])) as T | undefined;
  }

  run(sql: string, ...params: unknown[]): { changes: number; lastInsertRowid: number } {
    const result = this.prepare(sql).run(...(params as never[]));
    return {
      changes: Number(result.changes),
      lastInsertRowid: Number(result.lastInsertRowid),
    };
  }

  exec(sql: string): void {
    this.#db.exec(sql);
  }

  /** Runs `fn` in a transaction, rolling back on any throw. */
  transaction<T>(fn: () => T): T {
    this.#db.exec("BEGIN");
    try {
      const result = fn();
      this.#db.exec("COMMIT");
      return result;
    } catch (error) {
      this.#db.exec("ROLLBACK");
      throw error;
    }
  }

  close(): void {
    this.#statements.clear();
    this.#db.close();
  }
}

/**
 * Applies every migration the database has not seen yet, each in its own
 * transaction, and returns what was applied. Safe to call on every boot.
 */
export function migrate(
  db: Database,
  migrations: readonly Migration[] = MIGRATIONS,
  now = Date.now()
): MigrationResult {
  db.exec(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version    INTEGER PRIMARY KEY,
      name       TEXT    NOT NULL,
      applied_at INTEGER NOT NULL
    )
  `);

  const seen = new Set(
    db.all<{ version: number }>("SELECT version FROM schema_migrations").map((r) => r.version)
  );
  const applied: number[] = [];

  for (const migration of [...migrations].sort((a, b) => a.version - b.version)) {
    if (seen.has(migration.version)) continue;
    db.transaction(() => {
      db.exec(migration.sql);
      db.run(
        "INSERT INTO schema_migrations(version, name, applied_at) VALUES(?, ?, ?)",
        migration.version,
        migration.name,
        now
      );
    });
    applied.push(migration.version);
  }

  return { applied, version: schemaVersion(db) };
}

export function schemaVersion(db: Database): number {
  const row = db.get<{ version: number }>(
    "SELECT MAX(version) AS version FROM schema_migrations"
  );
  return row?.version ?? 0;
}

/** Opens a database file (or `:memory:`) and brings it up to date. */
export function openDatabase(location = ":memory:"): Database {
  const db = new Database(location);
  migrate(db);
  return db;
}
