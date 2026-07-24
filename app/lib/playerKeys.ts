/*
 * Pure mapping from a key / TV-remote media button to a player action.
 *
 * Why this exists: the previous player only toggled play on Space/"k" when
 * `document.activeElement === document.body`. But SpatialNav always moves focus
 * onto a control, so that branch never fired and Space/"k" did nothing. TV
 * remotes also emit dedicated media keys (developer.android.com media keys /
 * the KeyboardEvent "MediaPlayPause" family), which the player ignored.
 *
 * Keeping the mapping pure makes the remote contract explicit and unit-testable
 * without a DOM. The component maps the action to state; native Enter/Space on
 * a focused button still activate that button as usual.
 */

export type PlayerAction =
  | "toggle"
  | "exit"
  | "next"
  | "seekForward"
  | "seekBack";

/** Returns the action for a KeyboardEvent.key, or null if unmapped. */
export function playerKeyAction(key: string): PlayerAction | null {
  switch (key) {
    case "MediaPlayPause":
    case "MediaPlay":
    case "MediaPause":
    case "k": // YouTube convention (Space is left to the focused button)
      return "toggle";
    case "MediaStop":
      return "exit";
    case "MediaTrackNext":
      return "next";
    case "MediaFastForward":
      return "seekForward";
    case "MediaRewind":
      return "seekBack";
    default:
      return null;
  }
}
