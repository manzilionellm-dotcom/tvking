"use client";

import { useEffect, useRef } from "react";
import { usePathname, useRouter } from "next/navigation";
import { bestCandidateIndex, KEY_TO_DIR, type Box } from "../lib/spatial";
import { focusMemory, keyOf } from "../lib/focusMemory";

/*
 * D-pad / arrow-key spatial navigation for the 10-foot UI.
 *
 * TV remotes only emit up/down/left/right/select (+ BACK + media keys), so we
 * cannot rely on the DOM tab order. On each arrow we pick the focusable whose
 * geometry is "most in that direction" — the nearest-element model of Android
 * TV. The scoring lives in ../lib/spatial (pure + unit-tested).
 *
 * This component is mounted once in the root layout, so it survives client
 * navigations. That lets it own two TV essentials the app was missing:
 *   - BACK (Escape / TV Back) → consistent within-app back, never a dead end;
 *   - focus restoration → returning to a screen restores the element you left
 *     from (../lib/focusMemory), instead of dumping focus at the top-left.
 *
 * Focusable = anything with [data-focusable] (cards, nav items, buttons).
 */

function focusables(): HTMLElement[] {
  return Array.from(
    document.querySelectorAll<HTMLElement>("[data-focusable]"),
  ).filter((el) => el.offsetParent !== null && !el.hasAttribute("disabled"));
}

export default function SpatialNav() {
  const pathname = usePathname();
  const router = useRouter();

  // Mirror the current path into a ref so the long-lived listeners below (which
  // are attached once) always read the latest value.
  const pathRef = useRef(pathname);
  useEffect(() => {
    pathRef.current = pathname;
  }, [pathname]);

  // Arrow navigation + BACK — attached once for the app's lifetime.
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      // BACK (Escape or the TV Back button surfaced as Escape/GoBack): step
      // back within the app; at the root we let the platform handle exit.
      if (e.key === "Escape" || e.key === "GoBack" || e.key === "BrowserBack") {
        if (pathRef.current !== "/") {
          e.preventDefault();
          router.back();
        }
        return;
      }

      const dir = KEY_TO_DIR[e.key];
      if (!dir) return;

      const els = focusables();
      if (!els.length) return;

      const active = document.activeElement as HTMLElement | null;
      const curIdx =
        active && active.hasAttribute("data-focusable") ? els.indexOf(active) : -1;
      const from = curIdx >= 0 ? els[curIdx] : els[0];

      const boxes: Box[] = els.map((el) => el.getBoundingClientRect());
      const idx = bestCandidateIndex(from.getBoundingClientRect(), boxes, dir, curIdx);
      if (idx >= 0) {
        e.preventDefault();
        const next = els[idx];
        next.focus();
        next.scrollIntoView({ behavior: "smooth", block: "nearest", inline: "center" });
      }
    }

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [router]);

  // Remember the last focused element per path, so BACK can restore it.
  useEffect(() => {
    function onFocusIn(e: FocusEvent) {
      const t = e.target as HTMLElement | null;
      if (t && t.hasAttribute("data-focusable")) {
        focusMemory.remember(pathRef.current, keyOf(t));
      }
    }
    document.addEventListener("focusin", onFocusIn);
    return () => document.removeEventListener("focusin", onFocusIn);
  }, []);

  // On every navigation, put focus somewhere visible: the remembered element if
  // we have one for this path, otherwise the first focusable.
  useEffect(() => {
    const raf = requestAnimationFrame(() => {
      const els = focusables();
      if (!els.length) return;
      const key = focusMemory.recall(pathname);
      const target = (key && els.find((el) => keyOf(el) === key)) || els[0];
      target.focus();
      target.scrollIntoView({ block: "nearest", inline: "center" });
    });
    return () => cancelAnimationFrame(raf);
  }, [pathname]);

  return null;
}
