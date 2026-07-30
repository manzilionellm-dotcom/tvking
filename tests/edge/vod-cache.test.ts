/*
 * VOD chunk cache: the bandwidth claim ("popular titles cost the WAN once")
 * measured against an origin that counts its own range requests.
 */

import { mkdtemp, rm, readdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { openDatabase, type Database } from "../../server/edge/db/database.ts";
import { ChunkCache, VodError, chunkKey } from "../../server/edge/vod/cache.ts";
import { masterDevice } from "../../server/edge/sanitize.ts";
import type { OriginRequest, OriginResponse, OriginTransport } from "../../server/edge/origin.ts";
import { tick } from "./mock-origin.ts";

/** An origin serving one deterministic file, with real Range semantics. */
class FileOrigin implements OriginTransport {
  requests: Array<{ url: string; range: string | undefined }> = [];
  bytesServed = 0;
  delayMs = 0;
  supportsRanges = true;
  #size: number;

  constructor(size: number) {
    this.#size = size;
  }

  /** Byte i of the file is `i % 251` — any misplacement is detectable. */
  static byteAt(index: number): number {
    return index % 251;
  }

  async open(request: OriginRequest): Promise<OriginResponse> {
    const range = request.headers.range;
    this.requests.push({ url: request.url, range });
    if (this.delayMs > 0) await new Promise((resolve) => setTimeout(resolve, this.delayMs));

    if (!this.supportsRanges) {
      const body = this.#slice(0, this.#size - 1);
      return this.#respond(200, { "content-length": String(this.#size) }, body);
    }

    const match = /^bytes=(\d+)-(\d*)$/.exec(range ?? "");
    if (!match) {
      return this.#respond(200, { "content-length": String(this.#size) }, this.#slice(0, this.#size - 1));
    }
    const start = Number(match[1]);
    if (start >= this.#size) return this.#respond(416, {}, new Uint8Array());
    const end = Math.min(match[2] === "" ? this.#size - 1 : Number(match[2]), this.#size - 1);

    return this.#respond(
      206,
      { "content-range": `bytes ${start}-${end}/${this.#size}` },
      this.#slice(start, end)
    );
  }

  #slice(start: number, end: number): Uint8Array {
    const out = new Uint8Array(end - start + 1);
    for (let i = 0; i < out.length; i += 1) out[i] = FileOrigin.byteAt(start + i);
    this.bytesServed += out.length;
    return out;
  }

  #respond(status: number, headers: Record<string, string>, body: Uint8Array): OriginResponse {
    return {
      status,
      headers: { "content-type": "video/mp4", ...headers },
      // Delivered in small pieces, like a real socket.
      body: (async function* stream() {
        for (let offset = 0; offset < body.byteLength; offset += 4096) {
          yield body.subarray(offset, Math.min(offset + 4096, body.byteLength));
        }
      })(),
      close() {},
    };
  }
}

const IDENTITY = masterDevice("vlc");
const FILE_SIZE = 40_000;
const CHUNK = 8_192;

let db: Database;
let dir: string;

beforeEach(async () => {
  db = openDatabase(":memory:");
  dir = await mkdtemp(path.join(tmpdir(), "tvking-vod-"));
});

afterEach(async () => {
  db.close();
  await rm(dir, { recursive: true, force: true });
});

function makeCache(origin: FileOrigin, maxBytes = 10 * 1024 * 1024) {
  return new ChunkCache({ db, dir, transport: origin, chunkBytes: CHUNK, maxBytes });
}

