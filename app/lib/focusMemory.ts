/*
 * Per-route focus memory (S7 — "restauration du focus au retour d'un écran").
 *
 * On a TV, losing your place is a real cost: browse deep into a row, open a
 * title, press BACK — you should land back on the card you came from, not at
 * the top-left. SpatialNav is mounted once in the root layout, so it survives
 * client navigations; it records the focused element's stable key for the
 * current path and, when the path changes, restores the remembered element.
 *
 * The key derivation and the store are kept pure here so they can be unit
 * tested without a browser.
 */

/** The subset of an element we need to derive a stable focus key. */
export interface Keyable {
  getAttribute(name: string): string | null;
  tagName: string;
}

/**
 * A stable identifier for a focusable, resilient across re-renders:
 *   1. explicit `data-focus-key` (author-controlled), else
 *   2. an anchor's href (cards/nav link to a stable route), else
 *   3. null (caller falls back to positional focus).
 */
export function keyOf(el: Keyable | null | undefined): string | null {
  if (!el) return null;
  const explicit = el.getAttribute("data-focus-key");
  if (explicit) return explicit;
  if (el.tagName === "A") {
    const href = el.getAttribute("href");
    if (href) return `href:${href}`;
  }
  return null;
}

export interface FocusMemory {
  remember(path: string, key: string | null): void;
  recall(path: string): string | null;
}

/** A focus store backed by a Map (injectable for tests). */
export function createFocusMemory(
  store: Map<string, string> = new Map(),
): FocusMemory {
  return {
    remember(path, key) {
      if (key) store.set(path, key);
    },
    recall(path) {
      return store.get(path) ?? null;
    },
  };
}

/** Process-wide singleton used by SpatialNav. */
export const focusMemory = createFocusMemory();
