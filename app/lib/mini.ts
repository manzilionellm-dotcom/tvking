/*
 * Global reduced-playback state — the YouTube-style floating mini-player.
 *
 * Minimising the full-screen player hands playback over to this store; the
 * MiniPlayer component (mounted once in the layout) renders it above every
 * page, so watching — or just listening with the écouteurs (audio-only) mode —
 * continues while the user browses the app.
 *
 * A tiny module-level external store (useSyncExternalStore-compatible):
 * playback is session-scoped by design, the resume store handles persistence.
 */

import type { MediaItem } from "./data";

export interface MiniState {
  item: MediaItem;
  /** Up-next target for the ⏭ control (null: control hidden). */
  next: MediaItem | null;
  /** Playhead in seconds. */
  pos: number;
  playing: boolean;
  /** Écouteurs mode: audio keeps playing, the video surface is put away. */
  audioOnly: boolean;
}

let state: MiniState | null = null;
const listeners = new Set<() => void>();

export function subscribeMini(cb: () => void): () => void {
  listeners.add(cb);
  return () => listeners.delete(cb);
}

export function getMini(): MiniState | null {
  return state;
}

/** Server snapshot — there is never a mini-player in static HTML. */
export function getMiniServer(): MiniState | null {
  return null;
}

export function setMini(next: MiniState | null): void {
  state = next;
  listeners.forEach((l) => l());
}

export function updateMini(patch: Partial<MiniState>): void {
  if (state) setMini({ ...state, ...patch });
}
