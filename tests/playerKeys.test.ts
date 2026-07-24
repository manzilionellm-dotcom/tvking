import { describe, it, expect } from "vitest";
import { playerKeyAction } from "../app/lib/playerKeys";

describe("playerKeyAction", () => {
  it("toggles on media play/pause keys and 'k'", () => {
    for (const key of ["MediaPlayPause", "MediaPlay", "MediaPause", "k"]) {
      expect(playerKeyAction(key)).toBe("toggle");
    }
  });

  it("maps stop / next / seek keys", () => {
    expect(playerKeyAction("MediaStop")).toBe("exit");
    expect(playerKeyAction("MediaTrackNext")).toBe("next");
    expect(playerKeyAction("MediaFastForward")).toBe("seekForward");
    expect(playerKeyAction("MediaRewind")).toBe("seekBack");
  });

  it("returns null for unmapped keys (incl. bare Space, left to the focused button)", () => {
    for (const key of [" ", "Enter", "ArrowUp", "a", "Escape"]) {
      expect(playerKeyAction(key)).toBeNull();
    }
  });
});
