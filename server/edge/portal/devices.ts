/*
 * Subscriber devices: packages, MAC/Xtream identities, and their grants.
 *
 * A note on what is stored here, given the rest of this proxy goes out of its
 * way NOT to collect anything about viewers: a MAC address or an Xtream login
 * IS the subscriber identity — it is the thing being authorised, not telemetry
 * collected on the side. It never leaves the process towards the origin (the
 * master signature has no room for it), and it is visible only to the operator
 * who created it. Nothing else about the viewer is recorded: no IP, no user
 * agent, no viewing history beyond the live session list.
 *
 * MAC authentication is weak by nature — a MAC is trivially spoofable and
 * travels in a cookie. It is implemented because that is how MAG-style boxes
 * work, not because it is strong; treat it as an identifier, not a secret, and
 * put the portal on a trusted network.
 */

import { randomBytes, scryptSync, timingSafeEqual } from "node:crypto";
import type { Database } from "../db/database.ts";
import { systemWallClock, type WallClock } from "../clock.ts";
import { PLANS, isPlanId, planExpiry, renewalStart, type PlanId } from "./plans.ts";

export interface PackageRecord {
  id: number;
  name: string;
  accountId: string;
  /** Allowed group titles; empty means "everything in the account". */
  groups: string[];
  /** Explicit channel ids; empty means "no channel restriction". */
  channels: string[];
  vodEnabled: boolean;
  createdAt: number;
}

export interface DeviceRecord {
  id: number;
  mac: string | null;
  username: string | null;
  label: string;
  packageId: number | null;
  maxConnections: number;
  disabled: boolean;
  note: string;
  createdAt: number;
  updatedAt: number;
}

export interface SubscriptionRecord {
  id: number;
  deviceId: number;
  plan: PlanId;
  startsAt: number;
  expiresAt: number;
  createdAt: number;
  revokedAt: number | null;
  note: string;
}

export type AccessState = "active" | "expired" | "revoked" | "none" | "disabled";

export interface DeviceStatus {
  device: DeviceRecord;
  package: PackageRecord | null;
  subscription: SubscriptionRecord | null;
  state: AccessState;
  /** Milliseconds left; 0 when not active. */
  remainingMs: number;
}

export type AuthFailure =
  | "unknown-device"
  | "bad-credentials"
  | "disabled"
  | "no-subscription"
  | "expired"
  | "no-package";

export type AuthResult =
  | { ok: true; status: DeviceStatus; package: PackageRecord }
  | { ok: false; reason: AuthFailure; status?: DeviceStatus };

export class PortalError extends Error {
  name = "PortalError";
}

const MAC_RE = /^[0-9A-F]{2}(:[0-9A-F]{2}){5}$/;

/** Canonical form: upper-case, colon separated. Accepts the usual variants. */
export function normalizeMac(input: string): string {
  const hex = input.trim().toUpperCase().replace(/[^0-9A-F]/g, "");
  if (hex.length !== 12) throw new PortalError(`invalid MAC address: ${JSON.stringify(input)}`);
  const mac = (hex.match(/.{2}/g) as string[]).join(":");
  if (!MAC_RE.test(mac)) throw new PortalError(`invalid MAC address: ${JSON.stringify(input)}`);
  return mac;
}

export function isMac(input: string): boolean {
  try {
    normalizeMac(input);
    return true;
  } catch {
    return false;
  }
}

export function hashPassword(password: string): string {
  const salt = randomBytes(16);
  const hash = scryptSync(password, salt, 32);
  return `scrypt$${salt.toString("hex")}$${hash.toString("hex")}`;
}

