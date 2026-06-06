"use client";

/*
 * Identité d'appareil NOVA+ — le "MAC virtuel".
 *
 * Pourquoi pas le vrai MAC matériel ? Parce qu'il est INACCESSIBLE :
 *  - depuis Android 6+ (notre cible) `WifiManager.getMacAddress()` renvoie une
 *    valeur bidon constante `02:00:00:00:00:00` (et Android 10+ randomise) ;
 *  - depuis une WebView (ce qu'est NOVA+) aucune API navigateur n'expose le
 *    matériel du tout.
 *
 * On génère donc, au tout premier lancement, un identifiant aléatoire présenté
 * AU FORMAT d'un MAC, puis on le persiste (localStorage). Côté télécommande et
 * côté panel admin c'est indistinguable d'un "vrai" MAC : c'est le code que tu
 * actives à distance. C'est exactement la stratégie de l'app Flutter 7 MOTION.
 *
 * Préfixe `MK:` (et non `NV:`) à dessein : le Worker Cloudflare existant
 * n'accepte que ce format (`/^MK(?::[0-9A-F]{2}){5}$/i`). NOVA+ se branche ainsi
 * sur le backend déployé SANS aucune modification serveur.
 */

const K_MAC = "nova:deviceMac";
const MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/i;

/** Tire un MAC virtuel aléatoire `MK:XX:XX:XX:XX:XX` (5 octets, ~10^12). */
function randomMac(): string {
  const bytes = new Uint8Array(5);
  crypto.getRandomValues(bytes);
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0").toUpperCase());
  return `MK:${hex.join(":")}`;
}

/** MAC virtuel stable de cet appareil (créé et persisté au 1er appel). */
export function getDeviceMac(): string {
  if (typeof window === "undefined") return "";
  let mac = window.localStorage.getItem(K_MAC);
  if (!mac || !MAC_RX.test(mac)) {
    mac = randomMac();
    window.localStorage.setItem(K_MAC, mac);
  }
  return mac;
}

/**
 * Régénère un nouveau MAC virtuel (Réglages → Mon appareil). À utiliser si le
 * code a fuité : l'ancien devient inactif et il faudra réactiver le nouveau.
 */
export function regenerateDeviceMac(): string {
  const mac = randomMac();
  if (typeof window !== "undefined") window.localStorage.setItem(K_MAC, mac);
  return mac;
}
