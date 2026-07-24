import { describe, it, expect } from "vitest";
import { bestCandidateIndex, KEY_TO_DIR, type Box } from "../app/lib/spatial";

const box = (left: number, top: number, width = 100, height = 60): Box => ({
  left,
  top,
  width,
  height,
});

describe("KEY_TO_DIR", () => {
  it("maps the four arrow keys", () => {
    expect(KEY_TO_DIR.ArrowLeft).toBe("left");
    expect(KEY_TO_DIR.ArrowRight).toBe("right");
    expect(KEY_TO_DIR.ArrowUp).toBe("up");
    expect(KEY_TO_DIR.ArrowDown).toBe("down");
  });
  it("does not map non-arrow keys", () => {
    expect(KEY_TO_DIR.Enter).toBeUndefined();
  });
});

describe("bestCandidateIndex", () => {
  // A horizontal row: [0]=from at x0, [1] just right, [2] far right.
  const row = [box(0, 0), box(120, 0), box(400, 0)];

  it("picks the nearest element to the right", () => {
    expect(bestCandidateIndex(row[0], row, "right", 0)).toBe(1);
  });

  it("picks the nearest element to the left", () => {
    expect(bestCandidateIndex(row[2], row, "left", 2)).toBe(1);
  });

  it("returns -1 when nothing lies in the direction", () => {
    expect(bestCandidateIndex(row[2], row, "right", 2)).toBe(-1);
    expect(bestCandidateIndex(row[0], row, "up", 0)).toBe(-1);
  });

  it("excludes the origin element (fromIndex)", () => {
    // Moving right from index 1: only index 2 qualifies (index 1 is excluded,
    // index 0 is to the left).
    expect(bestCandidateIndex(row[1], row, "right", 1)).toBe(2);
  });

  it("prefers the axis-aligned candidate over a closer diagonal one", () => {
    const from = box(0, 0);
    const aligned = box(300, 0); // straight down-axis: far but aligned
    const diagonal = box(120, 200); // closer along X but big off-axis drift
    const boxes = [from, aligned, diagonal];
    // "right": aligned (idx 1) should beat the diagonal (idx 2) thanks to the
    // off-axis penalty.
    expect(bestCandidateIndex(from, boxes, "right", 0)).toBe(1);
  });

  it("navigates a vertical stack with up/down", () => {
    const stack = [box(0, 0), box(0, 100), box(0, 260)];
    expect(bestCandidateIndex(stack[0], stack, "down", 0)).toBe(1);
    expect(bestCandidateIndex(stack[2], stack, "up", 2)).toBe(1);
  });

  it("works with fromIndex = -1 (origin not part of the set)", () => {
    const origin = box(-200, 0);
    expect(bestCandidateIndex(origin, row, "right", -1)).toBe(0);
  });
});
