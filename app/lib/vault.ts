/*
 * Coffre aveugle (serveur) — logique pure, testable en node.
 *
 * MINIMISATION DES DONNÉES, appliquée par construction :
 *  - Un enregistrement = { iv, ct } et RIEN d'autre. Pas d'horodatage, pas
 *    d'IP, pas de user-agent, pas de taille variable (l'enveloppe est rejetée
 *    si le chiffré n'a pas EXACTEMENT la taille fixe attendue).
 *  - Les clés du coffre sont des slot IDs aveuglés (HMAC côté client) : le
 *    serveur ne peut ni les relier à un contenu, ni les énumérer utilement.
 *  - L'éviction est FIFO sur l'ordre d'insertion — précisément parce qu'on
 *    refuse de stocker des horodatages (un LRU daté serait une métadonnée).
 *  - Toute lecture agrégée passe par `presenceOf` : il est IMPOSSIBLE de
 *    sortir un compte de ce module, seulement présent/absent.
 */

import { type Envelope, type Presence, isSlotId, parseEnvelope, presenceOf } from "./zk";

/** Plafond de slots — borne la mémoire, jamais exposé en tant que nombre. */
export const MAX_SLOTS = 512;

export interface Vault {
  /** slotId aveuglé → enveloppe opaque. L'ordre d'insertion sert d'ordre FIFO. */
  slots: Map<string, Envelope>;
}

export function emptyVault(): Vault {
  return { slots: new Map() };
}

export type PutResult = "stored" | "rejected";

/**
 * Dépose une enveloppe dans un slot. Rejette tout ce qui n'est pas
 * strictement conforme (slot non aveuglé, enveloppe malformée ou de taille
 * inattendue). Un dépôt réécrit son slot en fin de file (FIFO rafraîchi) ;
 * au-delà de MAX_SLOTS, le plus ancien est évincé.
 */
export function putSlot(vault: Vault, slotId: unknown, rawEnvelope: unknown): PutResult {
  if (!isSlotId(slotId)) return "rejected";
  const env = parseEnvelope(rawEnvelope);
  if (!env) return "rejected";
  vault.slots.delete(slotId);
  vault.slots.set(slotId, env);
  while (vault.slots.size > MAX_SLOTS) {
    const oldest = vault.slots.keys().next().value;
    if (oldest === undefined) break;
    vault.slots.delete(oldest);
  }
  return "stored";
}

/** L'enveloppe d'un slot, ou null. Seul l'appareil détenteur de la clé peut la lire. */
export function getSlot(vault: Vault, slotId: unknown): Envelope | null {
  if (!isSlotId(slotId)) return null;
  return vault.slots.get(slotId) ?? null;
}

/** Droit à l'effacement : supprime le slot s'il existe. */
export function deleteSlot(vault: Vault, slotId: unknown): void {
  if (!isSlotId(slotId)) return;
  vault.slots.delete(slotId);
}

/* --------------------- vue panel : binaire uniquement ---------------------- */

/** État global du coffre — au moins un dépôt existe, oui ou non. Jamais un compte. */
export function vaultPresence(vault: Vault): Presence {
  return presenceOf(vault.slots);
}

/** État d'un slot précis — présent/absent, rien d'autre. */
export function slotPresence(vault: Vault, slotId: unknown): Presence {
  return presenceOf(isSlotId(slotId) && vault.slots.has(slotId));
}
