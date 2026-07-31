import { describe, expect, it } from "vitest";
import { accept, isAccepted, parseConsent, TERMS_VERSION } from "../app/lib/consent";

describe("parseConsent", () => {
  it("yields null from null, junk, bad JSON or wrong version", () => {
    expect(parseConsent(null)).toBeNull();
    expect(parseConsent("not json {")).toBeNull();
    expect(parseConsent(JSON.stringify({ v: 2, terms: 1, at: 0 }))).toBeNull();
    expect(parseConsent(JSON.stringify([1, 2]))).toBeNull();
    expect(parseConsent(JSON.stringify(null))).toBeNull();
    expect(parseConsent(JSON.stringify({ v: 1, terms: "1", at: 0 }))).toBeNull();
    expect(parseConsent(JSON.stringify({ v: 1, terms: Infinity, at: 0 }))).toBeNull();
    expect(parseConsent(JSON.stringify({ v: 1, terms: 1 }))).toBeNull();
  });

  it("round-trips a valid acceptance", () => {
    const c = accept(1234);
    expect(parseConsent(JSON.stringify(c))).toEqual(c);
  });
});

describe("isAccepted", () => {
  it("rejects a missing consent", () => {
    expect(isAccepted(null)).toBe(false);
  });

  it("accepts the current terms version and any newer one", () => {
    expect(isAccepted(accept(0))).toBe(true);
    expect(isAccepted({ v: 1, terms: TERMS_VERSION + 1, at: 0 })).toBe(true);
  });

  it("forces re-acceptance when the terms version is bumped", () => {
    const old = accept(0, TERMS_VERSION);
    expect(isAccepted(old, TERMS_VERSION + 1)).toBe(false);
  });
});
