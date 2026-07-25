"use client";

import { usePathname } from "next/navigation";
import { useEffect } from "react";
import { KEY_TO_DIR, bestIndex, type Point } from "../lib/spatial";

/*
 * D-pad / arrow-key spatial navigation.
 *
 * TV remotes only emit up/down/left/right/select, so we cannot rely on the DOM
 * tab order. On each arrow press we find the focusable element whose centre is
 * "most in that direction" from the current one — the nearest-element model used
 * by Android TV (developer.android.com/.../navigation-on-tv). The geometry
 * lives in lib/spatial.ts (pure, unit-tested).
 *
 * Focusable = anything with [data-focusable] (cards, nav items, buttons).
 * Enter/Space activate; clicking is also fine (pointer users).
 *
 * Focus scope: when an overlay marked [data-focus-scope] is open (the player),
 * navigation is confined to it — focus must never land on an element hidden
 * behind a full-screen surface.
 *
 * Focus restoration: the last focused element's [data-focus-key] is remembered
 * per route; returning to that route restores it (back from a detail page lands
 * on the card you came from). Otherwise focus goes to [data-focus-default]
 * (e.g. a page's primary CTA) or the first focusable in the main content.
 */

function activeScope(): ParentNode {
  const scopes = document.querySelectorAll<HTMLElement>("[data-focus-scope]");
  return scopes.length > 0 ? scopes[scopes.length - 1] : document;
}

function focusables(): HTMLElement[] {
  return Array.from(
    activeScope().querySelectorAll<HTMLElement>("[data-focusable]")
  ).filter((el) => el.offsetParent !== null && !el.hasAttribute("disabled"));
}

function center(el: HTMLElement): Point {
  const r = el.getBoundingClientRect();
  return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
}

/** Last focused [data-focus-key] per pathname — survives navigation, not reload. */
const focusMemory = new Map<string, string>();

export default function SpatialNav() {
  const pathname = usePathname();

  // On arrival on a route (including first mount), place focus deliberately:
  // remembered element → page default → first focusable in the content.
  useEffect(() => {
    const frame = requestAnimationFrame(() => {
      const active = document.activeElement;
      if (active instanceof HTMLElement && active.hasAttribute("data-focusable")) return;

      const remembered = focusMemory.get(pathname);
      const target =
        (remembered &&
          document.querySelector<HTMLElement>(
            `[data-focus-key="${CSS.escape(remembered)}"]`
          )) ||
        activeScope().querySelector<HTMLElement>("[data-focus-default][data-focusable]") ||
        document.querySelector<HTMLElement>("main [data-focusable]") ||
        focusables()[0];
      target?.focus();
    });
    return () => cancelAnimationFrame(frame);
  }, [pathname]);

  // Remember where focus is on this route, by stable key when one is provided.
  useEffect(() => {
    function onFocusIn(e: FocusEvent) {
      const el = e.target;
      if (el instanceof HTMLElement) {
        const key = el.getAttribute("data-focus-key");
        if (key) focusMemory.set(pathname, key);
      }
    }
    window.addEventListener("focusin", onFocusIn);
    return () => window.removeEventListener("focusin", onFocusIn);
  }, [pathname]);

  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      const dir = KEY_TO_DIR[e.key];
      if (!dir) return;

      const all = focusables();
      const active = document.activeElement as HTMLElement | null;
      const current =
        active && active.hasAttribute("data-focusable") && all.includes(active)
          ? active
          : all[0];
      if (!current) return;

      const candidates = all.filter((el) => el !== current);
      const idx = bestIndex(center(current), candidates.map(center), dir);
      if (idx >= 0) {
        e.preventDefault();
        const next = candidates[idx];
        next.focus();
        next.scrollIntoView({ behavior: "smooth", block: "nearest", inline: "center" });
      }
    }

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  return null;
}
