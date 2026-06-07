"use client";

/*
 * Pile de gestionnaires « Retour » (touche BACK de la télécommande).
 *
 * Le wrapper natif (MainActivity) appelle `window.__novaBack()` à chaque appui
 * sur BACK AVANT de reculer dans l'historique ou de quitter l'app. On exécute
 * les gestionnaires du plus récent au plus ancien : le premier qui renvoie
 * `true` consomme l'appui (ex. fermer le clavier à l'écran, fermer une fenêtre,
 * revenir à l'accueil). Si aucun ne gère, le natif recule/quitte.
 *
 * C'est ce qui évite que BACK « sorte de l'app » par surprise : tant qu'il
 * reste quelque chose à fermer ou un écran où revenir, on reste dans l'app.
 */

type BackHandler = () => boolean;

const stack: BackHandler[] = [];

/** Enregistre un gestionnaire (priorité au dernier inscrit). Renvoie le retrait. */
export function pushBackHandler(handler: BackHandler): () => void {
  stack.push(handler);
  return () => {
    const i = stack.lastIndexOf(handler);
    if (i >= 0) stack.splice(i, 1);
  };
}

/** Exécute les gestionnaires (récent → ancien). `true` = appui consommé. */
export function handleBack(): boolean {
  for (let i = stack.length - 1; i >= 0; i--) {
    try {
      if (stack[i]()) return true;
    } catch {
      /* un gestionnaire défaillant ne doit pas bloquer le Retour */
    }
  }
  return false;
}

// Exposé au natif. Toujours défini côté client, même sans gestionnaire inscrit.
if (typeof window !== "undefined") {
  (window as unknown as { __novaBack: () => boolean }).__novaBack = handleBack;
}
