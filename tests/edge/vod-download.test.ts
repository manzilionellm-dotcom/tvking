/*
 * The on-demand engine: "Télécharger" on a source (pull its catalogue) and on
 * an item (pull the media onto disk), plus serving those local files with
 * Range. Nothing here is periodic — that is the property under test as much as
 * the bytes are.
 */

import http from "node:http";
import { readFile, mkdtemp, rm, readdir, writeFile } from "node:fs/promises";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { ManualWallClock } from "../../server/edge/clock.ts";
import { openDatabase, type Database } from "../../server/edge/db/database.ts";
import { VodLibrary } from "../../server/edge/vod/library.ts";
import { VodDownloader } from "../../server/edge/vod/downloader.ts";
import { deliverFile, parseRange } from "../../server/edge/http/deliver.ts";
import { masterDevice } from "../../server/edge/sanitize.ts";
import type { OriginRequest, OriginResponse, OriginTransport } from "../../server/edge/origin.ts";
import { tick } from "./mock-origin.ts";

const PLAYLIST = `#EXTM3U
#EXTINF:-1 tvg-id="tf1" group-title="Généralistes",TF1
http://provider.example/live/tf1.ts
#EXTINF:-1 tvg-logo="http://img/gb.jpg" group-title="VOD | ACTION",FR - Le Grand Bleu (1988) [MULTI 1080p]
http://provider.example/movie/u/p/501.mkv
#EXTINF:-1 group-title="VOD | SF",Dune (2021) 4K
http://provider.example/movie/u/p/502.mp4
`;

/** Serves one deterministic file, with Range and a controllable stall. */
class FileOrigin implements OriginTransport {
  requests: Array<{ url: string; range: string | undefined }> = [];
  size = 20_000;
  status = 200;
  ignoreRange = false;
  /** Pause after this many bytes so a test can cancel mid-flight. */
  stallAfter = 0;
  #release: (() => void) | null = null;

  static byteAt(index: number): number {
    return index % 251;
  }

  resume(): void {
    this.#release?.();
    this.#release = null;
  }

  async open(request: OriginRequest): Promise<OriginResponse> {
    const range = request.headers.range;
    this.requests.push({ url: request.url, range });

    const match = /^bytes=(\d+)-/.exec(this.ignoreRange ? "" : (range ?? ""));
    const start = match ? Number(match[1]) : 0;
    if (start >= this.size) {
      return { status: 416, headers: {}, body: empty(), close() {} };
    }
    const body = new Uint8Array(this.size - start);
    for (let i = 0; i < body.length; i += 1) body[i] = FileOrigin.byteAt(start + i);

    const stallAfter = this.stallAfter;
    const hold = (resolve: () => void) => {
      this.#release = resolve;
    };
    return {
      status: this.status === 200 && start > 0 && !this.ignoreRange ? 206 : this.status,
      headers: { "content-length": String(body.byteLength), "content-type": "video/x-matroska" },
      body: (async function* stream() {
        let sent = 0;
        for (let offset = 0; offset < body.byteLength; offset += 4096) {
          const piece = body.subarray(offset, Math.min(offset + 4096, body.byteLength));
          yield piece;
          sent += piece.byteLength;
          if (stallAfter > 0 && sent >= stallAfter) {
            await new Promise<void>(hold);
          }
        }
      })(),
      close() {},
    };
  }
}

function empty(): AsyncGenerator<Uint8Array> {
  return (async function* nothing() {})();
}

let db: Database;
let dir: string;
let library: VodLibrary;
let origin: FileOrigin;
let downloader: VodDownloader;
let playlists: Record<string, string>;
let leases: number;

