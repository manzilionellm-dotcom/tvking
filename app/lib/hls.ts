/*
 * Pipeline HLS Zero-Knowledge.
 *
 * Le flux binaire unique est découpé en segments, CHAQUE segment est chiffré
 * sur l'appareil en AES-128-CBC (le chiffrement natif de HLS, RFC 8216 §4.3.2.4),
 * puis publié comme octets opaques. Le serveur ne reçoit qu'une playlist M3U8
 * d'indexation (ordre, durées, IV publics) et des chunks chiffrés :
 *
 *   - la CLÉ de contenu n'est jamais déposée sur le relais — elle est dérivée
 *     du secret d'appareil (HKDF) et l'URI de clé du M3U8 pointe vers un schéma
 *     que le relais REFUSE de servir (`assertBlindKeyUri`) ; le relais ne peut
 *     donc structurellement pas devenir un oracle de déchiffrement ;
 *   - les octets des chunks audio/vidéo sont opaques : le relais ne peut ni les
 *     déchiffrer, ni les analyser.
 *
 * Tout est pur ou WebCrypto → identique en navigateur et en node (tests).
 *
 * Note d'honnêteté : SAMPLE-AES (chiffrement au niveau échantillon à
 * l'intérieur du conteneur TS/fMP4) exige un muxer natif ; ici seule la méthode
 * AES-128 (segment entier) est réellement implémentée. `keyMethod` peut annoncer
 * SAMPLE-AES pour un lecteur qui le gère en aval, mais encrypt/decrypt ci-dessous
 * font de l'AES-128 pleine longueur.
 */

import { isSlotId } from "./zk";

export const HLS_MANIFEST_VERSION = 1 as const;

/** IV AES-128 : 16 octets → 32 caractères hex. */
export const HLS_IV_BYTES = 16;
export const HLS_KEY_BYTES = 16;

/** Schéma d'URI de clé imposé : le relais REFUSE tout http(s) (anti-oracle). */
export const BLIND_KEY_SCHEME = "tvking-key:";

const IV_HEX_PATTERN = /^[0-9a-f]{32}$/;

export type HlsKeyMethod = "AES-128" | "SAMPLE-AES";

/** Une entrée de segment telle qu'indexée par le relais (rien de secret ici). */
export interface HlsSegment {
  /** slot aveuglé du segment chiffré (64 hex). */
  slot: string;
  /** durée en secondes (EXTINF). */
  dur: number;
  /** IV public du segment (32 hex). */
  iv: string;
}

/**
 * Le manifeste que le relais indexe. Il ne contient AUCUNE clé — seulement un
 * `keyUri` opaque que le lecteur résout localement.
 */
export interface HlsManifest {
  v: typeof HLS_MANIFEST_VERSION;
  target: number;
  keyMethod: HlsKeyMethod;
  keyUri: string;
  segments: HlsSegment[];
}

/* ------------------------------ validation --------------------------------- */

/** Vrai IV HLS : 32 hex minuscules. */
export function isIv(s: unknown): s is string {
  return typeof s === "string" && IV_HEX_PATTERN.test(s);
}

/**
 * Vrai SI l'URI de clé est aveugle (schéma maison), FAUX pour http(s):// ou
 * tout autre schéma que le relais pourrait résoudre. C'est le verrou qui
 * empêche le serveur de servir la clé.
 */
export function isBlindKeyUri(s: unknown): s is string {
  if (typeof s !== "string" || s.length === 0 || s.length > 256) return false;
  if (!s.startsWith(BLIND_KEY_SCHEME)) return false;
  return !/^[a-z][a-z0-9+.-]*:\/\//i.test(s); // aucun schéma réseau
}

/**
 * Parse défensif d'un manifeste (même philosophie que parseEnvelope) : tout
 * écart rend null. En particulier, un `keyUri` non aveugle est rejeté — le
 * relais ne stockera jamais un manifeste qui ferait de lui un oracle de clé.
 */
