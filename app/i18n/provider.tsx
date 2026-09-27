"use client";

/*
 * Fournit la langue et ses textes aux composants client (lecteur, menu,
 * conditions…). Le layout de chaque langue le monte une seule fois.
 */
import { createContext, useContext } from "react";
import { localeHref, type Locale } from "./config";
import { fmt, type Messages } from "./messages";

type I18n = {
  lang: Locale;
  m: Messages;
  fmt: typeof fmt;
  /** Lien interne dans la langue courante (cf. localeHref). */
  href: (path: string) => string;
};

const Ctx = createContext<I18n | null>(null);

export function I18nProvider({
  lang,
  messages,
  children,
}: {
  lang: Locale;
  messages: Messages;
  children: React.ReactNode;
}) {
  const value: I18n = { lang, m: messages, fmt, href: (p) => localeHref(lang, p) };
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useI18n(): I18n {
  const v = useContext(Ctx);
  if (!v) throw new Error("useI18n() hors de <I18nProvider>");
  return v;
}
