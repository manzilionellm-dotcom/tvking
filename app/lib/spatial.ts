/*
 * Pure geometry for D-pad spatial navigation — no DOM here, so the scoring
 * model is unit-testable. SpatialNav.tsx feeds it element centres.
 *
 * Model: from the current centre, a candidate is eligible if it lies primarily
 * in the pressed direction; the best one minimises distance along the axis of
 * travel plus a penalty for off-axis drift (aligned items win over closer
 * diagonal ones) — the nearest-element model used by Android TV.
 */

export type Dir = "left" | "right" | "up" | "down";

export interface Point {
  x: number;
  y: number;
}

export const KEY_TO_DIR: Record<string, Dir> = {
  ArrowLeft: "left",
  ArrowRight: "right",
  ArrowUp: "up",
  ArrowDown: "down",
};

/** Off-axis drift costs 2.5× the on-axis distance. */
export const ACROSS_PENALTY = 2.5;

export function isInDirection(from: Point, to: Point, dir: Dir): boolean {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  switch (dir) {
    case "left":
      return dx < -1;
    case "right":
      return dx > 1;
    case "up":
      return dy < -1;
    case "down":
      return dy > 1;
  }
}

/** Lower is better; null when the candidate is not in the direction at all. */
export function directionalScore(from: Point, to: Point, dir: Dir): number | null {
  if (!isInDirection(from, to, dir)) return null;
  const dx = Math.abs(to.x - from.x);
  const dy = Math.abs(to.y - from.y);
  const horizontal = dir === "left" || dir === "right";
  const along = horizontal ? dx : dy;
  const across = horizontal ? dy : dx;
  return along + across * ACROSS_PENALTY;
}

/** Index of the best candidate in `dir`, or -1 when none is eligible. */
export function bestIndex(from: Point, candidates: readonly Point[], dir: Dir): number {
  let best = -1;
  let bestScore = Infinity;
  for (let i = 0; i < candidates.length; i++) {
    const score = directionalScore(from, candidates[i], dir);
    if (score !== null && score < bestScore) {
      bestScore = score;
      best = i;
    }
  }
  return best;
}
