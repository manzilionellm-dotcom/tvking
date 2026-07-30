/*
 * Côté appareil : sauvegarde/restauration Zero-Knowledge de la reprise de
 * lecture (« Reprendre »).
 *
 * Le secret d'appareil est généré localement (CSPRNG) et persisté UNIQUEMENT
 * dans le localStorage de la box — il n'est jamais transmis. Tout ce qui part
 * sur le réseau est une enveloppe AES-GCM de taille fixe sous un slot ID
 * aveuglé : le serveur (et son panel) ne peuvent connaître ni le contenu, ni
 * le nombre d'entrées, ni même le fait qu'il s'agit d'une reprise de lecture.
 */

import { RESUME_KEY, parseStore, saveResume } from "./resume";
import { type ZkKeys, blindSlotId, deriveKeys, fromBase64, open, seal, toBase64 } from "./zk";

export const ZK_SECRET_KEY = "tvking.v1.zk.secret";
const SECRET_BYTES = 32;

/** Étiquette aveuglée côté client — le serveur n'en voit que le HMAC. */
const RESUME_LABEL = "resume/v1";

export type BackupResult = "ok" | "trop-gros" | "erreur";
export type RestoreResult = "ok" | "absent" | "erreur";

const te = new TextEncoder();
const td = new TextDecoder();

/** Secret d'appareil : créé au premier usage, jamais envoyé. Null hors navigateur. */
export function getOrCreateDeviceSecret(): Uint8Array | null {
  if (typeof window === "undefined") return null;
  try {
    const existing = window.localStorage.getItem(ZK_SECRET_KEY);
    if (existing) {
      const bytes = fromBase64(existing);
      if (bytes && bytes.length === SECRET_BYTES) return bytes;
    }
    const fresh = crypto.getRandomValues(new Uint8Array(SECRET_BYTES));
    window.localStorage.setItem(ZK_SECRET_KEY, toBase64(fresh));
    return fresh;
  } catch {
    return null;
  }
}

let cachedKeys: Promise<ZkKeys> | null = null;

function deviceKeys(): Promise<ZkKeys> | null {
  if (!cachedKeys) {
    const secret = getOrCreateDeviceSecret();
    if (!secret) return null;
    cachedKeys = deriveKeys(secret);
  }
  return cachedKeys;
}

/** Le slot ID aveuglé de cet appareil (affichable : il ne révèle que la présence). */
export async function resumeSlotId(): Promise<string | null> {
  const keys = await deviceKeys();
  if (!keys) return null;
  return blindSlotId(keys, RESUME_LABEL);
}

/** Chiffre l'état « Reprendre » local et le dépose dans le coffre aveugle. */
export async function backupResume(): Promise<BackupResult> {
  try {
    const keys = await deviceKeys();
    if (!keys) return "erreur";
    // On sérialise le store VALIDÉ (jamais le brut du localStorage) pour ne
    // pas embarquer d'octets inattendus dans la sauvegarde.
    const store = parseStore(window.localStorage.getItem(RESUME_KEY));
    const envelope = await seal(keys, te.encode(JSON.stringify(store)));
    if (!envelope) return "trop-gros";
    const slot = await blindSlotId(keys, RESUME_LABEL);
    const res = await fetch(`/api/vault/${slot}`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(envelope),
    });
    return res.ok ? "ok" : "erreur";
  } catch {
    return "erreur";
  }
}

/** Récupère la sauvegarde, la déchiffre localement et remplace l'état « Reprendre ». */
export async function restoreResume(): Promise<RestoreResult> {
  try {
    const keys = await deviceKeys();
    if (!keys) return "erreur";
    const slot = await blindSlotId(keys, RESUME_LABEL);
    const res = await fetch(`/api/vault/${slot}`);
    if (res.status === 404) return "absent";
    if (!res.ok) return "erreur";
    const payload = await open(keys, await res.json());
    if (!payload) return "erreur";
    // parseStore re-valide tout : une sauvegarde corrompue donne un store sain.
    saveResume(parseStore(td.decode(payload)));
    return "ok";
  } catch {
    return "erreur";
  }
}

/** Droit à l'effacement : supprime la sauvegarde distante (le local reste). */
export async function eraseBackup(): Promise<BackupResult> {
  try {
    const keys = await deviceKeys();
    if (!keys) return "erreur";
    const slot = await blindSlotId(keys, RESUME_LABEL);
    const res = await fetch(`/api/vault/${slot}`, { method: "DELETE" });
    return res.ok ? "ok" : "erreur";
  } catch {
    return "erreur";
  }
}