beforeEach(async () => {
  db = openDatabase(":memory:");
  dir = await mkdtemp(path.join(tmpdir(), "tvking-vodfiles-"));
  library = new VodLibrary(db, new ManualWallClock("2026-07-01T09:00:00Z"));
  origin = new FileOrigin();
  playlists = { "http://provider.example/vod.m3u": PLAYLIST };
  leases = 0;

  downloader = new VodDownloader({
    library,
    transport: origin,
    dir,
    identityFor: () => masterDevice("vlc"),
    acquireLease: async () => {
      leases += 1;
      return { release: () => (leases -= 1) };
    },
    fetchPlaylist: async (accountId, url) => {
      const body = playlists[url];
      if (body === undefined) throw new Error(`404 for ${url}`);
      return body;
    },
    progressEveryBytes: 4096,
  });
});

afterEach(async () => {
  db.close();
  await rm(dir, { recursive: true, force: true });
});

function addSource() {
  return library.addSource({
    name: "provider",
    url: "http://provider.example/vod.m3u",
    accountId: "master",
  });
}

describe("import on demand", () => {
  it("pulls a catalogue only when asked, and keeps the live channel out", async () => {
    const source = addSource();
    expect(library.counts().items).toBe(0); // adding did nothing by itself

    const report = await downloader.importSource(source.id);

    expect(report.ok).toBe(true);
    expect(report.entries).toBe(2); // the .ts live channel is not VOD
    expect(report.created).toBe(2);
    expect(library.items().map((item) => item.title).sort()).toEqual(["Dune", "Le Grand Bleu"]);
    expect(library.items().every((item) => item.state === "pending")).toBe(true);
    expect(library.source(source.id)?.lastImportAt).not.toBeNull();
  });

  it("is idempotent: a second import updates instead of duplicating", async () => {
    const source = addSource();
    await downloader.importSource(source.id);
    const second = await downloader.importSource(source.id);

    expect(second.created).toBe(0);
    expect(second.updated).toBe(2);
    expect(library.counts().items).toBe(2);
  });

  it("records a failure against the source without emptying the library", async () => {
    const source = addSource();
    await downloader.importSource(source.id);
    delete playlists["http://provider.example/vod.m3u"];

    const report = await downloader.importSource(source.id);

    expect(report.ok).toBe(false);
    expect(report.error).toMatch(/404/);
    expect(library.source(source.id)?.lastError).toMatch(/404/);
    expect(library.counts().items).toBe(2); // still there
  });

  it("refuses an unknown source", async () => {
    await expect(downloader.importSource(999)).rejects.toThrow(/unknown VOD source/);
  });
});

