/*
 * VOD aggregation: turning provider playlist lines into one deduplicated
 * catalogue, and the worker that keeps it fresh without stealing the account's
 * only connection from a viewer.
 */

import { describe, expect, it } from "vitest";
import { ManualClock, ManualWallClock } from "../../server/edge/clock.ts";
import { openDatabase } from "../../server/edge/db/database.ts";
import { VodCatalog } from "../../server/edge/vod/catalog.ts";
import { VodIngestWorker } from "../../server/edge/vod/ingest.ts";
import { classify, looksLikeVod, normalizeTitle } from "../../server/edge/vod/classify.ts";
import { EdgeProxy } from "../../server/edge/edge.ts";
import { MockOrigin, tick } from "./mock-origin.ts";

const PROVIDER_A = `#EXTM3U
#EXTINF:-1 tvg-name="TF1" group-title="FR | GENERALISTE",FR - TF1 HD
http://provider-a.example/live/1.ts
#EXTINF:-1 tvg-logo="http://img/gb.jpg" group-title="VOD | ACTION",FR - Le Grand Bleu (1988) [MULTI 1080p]
http://provider-a.example/movie/u/p/501.mkv
#EXTINF:-1 group-title="VOD | DRAME",EN | The Godfather (1972) 4K
http://provider-a.example/movie/u/p/502.mp4
#EXTINF:-1 group-title="SERIES | DRAME",EN - Breaking Bad S05E14 1080p
http://provider-a.example/series/u/p/9001.mkv
`;

const PROVIDER_B = `#EXTM3U
#EXTINF:-1 group-title="Films Action",Le Grand Bleu (1988)
http://provider-b.example/movie/x/y/77.mp4
#EXTINF:-1 group-title="Films",Le grand bleu 1988 VF
http://provider-b.example/movie/x/y/78.mkv
`;

function harness() {
  const db = openDatabase(":memory:");
  const wallClock = new ManualWallClock("2026-05-01T00:00:00Z");
  const catalog = new VodCatalog(db, wallClock);
  return { db, catalog, wallClock };
}

describe("classify", () => {
  it("strips provider decoration down to the work", () => {
    const item = classify({
      name: "FR - Le Grand Bleu (1988) [MULTI 1080p]",
      url: "http://o/movie/u/p/1.mkv",
      group: "VOD | ACTION",
    });
    expect(item).toMatchObject({
      kind: "movie",
      title: "Le Grand Bleu",
      year: 1988,
      quality: "MULTI",
      container: "mkv",
      category: "Action",
    });
  });

  it("detects series and keeps the show as the title", () => {
    const item = classify({
      name: "EN - Breaking Bad S05E14 1080p",
      url: "http://o/series/u/p/1.mkv",
      group: "SERIES | DRAME",
    });
    expect(item).toMatchObject({ kind: "series", title: "Breaking Bad", season: 5, episode: 14 });
  });

  it("reads the alternative 5x14 episode notation", () => {
    expect(classify({ name: "Breaking Bad 5x14", url: "http://o/a.mkv" })).toMatchObject({
      kind: "series",
      season: 5,
      episode: 14,
    });
  });

  it("normalises titles so the same work matches across providers", () => {
    expect(normalizeTitle("Le Grand Bleu")).toBe(normalizeTitle("LE GRAND BLEU"));
    expect(normalizeTitle("L'Été dernier")).toBe(normalizeTitle("Lete dernier"));
    expect(normalizeTitle("Fast & Furious")).toBe(normalizeTitle("Fast and Furious"));
  });

  it("never returns an empty title", () => {
    expect(classify({ name: "1080p", url: "http://o/a.mkv" }).title).toBe("1080p");
  });

  it("tells VOD lines from live channels", () => {
    expect(looksLikeVod({ name: "TF1", url: "http://o/live/1.ts", group: "FR" })).toBe(false);
    expect(looksLikeVod({ name: "Film", url: "http://o/movie/u/p/1.mkv", group: "" })).toBe(true);
    expect(looksLikeVod({ name: "Film", url: "http://o/x", group: "VOD | ACTION" })).toBe(true);
  });
});

