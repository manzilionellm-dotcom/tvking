"use client";

/*
 * Identité d'appareil NOVA+ — le "MAC virtuel" (code d'activation).
 *
 * Le vrai MAC matériel est INACCESSIBLE (Android 6+ renvoie un MAC bidon ; une
 * WebView n'a aucun accès au matériel). On présente donc un identifiant AU
 * FORMAT d'un MAC `MK:XX:XX:XX:XX:XX` — le code que tu actives à distance.
 *
 * STABILITÉ (crucial pour ne pas faire "racheter" le client) :
 *  1. Si le wrapper Android fournit un identifiant matériel stable via le pont
 *     `window.NovaNative.getDeviceId()` (= ANDROID_ID, constant pour un appareil
 *     + clé de signature), on en DÉRIVE le MAC de façon déterministe. Résultat :
 *     le même appareil garde TOUJOURS le même code, même après une
 *     désinstallation/réinstallation (localStorage est pourtant effacé).
 *  2. Sinon (navigateur/dev, pas de pont natif), on génère un MAC aléatoire
 *     persisté en localStorage.
 *
 * Préfixe `MK:` exigé par le Worker Cloudflare existant (aucune modif serveur).
 */

const K_MAC = "nova:deviceMac";
const MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/i;

/** Octets → `MK:XX:XX:XX:XX:XX` (hex majuscule). */
function formatMac(bytes: number[]): string {
  const hex = bytes.map((b) => (b & 0xff).toString(16).padStart(2, "0").toUpperCase());
  return `MK:${hex.join(":")}`;
}

/** MAC aléatoire (5 octets) — repli navigateur/dev. */
function randomMac(): string {
  const bytes = new Uint8Array(5);
  crypto.getRandomValues(bytes);
  return formatMac(Array.from(bytes));
}

/**
 * Dérive un MAC DÉTERMINISTE à partir d'une graine (l'identifiant matériel).
 * Deux hachages 32 bits indépendants → 5 octets bien répartis. Même graine →
 * même MAC, à chaque fois, sur n'importe quelle réinstallation.
 */
function macFromSeed(seed: string): string {
  let h1 = 0x811c9dc5;
  let h2 = 0x1000193;
  for (let i = 0; i < seed.length; i++) {
    const c = seed.charCodeAt(i);
    h1 = Math.imul(h1 ^ c, 0x01000193);
    h2 = Math.imul(h2 ^ c, 0x85ebca77);
  }
  h1 >>>= 0;
  h2 >>>= 0;
  return formatMac([(h1 >>> 24) & 0xff, (h1 >>> 16) & 0xff, (h1 >>> 8) & 0xff, h1 & 0xff, (h2 >>> 24) & 0xff]);
}

/** Identifiant matériel stable fourni par le wrapper natif, sinon "". */
function readNativeId(): string {
  try {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const n = (window as any).NovaNative;
    if (n && typeof n.getDeviceId === "function") {
      const id = n.getDeviceId();
      if (typeof id === "string" && id.length >= 8) return id;
    }
  } catch {
    /* pas de pont natif (navigateur) */
  }
  return "";
}

/** Vrai si l'identité est ancrée au matériel (donc stable après réinstall). */
export function hasNativeDeviceId(): boolean {
  return typeof window !== "undefined" && readNativeId() !== "";
}

/** MAC virtuel stable de cet appareil (= code d'activation). */
export function getDeviceMac(): string {
  if (typeof window === "undefined") return "";

  // 1) Identité ancrée au matériel (survit à la désinstallation).
  const native = readNativeId();
  if (native) {
    const mac = macFromSeed(native);
    window.localStorage.setItem(K_MAC, mac); // cache (info/diagnostic)
    return mac;
  }

  // 2) Repli navigateur/dev : MAC aléatoire persisté.
  let mac = window.localStorage.getItem(K_MAC);
  if (!mac || !MAC_RX.test(mac)) {
    mac = randomMac();
    window.localStorage.setItem(K_MAC, mac);
  }
  return mac;
}

/**
 * Régénère un MAC (repli navigateur uniquement). Sur un appareil avec identité
 * matérielle, le code est volontairement FIXE : on re-dérive le même.
 */
export function regenerateDeviceMac(): string {
  if (hasNativeDeviceId()) return getDeviceMac();
  const mac = randomMac();
  if (typeof window !== "undefined") window.localStorage.setItem(K_MAC, mac);
  return mac;
}