describe("download on demand", () => {
  async function importedItem() {
    const source = addSource();
    await downloader.importSource(source.id);
    return library.items({ search: "Grand Bleu" })[0];
  }

  it("stores the media on disk and marks the entry ready", async () => {
    const item = await importedItem();
    const report = await downloader.download(item.id);

    expect(report.ok).toBe(true);
    expect(report.bytes).toBe(origin.size);

    const after = library.item(item.id) as { state: string; filePath: string; bytesDone: number };
    expect(after.state).toBe("ready");
    expect(after.bytesDone).toBe(origin.size);
    expect(path.basename(after.filePath)).toBe(`${item.id}.mkv`);

    const bytes = await readFile(after.filePath);
    expect(bytes.byteLength).toBe(origin.size);
    expect(bytes[0]).toBe(FileOrigin.byteAt(0));
    expect(bytes[19_999]).toBe(FileOrigin.byteAt(19_999));
    // No leftover partial file.
    expect(await readdir(dir)).toEqual([`${item.id}.mkv`]);
  });

  it("takes a connection slot for the download and gives it back", async () => {
    const item = await importedItem();
    await downloader.download(item.id);
    expect(leases).toBe(0);
  });

  it("refuses to download when the account is busy streaming", async () => {
    const busy = new VodDownloader({
      library,
      transport: origin,
      dir,
      identityFor: () => masterDevice("vlc"),
      acquireLease: async () => null,
      fetchPlaylist: async () => PLAYLIST,
    });
    const item = await importedItem();
    const report = await busy.download(item.id);

    expect(report.ok).toBe(false);
    expect(report.error).toMatch(/busy streaming/);
    expect(library.item(item.id)?.state).toBe("failed");
  });

  it("sends the master signature, plus a resume offset and nothing else", async () => {
    const item = await importedItem();
    await downloader.download(item.id);
    // The signature check inside the downloader would have thrown otherwise;
    // this pins that a first download carries no Range at all.
    expect(origin.requests.at(-1)?.range).toBeUndefined();
  });

  it("resumes a partial file instead of starting over", async () => {
    const item = await importedItem();
    await writeFile(path.join(dir, `${item.id}.mkv.part`), Buffer.alloc(4096, 0));

    const report = await downloader.download(item.id);

    expect(report.resumedFrom).toBe(4096);
    expect(origin.requests.at(-1)?.range).toBe("bytes=4096-");
    expect(report.bytes).toBe(origin.size);
  });

  it("starts over when the origin ignores the resume request", async () => {
    const item = await importedItem();
    await writeFile(path.join(dir, `${item.id}.mkv.part`), Buffer.alloc(4096, 0xff));
    origin.ignoreRange = true;

    await downloader.download(item.id);

    const bytes = await readFile(library.item(item.id)?.filePath as string);
    expect(bytes.byteLength).toBe(origin.size); // not 4096 + size
    expect(bytes[0]).toBe(FileOrigin.byteAt(0)); // the junk prefix is gone
  });

  it("reports progress while it runs and can be cancelled", async () => {
    const item = await importedItem();
    origin.stallAfter = 8192;

    const running = downloader.download(item.id);
    await tick(20);

    const midway = library.item(item.id);
    expect(midway?.state).toBe("downloading");
    expect(midway?.bytesTotal).toBe(origin.size);
    expect(midway?.bytesDone).toBeGreaterThan(0);
    expect(downloader.isDownloading(item.id)).toBe(true);

    expect(downloader.cancel(item.id)).toBe(true);
    origin.resume();
    const report = await running;

    expect(report.cancelled).toBe(true);
    // Cancelling is not discarding: the partial file stays for a resume.
    expect(library.item(item.id)?.state).toBe("pending");
    expect(await readdir(dir)).toEqual([`${item.id}.mkv.part`]);
  });

  it("records the reason when the origin refuses", async () => {
    const item = await importedItem();
    origin.status = 403;

    const report = await downloader.download(item.id);

    expect(report.ok).toBe(false);
    expect(library.item(item.id)?.state).toBe("failed");
    expect(library.item(item.id)?.error).toMatch(/HTTP 403/);
  });

  it("refuses a file over the configured size limit", async () => {
    const capped = new VodDownloader({
      library,
      transport: origin,
      dir,
      identityFor: () => masterDevice("vlc"),
      fetchPlaylist: async () => PLAYLIST,
      maxFileBytes: 1000,
    });
    const item = await importedItem();

    const report = await capped.download(item.id);
    expect(report.ok).toBe(false);
    expect(report.error).toMatch(/limit/);
  });

  it("returns immediately for something already downloaded", async () => {
    const item = await importedItem();
    await downloader.download(item.id);
    const upstreamCalls = origin.requests.length;

    const again = await downloader.download(item.id);
    expect(again.ok).toBe(true);
    expect(origin.requests).toHaveLength(upstreamCalls); // no second fetch
  });

  it("frees the disk but keeps the entry", async () => {
    const item = await importedItem();
    await downloader.download(item.id);

    expect(await downloader.removeFile(item.id)).toBe(true);
    expect(await readdir(dir)).toEqual([]);
    const after = library.item(item.id);
    expect(after?.state).toBe("pending");
    expect(after?.filePath).toBeNull();
  });

  it("deletes the entry and its bytes together", async () => {
    const item = await importedItem();
    await downloader.download(item.id);

    expect(await downloader.removeItem(item.id)).toBe(true);
    expect(library.item(item.id)).toBeNull();
    expect(await readdir(dir)).toEqual([]); // no orphan file left behind
  });
});

