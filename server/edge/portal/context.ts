/*
 * What both subscriber portals need, and the small pieces they share.
 *
 * Both portals answer the same three questions in their own dialect: who are
 * you, what may you watch, and give me a playable URL. Keeping the resolution
 * of those answers here means the Xtream and Stalker surfaces stay thin
 * translations rather than two divergent implementations of the rules.
 */

import type { EdgeProxy } from "../edge.ts";
import type { WallClock } from "../clock.ts";
import type { M3uEntry } from "../m3u.ts";
import type { VodLibrary } from "../vod/library.ts";
import type { AuthFailure, DeviceStatus, PackageRecord, PortalRepository } from "./devices.ts";

export interface PortalContext {
  repo: PortalRepository;
  library: VodLibrary;
  edge: EdgeProxy;
  wallClock: WallClock;
  egressBytesPerSecond: number;
  /** Public origin used in generated links, e.g. "http://edge.lan:8787". */
  publicBase?: string;
  onEvent?: (event: PortalEvent) => void;
}

export type PortalEvent =
  | { type: "portal-auth"; portal: "xtream" | "stalker"; device: number; label: string }
  | { type: "portal-denied"; portal: "xtream" | "stalker"; reason: AuthFailure }
  | { type: "portal-limit"; device: number; label: string; max: number };

/** The library rows a subscriber may watch: downloaded AND assigned to them. */
export function visibleVod(
  context: PortalContext,
  status: DeviceStatus,
  query: { kind?: "movie" | "series"; categoryId?: number } = {}
) {
  if (!status.package?.vodEnabled) return [];
  return context.library.visibleItems(
    { packageId: status.package.id, deviceId: status.device.id },
    query
  );
}

/** Human-readable reason, safe to hand back to a player. */
export const DENIAL_MESSAGES: Record<AuthFailure, string> = {
  "unknown-device": "device not registered",
  "bad-credentials": "invalid credentials",
  disabled: "device disabled",
  "no-subscription": "no active subscription",
  expired: "subscription expired",
  "no-package": "no package assigned",
};

/**
 * Stable numeric id for a channel whose real id is a string. Xtream and Stalker
 * both insist on integers; a hash keeps the mapping stable across restarts and
 * playlist reorders, which an array index would not.
 */
export function numericId(value: string): number {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i += 1) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 1) % 2_000_000_000;
}

/** Channels a package grants, in catalogue order. */
export async function packageChannels(
  context: PortalContext,
  pack: PackageRecord
): Promise<M3uEntry[]> {
  const channels = await context.edge.channels(pack.accountId).catch(() => []);
  const groups = new Set(pack.groups.map((group) => group.toLowerCase()));
  const explicit = new Set(pack.channels);

  return channels.filter((channel) => {
    if (explicit.size > 0 && !explicit.has(channel.id)) return false;
    if (groups.size > 0 && !groups.has((channel.group ?? "").toLowerCase())) return false;
    return true;
  });
}

export function findChannelByNumericId(
  channels: readonly M3uEntry[],
  id: number
): M3uEntry | undefined {
  return channels.find((channel) => numericId(channel.id) === id);
}

/**
 * Refuses a new stream when the device already has as many as it bought.
 * Counted from live sessions, so it reflects reality rather than a stored guess.
 */
export function withinConnectionLimit(context: PortalContext, status: DeviceStatus): boolean {
  const active = context.edge.sessionsForDevice(status.device.id).length;
  if (active < status.device.maxConnections) return true;
  context.onEvent?.({
    type: "portal-limit",
    device: status.device.id,
    label: status.device.label,
    max: status.device.maxConnections,
  });
  return false;
}

export function baseUrl(context: PortalContext, host: string | undefined): string {
  return context.publicBase ?? `http://${host ?? "edge.lan"}`;
}

/** `2026-07-30 11:24:00` — the format both portals use in their payloads. */
export function formatTimestamp(epochMs: number): string {
  return new Date(epochMs).toISOString().replace("T", " ").slice(0, 19);
}
