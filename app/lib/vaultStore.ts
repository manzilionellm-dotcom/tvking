/*
 * Instance serveur du coffre aveugle.
 *
 * Stockage en mémoire du processus (démo / mono-instance), accroché à
 * globalThis pour survivre au rechargement HMR de `next dev`. Pour la
 * production Cloudflare (Worker `seven-motion-backend`), remplacer par un KV :
 * l'interface reste `putSlot/getSlot/deleteSlot` sur des enveloppes opaques —
 * le KV ne verrait exactement que ce que voit cette Map : des blobs chiffrés
 * de taille fixe sous des clés aveuglées.
 */

import { type Vault, emptyVault } from "./vault";

const g = globalThis as typeof globalThis & { __tvkingVault?: Vault };

export function serverVault(): Vault {
  if (!g.__tvkingVault) g.__tvkingVault = emptyVault();
  return g.__tvkingVault;
}
