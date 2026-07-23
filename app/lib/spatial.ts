/*
 * Pure geometry for D-pad / spatial navigation.
 *
 * Extracted from SpatialNav so the "which element is next in direction X"
 * decision is a plain function of rectangles — no DOM, no React — and can be
 * unit-tested deterministically. SpatialNav wires it to real elements.
 *
 * Model: the nearest-element heuristic used by Android TV
 * (developer.android.com/training/tv/start/navigation). From the focused
 * element's centre, a candidate must lie primarily in the requested direction;
 * we then score by distance along the axis of travel plus a penalty for
 * off-axis drift, so aligned items win and we never jump diagonally across the
 * screen.
 */

export type Dir = "left" | "right" | "up" | "down";

/** Minimal rectangle shape (a subset of DOMRect) so callers can pass any box. */
export interface Box {
  left: number;
  top: number;
  width: number;
  height: number;
}

export const KEY_TO_DIR: Record<string, Dir> = {
  ArrowLeft: "left",
  ArrowRight: "right",
  ArrowUp: "up",
  ArrowDown: "down",
};

/** Weight applied to off-axis drift; > 1 keeps focus travel aligned to a row/column. */
export const ACROSS_PENALTY = 2.5;

function centre(b: Box) {
  return { x: b.left + b.width / 2, y: b.top + b.height / 2 };
}

/**
 * Index of the best candidate in `boxes` when moving `dir` from `from`.
 * Returns -1 when nothing lies in that direction. `fromIndex` (the currently
 * focused box, if it is part of `boxes`) is excluded from the search.
 */
export function bestCandidateIndex(
  from: Box,
  boxes: readonly Box[],
  dir: Dir,
  fromIndex = -1,
): number {
  const a = centre(from);
  let best = -1;
  let bestScore = Infinity;

  for (let i = 0; i < boxes.length; i++) {
    if (i === fromIndex) continue;
    const b = centre(boxes[i]);
    const dx = b.x - a.x;
    const dy = b.y - a.y;

    const inDir =
      (dir === "left" && dx < -1) ||
      (dir === "right" && dx > 1) ||
      (dir === "up" && dy < -1) ||
      (dir === "down" && dy > 1);
    if (!inDir) continue;

    const horizontal = dir === "left" || dir === "right";
    const along = horizontal ? Math.abs(dx) : Math.abs(dy);
    const across = horizontal ? Math.abs(dy) : Math.abs(dx);
    const score = along + across * ACROSS_PENALTY;

    if (score < bestScore) {
      bestScore = score;
      best = i;
    }
  }
  return best;
}
