/* Aide côté serveur : langue de la page + ses textes, depuis les params. */
import { DEFAULT_LOCALE, isLocale, type Locale } from "./config";
import { getMessages, type Messages } from "./messages";

export async function pageI18n(
  params: Promise<{ lang: string }>,
): Promise<{ lang: Locale; m: Messages }> {
  const { lang } = await params;
  const l: Locale = isLocale(lang) ? lang : DEFAULT_LOCALE;
  return { lang: l, m: getMessages(l) };
}