describe("serving local files", () => {
  let server: http.Server;
  let base: string;
  let filePath: string;

  beforeEach(async () => {
    const source = addSource();
    await downloader.importSource(source.id);
    const item = library.items({ search: "Grand Bleu" })[0];
    await downloader.download(item.id);
    filePath = library.item(item.id)?.filePath as string;

    server = http.createServer((req, res) => {
      void deliverFile({ filePath, req, res, contentType: "video/x-matroska" }).catch(() => {
        if (!res.headersSent) res.writeHead(404);
        res.end();
      });
    });
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    base = `http://127.0.0.1:${(server.address() as AddressInfo).port}/`;
  });

  afterEach(async () => {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  });

  it("serves the whole file with a length", async () => {
    const response = await fetch(base);
    expect(response.status).toBe(200);
    expect(response.headers.get("content-length")).toBe(String(origin.size));
    expect(response.headers.get("accept-ranges")).toBe("bytes");
    expect(response.headers.get("content-type")).toBe("video/x-matroska");

    const body = new Uint8Array(await response.arrayBuffer());
    expect(body.byteLength).toBe(origin.size);
    expect(body[123]).toBe(FileOrigin.byteAt(123));
  });

  it("answers a Range request so a player can seek", async () => {
    const response = await fetch(base, { headers: { range: "bytes=1000-1099" } });
    expect(response.status).toBe(206);
    expect(response.headers.get("content-range")).toBe(`bytes 1000-1099/${origin.size}`);
    expect(response.headers.get("content-length")).toBe("100");

    const body = new Uint8Array(await response.arrayBuffer());
    expect(body.byteLength).toBe(100);
    expect(body[0]).toBe(FileOrigin.byteAt(1000));
    expect(body[99]).toBe(FileOrigin.byteAt(1099));
  });

  it("serves an open-ended and a suffix range", async () => {
    const open = await fetch(base, { headers: { range: "bytes=19900-" } });
    expect(open.status).toBe(206);
    expect((await open.arrayBuffer()).byteLength).toBe(100);

    const suffix = await fetch(base, { headers: { range: "bytes=-50" } });
    expect(suffix.headers.get("content-range")).toBe(`bytes 19950-19999/${origin.size}`);
  });

  it("rejects an unsatisfiable range with 416", async () => {
    const response = await fetch(base, { headers: { range: "bytes=999999-" } });
    expect(response.status).toBe(416);
    expect(response.headers.get("content-range")).toBe(`bytes */${origin.size}`);
    await response.body?.cancel();
  });

  it("answers HEAD without a body", async () => {
    const response = await fetch(base, { method: "HEAD" });
    expect(response.status).toBe(200);
    expect(response.headers.get("content-length")).toBe(String(origin.size));
  });

  it("never touches the provider to serve a downloaded file", async () => {
    const before = origin.requests.length;
    await (await fetch(base, { headers: { range: "bytes=0-99" } })).arrayBuffer();
    expect(origin.requests).toHaveLength(before);
  });
});

describe("parseRange", () => {
  it("reads the forms players actually send", () => {
    expect(parseRange(undefined, 100)).toBeNull();
    expect(parseRange("bytes=0-99", 100)).toEqual({ start: 0, end: 99 });
    expect(parseRange("bytes=10-", 100)).toEqual({ start: 10, end: 99 });
    expect(parseRange("bytes=-20", 100)).toEqual({ start: 80, end: 99 });
    expect(parseRange("bytes=0-999", 100)).toEqual({ start: 0, end: 99 }); // clamped
  });

  it("rejects the nonsense ones", () => {
    for (const bad of ["bytes=-", "items=0-9", "bytes=abc", "bytes=100-", "bytes=50-10"]) {
      expect(parseRange(bad, 100)).toBe("invalid");
    }
  });
});