async function collect(source: AsyncIterable<Uint8Array>): Promise<Uint8Array> {
  const pieces: Uint8Array[] = [];
  let total = 0;
  for await (const piece of source) {
    pieces.push(piece);
    total += piece.byteLength;
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (const piece of pieces) {
    out.set(piece, offset);
    offset += piece.byteLength;
  }
  return out;
}

function expectBytes(data: Uint8Array, start: number): void {
  for (let i = 0; i < data.length; i += 1) {
    if (data[i] !== FileOrigin.byteAt(start + i)) {
      throw new Error(`byte ${start + i} is ${data[i]}, expected ${FileOrigin.byteAt(start + i)}`);
    }
  }
}

describe("ChunkCache", () => {
  it("serves an exact byte range and caches what it fetched", async () => {
    const origin = new FileOrigin(FILE_SIZE);
    const cache = makeCache(origin);
    const target = { url: "http://o/movie/1.mp4", identity: IDENTITY };

    const data = await collect(cache.read(target, 100, 999));
    expect(data.byteLength).toBe(900);
    expectBytes(data, 100);
    expect(origin.requests).toHaveLength(1); // one chunk covered it

    const stats = cache.stats();
    expect(stats.chunks).toBe(1);
    expect(stats.misses).toBe(1);
    expect(stats.hits).toBe(0);
  });

  it("costs the WAN nothing the second time — the popular-title case", async () => {
    const origin = new FileOrigin(FILE_SIZE);
    const cache = makeCache(origin);
    const target = { url: "http://o/movie/1.mp4", identity: IDENTITY };

    const first = await collect(cache.read(target, 0, 20_000));
    const upstreamAfterFirst = origin.requests.length;
    const wanAfterFirst = cache.stats().bytesFromOrigin;
    const second = await collect(cache.read(target, 0, 20_000));

    expect(second).toEqual(first);
    expect(origin.requests).toHaveLength(upstreamAfterFirst); // not one request
    expect(cache.stats().bytesFromOrigin).toBe(wanAfterFirst); // not one byte
    expect(cache.stats().hits).toBeGreaterThan(0);
    // The ratio counts WHOLE chunks pulled against bytes served, so it lags at
    // first (a 100-byte read still costs a chunk) and climbs as the film is
    // watched. A second full pass already puts it above a third.
    expect(cache.stats().hitRatio).toBeGreaterThan(0.35);
  });

  it("collapses concurrent readers of the same missing chunk onto one request", async () => {
    const origin = new FileOrigin(FILE_SIZE);
    origin.delayMs = 10; // make the window real
    const cache = makeCache(origin);
    const target = { url: "http://o/movie/1.mp4", identity: IDENTITY };

    const readers = await Promise.all(
      Array.from({ length: 25 }, () => collect(cache.read(target, 0, 4_000)))
    );

    for (const data of readers) expectBytes(data, 0);
    // One size probe + one chunk, however many viewers arrived together.
    expect(origin.requests.filter((r) => r.range === `bytes=0-${CHUNK - 1}`)).toHaveLength(1);
  });

  it("fetches only the chunks a seek touches", async () => {
    const origin = new FileOrigin(FILE_SIZE);
    const cache = makeCache(origin);
    const target = { url: "http://o/movie/1.mp4", identity: IDENTITY };

    const data = await collect(cache.read(target, 30_000, 30_100));
    expectBytes(data, 30_000);
    // Chunk 3 only (24576..32767): a seek must not drag the whole film.
    const ranges = origin.requests.map((r) => r.range).filter(Boolean);
    expect(ranges).toEqual([`bytes=${3 * CHUNK}-${4 * CHUNK - 1}`]);
    expect(cache.stats().bytesFromOrigin).toBeLessThanOrEqual(CHUNK);
  });

  it("clamps a range that runs past the end of the file", async () => {
    const origin = new FileOrigin(FILE_SIZE);
    const cache = makeCache(origin);
    const target = { url: "http://o/movie/1.mp4", identity: IDENTITY };

    const data = await collect(cache.read(target, FILE_SIZE - 50, FILE_SIZE + 5_000));
    expect(data.byteLength).toBe(50);
    expectBytes(data, FILE_SIZE - 50);
  });

  it("learns the file size from Content-Range", async () => {
    const origin = new FileOrigin(FILE_SIZE);
    const cache = makeCache(origin);
    const target = { url: "http://o/movie/1.mp4", identity: IDENTITY };

    expect(cache.knownSize(target.url)).toBeNull();
    expect(await cache.probeSize(target)).toBe(FILE_SIZE);
    expect(cache.knownSize(target.url)).toBe(FILE_SIZE);
    // Remembered: no second probe.
    const before = origin.requests.length;
    await cache.probeSize(target);
    expect(origin.requests).toHaveLength(before);
  });

  it("evicts least-recently-used chunks to stay within the disk budget", async () => {
    const origin = new FileOrigin(FILE_SIZE);
    const cache = makeCache(origin, 3 * CHUNK); // room for 3 chunks
    const target = { url: "http://o/movie/1.mp4", identity: IDENTITY };

    await collect(cache.read(target, 0, CHUNK - 1)); // chunk 0
    await collect(cache.read(target, CHUNK, 2 * CHUNK - 1)); // chunk 1
    await collect(cache.read(target, 2 * CHUNK, 3 * CHUNK - 1)); // chunk 2
    await collect(cache.read(target, 0, 10)); // touch chunk 0 so 1 is oldest
    await collect(cache.read(target, 3 * CHUNK, 4 * CHUNK - 1)); // chunk 3 → evict

    const stats = cache.stats();
    expect(stats.bytes).toBeLessThanOrEqual(3 * CHUNK);
    expect(stats.evictions).toBeGreaterThan(0);

    const rows = db.all<{ idx: number }>("SELECT idx FROM vod_chunks ORDER BY idx");
    expect(rows.map((r) => r.idx)).not.toContain(1); // the least recently used one
    expect(rows.map((r) => r.idx)).toContain(0);
  });

  it("keeps the on-disk files in step with the index", async () => {
    const origin = new FileOrigin(FILE_SIZE);
    const cache = makeCache(origin);
    const target = { url: "http://o/movie/1.mp4", identity: IDENTITY };
    await collect(cache.read(target, 0, 100));

    const key = chunkKey(target.url);
    const files = await readdir(path.join(dir, key.slice(0, 2), key));
    expect(files).toEqual(["0.bin"]);

    expect(await cache.purge(target.url)).toBe(1);
    expect(cache.stats().chunks).toBe(0);
  });

  it("refuses an origin that ignores Range instead of pulling the whole film", async () => {
    const origin = new FileOrigin(FILE_SIZE);
    origin.supportsRanges = false;
    const cache = makeCache(origin);
    const target = { url: "http://o/movie/1.mp4", identity: IDENTITY };

    await expect(collect(cache.read(target, 30_000, 30_100))).rejects.toThrow(
      /does not support range/
    );
  });

  it("sends the master signature plus a range derived from the chunk grid", async () => {
    const origin = new FileOrigin(FILE_SIZE);
    const cache = makeCache(origin);
    await collect(cache.read({ url: "http://o/movie/1.mp4", identity: IDENTITY }, 9_000, 9_100));

    // Byte offsets are multiples of the chunk size: identical whoever asked.
    const ranges = origin.requests.map((r) => r.range);
    expect(ranges).toContain(`bytes=${CHUNK}-${2 * CHUNK - 1}`);
    for (const range of ranges) {
      if (!range || range === "bytes=0-0") continue;
      const start = Number(/^bytes=(\d+)-/.exec(range)?.[1]);
      expect(start % CHUNK).toBe(0);
    }
  });

  it("gives up rather than share a slot a live viewer is using", async () => {
    const origin = new FileOrigin(FILE_SIZE);
    const cache = makeCache(origin);
    const target = {
      url: "http://o/movie/1.mp4",
      identity: IDENTITY,
      acquireLease: async () => null, // the account is busy streaming
    };

    await expect(collect(cache.read(target, 0, 100))).rejects.toBeInstanceOf(VodError);
  });

  it("releases the lease once the response is done", async () => {
    const origin = new FileOrigin(FILE_SIZE);
    const cache = makeCache(origin);
    let held = 0;
    const target = {
      url: "http://o/movie/1.mp4",
      identity: IDENTITY,
      acquireLease: async () => {
        held += 1;
        return { release: () => (held -= 1) };
      },
    };

    await collect(cache.read(target, 0, 20_000));
    await tick();
    expect(held).toBe(0);
    // One lease for the whole response, not one per chunk.
    expect(cache.stats().misses).toBeGreaterThan(1);
  });
});
