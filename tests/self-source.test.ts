import { describe, expect, it } from "vitest";
import { buildBody, itemsOf, normalizeMac, outcomeOf } from "../app/lib/self-source";

describe("normalizeMac", () => {
  it("accepte le format affiché par Zuno et les saisies approximatives", () => {
    expect(normalizeMac("MK:80:78:60:07:4F")).toBe("MK:80:78:60:07:4F");
    expect(normalizeMac(" mk:80:78:60:07:4f ")).toBe("MK:80:78:60:07:4F");
    expect(normalizeMac("807860074F")).toBe("MK:80:78:60:07:4F");
    expect(normalizeMac("MK-80-78-60-07-4F")).toBe("MK:80:78:60:07:4F");
  });
  it("refuse le reste", () => {
    expect(normalizeMac("")).toBeNull();
    expect(normalizeMac("MK:80:78:60:07")).toBeNull();
    expect(normalizeMac("hello")).toBeNull();
  });
});

describe("buildBody", () => {
  it("Xtream : champs complets, slash final retiré", () => {
    expect(buildBody({ type: "xtream", label: "A", server: "http://s.tv:8080/", username: "u", password: "p" }))
      .toEqual({ type: "xtream", label: "A", server_url: "http://s.tv:8080", username: "u", password: "p" });
  });
  it("refuse un champ manquant ou une adresse sans http", () => {
    expect(buildBody({ type: "xtream", label: "", server: "s.tv", username: "u", password: "p" })).toBeNull();
    expect(buildBody({ type: "xtream", label: "", server: "http://s.tv", username: "", password: "p" })).toBeNull();
    expect(buildBody({ type: "m3u", label: "", url: "ftp://x" })).toBeNull();
  });
});

describe("outcomeOf / itemsOf", () => {
  it("lit les réponses réelles du panel", () => {
    expect(outcomeOf(200, { ok: true })).toBe("ok");
    expect(outcomeOf(200, { ok: false, error: "not_entitled", blocked: "no_license" })).toBe("notEntitled");
    expect(outcomeOf(409, { ok: false, reason: "too_many" })).toBe("tooMany");
    expect(outcomeOf(400, { error: "invalid mac" })).toBe("mac");
    expect(outcomeOf(400, { error: "m3u requires m3u_url" })).toBe("fields");
    expect(outcomeOf(500, {})).toBe("generic");
  });
  it("liste : items verrouillés (panel) et propres (self)", () => {
    const items = itemsOf({ items: [
      { id: "panel-0", origin: "panel", locked: true, type: "xtream", label: "Abo", server_url: "http://s", username: "u" },
      { id: "x1", origin: "self", locked: false, type: "m3u", label: "Ma liste", m3u_url: "http://m" },
    ] });
    expect(items.map((i) => [i.id, i.locked, i.type])).toEqual([["panel-0", true, "xtream"], ["x1", false, "m3u"]]);
    expect(itemsOf({ ok: false, playlists: [] })).toEqual([]);
  });
});
