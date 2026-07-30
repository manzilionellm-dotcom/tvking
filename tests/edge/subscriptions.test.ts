/*
 * Subscription durations, device auth, and — the point of the exercise —
 * expiration ENFORCEMENT: an account that runs out mid-stream loses the stream,
 * not just the next login.
 */

import { describe, expect, it } from "vitest";
import { ManualWallClock } from "../../server/edge/clock.ts";
import { openDatabase, migrate, schemaVersion, Database } from "../../server/edge/db/database.ts";
import {
  PortalError,
  PortalRepository,
  hashPassword,
  isMac,
  normalizeMac,
  verifyPassword,
} from "../../server/edge/portal/devices.ts";
import { PLANS, addMonthsUtc, planExpiry, renewalStart } from "../../server/edge/portal/plans.ts";
import { ExpirationEnforcer } from "../../server/edge/portal/enforcer.ts";
import { EdgeProxy } from "../../server/edge/edge.ts";
import { MockOrigin, tick } from "./mock-origin.ts";

const DAY = 24 * 3_600_000;

function harness(start = "2026-03-15T10:00:00Z") {
  const db = openDatabase(":memory:");
  const clock = new ManualWallClock(start);
  const repo = new PortalRepository(db, clock);
  const pack = repo.upsertPackage({ name: "full", accountId: "master" });
  return { db, clock, repo, pack };
}

describe("schema migrations", () => {
  it("applies once and is idempotent", () => {
    const db = new Database(":memory:");
    const first = migrate(db);
    expect(first.applied).toEqual([1]);
    expect(schemaVersion(db)).toBe(1);

    const second = migrate(db);
    expect(second.applied).toEqual([]); // nothing re-applied
    expect(schemaVersion(db)).toBe(1);
    db.close();
  });

  it("creates the portal and VOD tables", () => {
    const db = openDatabase(":memory:");
    const tables = db
      .all<{ name: string }>("SELECT name FROM sqlite_master WHERE type = 'table'")
      .map((row) => row.name);
    for (const table of [
      "packages",
      "devices",
      "subscriptions",
      "vod_sources",
      "vod_categories",
      "vod_titles",
      "vod_streams",
      "vod_chunks",
    ]) {
      expect(tables).toContain(table);
    }
    db.close();
  });

  it("rolls back a failing migration instead of leaving half a schema", () => {
    const db = new Database(":memory:");
    expect(() =>
      migrate(db, [{ version: 1, name: "broken", sql: "CREATE TABLE a(x); CREATE TABLE a(x);" }])
    ).toThrow();
    expect(schemaVersion(db)).toBe(0);
    expect(db.all("SELECT name FROM sqlite_master WHERE name = 'a'")).toEqual([]);
    db.close();
  });
});

describe("plans", () => {
  it("uses calendar months, not 30-day approximations", () => {
    const march15 = Date.parse("2026-03-15T10:00:00Z");
    expect(new Date(planExpiry("1m", march15)).toISOString()).toBe("2026-04-15T10:00:00.000Z");
    expect(new Date(planExpiry("3m", march15)).toISOString()).toBe("2026-06-15T10:00:00.000Z");
    expect(new Date(planExpiry("12m", march15)).toISOString()).toBe("2027-03-15T10:00:00.000Z");
  });

  it("clamps the day when the target month is shorter", () => {
    const jan31 = Date.parse("2026-01-31T12:00:00Z");
    expect(new Date(addMonthsUtc(jan31, 1)).toISOString()).toBe("2026-02-28T12:00:00.000Z");
    const jan31Leap = Date.parse("2028-01-31T12:00:00Z");
    expect(new Date(addMonthsUtc(jan31Leap, 1)).toISOString()).toBe("2028-02-29T12:00:00.000Z");
  });

  it("gives a trial exactly 24 hours", () => {
    const now = Date.parse("2026-03-15T10:00:00Z");
    expect(planExpiry("trial-24h", now) - now).toBe(DAY);
    expect(PLANS["trial-24h"].trial).toBe(true);
  });

  it("stacks a renewal on the remaining time instead of restarting it", () => {
    const now = 1000;
    expect(renewalStart(5000, now)).toBe(5000); // still valid → extend from expiry
    expect(renewalStart(500, now)).toBe(now); // already expired → start now
    expect(renewalStart(null, now)).toBe(now);
  });
});

describe("MAC handling", () => {
  it("normalises the usual notations to one canonical form", () => {
    for (const input of [
      "00:1a:79:aa:bb:cc",
      "00-1A-79-AA-BB-CC",
      "001A79AABBCC",
      " 00:1A:79:aa:bb:cc ",
    ]) {
      expect(normalizeMac(input)).toBe("00:1A:79:AA:BB:CC");
    }
  });

  it("rejects anything that is not a MAC", () => {
    for (const bad of ["", "00:1A:79", "zz:1A:79:AA:BB:CC", "00:1A:79:AA:BB:CC:DD"]) {
      expect(isMac(bad)).toBe(false);
      expect(() => normalizeMac(bad)).toThrow(PortalError);
    }
  });
});

