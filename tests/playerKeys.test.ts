import { describe, expect, it } from "vitest";
import { BACK_KEYS, SEEK_STEP, playerKeyAction, seek } from "../app/lib/playerKeys";

describe("playerKeyAction", () => {
  it("leaves the player on every platform's BACK key", () => {
    for (const key of BACK_KEYS) expect(playerKeyAction(key)).toBe("exit");
    expect(playerKeyAction("MediaStop")).toBe("exit");
  });

  it("maps the remote transport keys", () => {
    expect(playerKeyAction("MediaPlayPause")).toBe("toggle");
    expect(playerKeyAction("MediaPlay")).toBe("play");
    expect(playerKeyAction("MediaPause")).toBe("pause");
    expect(playerKeyAction("MediaTrackNext")).toBe("next");
    expect(playerKeyAction("MediaFastForward")).toBe("seekForward");
    expect(playerKeyAction("MediaRewind")).toBe("seekBack");
  });

  it("only lets Space/k toggle when no control holds the focus", () => {
    expect(playerKeyAction(" ", true)).toBe("toggle");
    expect(playerKeyAction("k", true)).toBe("toggle");
    // A D-pad user always has focus on a button: Space must activate it.
    expect(playerKeyAction(" ", false)).toBeNull();
    expect(playerKeyAction("k", false)).toBeNull();
  });

  it("ignores navigation and unknown keys so SpatialNav keeps them", () => {
    for (const key of ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Enter", "F5", "é"]) {
      expect(playerKeyAction(key, true), key).toBeNull();
    }
  });
});

describe("seek", () => {
  it("clamps to the programme bounds", () => {
    expect(seek(5, -SEEK_STEP, 40)).toBe(0);
    expect(seek(35, SEEK_STEP, 40)).toBe(40);
    expect(seek(10, SEEK_STEP, 40)).toBe(20);
  });
});