export function parseManifest(raw: unknown): HlsManifest | null {
  if (typeof raw !== "object" || raw === null) return null;
  const m = raw as Record<string, unknown>;
  if (m.v !== HLS_MANIFEST_VERSION) return null;
  if (typeof m.target !== "number" || !Number.isFinite(m.target) || m.target <= 0) return null;
  if (m.keyMethod !== "AES-128" && m.keyMethod !== "SAMPLE-AES") return null;
  if (!isBlindKeyUri(m.keyUri)) return null;
  if (!Array.isArray(m.segments) || m.segments.length === 0 || m.segments.length > 4096) return null;
  if (Object.keys(m).length !== 5) return null;

  const segments: HlsSegment[] = [];
  for (const s of m.segments) {
    if (typeof s !== "object" || s === null) return null;
    const seg = s as Record<string, unknown>;
    if (Object.keys(seg).length !== 3) return null;
    if (!isSlotId(seg.slot)) return null;
    if (typeof seg.dur !== "number" || !Number.isFinite(seg.dur) || seg.dur <= 0) return null;
    if (!isIv(seg.iv)) return null;
    segments.push({ slot: seg.slot, dur: seg.dur, iv: seg.iv });
  }
  return {
    v: HLS_MANIFEST_VERSION,
    target: Math.ceil(m.target),
    keyMethod: m.keyMethod,
    keyUri: m.keyUri,
    segments,
  };
}

/* ------------------------- génération de la playlist ----------------------- */

/**
 * Construit un M3U8 média à partir du manifeste. Chaque segment reçoit sa
 * propre ligne EXT-X-KEY (même URI aveugle, IV propre) — valide en HLS et cohérent
 * avec un IV par segment. `segUri` mappe un slot vers l'URL relayée du chunk.
 */
export function buildMediaPlaylist(manifest: HlsManifest, segUri: (slot: string) => string): string {
  const lines: string[] = [
    "#EXTM3U",
    "#EXT-X-VERSION:3",
    `#EXT-X-TARGETDURATION:${manifest.target}`,
    "#EXT-X-MEDIA-SEQUENCE:0",
    "#EXT-X-PLAYLIST-TYPE:VOD",
  ];
  for (const seg of manifest.segments) {
    lines.push(`#EXT-X-KEY:METHOD=${manifest.keyMethod},URI="${manifest.keyUri}",IV=0x${seg.iv}`);
    lines.push(`#EXTINF:${seg.dur.toFixed(3)},`);
    lines.push(segUri(seg.slot));
  }
  lines.push("#EXT-X-ENDLIST");
  return lines.join("\n") + "\n";
}

/* --------------------------- crypto de segment ----------------------------- */

export function ivToHex(iv: Uint8Array): string {
  let s = "";
  for (let i = 0; i < iv.length; i++) s += iv[i].toString(16).padStart(2, "0");
  return s;
}

export function ivFromHex(hex: string): Uint8Array | null {
  if (!isIv(hex)) return null;
  const out = new Uint8Array(HLS_IV_BYTES);
  for (let i = 0; i < HLS_IV_BYTES; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

export function randomIv(): Uint8Array {
  return crypto.getRandomValues(new Uint8Array(HLS_IV_BYTES));
}

async function importAesCbc(rawKey: Uint8Array): Promise<CryptoKey> {
  if (rawKey.length !== HLS_KEY_BYTES) throw new Error("clé AES-128 invalide");
  return crypto.subtle.importKey("raw", rawKey as BufferSource, { name: "AES-CBC" }, false, [
    "encrypt",
    "decrypt",
  ]);
}

/** Chiffre un segment (AES-128-CBC natif HLS, padding PKCS7). */
export async function encryptSegment(
  rawKey: Uint8Array,
  iv: Uint8Array,
  data: Uint8Array
): Promise<Uint8Array> {
  const key = await importAesCbc(rawKey);
  const ct = await crypto.subtle.encrypt({ name: "AES-CBC", iv: iv as BufferSource }, key, data as BufferSource);
  return new Uint8Array(ct);
}

/**
 * Déchiffre un segment. Null si la clé est mauvaise ou le chunk altéré au point
 * de casser le padding (AES-128-CBC = confidentialité, pas d'authenticité —
 * c'est le modèle natif de HLS).
 */
export async function decryptSegment(
  rawKey: Uint8Array,
  iv: Uint8Array,
  ct: Uint8Array
): Promise<Uint8Array | null> {
  try {
    const key = await importAesCbc(rawKey);
    const pt = await crypto.subtle.decrypt(
      { name: "AES-CBC", iv: iv as BufferSource },
      key,
      ct as BufferSource
    );
    return new Uint8Array(pt);
  } catch {
    return null;
  }
}
