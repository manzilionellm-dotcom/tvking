/*
 * Zero-Knowledge core — chiffrement côté client, serveur aveugle.
 *
 * Propriétés garanties par construction :
 *  - CONFIDENTIALITÉ : AES-256-GCM ; la clé est dérivée (HKDF) d'un secret qui
 *    ne quitte JAMAIS l'appareil. Le serveur ne voit que du chiffré.
 *  - AUCUNE MÉTADONNÉE : l'identifiant de stockage (« slot ») est un HMAC
 *    aveuglé — le serveur ne peut ni le relier à un contenu, ni à un compte.
 *  - AUCUNE FUITE DE QUANTITÉ : tout payload est rembourré à une taille FIXE
 *    (BUCKET_BYTES) avant chiffrement ; 1 entrée ou 100 entrées produisent
 *    exactement le même nombre d'octets sur le réseau et au repos.
 *  - MASQUAGE : toute grandeur exposée à un panel est réduite à un état
 *    binaire présence/absence (`Presence`), jamais un compte.
 *
 * Tout est pur ou basé sur WebCrypto (`globalThis.crypto`), donc identique en
 * navigateur et en node (tests vitest).
 */

export const ZK_VERSION = 1 as const;

/** Taille fixe du bloc clair rembourré — UNE seule taille pour tous. */
export const BUCKET_BYTES = 16384;

/** Octets réservés au préfixe de longueur dans le bloc rembourré. */
export const LENGTH_PREFIX_BYTES = 4;

/** Charge utile maximale (le préfixe de longueur occupe le reste). */
export const MAX_PAYLOAD_BYTES = BUCKET_BYTES - LENGTH_PREFIX_BYTES;

export const IV_BYTES = 12;
export const GCM_TAG_BYTES = 16;

/** Longueur EXACTE du chiffré : bloc fixe + tag GCM. Toute autre → rejet. */
export const CIPHERTEXT_BYTES = BUCKET_BYTES + GCM_TAG_BYTES;

/** Slot ID = HMAC-SHA-256 hex → exactement 64 caractères hexadécimaux. */
export const SLOT_ID_PATTERN = /^[0-9a-f]{64}$/;

/** Sel HKDF public et fixe (la sécurité repose sur le secret, pas sur le sel). */
const HKDF_SALT = "tvking/zk/v1";
const INFO_ENC = "tvking/zk/enc/v1";
const INFO_SID = "tvking/zk/sid/v1";

/* ------------------------------ enveloppe ---------------------------------- */

/**
 * La SEULE forme que le serveur accepte : version, IV et chiffré opaque de
 * taille exacte. Pas de nom, pas d'horodatage, pas de type de contenu.
 */
export interface Envelope {
  v: typeof ZK_VERSION;
  iv: string; // base64, IV_BYTES octets
  ct: string; // base64, CIPHERTEXT_BYTES octets
}

/* ------------------------- présence (data masking) ------------------------- */

/** L'unique granularité autorisée à sortir vers un panel. */
export type Presence = "present" | "absent";

/**
 * Réduit n'importe quelle grandeur (compte, taille, collection…) à un état
 * binaire. C'est le SEUL chemin par lequel une quantité peut être exposée.
 */
export function presenceOf(value: number | boolean | { size: number } | { length: number } | null | undefined): Presence {
  if (value === null || value === undefined) return "absent";
  if (typeof value === "boolean") return value ? "present" : "absent";
  if (typeof value === "number") return value > 0 ? "present" : "absent";
  if ("size" in value) return value.size > 0 ? "present" : "absent";
  return value.length > 0 ? "present" : "absent";
}

/* ------------------------------ base64 / hex ------------------------------- */

