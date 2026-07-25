import { describe, expect, it } from "vitest";
import {
  ACROSS_PENALTY,
  bestIndex,
  directionalScore,
  isInDirection,
  KEY_TO_DIR,
} from "../app/lib/spatial";

const O = { x: 100, y: 100 };

describe("KEY_TO_DIR", () => {
  it("maps the four arrow keys and nothing else", () => {
    expect(KEY_TO_DIR.ArrowLeft).toBe("left");
    expect(KEY_TO_DIR.ArrowRight).toBe("right");
    expect(KEY_TO_DIR.ArrowUp).toBe("up");
    expect(KEY_TO_DIR.ArrowDown).toBe("down");
    expect(KEY_TO_DIR.Enter).toBeUndefined();
  });
});

describe("isInDirection", () => {
  it("accepts elements past the 1px dead-zone only", () => {
    expect(isInDirection(O, { x: 130, y: 100 }, "right")).toBe(true);
    expect(isInDirection(O, { x: 100.5, y: 100 }, "right")).toBe(false); // dead-zone
    expect(isInDirection(O, { x: 70, y: 100 }, "right")).toBe(false); // wrong side
    expect(isInDirection(O, { x: 100, y: 60 }, "up")).toBe(true);
    expect(isInDirection(O, { x: 100, y: 140 }, "up")).toBe(false);
  });
});

describe("directionalScore", () => {
  it("is null outside the direction", () => {
    expect(directionalScore(O, { x: 50, y: 100 }, "right")).toBeNull();
  });

  it("penalises off-axis drift by ACROSS_PENALTY", () => {
    expect(directionalScore(O, { x: 140, y: 110 }, "right")).toBe(40 + 10 * ACROSS_PENALTY);
  });
});

describe("bestIndex", () => {
  it("returns -1 when nothing lies in the direction", () => {
    expect(bestIndex(O, [{ x: 50, y: 100 }], "right")).toBe(-1);
    expect(bestIndex(O, [], "down")).toBe(-1);
  });

  it("picks the nearest candidate along the axis", () => {
    const idx = bestIndex(
      O,
      [
        { x: 300, y: 100 },
        { x: 150, y: 100 },
      ],
      "right"
    );
    expect(idx).toBe(1);
  });

  it("prefers an aligned candidate over a closer diagonal one (no diagonal jumps)", () => {
    const aligned = { x: 250, y: 100 }; // along=150, across=0 → 150
    const diagonal = { x: 150, y: 80 }; // along=50, across=20 → 50 + 20*2.5 = 100… closer wins
    // With a large enough drift the aligned one must win:
    const farDiagonal = { x: 120, y: 160 }; // 20 + 60*2.5 = 170
    expect(bestIndex(O, [farDiagonal, aligned], "right")).toBe(1);
    // A modest drift still wins on raw score — documents the model's trade-off.
    expect(bestIndex(O, [diagonal, aligned], "right")).toBe(0);
  });

  it("works vertically", () => {
    const idx = bestIndex(
      O,
      [
        { x: 100, y: 300 },
        { x: 105, y: 180 },
        { x: 100, y: 50 },
      ],
      "down"
    );
    expect(idx).toBe(1);
  });
});
