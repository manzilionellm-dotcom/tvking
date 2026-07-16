"use client";

import { useEffect } from "react";

/*
 * D-pad / arrow-key spatial navigation.
 *
 * TV remotes only emit up/down/left/right/select, so we cannot rely on the DOM
 * tab order. On each arrow press we find the focusable element whose centre is
 * "most in that direction" from the current one — the nearest-element model used
 * by Android TV (developer.android.com/.../navigation-on-tv).
 *
 * Focusable = anything with [data-focusable] (cards, nav items, buttons).
 * Enter/Space activate; clicking is also fine (pointer users).
 */

type Dir = "left" | "right" | "up" | "down";

const KEY_TO_DIR: Record<string, Dir> = {
  ArrowLeft: "left",
  ArrowRight: "right",
  ArrowUp: "up",
  ArrowDown: "down",
};

function focusables(): HTMLElement[] {
  return Array.from(
    document.querySelectorAll<HTMLElement>("[data-focusable]")
  ).filter((el) => el.offsetParent !== null && !el.hasAttribute("disabled"));
}

function center(el: HTMLElement) {
  const r = el.getBoundingClientRect();
  return { x: r.left + r.width / 2, y: r.top + r.height / 2, r };
}

/** Pick the best candidate in `dir` from the focused element's geometry. */
function bestCandidate(current: HTMLElement, dir: Dir): HTMLElement | null {
  const from = center(current);
  let best: HTMLElement | null = null;
  let bestScore = Infinity;

  for (const el of focusables()) {
    if (el === current) continue;
    const to = center(el);
    const dx = to.x - from.x;
    const dy = to.y - from.y;

    // Must be primarily in the requested direction.
    const inDir =
      (dir === "left" && dx < -1) ||
      (dir === "right" && dx > 1) ||
      (dir === "up" && dy < -1) ||
      (dir === "down" && dy > 1);
    if (!inDir) continue;

    // Distance along the axis of travel + a penalty for off-axis drift, so we
    // prefer aligned items and don't jump diagonally across the screen.
    const along = dir === "left" || dir === "right" ? Math.abs(dx) : Math.abs(dy);
    const across = dir === "left" || dir === "right" ? Math.abs(dy) : Math.abs(dx);
    const score = along + across * 2.5;

    if (score < bestScore) {
      bestScore = score;
      best = el;
    }
  }
  return best;
}

export default function SpatialNav() {
  useEffect(() => {
    // Focus the first focusable on mount so a remote has a starting point —
    // but not on touch/pocket screens, where a focus ring at load is noise.
    const touchUI = window.matchMedia("(hover: none), (width < 48rem)").matches;
    if (!touchUI) {
      const first = focusables()[0];
      if (first && document.activeElement === document.body) first.focus();
    }

    function onKeyDown(e: KeyboardEvent) {
      const dir = KEY_TO_DIR[e.key];
      if (!dir) return;

      const active = document.activeElement as HTMLElement | null;
      const current =
        active && active.hasAttribute("data-focusable") ? active : focusables()[0];
      if (!current) return;

      const next = bestCandidate(current, dir);
      if (next) {
        e.preventDefault();
        next.focus();
        next.scrollIntoView({ behavior: "smooth", block: "nearest", inline: "center" });
      }
    }

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  return null;
}
