import { describe, expect, it } from "vitest";
import { parseM3u, slugify } from "../../server/edge/m3u.ts";

const PLAYLIST = `#EXTM3U
#EXTINF:-1 tvg-id="tf1.fr" tvg-name="TF1 HD" tvg-logo="http://logo/tf1.png" group-title="Généralistes",TF1 HD
http://provider.example/live/1001.ts
#EXTINF:-1 tvg-id="m6.fr" group-title="Généralistes",M6
http://provider.example/live/1002.ts
#EXTGRP:Sport
#EXTINF:-1,beIN SPORTS 1
http://provider.example/live/2001.ts
`;

describe("parseM3u", () => {
  it("maps channels by tvg-id with their attributes", () => {
    const playlist = parseM3u(PLAYLIST);
    expect(playlist.entries).toHaveLength(3);

    const tf1 = playlist.byId.get("tf1-fr");
    expect(tf1?.name).toBe("TF1 HD");
    expect(tf1?.url).toBe("http://provider.example/live/1001.ts");
    expect(tf1?.group).toBe("Généralistes");
    expect(tf1?.logo).toBe("http://logo/tf1.png");
    expect(tf1?.attributes["tvg-name"]).toBe("TF1 HD");
  });

  it("falls back to the display name and honours #EXTGRP", () => {
    const bein = parseM3u(PLAYLIST).byId.get("bein-sports-1");
    expect(bein?.url).toBe("http://provider.example/live/2001.ts");
    expect(bein?.group).toBe("Sport");
  });

  it("survives CRLF, a BOM, blank lines and unknown directives", () => {
    const messy =
      "﻿#EXTM3U\r\n\r\n#EXTVLCOPT:network-caching=1000\r\n" +
      '#KODIPROP:inputstream=ffmpeg\r\n#EXTINF:-1 tvg-id="a",A\r\nhttp://o/a.ts\r\n';
    const playlist = parseM3u(messy);
    expect(playlist.entries).toHaveLength(1);
    expect(playlist.byId.get("a")?.url).toBe("http://o/a.ts");
  });

  it("de-duplicates ids instead of losing channels", () => {
    const playlist = parseM3u(
      "#EXTM3U\n#EXTINF:-1,Sport\nhttp://o/1.ts\n#EXTINF:-1,Sport\nhttp://o/2.ts\n"
    );
    expect(playlist.entries.map((entry) => entry.id)).toEqual(["sport", "sport-2"]);
  });

  it("counts entries it had to skip rather than throwing", () => {
    const playlist = parseM3u("#EXTM3U\n#EXTINF:-1,Orphan\n#EXTINF:-1,Real\nhttp://o/1.ts\n");
    expect(playlist.entries).toHaveLength(1);
    expect(playlist.skipped).toBe(1);
  });

  it("ignores a URL with no #EXTINF (nothing to address it by)", () => {
    expect(parseM3u("#EXTM3U\nhttp://o/orphan.ts\n").entries).toHaveLength(0);
  });

  it("returns an empty playlist for empty input", () => {
    expect(parseM3u("").entries).toEqual([]);
    expect(parseM3u("#EXTM3U\n").entries).toEqual([]);
  });
});

describe("slugify", () => {
  it("produces URL-safe ids", () => {
    expect(slugify("beIN SPORTS 1 HD")).toBe("bein-sports-1-hd");
    expect(slugify("Canal+ Décalé")).toBe("canal-decale");
    expect(slugify("  ")).toBe("channel");
    expect(slugify("é".repeat(200)).length).toBeLessThanOrEqual(96);
  });
});
