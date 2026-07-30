import { describe, expect, it } from "vitest";
import { AccountError, AccountRegistry } from "../../server/edge/accounts.ts";
import { ManualClock } from "../../server/edge/clock.ts";
import { tick } from "./mock-origin.ts";

const PLAYLIST = `#EXTM3U
#EXTINF:-1 tvg-id="tf1",TF1
http://provider.example/live/1001.ts
#EXTINF:-1 tvg-id="m6",M6
http://provider.example/live/1002.ts
`;

function makeRegistry(body: () => string | Promise<string>) {
  const clock = new ManualClock();
  let fetches = 0;
  const registry = new AccountRegistry({
    clock,
    fetchPlaylist: async () => {
      fetches += 1;
      return body();
    },
  });
  return { registry, clock, fetches: () => fetches };
}

describe("AccountRegistry", () => {
  it("validates accounts at declaration time", () => {
    const { registry } = makeRegistry(() => PLAYLIST);
    expect(() => registry.upsert({ id: "bad id", channelTemplate: "http://o/{id}" })).toThrow(
      AccountError
    );
    expect(() => registry.upsert({ id: "a" })).toThrow(/no playlistUrl/);
    expect(() => registry.upsert({ id: "a", channelTemplate: "http://o/x" })).toThrow(/\{id\}/);
    expect(() => registry.upsert({ id: "a", playlistUrl: "ftp://o/x.m3u" })).toThrow(/http/);
    expect(() =>
      registry.upsert({ id: "a", channelTemplate: "http://o/{id}", maxConnections: 0 })
    ).toThrow(/positive integer/);
    expect(() =>
      // @ts-expect-error deliberately invalid device name
      registry.upsert({ id: "a", channelTemplate: "http://o/{id}", device: "nokia" })
    ).toThrow(/unknown master device/);
  });

  it("resolves channels from the master playlist", async () => {
    const { registry } = makeRegistry(() => PLAYLIST);
    registry.upsert({ id: "master", playlistUrl: "http://provider.example/get.php" });

    expect(await registry.resolve("master", "tf1")).toEqual({
      url: "http://provider.example/live/1001.ts",
      extra: {},
    });
    expect(await registry.resolve("master", "unknown")).toBeNull();
    expect(await registry.resolve("nobody", "tf1")).toBeNull();
  });

  it("downloads the playlist ONCE for a herd of cold requests", async () => {
    const { registry, fetches } = makeRegistry(async () => {
      await tick(3);
      return PLAYLIST;
    });
    registry.upsert({ id: "master", playlistUrl: "http://provider.example/get.php" });

    const resolved = await Promise.all(
      Array.from({ length: 100 }, () => registry.resolve("master", "tf1"))
    );
    expect(fetches()).toBe(1);
    expect(resolved.every((target) => target?.url.endsWith("1001.ts"))).toBe(true);
  });

  it("re-downloads only after the TTL", async () => {
    const { registry, clock, fetches } = makeRegistry(() => PLAYLIST);
    registry.upsert({
      id: "master",
      playlistUrl: "http://provider.example/get.php",
      playlistTtlMs: 1000,
    });

    await registry.resolve("master", "tf1");
    await registry.resolve("master", "m6");
    expect(fetches()).toBe(1);

    await clock.advance(1001);
    await registry.resolve("master", "tf1");
    expect(fetches()).toBe(2);
  });

  it("keeps serving the last good playlist when a refresh fails", async () => {
    let fail = false;
    const { registry, clock } = makeRegistry(() => {
      if (fail) throw new Error("provider down");
      return PLAYLIST;
    });
    registry.upsert({
      id: "master",
      playlistUrl: "http://provider.example/get.php",
      playlistTtlMs: 1000,
    });

    await registry.resolve("master", "tf1");
    fail = true;
    await clock.advance(2000);

    // Stale beats blank: the channel map survives a provider hiccup...
    expect((await registry.resolve("master", "tf1"))?.url).toContain("1001.ts");
    // ...and the operator can see that the refresh failed.
    expect(registry.snapshot()[0].playlistError).toMatch(/provider down/);
  });

  it("surfaces a first-fetch failure instead of pretending the line is empty", async () => {
    const { registry } = makeRegistry(() => {
      throw new Error("401 unauthorized");
    });
    registry.upsert({ id: "master", playlistUrl: "http://provider.example/get.php" });
    await expect(registry.resolve("master", "tf1")).rejects.toThrow(/playlist fetch failed/);
  });

  it("prefers an explicit table, then the playlist, then the template", async () => {
    const { registry } = makeRegistry(() => PLAYLIST);
    registry.upsert({ id: "table", channels: { a: "http://o/a.ts" } });
    registry.upsert({ id: "tpl", channelTemplate: "http://o/{id}.ts" });

    expect((await registry.resolve("table", "a"))?.url).toBe("http://o/a.ts");
    expect(await registry.resolve("table", "zzz")).toBeNull();
    expect((await registry.resolve("tpl", "sport 1"))?.url).toBe("http://o/sport%201.ts");
  });

  it("gives each account its own master device signature and credentials", () => {
    const { registry } = makeRegistry(() => PLAYLIST);
    registry.upsert({
      id: "master",
      channelTemplate: "http://o/{id}",
      device: "kodi",
      headers: { "x-provider-token": "s3cret" },
    });

    const identity = registry.identity("master");
    expect(identity.userAgent).toContain("Kodi");
    expect(identity.extra).toEqual({ "x-provider-token": "s3cret" });
    expect(() => registry.identity("ghost")).toThrow(AccountError);
  });

  it("reports credential field NAMES only in the snapshot", () => {
    const { registry } = makeRegistry(() => PLAYLIST);
    registry.upsert({
      id: "master",
      channelTemplate: "http://o/{id}",
      headers: { "x-provider-token": "s3cret" },
    });

    const snapshot = registry.snapshot()[0];
    expect(snapshot.credentialHeaders).toEqual(["x-provider-token"]);
    expect(JSON.stringify(snapshot)).not.toContain("s3cret");
  });

  it("drops the cached channel map when the account is re-pointed", async () => {
    let body = PLAYLIST;
    const { registry, fetches } = makeRegistry(() => body);
    registry.upsert({ id: "master", playlistUrl: "http://provider.example/a.m3u" });
    await registry.resolve("master", "tf1");

    body = '#EXTM3U\n#EXTINF:-1 tvg-id="tf1",TF1\nhttp://other.example/9.ts\n';
    registry.upsert({ id: "master", playlistUrl: "http://provider.example/b.m3u" });
    expect((await registry.resolve("master", "tf1"))?.url).toBe("http://other.example/9.ts");
    expect(fetches()).toBe(2);
  });

  it("lists channels for the dashboard and can force a refresh", async () => {
    const { registry, fetches } = makeRegistry(() => PLAYLIST);
    registry.upsert({ id: "master", playlistUrl: "http://provider.example/get.php" });

    expect((await registry.channels("master")).map((c) => c.id)).toEqual(["tf1", "m6"]);
    await registry.channels("master", { refresh: true });
    expect(fetches()).toBe(2);
    await expect(registry.channels("ghost")).rejects.toThrow(AccountError);
  });

  it("removes accounts", () => {
    const { registry } = makeRegistry(() => PLAYLIST);
    registry.upsert({ id: "master", channelTemplate: "http://o/{id}" });
    expect(registry.remove("master")).toBe(true);
    expect(registry.remove("master")).toBe(false);
    expect(registry.size).toBe(0);
  });
});