export function toBase64(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

/** Décodage strict : null sur toute entrée non base64. */
export function fromBase64(s: string): Uint8Array | null {
  try {
    const bin = atob(s);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

export function toHex(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += bytes[i].toString(16).padStart(2, "0");
  return s;
}

/* ------------------------ rembourrage à taille fixe ------------------------ */

/**
 * Rembourre `payload` dans un bloc de BUCKET_BYTES exactement :
 * [longueur u32 BE][payload][zéros]. Null si la charge dépasse le bloc —
 * l'appelant doit élaguer ses données, jamais agrandir le bloc (sinon la
 * taille redevient un canal d'information).
 */
export function padToBucket(payload: Uint8Array): Uint8Array | null {
  if (payload.length > MAX_PAYLOAD_BYTES) return null;
  const block = new Uint8Array(BUCKET_BYTES);
  new DataView(block.buffer).setUint32(0, payload.length, false);
  block.set(payload, LENGTH_PREFIX_BYTES);
  return block;
}

/** Inverse de padToBucket ; null sur bloc mal formé. */
export function unpadBucket(block: Uint8Array): Uint8Array | null {
  if (block.length !== BUCKET_BYTES) return null;
  const len = new DataView(block.buffer, block.byteOffset).getUint32(0, false);
  if (len > MAX_PAYLOAD_BYTES) return null;
  return block.slice(LENGTH_PREFIX_BYTES, LENGTH_PREFIX_BYTES + len);
}

/* ------------------------- validation d'enveloppe -------------------------- */

/**
 * Parse défensif (même philosophie que resume.parseStore) : tout écart —
 * champ en trop, base64 invalide, LONGUEUR différente de la taille fixe —
 * rend null. C'est ce qui ferme le canal « taille » côté serveur.
 */
export function parseEnvelope(raw: unknown): Envelope | null {
  if (typeof raw !== "object" || raw === null) return null;
  const e = raw as Record<string, unknown>;
  if (e.v !== ZK_VERSION) return null;
  if (typeof e.iv !== "string" || typeof e.ct !== "string") return null;
  if (Object.keys(e).length !== 3) return null;
  const iv = fromBase64(e.iv);
  const ct = fromBase64(e.ct);
  if (!iv || iv.length !== IV_BYTES) return null;
  if (!ct || ct.length !== CIPHERTEXT_BYTES) return null;
  // Re-sérialise pour ne garder qu'une forme canonique (pas d'octets cachés
  // dans une variante base64 exotique).
  return { v: ZK_VERSION, iv: toBase64(iv), ct: toBase64(ct) };
}

export function isSlotId(s: unknown): s is string {
  return typeof s === "string" && SLOT_ID_PATTERN.test(s);
}

/* ------------------------------- clés (HKDF) ------------------------------- */

export interface ZkKeys {
  /** AES-256-GCM — chiffre/déchiffre les blocs rembourrés. */
  enc: CryptoKey;
  /** HMAC-SHA-256 — aveugle les identifiants de slot. */
  sid: CryptoKey;
}

const te = new TextEncoder();

/**
 * Dérive les deux clés d'usage depuis le secret d'appareil (≥ 16 octets).
 * Deux clés distinctes : compromettre l'une ne révèle rien sur l'autre.
 */
export async function deriveKeys(secret: Uint8Array): Promise<ZkKeys> {
  if (secret.length < 16) throw new Error("secret trop court");
  const master = await crypto.subtle.importKey("raw", secret as BufferSource, "HKDF", false, ["deriveKey"]);
  const hkdf = (info: string) => ({
    name: "HKDF",
    hash: "SHA-256",
    salt: te.encode(HKDF_SALT) as BufferSource,
    info: te.encode(info) as BufferSource,
  });
  const enc = await crypto.subtle.deriveKey(
    hkdf(INFO_ENC),
    master,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"]
  );
  const sid = await crypto.subtle.deriveKey(
    hkdf(INFO_SID),
    master,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  return { enc, sid };
}

/**
 * Dérive une clé de contenu HLS de 16 octets (AES-128) depuis le secret
 * d'appareil. C'est une valeur BRUTE (les segments HLS sont chiffrés en
 * AES-128-CBC natif, qui exige la clé en clair côté lecteur) — elle ne quitte
 * jamais l'appareil et n'est JAMAIS déposée sur le relais.
 */
export async function deriveHlsKey(secret: Uint8Array, label = "tvking/hls/key/v1"): Promise<Uint8Array> {
  if (secret.length < 16) throw new Error("secret trop court");
  const master = await crypto.subtle.importKey("raw", secret as BufferSource, "HKDF", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: te.encode(HKDF_SALT) as BufferSource,
      info: te.encode(label) as BufferSource,
    },
    master,
    128
  );
  return new Uint8Array(bits);
}

/**
 * Identifiant de stockage AVEUGLÉ : HMAC(label) sous la clé de l'appareil.
 * Déterministe pour l'appareil (il retrouve son slot), opaque pour le serveur
 * (aucun lien inversible vers le label ni vers un autre appareil).
 */
export async function blindSlotId(keys: ZkKeys, label: string): Promise<string> {
  const mac = await crypto.subtle.sign("HMAC", keys.sid, te.encode(label) as BufferSource);
  return toHex(new Uint8Array(mac));
}

/* ----------------------------- seal / open --------------------------------- */

/**
 * Chiffre une charge utile en enveloppe opaque de taille fixe.
 * Null si la charge dépasse MAX_PAYLOAD_BYTES.
 */
export async function seal(keys: ZkKeys, payload: Uint8Array): Promise<Envelope | null> {
  const block = padToBucket(payload);
  if (!block) return null;
  const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES));
  const ct = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: iv as BufferSource },
    keys.enc,
    block as BufferSource
  );
  return { v: ZK_VERSION, iv: toBase64(iv), ct: toBase64(new Uint8Array(ct)) };
}

/**
 * Déchiffre une enveloppe. Null sur enveloppe mal formée, clé étrangère ou
 * chiffré altéré (le tag GCM authentifie tout le bloc).
 */
export async function open(keys: ZkKeys, raw: unknown): Promise<Uint8Array | null> {
  const env = parseEnvelope(raw);
  if (!env) return null;
  const iv = fromBase64(env.iv)!;
  const ct = fromBase64(env.ct)!;
  try {
    const block = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: iv as BufferSource },
      keys.enc,
      ct as BufferSource
    );
    return unpadBucket(new Uint8Array(block));
  } catch {
    return null;
  }
}

/* -------------------- comparaison en temps constant ------------------------ */

/**
 * Égalité de secrets sans fuite de timing : on compare les SHA-256 des deux
 * valeurs octet par octet, sans court-circuit — la durée ne dépend ni de la
 * longueur ni du point de divergence.
 */
export async function timingSafeEqual(a: string, b: string): Promise<boolean> {
  const [da, db] = await Promise.all([
    crypto.subtle.digest("SHA-256", te.encode(a) as BufferSource),
    crypto.subtle.digest("SHA-256", te.encode(b) as BufferSource),
  ]);
  const ua = new Uint8Array(da);
  const ub = new Uint8Array(db);
  let diff = 0;
  for (let i = 0; i < ua.length; i++) diff |= ua[i] ^ ub[i];
  return diff === 0;
}
