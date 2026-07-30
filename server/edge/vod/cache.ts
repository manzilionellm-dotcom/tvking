/*
 * VOD chunk cache.
 *
 * Live and VOD need opposite caches. Live is a moving window everyone reads at
 * the same offset — hence the in-memory ring buffer. VOD is a fixed file that
 * different viewers enter at different points and seek around in, so the useful
 * unit is a fixed-size byte range on disk, keyed by (file, chunk index).
 *
 * What that buys: the second viewer of a popular film costs zero WAN bytes for
 * every chunk the first one already pulled, and a seek back into an already
 * watched part is free. Concurrent readers of the same missing chunk collapse
 * onto ONE upstream range request (single-flight again).
 *
 * The index lives in SQLite so eviction order survives a restart: an LRU that
 * forgets what was recently used is not an LRU.
 */

import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { mkdir, rename, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import type { Database } from "../db/database.ts";
import { systemWallClock, type WallClock } from "../clock.ts";
import { SingleFlight } from "../singleflight.ts";
import { UpstreamError, type OriginTransport } from "../origin.ts";
import {
  assertMirrorsMasterSignature,
  masterSignature,
  type UpstreamIdentity,
} from "../sanitize.ts";
import type { SlotLease } from "../slots.ts";

export interface ChunkCacheOptions {
  db: Database;
  dir: string;
  transport: OriginTransport;
  /** Chunk size. Bigger = fewer requests, more waste on a seek. */
  chunkBytes?: number;
  /** Total disk budget; the least recently used chunks go first. */
  maxBytes?: number;
  clock?: WallClock;
}

export interface CacheStats {
  chunks: number;
  bytes: number;
  maxBytes: number;
  hits: number;
  misses: number;
  evictions: number;
  bytesFromOrigin: number;
  bytesServed: number;
  /** Share of served bytes that never crossed the WAN. */
  hitRatio: number;
}

export interface VodTarget {
  url: string;
  identity: UpstreamIdentity;
  /** Opened lazily on the first miss and released by the caller. */
  acquireLease?: () => Promise<SlotLease | null>;
}

export class VodError extends Error {
  name = "VodError";
  status: number;

  constructor(message: string, status = 502) {
    super(message);
    this.status = status;
  }
}

const DEFAULT_CHUNK = 4 * 1024 * 1024;

export function chunkKey(url: string): string {
  return createHash("sha256").update(url).digest("hex").slice(0, 32);
}

export class ChunkCache {
  #db: Database;
  #dir: string;
  #transport: OriginTransport;
  #chunkBytes: number;
  #maxBytes: number;
  #clock: WallClock;
  #flight = new SingleFlight<number>();
  #sizes = new Map<string, number>(); // key → total file size, learned from Content-Range
  #hits = 0;
  #misses = 0;
  #evictions = 0;
  #bytesFromOrigin = 0;
  #bytesServed = 0;

  constructor(options: ChunkCacheOptions) {
    this.#db = options.db;
    this.#dir = options.dir;
    this.#transport = options.transport;
    this.#chunkBytes = options.chunkBytes ?? DEFAULT_CHUNK;
    this.#maxBytes = options.maxBytes ?? 2 * 1024 * 1024 * 1024;
    this.#clock = options.clock ?? systemWallClock;
  }

  get chunkBytes(): number {
    return this.#chunkBytes;
  }

  stats(): CacheStats {
    const row = this.#db.get<{ chunks: number; bytes: number }>(
      "SELECT COUNT(*) AS chunks, COALESCE(SUM(bytes), 0) AS bytes FROM vod_chunks"
    );
    return {
      chunks: Number(row?.chunks ?? 0),
      bytes: Number(row?.bytes ?? 0),
      maxBytes: this.#maxBytes,
      hits: this.#hits,
      misses: this.#misses,
      evictions: this.#evictions,
      bytesFromOrigin: this.#bytesFromOrigin,
      bytesServed: this.#bytesServed,
      hitRatio:
        this.#bytesServed === 0
          ? 0
          : Math.max(0, (this.#bytesServed - this.#bytesFromOrigin) / this.#bytesServed),
    };
  }

  /** Total size of the remote file, once known (after the first range request). */
  knownSize(url: string): number | null {
    return this.#sizes.get(chunkKey(url)) ?? null;
  }

  /**
   * Learns the file size so a Range response can carry Content-Range. Costs one
   * one-byte request per file per process — after that it is remembered. Returns
   * null when the origin will not say (no Content-Range), in which case the
   * response falls back to a plain unsized stream.
   */
  async probeSize(target: VodTarget, signal?: AbortSignal): Promise<number | null> {
    const key = chunkKey(target.url);
    const known = this.#sizes.get(key);
    if (known !== undefined) return known;

    let lease: SlotLease | null = null;
    try {
      if (target.acquireLease) {
        lease = await target.acquireLease();
        if (!lease) throw new VodError("master account is busy streaming", 503);
      }
      const headers = { ...masterSignature(target.identity), range: "bytes=0-0" };
      const response = await this.#transport.open({
        url: target.url,
        headers,
        signal: signal ?? new AbortController().signal,
      });
      try {
        this.#learnSize(key, response.headers["content-range"]);
        const length = response.headers["content-length"];
        if (!this.#sizes.has(key) && response.status === 200 && length) {
          this.#sizes.set(key, Number(length));
        }
      } finally {
        response.close();
      }
      return this.#sizes.get(key) ?? null;
    } finally {
      lease?.release();
    }
  }

  /**
   * Yields `[start, end]` (inclusive) of the remote file, pulling only the
   * chunks that are missing. `end` may be beyond the file; it is clamped once
   * the real size is known.
   */
  async *read(
    target: VodTarget,
    start: number,
    end: number,
    signal?: AbortSignal
  ): AsyncGenerator<Uint8Array> {
    if (start < 0 || end < start) throw new VodError("invalid byte range", 416);
    const key = chunkKey(target.url);
    let lease: SlotLease | null = null;

    try {
      let offset = start;
      while (offset <= end) {
        if (signal?.aborted) return;
        const index = Math.floor(offset / this.#chunkBytes);
        const chunkStart = index * this.#chunkBytes;

        let bytes = this.#lookup(key, index);
        if (bytes === null) {
          this.#misses += 1;
          // The lease is taken on the FIRST miss and held for the rest of the
          // response: acquiring per chunk would make a film fight the live
          // channel for the slot every few seconds.
          if (!lease && target.acquireLease) {
            lease = await target.acquireLease();
            if (!lease) {
              throw new VodError("master account is busy streaming", 503);
            }
          }
          bytes = await this.#flight.run(`${key}:${index}`, () =>
            this.#fetchChunk(key, target, index, signal)
          );
        } else {
          this.#hits += 1;
          this.#touch(key, index);
        }

        if (bytes === 0) return; // past the end of the file
        const chunkEnd = chunkStart + bytes - 1;
        const from = offset - chunkStart;
        const to = Math.min(end, chunkEnd) - chunkStart;
        if (to < from) return;

        for await (const piece of this.#readChunk(key, index, from, to)) {
          this.#bytesServed += piece.byteLength;
          yield piece;
        }

        offset = chunkEnd + 1;
        if (bytes < this.#chunkBytes) return; // short chunk = end of file
      }
    } finally {
      lease?.release();
    }
  }

  /** Drops every chunk of one file (used when a source URL changes). */
  async purge(url: string): Promise<number> {
    const key = chunkKey(url);
    const rows = this.#db.all<{ idx: number }>("SELECT idx FROM vod_chunks WHERE key = ?", key);
    await rm(this.#chunkDir(key), { recursive: true, force: true });
    this.#db.run("DELETE FROM vod_chunks WHERE key = ?", key);
    return rows.length;
  }

  // ----------------------------------------------------------- internals

  #chunkDir(key: string): string {
    return path.join(this.#dir, key.slice(0, 2), key);
  }

  #chunkPath(key: string, index: number): string {
    return path.join(this.#chunkDir(key), `${index}.bin`);
  }

  #lookup(key: string, index: number): number | null {
    const row = this.#db.get<{ bytes: number }>(
      "SELECT bytes FROM vod_chunks WHERE key = ? AND idx = ?",
      key,
      index
    );
    return row ? Number(row.bytes) : null;
  }

  #touch(key: string, index: number): void {
    this.#db.run(
      "UPDATE vod_chunks SET last_used_at = ?, hits = hits + 1 WHERE key = ? AND idx = ?",
      this.#clock.now(),
      key,
      index
    );
  }

  async *#readChunk(key: string, index: number, from: number, to: number): AsyncGenerator<Uint8Array> {
    const stream = createReadStream(this.#chunkPath(key, index), { start: from, end: to });
    for await (const piece of stream) yield piece as Uint8Array;
  }

  async #fetchChunk(
    key: string,
    target: VodTarget,
    index: number,
    signal?: AbortSignal
  ): Promise<number> {
    const cached = this.#lookup(key, index);
    if (cached !== null) return cached; // filled while we queued behind the flight

    const start = index * this.#chunkBytes;
    const end = start + this.#chunkBytes - 1;
    const controller = new AbortController();
    const onAbort = () => controller.abort();
    signal?.addEventListener("abort", onAbort, { once: true });

    // The master signature plus ONE extra field: a byte range derived from the
    // chunk grid. It is a multiple of the chunk size, identical whichever
    // client asked, so it says nothing about the viewer.
    const headers = { ...masterSignature(target.identity), range: `bytes=${start}-${end}` };
    assertMirrorsMasterSignature(headers, target.identity, { allow: ["range"] });

    let response;
    try {
      response = await this.#transport.open({ url: target.url, headers, signal: controller.signal });
    } finally {
      signal?.removeEventListener("abort", onAbort);
    }

    try {
      if (response.status === 416) return 0; // past the end of the file
      if (response.status !== 206 && response.status !== 200) {
        throw new VodError(`origin refused the range request (HTTP ${response.status})`);
      }
      if (response.status === 200 && index > 0) {
        // Without ranges we would have to download the whole film to serve its
        // middle: refuse loudly instead of quietly wasting the budget.
        throw new VodError("origin does not support range requests");
      }
      this.#learnSize(key, response.headers["content-range"]);

      const pieces: Uint8Array[] = [];
      let total = 0;
      for await (const piece of response.body) {
        pieces.push(piece);
        total += piece.byteLength;
        if (total >= this.#chunkBytes) break;
      }
      const buffer = new Uint8Array(Math.min(total, this.#chunkBytes));
      let offset = 0;
      for (const piece of pieces) {
        const room = buffer.byteLength - offset;
        if (room <= 0) break;
        buffer.set(piece.subarray(0, Math.min(piece.byteLength, room)), offset);
        offset += Math.min(piece.byteLength, room);
      }

      this.#bytesFromOrigin += buffer.byteLength;
      if (buffer.byteLength > 0) await this.#store(key, index, buffer);
      return buffer.byteLength;
    } catch (error) {
      if (error instanceof VodError) throw error;
      const message = error instanceof Error ? error.message : String(error);
      throw new UpstreamError(`VOD chunk fetch failed: ${message}`);
    } finally {
      response.close();
    }
  }

  #learnSize(key: string, contentRange: string | undefined): void {
    const match = /\/(\d+)\s*$/.exec(contentRange ?? "");
    if (match) this.#sizes.set(key, Number(match[1]));
  }

  async #store(key: string, index: number, data: Uint8Array): Promise<void> {
    const dir = this.#chunkDir(key);
    await mkdir(dir, { recursive: true });
    const target = this.#chunkPath(key, index);
    // Write-then-rename: a reader must never open a half-written chunk.
    const temp = `${target}.${process.pid}.tmp`;
    await writeFile(temp, data);
    await rename(temp, target);

    const now = this.#clock.now();
    this.#db.run(
      `INSERT INTO vod_chunks(key, idx, bytes, created_at, last_used_at, hits)
       VALUES(?, ?, ?, ?, ?, 0)
       ON CONFLICT(key, idx) DO UPDATE SET bytes = excluded.bytes, last_used_at = excluded.last_used_at`,
      key,
      index,
      data.byteLength,
      now,
      now
    );
    await this.#evict();
  }

  async #evict(): Promise<void> {
    let total = Number(
      this.#db.get<{ bytes: number }>("SELECT COALESCE(SUM(bytes), 0) AS bytes FROM vod_chunks")
        ?.bytes ?? 0
    );
    while (total > this.#maxBytes) {
      const victim = this.#db.get<{ key: string; idx: number; bytes: number }>(
        "SELECT key, idx, bytes FROM vod_chunks ORDER BY last_used_at ASC, idx ASC LIMIT 1"
      );
      if (!victim) return;
      await rm(this.#chunkPath(victim.key, victim.idx), { force: true });
      this.#db.run("DELETE FROM vod_chunks WHERE key = ? AND idx = ?", victim.key, victim.idx);
      total -= Number(victim.bytes);
      this.#evictions += 1;
    }
  }
}