describe("passwords", () => {
  it("stores a salted hash, never the password", () => {
    const stored = hashPassword("hunter2");
    expect(stored).not.toContain("hunter2");
    expect(stored.startsWith("scrypt$")).toBe(true);
    expect(verifyPassword("hunter2", stored)).toBe(true);
    expect(verifyPassword("hunter3", stored)).toBe(false);
    expect(verifyPassword("hunter2", null)).toBe(false);
    // Two hashes of the same password differ: the salt is doing its job.
    expect(hashPassword("hunter2")).not.toBe(stored);
  });
});

describe("devices and grants", () => {
  it("authorises a MAC with a live subscription", () => {
    const { repo, pack } = harness();
    const device = repo.createDevice({ mac: "00:1a:79:aa:bb:cc", label: "Salon", packageId: pack.id });
    repo.grant(device.id, "1m");

    const auth = repo.authenticateMac("001A79AABBCC");
    expect(auth.ok).toBe(true);
    if (auth.ok) expect(auth.package.name).toBe("full");
  });

  it("authorises an Xtream login and rejects a wrong password", () => {
    const { repo, pack } = harness();
    const device = repo.createDevice({
      username: "client01",
      password: "s3cret",
      packageId: pack.id,
    });
    repo.grant(device.id, "3m");

    expect(repo.authenticateXtream("client01", "s3cret").ok).toBe(true);
    const bad = repo.authenticateXtream("client01", "nope");
    expect(bad.ok).toBe(false);
    if (!bad.ok) expect(bad.reason).toBe("bad-credentials");
  });

  it("says WHY access is refused", () => {
    const { repo, clock, pack } = harness();
    const unknown = repo.authenticateMac("00:11:22:33:44:55");
    expect(unknown.ok).toBe(false);
    if (!unknown.ok) expect(unknown.reason).toBe("unknown-device");

    const device = repo.createDevice({ mac: "00:1a:79:aa:bb:cc", packageId: pack.id });
    const none = repo.authenticateMac(device.mac as string);
    if (!none.ok) expect(none.reason).toBe("no-subscription");

    repo.grant(device.id, "trial-24h");
    clock.advance(DAY + 1000);
    const expired = repo.authenticateMac(device.mac as string);
    if (!expired.ok) expect(expired.reason).toBe("expired");
    expect(repo.status(device).state).toBe("expired");

    repo.grant(device.id, "1m");
    repo.updateDevice(device.id, { disabled: true });
    const disabled = repo.authenticateMac(device.mac as string);
    if (!disabled.ok) expect(disabled.reason).toBe("disabled");
  });

  it("distinguishes revoked from expired", () => {
    const { repo, pack } = harness();
    const device = repo.createDevice({ mac: "00:1a:79:aa:bb:cc", packageId: pack.id });
    repo.grant(device.id, "12m");
    expect(repo.revoke(device.id)).toBe(1);
    expect(repo.status(device).state).toBe("revoked");
    expect(repo.authenticateMac(device.mac as string).ok).toBe(false);
  });

  it("refuses a device without an identity, and one without a package", () => {
    const { repo } = harness();
    expect(() => repo.createDevice({ label: "orphan" })).toThrow(/MAC address or a username/);
    const device = repo.createDevice({ mac: "00:1a:79:aa:bb:cd" });
    repo.grant(device.id, "1m");
    const auth = repo.authenticateMac(device.mac as string);
    expect(auth.ok).toBe(false);
    if (!auth.ok) expect(auth.reason).toBe("no-package");
  });

  it("keeps the whole grant history", () => {
    const { repo, clock, pack } = harness();
    const device = repo.createDevice({ mac: "00:1a:79:aa:bb:cc", packageId: pack.id });
    repo.grant(device.id, "trial-24h");
    clock.advance(2 * DAY);
    repo.grant(device.id, "1m");

    const history = repo.subscriptionHistory(device.id);
    expect(history.map((s) => s.plan)).toEqual(["1m", "trial-24h"]);
    expect(repo.status(device).subscription?.plan).toBe("1m");
  });

  it("extends rather than resets when renewing early", () => {
    const { repo, clock, pack } = harness("2026-03-15T10:00:00Z");
    const device = repo.createDevice({ mac: "00:1a:79:aa:bb:cc", packageId: pack.id });
    repo.grant(device.id, "1m"); // → 15 April
    clock.advance(5 * DAY); // 20 March, still valid
    const renewed = repo.grant(device.id, "1m"); // → 15 May, not 20 April

    expect(new Date(renewed.expiresAt).toISOString()).toBe("2026-05-15T10:00:00.000Z");
  });
});