export function verifyPassword(password: string, stored: string | null): boolean {
  if (!stored) return false;
  const [scheme, saltHex, hashHex] = stored.split("$");
  if (scheme !== "scrypt" || !saltHex || !hashHex) return false;
  const expected = Buffer.from(hashHex, "hex");
  const actual = scryptSync(password, Buffer.from(saltHex, "hex"), expected.length);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

/** Credentials for a device created without an explicit login. */
export function generateCredentials(): { username: string; password: string } {
  return {
    username: `tv${randomBytes(4).toString("hex")}`,
    password: randomBytes(6).toString("hex"),
  };
}

interface DeviceRow {
  id: number;
  mac: string | null;
  username: string | null;
  password_hash: string | null;
  label: string;
  package_id: number | null;
  max_connections: number;
  disabled: number;
  note: string;
  created_at: number;
  updated_at: number;
}

interface PackageRow {
  id: number;
  name: string;
  account_id: string;
  groups_json: string;
  channels_json: string;
  vod_enabled: number;
  created_at: number;
}

interface SubscriptionRow {
  id: number;
  device_id: number;
  plan: string;
  starts_at: number;
  expires_at: number;
  created_at: number;
  revoked_at: number | null;
  note: string;
}

function toPackage(row: PackageRow): PackageRecord {
  return {
    id: row.id,
    name: row.name,
    accountId: row.account_id,
    groups: JSON.parse(row.groups_json) as string[],
    channels: JSON.parse(row.channels_json) as string[],
    vodEnabled: row.vod_enabled === 1,
    createdAt: row.created_at,
  };
}

function toDevice(row: DeviceRow): DeviceRecord {
  return {
    id: row.id,
    mac: row.mac,
    username: row.username,
    label: row.label,
    packageId: row.package_id,
    maxConnections: row.max_connections,
    disabled: row.disabled === 1,
    note: row.note,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function toSubscription(row: SubscriptionRow): SubscriptionRecord {
  return {
    id: row.id,
    deviceId: row.device_id,
    plan: row.plan as PlanId,
    startsAt: row.starts_at,
    expiresAt: row.expires_at,
    createdAt: row.created_at,
    revokedAt: row.revoked_at,
    note: row.note,
  };
}

export interface PackageInput {
  name: string;
  accountId: string;
  groups?: string[];
  channels?: string[];
  vodEnabled?: boolean;
}

export interface DeviceInput {
  mac?: string | null;
  username?: string | null;
  password?: string | null;
  label?: string;
  packageId?: number | null;
  maxConnections?: number;
  disabled?: boolean;
  note?: string;
}

export class PortalRepository {
  #db: Database;
  #clock: WallClock;

  constructor(db: Database, clock: WallClock = systemWallClock) {
    this.#db = db;
    this.#clock = clock;
  }

  // ------------------------------------------------------------- packages

  upsertPackage(input: PackageInput): PackageRecord {
    if (!input.name?.trim()) throw new PortalError("a package needs a name");
    if (!input.accountId?.trim()) throw new PortalError("a package needs a master account");
    const now = this.#clock.now();
    this.#db.run(
      `INSERT INTO packages(name, account_id, groups_json, channels_json, vod_enabled, created_at)
       VALUES(?, ?, ?, ?, ?, ?)
       ON CONFLICT(name) DO UPDATE SET
         account_id = excluded.account_id,
         groups_json = excluded.groups_json,
         channels_json = excluded.channels_json,
         vod_enabled = excluded.vod_enabled`,
      input.name.trim(),
      input.accountId.trim(),
      JSON.stringify(input.groups ?? []),
      JSON.stringify(input.channels ?? []),
      input.vodEnabled === false ? 0 : 1,
      now
    );
    return this.packageByName(input.name.trim()) as PackageRecord;
  }

  packageByName(name: string): PackageRecord | null {
    const row = this.#db.get<PackageRow>("SELECT * FROM packages WHERE name = ?", name);
    return row ? toPackage(row) : null;
  }

  package(id: number): PackageRecord | null {
    const row = this.#db.get<PackageRow>("SELECT * FROM packages WHERE id = ?", id);
    return row ? toPackage(row) : null;
  }

  listPackages(): PackageRecord[] {
    return this.#db.all<PackageRow>("SELECT * FROM packages ORDER BY name").map(toPackage);
  }

  removePackage(id: number): boolean {
    return this.#db.run("DELETE FROM packages WHERE id = ?", id).changes > 0;
  }

  // -------------------------------------------------------------- devices

  createDevice(input: DeviceInput): DeviceRecord {
    const mac = input.mac ? normalizeMac(input.mac) : null;
    const username = input.username?.trim() || null;
    if (!mac && !username) {
      throw new PortalError("a device needs a MAC address or a username");
    }
    if (username && !input.password) {
      throw new PortalError("an Xtream login needs a password");
    }
    const now = this.#clock.now();
    const result = this.#db.run(
      `INSERT INTO devices(mac, username, password_hash, label, package_id, max_connections,
                           disabled, note, created_at, updated_at)
       VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      mac,
      username,
      input.password ? hashPassword(input.password) : null,
      input.label ?? "",
      input.packageId ?? null,
      input.maxConnections ?? 1,
      input.disabled ? 1 : 0,
      input.note ?? "",
      now,
      now
    );
    return this.device(result.lastInsertRowid) as DeviceRecord;
  }

  updateDevice(id: number, patch: DeviceInput): DeviceRecord {
    const existing = this.device(id);
    if (!existing) throw new PortalError(`unknown device ${id}`);

    const mac = patch.mac === undefined ? existing.mac : patch.mac ? normalizeMac(patch.mac) : null;
    const username =
      patch.username === undefined ? existing.username : patch.username?.trim() || null;
    if (!mac && !username) {
      throw new PortalError("a device needs a MAC address or a username");
    }

    this.#db.run(
      `UPDATE devices SET mac = ?, username = ?, label = ?, package_id = ?, max_connections = ?,
                          disabled = ?, note = ?, updated_at = ?
       WHERE id = ?`,
      mac,
      username,
      patch.label ?? existing.label,
      patch.packageId === undefined ? existing.packageId : patch.packageId,
      patch.maxConnections ?? existing.maxConnections,
      (patch.disabled ?? existing.disabled) ? 1 : 0,
      patch.note ?? existing.note,
      this.#clock.now(),
      id
    );
    if (patch.password) {
      this.#db.run("UPDATE devices SET password_hash = ? WHERE id = ?", hashPassword(patch.password), id);
    }
    return this.device(id) as DeviceRecord;
  }

  removeDevice(id: number): boolean {
    return this.#db.run("DELETE FROM devices WHERE id = ?", id).changes > 0;
  }

  device(id: number): DeviceRecord | null {
    const row = this.#db.get<DeviceRow>("SELECT * FROM devices WHERE id = ?", id);
    return row ? toDevice(row) : null;
  }

  deviceByMac(mac: string): DeviceRecord | null {
    let normalized: string;
    try {
      normalized = normalizeMac(mac);
    } catch {
      return null;
    }
    const row = this.#db.get<DeviceRow>("SELECT * FROM devices WHERE mac = ?", normalized);
    return row ? toDevice(row) : null;
  }

  deviceByUsername(username: string): DeviceRecord | null {
    const row = this.#db.get<DeviceRow>("SELECT * FROM devices WHERE username = ?", username);
    return row ? toDevice(row) : null;
  }

  listDevices(): DeviceStatus[] {
    return this.#db
      .all<DeviceRow>("SELECT * FROM devices ORDER BY created_at DESC")
      .map((row) => this.status(toDevice(row)));
  }

  // -------------------------------------------------------- subscriptions

  /**
   * Grants (or extends) access. Renewing before expiry stacks on the remaining
   * time instead of throwing it away.
   */
  grant(deviceId: number, plan: PlanId, options: { note?: string; now?: number } = {}): SubscriptionRecord {
    if (!isPlanId(plan)) throw new PortalError(`unknown plan: ${String(plan)}`);
    const device = this.device(deviceId);
    if (!device) throw new PortalError(`unknown device ${deviceId}`);

    const now = options.now ?? this.#clock.now();
    const current = this.activeSubscription(deviceId, now);
    const startsAt = renewalStart(current ? current.expiresAt : null, now);
    const expiresAt = planExpiry(plan, startsAt);

    const result = this.#db.run(
      `INSERT INTO subscriptions(device_id, plan, starts_at, expires_at, created_at, note)
       VALUES(?, ?, ?, ?, ?, ?)`,
      deviceId,
      plan,
      startsAt,
      expiresAt,
      now,
      options.note ?? PLANS[plan].label
    );
    return this.#subscription(result.lastInsertRowid) as SubscriptionRecord;
  }

  /** Revokes every live grant. Returns how many were affected. */
  revoke(deviceId: number, now = this.#clock.now()): number {
    return this.#db.run(
      "UPDATE subscriptions SET revoked_at = ? WHERE device_id = ? AND revoked_at IS NULL AND expires_at > ?",
      now,
      deviceId,
      now
    ).changes;
  }

  /** The grant that is valid right now, if any. */
  activeSubscription(deviceId: number, now = this.#clock.now()): SubscriptionRecord | null {
    const row = this.#db.get<SubscriptionRow>(
      `SELECT * FROM subscriptions
        WHERE device_id = ? AND revoked_at IS NULL AND expires_at > ? AND starts_at <= ?
        ORDER BY expires_at DESC LIMIT 1`,
      deviceId,
      now,
      now
    );
    return row ? toSubscription(row) : null;
  }

  subscriptionHistory(deviceId: number): SubscriptionRecord[] {
    return this.#db
      .all<SubscriptionRow>(
        "SELECT * FROM subscriptions WHERE device_id = ? ORDER BY created_at DESC",
        deviceId
      )
      .map(toSubscription);
  }

  status(device: DeviceRecord, now = this.#clock.now()): DeviceStatus {
    const pack = device.packageId ? this.package(device.packageId) : null;
    const active = this.activeSubscription(device.id, now);
    if (active) {
      return {
        device,
        package: pack,
        subscription: active,
        state: device.disabled ? "disabled" : "active",
        remainingMs: device.disabled ? 0 : Math.max(0, active.expiresAt - now),
      };
    }

    // No live grant: say WHY, since "expired" and "revoked" mean different
    // things to whoever is looking at the panel.
    const latest = this.#db.get<SubscriptionRow>(
      "SELECT * FROM subscriptions WHERE device_id = ? ORDER BY created_at DESC LIMIT 1",
      device.id
    );
    const state: AccessState = device.disabled
      ? "disabled"
      : !latest
        ? "none"
        : latest.revoked_at !== null
          ? "revoked"
          : "expired";
    return {
      device,
      package: pack,
      subscription: latest ? toSubscription(latest) : null,
      state,
      remainingMs: 0,
    };
  }

  // ----------------------------------------------------------------- auth

  authenticateMac(mac: string, now = this.#clock.now()): AuthResult {
    const device = this.deviceByMac(mac);
    if (!device) return { ok: false, reason: "unknown-device" };
    return this.#authorise(device, now);
  }

  authenticateXtream(username: string, password: string, now = this.#clock.now()): AuthResult {
    const device = this.deviceByUsername(username);
    if (!device) return { ok: false, reason: "unknown-device" };
    const row = this.#db.get<DeviceRow>("SELECT * FROM devices WHERE id = ?", device.id);
    if (!verifyPassword(password, row?.password_hash ?? null)) {
      return { ok: false, reason: "bad-credentials" };
    }
    return this.#authorise(device, now);
  }

  #authorise(device: DeviceRecord, now: number): AuthResult {
    const status = this.status(device, now);
    if (device.disabled) return { ok: false, reason: "disabled", status };
    if (!status.subscription) return { ok: false, reason: "no-subscription", status };
    if (status.state !== "active") {
      return { ok: false, reason: status.state === "revoked" ? "no-subscription" : "expired", status };
    }
    if (!status.package) return { ok: false, reason: "no-package", status };
    return { ok: true, status, package: status.package };
  }

  #subscription(id: number): SubscriptionRecord | null {
    const row = this.#db.get<SubscriptionRow>("SELECT * FROM subscriptions WHERE id = ?", id);
    return row ? toSubscription(row) : null;
  }
}
