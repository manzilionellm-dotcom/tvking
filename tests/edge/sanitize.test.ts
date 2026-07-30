import { describe, expect, it } from "vitest";
import {
  assertNoClientMetadata,
  buildUpstreamHeaders,
  connectionListedHeaders,
  inspectClientMetadata,
  redactUrl,
  sanitizeDownstreamHeaders,
  type UpstreamIdentity,
} from "../../server/edge/sanitize.ts";

const identity: UpstreamIdentity = { userAgent: "tvking-edge/1.0", via: "1.1 tvking-edge" };

/** What a real TV app request looks like once it has crossed a home router. */
const clientRequest = {
  host: "edge.lan:8787",
  "user-agent": "Mozilla/5.0 (Linux; Android 12; BRAVIA 4K) AppleWebKit/537.36",
  "x-forwarded-for": "192.168.1.44, 81.250.13.7",
  "x-real-ip": "192.168.1.44",
  forwarded: 'for=192.168.1.44;proto=http;by=192.168.1.1',
  cookie: "sid=6f2e1c9a; consent=1",
  referer: "http://edge.lan/watch/psg-om",
  authorization: "Bearer downstream-token",
  "accept-language": "fr-FR,fr;q=0.9",
  "sec-ch-ua-platform": '"Android"',
  "sec-ch-ua-model": '"BRAVIA 4K GB"',
  "device-memory": "4",
  dnt: "1",
  traceparent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
  "x-device-id": "tv-living-room",
  accept: "*/*",
};

describe("buildUpstreamHeaders", () => {
  it("emits only the edge identity — no client metadata survives", () => {
    const { headers } = buildUpstreamHeaders(identity, clientRequest);

    expect(Object.keys(headers).sort()).toEqual(
      ["accept", "accept-encoding", "accept-language", "user-agent", "via"].sort()
    );
    expect(headers["accept-language"]).toBe("*"); // constant, not the client's
    expect(headers["user-agent"]).toBe("tvking-edge/1.0");
    expect(inspectClientMetadata(headers, identity)).toEqual([]);
    expect(() => assertNoClientMetadata(headers, identity)).not.toThrow();
  });

  it("drops every identifying field explicitly, by name", () => {
    const { dropped } = buildUpstreamHeaders(identity, clientRequest);
    for (const name of [
      "user-agent",
      "x-forwarded-for",
      "x-real-ip",
      "forwarded",
      "cookie",
      "referer",
      "authorization",
      "accept-language",
      "sec-ch-ua-platform",
      "sec-ch-ua-model",
      "device-memory",
      "dnt",
      "traceparent",
      "x-device-id",
      "host",
    ]) {
      expect(dropped).toContain(name);
    }
  });

  it("reports dropped field NAMES only — no values leak into telemetry", () => {
    const report = buildUpstreamHeaders(identity, clientRequest);
    const serialised = JSON.stringify({ dropped: report.dropped, forwarded: report.forwarded });
    expect(serialised).not.toContain("192.168.1.44");
    expect(serialised).not.toContain("sid=6f2e1c9a");
    expect(serialised).not.toContain("downstream-token");
  });

  it("is deny-by-default: an unknown tracking header cannot leak", () => {
    const { headers } = buildUpstreamHeaders(identity, {
      "x-brand-new-fingerprint-2027": "abc",
    });
    expect(headers["x-brand-new-fingerprint-2027"]).toBeUndefined();
  });

  it("is case-insensitive about field names", () => {
    const { headers } = buildUpstreamHeaders(identity, {
      "X-Forwarded-For": "10.0.0.9",
      "USER-AGENT": "Sneaky/1.0",
      Cookie: "sid=1",
    });
    expect(inspectClientMetadata(headers, identity)).toEqual([]);
    expect(headers["user-agent"]).toBe("tvking-edge/1.0");
  });

  it("forwards the narrow allowlist and nothing else", () => {
    const { headers, forwarded } = buildUpstreamHeaders(identity, {
      accept: "video/mp2t",
      range: "bytes=0-100",
    });
    expect(forwarded).toEqual(["accept"]);
    expect(headers.accept).toBe("video/mp2t");
    // Range would either poison the shared buffer or force a second upstream.
    expect(headers.range).toBeUndefined();
  });

  it("lets the edge present its own origin credentials", () => {
    const { headers } = buildUpstreamHeaders(
      { ...identity, extra: { "x-origin-key": "edge-secret" } },
      clientRequest
    );
    expect(headers["x-origin-key"]).toBe("edge-secret");
    expect(headers.authorization).toBeUndefined(); // never the client's
  });

  it("announces itself with Via and never with Forwarded (RFC 7239)", () => {
    const { headers } = buildUpstreamHeaders(identity, clientRequest);
    expect(headers.via).toBe("1.1 tvking-edge");
    expect(headers.forwarded).toBeUndefined();
    expect(headers["x-forwarded-for"]).toBeUndefined();
  });

  it("asks for identity encoding — media is already compressed", () => {
    const { headers } = buildUpstreamHeaders(identity, { "accept-encoding": "br, gzip" });
    expect(headers["accept-encoding"]).toBe("identity");
  });

  it("drops fields named by Connection (RFC 9110 §7.6.1)", () => {
    const bag = { connection: "keep-alive, X-Custom-Hop", "x-custom-hop": "1", accept: "*/*" };
    expect(connectionListedHeaders(bag)).toEqual(new Set(["x-custom-hop"]));
    const { headers } = buildUpstreamHeaders(identity, bag, new Set(["accept", "x-custom-hop"]));
    expect(headers["x-custom-hop"]).toBeUndefined();
    expect(headers.accept).toBe("*/*");
  });

  it("assertNoClientMetadata throws when a leak is constructed by hand", () => {
    expect(() =>
      assertNoClientMetadata({ "x-forwarded-for": "192.168.1.44" }, identity)
    ).toThrow(/leak client metadata: x-forwarded-for/);
  });
});

describe("sanitizeDownstreamHeaders", () => {
  it("strips origin tracking and hop-by-hop fields", () => {
    const out = sanitizeDownstreamHeaders({
      "content-type": "video/mp2t",
      "set-cookie": "origin_session=abc",
      server: "nginx/1.25",
      "x-powered-by": "PHP/8",
      "cf-ray": "8a1b",
      connection: "keep-alive",
      "transfer-encoding": "chunked",
      "content-length": "1234",
      "accept-ranges": "bytes",
      "cache-control": "no-cache",
    });
    expect(out).toEqual({ "content-type": "video/mp2t", "cache-control": "no-cache" });
  });
});

describe("redactUrl", () => {
  it("keeps the shape of the URL and hides subscription secrets", () => {
    expect(redactUrl("https://origin.example/live/42.ts?token=s3cr3t&u=alice")).toBe(
      "https://origin.example/live/42.ts?token=***&u=***"
    );
    expect(redactUrl("https://user:pass@origin.example/live")).toContain("***");
    expect(redactUrl("not a url")).toBe("<unparseable-url>");
  });
});
