/*
 * Dictionnaires des 16 langues. fr.json est la SOURCE (textes d'origine) ;
 * les autres en sont la traduction exacte, clé pour clé (vérifié par
 * tests/i18n.test.ts). Chargés au build : chaque page est pré-rendue dans
 * chaque langue, aucun texte n'est téléchargé à part.
 */
import type { Locale } from "./config";
import fr from "./dictionaries/fr.json";
import en from "./dictionaries/en.json";
import es from "./dictionaries/es.json";
import ar from "./dictionaries/ar.json";
import da from "./dictionaries/da.json";
import nb from "./dictionaries/nb.json";
import sv from "./dictionaries/sv.json";
import sw from "./dictionaries/sw.json";
import de from "./dictionaries/de.json";
import it from "./dictionaries/it.json";
import pt from "./dictionaries/pt.json";
import nl from "./dictionaries/nl.json";
import tr from "./dictionaries/tr.json";
import ru from "./dictionaries/ru.json";
import zh from "./dictionaries/zh.json";
import hi from "./dictionaries/hi.json";

export type Messages = typeof fr;

const ALL: Record<Locale, Messages> = {
  fr, en, es, ar, da, nb, sv, sw, de, it, pt, nl, tr, ru, zh, hi,
} as Record<Locale, Messages>;

export function getMessages(lang: Locale): Messages {
  return ALL[lang] ?? fr;
}

/** « {n} leçons » + { n: 12 } → « 12 leçons ». Variable absente → laissée telle quelle. */
export function fmt(template: string, vars: Record<string, string | number> = {}): string {
  return template.replace(/\{(\w+)\}/g, (all, k: string) =>
    k in vars ? String(vars[k]) : all,
  );
}
