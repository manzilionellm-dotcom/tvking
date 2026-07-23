import { describe, it, expect, beforeEach } from "vitest";
import {
  scrub,
  scrubData,
  logEvent,
  logError,
  recentEvents,
  setSink,
  _reset,
  RING_CAPACITY,
  type TelemetryEvent,
} from "../app/lib/telemetry";

beforeEach(() => _reset());

describe("scrub", () => {
  it("redacts emails", () => {
    expect(scrub("contact user@example.com now")).toBe("contact [redacted-email] now");
  });
  it("redacts bearer tokens / api keys", () => {
    expect(scrub("Authorization: Bearer abc.def")).toContain("[redacted]");
    expect(scrub("token=SECRETVALUE")).toContain("[redacted]");
  });
  it("redacts long id/hex/digit runs", () => {
    expect(scrub("id deadbeefdeadbeef01")).toContain("[redacted-id]");
    expect(scrub("card 4111111111111111")).toContain("[redacted-id]");
  });
  it("leaves clean text untouched", () => {
    expect(scrub("channel zap 42")).toBe("channel zap 42");
  });
});

describe("scrubData", () => {
  it("returns undefined for no data", () => {
    expect(scrubData(undefined)).toBeUndefined();
  });
  it("keeps numbers/booleans and scrubs strings", () => {
    expect(scrubData({ n: 3, ok: true, who: "a@b.co" })).toEqual({
      n: 3,
      ok: true,
      who: "[redacted-email]",
    });
  });
});

describe("logEvent / ring buffer", () => {
  it("records a scrubbed event", () => {
    logEvent("nav", "focus user@x.com", { path: "/sport" });
    const evs = recentEvents();
    expect(evs).toHaveLength(1);
    expect(evs[0].name).toBe("focus [redacted-email]");
    expect(evs[0].data).toEqual({ path: "/sport" });
  });

  it("caps the ring at RING_CAPACITY (oldest dropped)", () => {
    for (let i = 0; i < RING_CAPACITY + 10; i++) logEvent("app", `e${i}`);
    const evs = recentEvents();
    expect(evs).toHaveLength(RING_CAPACITY);
    expect(evs[0].name).toBe("e10"); // first 10 dropped
  });

  it("forwards to a sink and survives a throwing sink", () => {
    const seen: TelemetryEvent[] = [];
    setSink((e) => seen.push(e));
    logEvent("player", "start");
    expect(seen).toHaveLength(1);

    setSink(() => {
      throw new Error("sink down");
    });
    expect(() => logEvent("player", "stop")).not.toThrow();
  });
});

describe("logError", () => {
  it("extracts a scrubbed message and digest", () => {
    const err = Object.assign(new Error("boom for user@x.com"), { digest: "d1" });
    const ev = logError(err, { where: "route" });
    expect(ev.category).toBe("error");
    expect(ev.data?.message).toBe("boom for [redacted-email]");
    expect(ev.data?.digest).toBe("d1");
    expect(ev.data?.where).toBe("route");
  });

  it("handles non-Error throwables", () => {
    const ev = logError("plain failure");
    expect(ev.data?.message).toBe("plain failure");
    expect(ev.data?.digest).toBeUndefined();
  });
});
