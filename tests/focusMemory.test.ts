import { describe, it, expect } from "vitest";
import { keyOf, createFocusMemory, type Keyable } from "../app/lib/focusMemory";

/** Minimal stub for an element with attributes + tag name. */
function el(tag: string, attrs: Record<string, string> = {}): Keyable {
  return {
    tagName: tag,
    getAttribute: (n: string) => (n in attrs ? attrs[n] : null),
  };
}

describe("keyOf", () => {
  it("prefers an explicit data-focus-key", () => {
    expect(keyOf(el("A", { "data-focus-key": "card:42", href: "/x" }))).toBe("card:42");
  });
  it("falls back to an anchor href", () => {
    expect(keyOf(el("A", { href: "/title/c1" }))).toBe("href:/title/c1");
  });
  it("returns null for a plain button with no key", () => {
    expect(keyOf(el("BUTTON"))).toBeNull();
  });
  it("returns null for null/undefined", () => {
    expect(keyOf(null)).toBeNull();
    expect(keyOf(undefined)).toBeNull();
  });
});

describe("createFocusMemory", () => {
  it("remembers and recalls a key per path", () => {
    const m = createFocusMemory();
    m.remember("/", "href:/title/c1");
    expect(m.recall("/")).toBe("href:/title/c1");
    expect(m.recall("/sport")).toBeNull();
  });

  it("ignores a null key (no positional overwrite)", () => {
    const m = createFocusMemory();
    m.remember("/", "href:/a");
    m.remember("/", null); // e.g. focus moved to a keyless button
    expect(m.recall("/")).toBe("href:/a");
  });

  it("overwrites with the most recent key for a path", () => {
    const m = createFocusMemory();
    m.remember("/sport", "href:/title/sl1");
    m.remember("/sport", "href:/title/sl2");
    expect(m.recall("/sport")).toBe("href:/title/sl2");
  });
});