describe("VodCatalog", () => {
  it("aggregates the same film from two providers into ONE title", () => {
    const { catalog } = harness();
    const a = catalog.upsertSource({ name: "A", url: "http://a/list.m3u", accountId: "master" });
    const b = catalog.upsertSource({ name: "B", url: "http://b/list.m3u", accountId: "master" });

    catalog.ingest(a.id, [
      {
        name: "FR - Le Grand Bleu (1988) [MULTI 1080p]",
        url: "http://a/movie/501.mkv",
        group: "VOD | ACTION",
        logo: "http://img/gb.jpg",
      },
    ]);
    const second = catalog.ingest(b.id, [
      { name: "Le Grand Bleu (1988)", url: "http://b/movie/77.mp4", group: "Films Action" },
    ]);

    const titles = catalog.titles({ kind: "movie" });
    expect(titles).toHaveLength(1);
    expect(titles[0].title).toBe("Le Grand Bleu");
    expect(titles[0].streams).toBe(2); // one work, two playable sources
    expect(second.duplicatesMerged).toBe(1);
    expect(second.titlesCreated).toBe(0);
  });

  it("keeps different years apart", () => {
    const { catalog } = harness();
    const source = catalog.upsertSource({ name: "A", url: "http://a", accountId: "master" });
    catalog.ingest(source.id, [
      { name: "Dune (1984)", url: "http://a/movie/1.mkv", group: "VOD" },
      { name: "Dune (2021)", url: "http://a/movie/2.mkv", group: "VOD" },
    ]);
    expect(catalog.titles({ kind: "movie" })).toHaveLength(2);
  });

  it("is idempotent: re-ingesting the same playlist adds nothing", () => {
    const { catalog } = harness();
    const source = catalog.upsertSource({ name: "A", url: "http://a", accountId: "master" });
    const entries = [
      { name: "Dune (2021)", url: "http://a/movie/2.mkv", group: "VOD | SF" },
      { name: "Arrival (2016)", url: "http://a/movie/3.mkv", group: "VOD | SF" },
    ];
    catalog.ingest(source.id, entries);
    const again = catalog.ingest(source.id, entries);

    expect(again.titlesCreated).toBe(0);
    expect(again.streamsCreated).toBe(0);
    expect(catalog.counts().movies).toBe(2);
    expect(catalog.counts().streams).toBe(2);
  });

  it("organises titles by category and can hide a category from subscribers", () => {
    const { catalog } = harness();
    const source = catalog.upsertSource({ name: "A", url: "http://a", accountId: "master" });
    catalog.ingest(source.id, [
      { name: "Dune (2021)", url: "http://a/movie/2.mkv", group: "VOD | SF" },
      { name: "Heat (1995)", url: "http://a/movie/4.mkv", group: "VOD | POLAR" },
    ]);

    const categories = catalog.listCategories("movie");
    // Short words stay upper-case: "SF" is an acronym, not a typo.
    expect(categories.map((c) => c.name).sort()).toEqual(["Polar", "SF"]);

    const sf = categories.find((c) => c.name === "SF") as { id: number };
    catalog.setCategoryEnabled(sf.id, false);
    const visible = catalog.titles({ kind: "movie", enabledOnly: true });
    expect(visible.map((t) => t.title)).toEqual(["Heat"]);
    // Hidden, not deleted: the operator can switch it back on.
    expect(catalog.titles({ kind: "movie" })).toHaveLength(2);
  });

  it("prefers the best quality stream of a title", () => {
    const { catalog } = harness();
    const source = catalog.upsertSource({ name: "A", url: "http://a", accountId: "master" });
    catalog.ingest(source.id, [
      { name: "Dune (2021) SD", url: "http://a/movie/sd.mkv", group: "VOD" },
      { name: "Dune (2021) 4K", url: "http://a/movie/4k.mkv", group: "VOD" },
    ]);
    const title = catalog.titles({ kind: "movie" })[0];
    expect(catalog.preferredStream(title.id)?.url).toBe("http://a/movie/4k.mkv");
  });

  it("ignores streams from a disabled source when choosing", () => {
    const { catalog } = harness();
    const a = catalog.upsertSource({ name: "A", url: "http://a", accountId: "master" });
    const b = catalog.upsertSource({ name: "B", url: "http://b", accountId: "master" });
    catalog.ingest(a.id, [{ name: "Dune (2021) 4K", url: "http://a/movie/4k.mkv", group: "VOD" }]);
    catalog.ingest(b.id, [{ name: "Dune (2021) SD", url: "http://b/movie/sd.mkv", group: "VOD" }]);

    const title = catalog.titles({ kind: "movie" })[0];
    catalog.setSourceEnabled(a.id, false);
    expect(catalog.preferredStream(title.id)?.url).toBe("http://b/movie/sd.mkv");
  });
});

