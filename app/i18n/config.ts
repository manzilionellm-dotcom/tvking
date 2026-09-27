/*
 * Langues du site — les 16 langues de l'application Zuno.
 *
 * La langue est choisie AUTOMATIQUEMENT, sans que le visiteur ait rien à
 * faire : c'est celle de son navigateur / téléphone (en-tête Accept-Language).
 * Langue non prise en charge → anglais (langue la plus comprise), sauf
 * absence totale d'information → français (langue d'origine du site).
 */

export const LOCALES = [
  "fr", "en", "es", "ar", "da", "nb", "sv", "sw",
  "de", "it", "pt", "nl", "tr", "ru", "zh", "hi",
] as const;

export type Locale = (typeof LOCALES)[number];

export const DEFAULT_LOCALE: Locale = "fr";

/** Langue de repli quand le visiteur parle une langue non prise en charge. */
export const FALLBACK_LOCALE: Locale = "en";

/** Langues écrites de droite à gauche. */
export const RTL_LOCALES: ReadonlySet<Locale> = new Set<Locale>(["ar"]);

export function isLocale(value: string | undefined | null): value is Locale {
  return !!value && (LOCALES as readonly string[]).includes(value);
}

/** Variantes régionales / anciens codes → langue du site. */
const ALIASES: Record<string, Locale> = {
  no: "nb", nn: "nb", "zh-hans": "zh", "zh-hant": "zh",
};

/** Code BCP 47 (« pt-BR », « zh-Hant-TW », « nb-NO ») → langue du site, ou null. */
export function matchLocale(tag: string): Locale | null {
  const t = tag.trim().toLowerCase();
  if (!t) return null;
  if (ALIASES[t]) return ALIASES[t];
  const base = t.split(/[-_]/)[0];
  if (ALIASES[base]) return ALIASES[base];
  return isLocale(base) ? base : null;
}

/**
 * En-tête Accept-Language → langue du site. Respecte l'ordre de préférence
 * (poids q) du visiteur : « de-CH,de;q=0.9,en;q=0.8 » → « de ».
 */
export function detectLocale(acceptLanguage: string | null | undefined): Locale {
  if (!acceptLanguage) return DEFAULT_LOCALE;
  const prefs = acceptLanguage
    .split(",")
    .map((part, i) => {
      const [tag, ...params] = part.trim().split(";");
      const q = params.map((p) => p.trim()).find((p) => p.startsWith("q="));
      const weight = q ? Number(q.slice(2)) : 1;
      return { tag, weight: Number.isFinite(weight) ? weight : 0, i };
    })
    .filter((p) => p.tag && p.tag !== "*" && p.weight > 0)
    .sort((a, b) => b.weight - a.weight || a.i - b.i);
  for (const p of prefs) {
    const m = matchLocale(p.tag);
    if (m) return m;
  }
  return prefs.length ? FALLBACK_LOCALE : DEFAULT_LOCALE;
}

/**
 * Chemin interne vers une page. Sur Vercel, les liens restent « /films »
 * (la langue est ajoutée invisiblement côté serveur, cf. proxy.ts) ; sur
 * l'export statique GitHub Pages (pas de serveur), la langue doit figurer
 * dans l'adresse : « /en/films ».
 */
export function localeHref(lang: Locale, path: string): string {
  if (process.env.NEXT_PUBLIC_LOCALE_IN_PATH !== "1") return path;
  return path === "/" ? `/${lang}` : `/${lang}${path}`;
}

/** Retire un éventuel préfixe de langue (« /en/films » → « /films »). */
export function stripLocale(pathname: string): string {
  const seg = pathname.split("/")[1];
  if (!isLocale(seg)) return pathname;
  const rest = pathname.slice(seg.length + 1);
  return rest === "" ? "/" : rest;
}
