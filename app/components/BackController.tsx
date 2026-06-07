"use client";

import { useEffect } from "react";
import { usePathname, useRouter } from "next/navigation";
import { pushBackHandler } from "../lib/back";

/*
 * Gestionnaire « Retour » par défaut (priorité la plus basse). Quand rien
 * d'autre (clavier, fenêtre) n'a consommé l'appui BACK :
 *   - hors de l'accueil  -> on revient à l'accueil (jamais de sortie surprise) ;
 *   - sur l'accueil      -> on NE gère pas -> le natif quitte l'app (attendu).
 *
 * Monté une seule fois dans le layout, sous le KeyboardProvider, pour que les
 * fenêtres modales (inscrites plus tard) soient prioritaires.
 */
export default function BackController() {
  const pathname = usePathname();
  const router = useRouter();

  useEffect(() => {
    const off = pushBackHandler(() => {
      if (pathname !== "/") {
        router.push("/");
        return true;
      }
      return false;
    });
    return off;
  }, [pathname, router]);

  return null;
}
