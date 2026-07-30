import { describe, expect, it } from "vitest";
import { ConfigError, buildResolver, loadConfig } from "../../server/edge/config.ts";

const minimal = { EDGE_ORIGIN_TEMPLATE: "https://origin.example/live/{id}.ts" };

describe("loadConfig", () => {
  it("defaults to loopback, one upstream, and a bounded cache", () => {
    const config = loadConfig(minimal);
    expect(config.host).toBe("127.0.0.1"); // opt in to LAN exposure, never by accident
    expect(config.port).toBe(8787);
    expect(config.edge.maxUpstreamConnections).toBe(1);
    expect(config.edge.ring).toEqual({ maxBytes: 16 * 1024 * 1024, maxChunks: 4096 });
    expect(config.edge.identity.userAgent).toBe("tvking-edge/1.0");
    expect(config.edge.lingerMs).toBe(15_000);
  });

  it("reads overrides from the environment", () => {
    const config = loadConfig({
      ...minimal,
      EDGE_HOST: "0.0.0.0",
      EDGE_PORT: "9000",
      EDGE_MAX_UPSTREAM: "2",
      EDGE_EGRESS_BPS: "1500000",
      EDGE_LINGER_MS: "3000",
      EDGE_USER_AGENT: "tvking-edge/2.0",
      EDGE_ALLOWED_HOSTS: "origin.example, cdn.example",
      EDGE_UPSTREAM_HEADERS: '{"x-origin-key":"secret"}',
    });
    expect(config.host).toBe("0.0.0.0");
    expect(config.port).toBe(9000);
    expect(config.edge.maxUpstreamConnections).toBe(2);
    expect(config.egressBytesPerSecond).toBe(1_500_000);
    expect(config.edge.lingerMs).toBe(3000);
    expect(config.edge.identity.userAgent).toBe("tvking-edge/2.0");
    expect(config.allowedHosts).toEqual(["origin.example", "cdn.example"]);
    expect(config.edge.identity.extra).toEqual({ "x-origin-key": "secret" });
  });

  it("refuses to start without an origin mapping", () => {
    expect(() => loadConfig({})).toThrow(ConfigError);
  });

  it("refuses a template without the {id} placeholder", () => {
    expect(() => loadConfig({ EDGE_ORIGIN_TEMPLATE: "https://origin.example/live.ts" })).toThrow(
      /\{id\} placeholder/
    );
  });

  it("refuses malformed numbers and JSON", () => {
    expect(() => loadConfig({ ...minimal, EDGE_PORT: "abc" })).toThrow(/positive number/);
    expect(() => loadConfig({ ...minimal, EDGE_PORT: "-1" })).toThrow(/positive number/);
    expect(() => loadConfig({ ...minimal, EDGE_STREAM_MAP: "{" })).toThrow(/valid JSON/);
    expect(() => loadConfig({ ...minimal, EDGE_STREAM_MAP: "[1]" })).toThrow(/JSON object/);
    expect(() => loadConfig({ ...minimal, EDGE_STREAM_MAP: '{"a":1}' })).toThrow(/must be a string/);
  });
});

describe("buildResolver", () => {
  it("prefers an explicit map and returns null for unlisted ids", () => {
    const resolve = buildResolver({ "sport-live": "https://origin.example/a.ts" }, undefined, null);
    expect(resolve("sport-live")).toEqual({ url: "https://origin.example/a.ts", extra: undefined });
    expect(resolve("unlisted")).toBeNull(); // a 404, never a guessed URL
  });

  it("encodes the id into a template", () => {
    const resolve = buildResolver(null, "https://origin.example/live/{id}.ts", null);
    expect(resolve("sport live")).toEqual({
      url: "https://origin.example/live/sport%20live.ts",
      extra: undefined,
    });
  });

  it("attaches the edge's own origin credentials to every target", () => {
    const resolve = buildResolver(null, "https://origin.example/{id}", { "x-key": "k" });
    expect(resolve("a")?.extra).toEqual({ "x-key": "k" });
  });

  it("resolves nothing when neither map nor template is configured", () => {
    expect(buildResolver(null, undefined, null)("a")).toBeNull();
  });
});
