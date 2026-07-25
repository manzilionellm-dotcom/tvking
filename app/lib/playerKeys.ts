/*
 * Pure mapping from a keyboard / TV-remote key to a player action.
 *
 * Why pure: the remote contract is the part of the player that cannot be
 * exercised in a browser test (no way to synthesise a real MediaPlayPause from
 * a set-top box), so it is extracted and unit-tested here, and the component
 * only maps action → state.
 *
 * BACK is emitted under several names depending on the platform (Android TV
 * WebView, Tizen, webOS, desktop browsers) — all of them leave the player.
 * Media keys follow the KeyboardEvent "Media*" family.
 */

export type PlayerAction =
  | "toggle"
  | "play"
  | "pause"
  | "exit"
  | "next"
  | "seekForward"
  | "seekBack";

export const BACK_KEYS = [
  "Escape",
  "Backspace",
  "GoBack",
  "BrowserBack",
  "XF86Back",
] as const;

/**
 * Action for a KeyboardEvent.key, or null when unmapped.
 *
 * `focusOnBody` mirrors the DOM state: Space and "k" only toggle when no
 * control holds the focus, otherwise Space must activate the focused button
 * (native behaviour) — the D-pad user always has focus somewhere.
 */
export function playerKeyAction(key: string, focusOnBody = false): PlayerAction | null {
  if ((BACK_KEYS as readonly string[]).includes(key)) return "exit";
  switch (key) {
    case "MediaPlayPause":
      return "toggle";
    case "MediaPlay":
      return "play";
    case "MediaPause":
      return "pause";
    case "MediaStop":
      return "exit";
    case "MediaTrackNext":
      return "next";
    case "MediaFastForward":
      return "seekForward";
    case "MediaRewind":
      return "seekBack";
    case " ":
    case "k":
      return focusOnBody ? "toggle" : null;
    default:
      return null;
  }
}

/** Seek step in seconds for the rewind / fast-forward keys and buttons. */
export const SEEK_STEP = 10;

/** Clamp a seek to the programme bounds. */
export function seek(pos: number, delta: number, duration: number): number {
  return Math.min(duration, Math.max(0, pos + delta));
}
