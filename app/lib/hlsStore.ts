/*
 * Relais HLS aveugle (serveur) — logique pure + instance mémoire.
 *
 * Le relais détient DEUX choses, et rien de plus :
 *   1. des manifestes d'indexation (ordre des segments, durées, IV publics,
 *      URI de clé AVEUGLE) — jamais la clé ;
 *   2. des segments média chiffrés opaques (octets AES-128).
 *
 * Il ne peut ni déchiffrer, ni analyser les chunks. `putManifest` REJETTE tout
 * manifeste dont l'URI de clé n'est pas aveugle : le relais ne peut donc pas,
 * même par erreur de configuration, devenir une source de clé.
 */

import { type HlsManifest, parseManifest } from "./hls";
import { isSlotId, type Presence, presenceOf } from "./zk";

/** Plafonds — bornent la mémoire, jamais exposés en tant que nombres. */
export const MAX_STREAMS = 128;
export const MAX_SEGMENTS = 8192;

/** Taille max d'un chunk chiffré accepté (octets). */
export const MAX_SEGMENT_BYTES = 8 * 1024 * 1024;

export interface StoredSegment {
  /** octets chiffrés opaques. */
  bytes: Uint8Array;
}

export interface HlsRelay {
  /** streamSlot aveuglé → manifeste d'indexation. */
  manifests: Map<string, HlsManifest>;
  /** segmentSlot aveuglé → octets chiffrés. */
  segments: Map<string, StoredSegment>;
}

export function emptyRelay(): HlsRelay {
  return { manifests: new Map(), segments: new Map() };
}

export type PutManifestResult = "stored" | "rejected";

export function putManifest(relay: HlsRelay, streamSlot: unknown, rawManifest: unknown): PutManifestResult {
  if (!isSlotId(streamSlot)) return "rejected";
  const manifest = parseManifest(rawManifest); // rejette un keyUri non aveugle
  if (!manifest) return "rejected";
  relay.manifests.delete(streamSlot);
  relay.manifests.set(streamSlot, manifest);
  while (relay.manifests.size > MAX_STREAMS) {
    const oldest = relay.manifests.keys().next().value;
    if (oldest === undefined) break;
    relay.manifests.delete(oldest);
  }
  return "stored";
}

export function getManifest(relay: HlsRelay, streamSlot: unknown): HlsManifest | null {
  if (!isSlotId(streamSlot)) return null;
  return relay.manifests.get(streamSlot) ?? null;
}

export function deleteStream(relay: HlsRelay, streamSlot: unknown): void {
  if (!isSlotId(streamSlot)) return;
  relay.manifests.delete(streamSlot);
}

export type PutSegmentResult = "stored" | "rejected";

export function putSegment(relay: HlsRelay, segSlot: unknown, bytes: Uint8Array): PutSegmentResult {
  if (!isSlotId(segSlot)) return "rejected";
  if (bytes.length === 0 || bytes.length > MAX_SEGMENT_BYTES) return "rejected";
  relay.segments.delete(segSlot);
  relay.segments.set(segSlot, { bytes });
  while (relay.segments.size > MAX_SEGMENTS) {
    const oldest = relay.segments.keys().next().value;
    if (oldest === undefined) break;
    relay.segments.delete(oldest);
  }
  return "stored";
}

export function getSegment(relay: HlsRelay, segSlot: unknown): Uint8Array | null {
  if (!isSlotId(segSlot)) return null;
  return relay.segments.get(segSlot)?.bytes ?? null;
}

export function deleteSegment(relay: HlsRelay, segSlot: unknown): void {
  if (!isSlotId(segSlot)) return;
  relay.segments.delete(segSlot);
}

/* ------------------- vue panel : présence binaire seule -------------------- */

/** Un flux (manifeste) existe-t-il pour ce slot ? présent/absent, jamais un compte. */
export function streamPresence(relay: HlsRelay, streamSlot: unknown): Presence {
  return presenceOf(isSlotId(streamSlot) && relay.manifests.has(streamSlot));
}

/* ----------------------------- instance serveur ---------------------------- */

const g = globalThis as typeof globalThis & { __tvkingHlsRelay?: HlsRelay };

export function serverRelay(): HlsRelay {
  if (!g.__tvkingHlsRelay) g.__tvkingHlsRelay = emptyRelay();
  return g.__tvkingHlsRelay;
}
