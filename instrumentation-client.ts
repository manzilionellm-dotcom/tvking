/*
 * Exécuté avant que l'application ne devienne interactive (convention Next
 * instrumentation-client) — c'est ici que les polyfills pour les WebView
 * anciens des box TV doivent se charger, avant tout code applicatif.
 */
import "./app/lib/polyfills";

/*
 * Service worker anti-écran-blanc : au redémarrage d'un box au réseau lent ou
 * coupé, l'app se sert du cache au lieu d'un WebView vide. Enregistré après
 * `load` pour ne rien coûter au démarrage ; toute erreur est silencieuse
 * (vieux WebView sans SW, contexte non sécurisé…).
 */
try {
  if (typeof window !== "undefined" && "serviceWorker" in navigator) {
    window.addEventListener("load", () => {
      const base = process.env.NEXT_PUBLIC_BASE_PATH || "";
      navigator.serviceWorker.register(`${base}/sw.js`).catch(() => {});
    });
  }
} catch {
  // Jamais bloquant : le SW est un plus, pas une condition de démarrage.
}
