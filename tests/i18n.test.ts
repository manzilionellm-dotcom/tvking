import { describe, expect, it } from "vitest";
import { LOCALES, detectLocale, localeHref, matchLocale, stripLocale } from "../app/i18n/config";
import { fmt, getMessages } from "../app/i18n/messages";

/* Chemins de toutes les feuilles d'un dictionnaire (« a.b.c » / « a.b[0] »). */
function leaves(o: unknown, prefix = ""): Map<string, unknown> {
  const out = new Map<string, unknown>();
  if (Array.isArray(o)) {
    o.forEach((v, i) => leaves(v, `${prefix}[${i}]`).forEach((x, k) => out.set(k, x)));
  } else if (o && typeof o === "object") {
    for (const [k, v] of Object.entries(o)) {
      leaves(v, prefix ? `${prefix}.${k}` : k).forEach((x, kk) => out.set(kk, x));
    }
  } else {
    out.set(prefix, o);
  }
  return out;
}

const placeholders = (s: unknown) =>
  typeof s === "string" ? [...s.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort() : [];

describe("dictionnaires : les 16 langues ont exactement les textes du français", () => {
  const fr = leaves(getMessages("fr"));
  for (const lang of LOCALES) {
    it(lang, () => {
      const other = leaves(getMessages(lang));
      expect([...other.keys()].sort()).toEqual([...fr.keys()].sort());
      for (const [k, v] of fr) {
        const t = other.get(k);
        expect(typeof t, `${lang}: ${k}`).toBe(typeof v);
        if (typeof t === "string") expect(t.trim().length, `${lang}: ${k} vide`).toBeGreaterThan(0);
        expect(placeholders(t), `${lang}: ${k}`).toEqual(placeholders(v));
      }
    });
  }
});

describe("détection automatique de la langue", () => {
  it("suit l'ordre de préférence du navigateur", () => {
    expect(detectLocale("de-CH,de;q=0.9,en;q=0.8")).toBe("de");
    expect(detectLocale("ja-JP,en;q=0.5")).toBe("en");
    expect(detectLocale("ja-JP")).toBe("en"); // langue inconnue → anglais
    expect(detectLocale("")).toBe("fr"); // aucune info → français
    expect(detectLocale(null)).toBe("fr");
    expect(detectLocale("en;q=0.2,ar;q=0.9")).toBe("ar");
  });
  it("variantes régionales", () => {
    expect(matchLocale("pt-BR")).toBe("pt");
    expect(matchLocale("zh-Hant-TW")).toBe("zh");
    expect(matchLocale("no")).toBe("nb");
    expect(matchLocale("nn-NO")).toBe("nb");
    expect(matchLocale("xx")).toBeNull();
  });
  it("chemins", () => {
    expect(stripLocale("/en/films")).toBe("/films");
    expect(stripLocale("/en")).toBe("/");
    expect(stripLocale("/films")).toBe("/films");
    expect(localeHref("de", "/films")).toBe("/films"); // Vercel : adresse inchangée
    expect(fmt("{n} leçons", { n: 3 })).toBe("3 leçons");
  });
});
