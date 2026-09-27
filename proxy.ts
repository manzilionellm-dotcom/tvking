/*
 * Langue AUTOMATIQUE et INVISIBLE (Vercel).
 *
 * Chaque page existe dans les 16 langues (app/[lang]/…). Quand un visiteur
 * demande « /films », on lit la langue de son navigateur (Accept-Language)
 * et on sert en interne « /de/films » — l'adresse affichée reste « /films » :
 * le visiteur n'a rien à choisir, rien ne change pour lui.
 *
 * Absent de l'export statique GitHub Pages (pas de serveur) : le workflow
 * deploy-pages.yml retire ce fichier avant le build.
 */
import { NextResponse, type NextRequest } from "next/server";
import { detectLocale, isLocale } from "./app/i18n/config";

export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;
  // Déjà une langue dans l'adresse (lien direct /en/…) : on laisse passer.
  if (isLocale(pathname.split("/")[1])) return NextResponse.next();

  const lang = detectLocale(request.headers.get("accept-language"));
  const url = request.nextUrl.clone();
  url.pathname = pathname === "/" ? `/${lang}` : `/${lang}${pathname}`;
  const res = NextResponse.rewrite(url);
  // Caches intermédiaires : la réponse dépend de la langue du visiteur.
  res.headers.set("Vary", "Accept-Language");
  return res;
}

export const config = {
  // Tout sauf les fichiers internes Next et les fichiers « à extension »
  // (icônes, manifeste, robots.txt, sitemap.xml, images…).
  matcher: ["/((?!_next/|api/|.*\\.[a-zA-Z0-9]+$).*)"],
};