describe("VodIngestWorker", () => {
  function workerHarness(playlists: Record<string, string>) {
    const { db, catalog } = harness();
    const clock = new ManualClock();
    const fetched: string[] = [];
    const worker = new VodIngestWorker({
      catalog,
      clock,
      fetchPlaylist: async (accountId, url) => {
        fetched.push(url);
        const body = playlists[url];
        if (body === undefined) throw new Error(`404 for ${url}`);
        return body;
      },
    });
    return { db, catalog, worker, fetched };
  }

  it("ingests every enabled source and skips the disabled ones", async () => {
    const { catalog, worker, fetched } = workerHarness({
      "http://a/list.m3u": PROVIDER_A,
      "http://b/list.m3u": PROVIDER_B,
    });
    catalog.upsertSource({ name: "A", url: "http://a/list.m3u", accountId: "master" });
    const b = catalog.upsertSource({ name: "B", url: "http://b/list.m3u", accountId: "master" });
    catalog.setSourceEnabled(b.id, false);

    const reports = await worker.runOnce();
    expect(fetched).toEqual(["http://a/list.m3u"]);
    expect(reports.find((r) => r.source === "B")?.skipped).toBe("disabled");

    // The live channel in the playlist must NOT land in the VOD catalogue.
    expect(catalog.counts()).toMatchObject({ movies: 2, series: 1 });
    expect(catalog.titles({ kind: "movie" }).map((t) => t.title).sort()).toEqual([
      "Le Grand Bleu",
      "The Godfather",
    ]);
  });

  it("merges two providers into one library", async () => {
    const { catalog, worker } = workerHarness({
      "http://a/list.m3u": PROVIDER_A,
      "http://b/list.m3u": PROVIDER_B,
    });
    catalog.upsertSource({ name: "A", url: "http://a/list.m3u", accountId: "master" });
    catalog.upsertSource({ name: "B", url: "http://b/list.m3u", accountId: "master" });

    await worker.runOnce();
    const grandBleu = catalog.titles({ search: "Grand Bleu" })[0];
    expect(grandBleu.streams).toBe(3); // 1 from A, 2 from B — one work
    expect(catalog.counts().movies).toBe(2);
  });

  it("records a source failure without blanking its catalogue", async () => {
    const playlists: Record<string, string> = { "http://a/list.m3u": PROVIDER_A };
    const { catalog, worker } = workerHarness(playlists);
    const source = catalog.upsertSource({ name: "A", url: "http://a/list.m3u", accountId: "master" });

    await worker.runOnce();
    expect(catalog.counts().movies).toBe(2);

    delete playlists["http://a/list.m3u"]; // provider goes down
    const reports = await worker.runOnce();

    expect(reports[0].ok).toBe(false);
    expect(catalog.source(source.id)?.lastError).toMatch(/404/);
    expect(catalog.counts().movies).toBe(2); // stale beats empty
  });

  it("never opens a second upstream connection to refresh a catalogue", async () => {
    // The account has ONE connection and a viewer is using it. The refresh must
    // wait its turn rather than becoming connection number two.
    const { db, catalog } = harness();
    const origin = new MockOrigin({ openDelayMs: 1 });
    const edge = new EdgeProxy({
      accounts: [{ id: "master", channelTemplate: "https://origin.example/{id}.ts", maxConnections: 1 }],
      transport: origin,
      lingerMs: 60_000,
      swapSettleMs: 0,
    });
    const worker = new VodIngestWorker({
      catalog,
      fetchPlaylist: (accountId, url, signal) => edge.fetchText(accountId, url, { signal }),
    });
    catalog.upsertSource({ name: "A", url: "https://origin.example/vod.m3u", accountId: "master" });

    const watching = await edge.subscribe("master/tf1");
    const reports = await worker.runOnce();

    expect(reports[0].skipped).toBe("busy");
    expect(edge.counters.activeMax).toBe(1); // the invariant survives ingestion
    expect(watching.subscription.closed).toBe(false); // and so does the viewer

    watching.subscription.close();
    await tick(5);
    await edge.shutdown();
    db.close();
  });

  it("uses the slot once the viewer is gone", async () => {
    const { catalog } = harness();
    const origin = new MockOrigin({ openDelayMs: 1 });
    const edge = new EdgeProxy({
      accounts: [{ id: "master", channelTemplate: "https://origin.example/{id}.ts", maxConnections: 1 }],
      transport: origin,
      lingerMs: 0,
      swapSettleMs: 0,
    });
    const worker = new VodIngestWorker({
      catalog,
      fetchPlaylist: async (accountId, url, signal) => {
        const body = edge.fetchText(accountId, url, { signal });
        // Feed the mock origin the playlist it is being asked for.
        setTimeout(() => origin.push(new TextEncoder().encode(PROVIDER_B)), 5);
        setTimeout(() => origin.endAll(), 10);
        return body;
      },
    });
    catalog.upsertSource({ name: "B", url: "https://origin.example/vod.m3u", accountId: "master" });

    const reports = await worker.runOnce();
    expect(reports[0].ok).toBe(true);
    expect(catalog.counts().movies).toBe(1);
    expect(edge.counters.activeMax).toBe(1);
    await edge.shutdown();
  });
});