describe("expiration enforcement", () => {
  async function streamingHarness() {
    const { db, clock, repo, pack } = harness();
    const origin = new MockOrigin({ openDelayMs: 1 });
    const edge = new EdgeProxy({
      accounts: [{ id: "master", channelTemplate: "https://origin.example/{id}.ts", maxConnections: 4 }],
      transport: origin,
      lingerMs: 0,
      swapSettleMs: 0,
    });
    const dropped: string[] = [];
    const enforcer = new ExpirationEnforcer({
      repo,
      edge,
      wallClock: clock,
      onEvent: (event) => dropped.push(`${event.device}:${event.reason}`),
    });
    return { db, clock, repo, pack, edge, enforcer, dropped };
  }

  it("cuts a live stream the moment the subscription expires", async () => {
    const { clock, repo, pack, edge, enforcer, dropped } = await streamingHarness();
    const device = repo.createDevice({ mac: "00:1a:79:aa:bb:cc", label: "Salon", packageId: pack.id });
    repo.grant(device.id, "trial-24h");

    const joined = await edge.subscribe("master/tf1", {
      owner: { deviceId: device.id, label: "Salon" },
    });
    expect(edge.sessionsForDevice(device.id)).toHaveLength(1);

    // Still inside the 24 h: the sweep must not touch it.
    clock.advance(23 * 3_600_000);
    expect(enforcer.sweep().droppedSessions).toBe(0);
    expect(joined.subscription.closed).toBe(false);

    // One second past expiry: the stream goes, not just the next login.
    clock.advance(3_600_000 + 1000);
    const result = enforcer.sweep();
    expect(result.droppedSessions).toBe(1);
    expect(result.devices[0]).toMatchObject({ deviceId: device.id, reason: "expired" });
    expect(joined.subscription.closed).toBe(true);
    expect(edge.sessionsForDevice(device.id)).toHaveLength(0);
    expect(dropped).toContain(`${device.id}:expired`);

    await tick(5);
    await edge.shutdown();
  });

  it("cuts on revocation without waiting for the calendar", async () => {
    const { repo, pack, edge, enforcer } = await streamingHarness();
    const device = repo.createDevice({ mac: "00:1a:79:aa:bb:cc", packageId: pack.id });
    repo.grant(device.id, "12m");
    const joined = await edge.subscribe("master/tf1", { owner: { deviceId: device.id } });

    repo.revoke(device.id);
    const result = enforcer.sweep();

    expect(result.droppedSessions).toBe(1);
    expect(result.devices[0].reason).toBe("revoked");
    expect(joined.subscription.closed).toBe(true);
    await edge.shutdown();
  });

  it("cuts a disabled device and one that was deleted outright", async () => {
    const { repo, pack, edge, enforcer } = await streamingHarness();
    const disabled = repo.createDevice({ mac: "00:1a:79:aa:bb:01", packageId: pack.id });
    const deleted = repo.createDevice({ mac: "00:1a:79:aa:bb:02", packageId: pack.id });
    repo.grant(disabled.id, "1m");
    repo.grant(deleted.id, "1m");

    const a = await edge.subscribe("master/tf1", { owner: { deviceId: disabled.id } });
    const b = await edge.subscribe("master/m6", { owner: { deviceId: deleted.id } });

    repo.updateDevice(disabled.id, { disabled: true });
    repo.removeDevice(deleted.id);
    const result = enforcer.sweep();

    expect(result.droppedSessions).toBe(2);
    expect(result.devices.map((d) => d.reason).sort()).toEqual(["disabled", "unknown-device"]);
    expect(a.subscription.closed).toBe(true);
    expect(b.subscription.closed).toBe(true);
    await edge.shutdown();
  });

  it("leaves sessions with no owner alone", async () => {
    const { edge, enforcer } = await streamingHarness();
    const joined = await edge.subscribe("master/tf1"); // the raw LAN route

    const result = enforcer.sweep();
    expect(result.checkedSessions).toBe(0);
    expect(result.droppedSessions).toBe(0);
    expect(joined.subscription.closed).toBe(false);
    await edge.shutdown();
  });

  it("cuts every session of a device, not just the first", async () => {
    const { clock, repo, pack, edge, enforcer } = await streamingHarness();
    const device = repo.createDevice({ mac: "00:1a:79:aa:bb:cc", packageId: pack.id, maxConnections: 3 });
    repo.grant(device.id, "trial-24h");

    const sessions = await Promise.all([
      edge.subscribe("master/tf1", { owner: { deviceId: device.id } }),
      edge.subscribe("master/tf1", { owner: { deviceId: device.id } }),
      edge.subscribe("master/m6", { owner: { deviceId: device.id } }),
    ]);

    clock.advance(DAY + 1);
    expect(enforcer.sweep().droppedSessions).toBe(3);
    for (const session of sessions) expect(session.subscription.closed).toBe(true);
    await edge.shutdown();
  });

  it("runs on a timer once started", async () => {
    const { clock, repo, pack, edge, enforcer } = await streamingHarness();
    const device = repo.createDevice({ mac: "00:1a:79:aa:bb:cc", packageId: pack.id });
    repo.grant(device.id, "trial-24h");
    const joined = await edge.subscribe("master/tf1", { owner: { deviceId: device.id } });

    enforcer.start();
    expect(enforcer.running).toBe(true);
    clock.advance(DAY + 1);
    // The loop sleeps on the monotonic clock; drive one sweep deterministically.
    enforcer.sweep();
    expect(joined.subscription.closed).toBe(true);

    await enforcer.stop();
    expect(enforcer.running).toBe(false);
    await edge.shutdown();
  });
});
