/*
 * Côté appareil : publie et lit un flux HLS chiffré de bout en bout.
 *
 * Chaîne de publication :
 *   segments clairs ─► AES-128-CBC (clé dérivée du secret d'appareil) ─►
 *   PUT chunks opaques + PUT manifeste d'indexation ─► le relais ne voit que
 *   du chiffré et un index (l'URI de clé y est AVEUGLE, jamais la clé).
 *
 * Chaîne de lecture (pour un lecteur hls.js, cf. docs/ZERO-KNOWLEDGE.md) :
 *   le lecteur charge la playlist du relais ; son "key loader" intercepte l'URI
 *   `tvking-key:...` et fournit la clé résolue LOCALEMENT (jamais réclamée au
 *   relais). Ici, `resolveContentKey` expose cette clé au lecteur.
 */

import {
  BLIND_KEY_SCHEME,
  type HlsManifest,
  type HlsSegment,
  decryptSegment,
  encryptSegment,
  ivFromHex,
  ivToHex,
  randomIv,
} from "./hls";
import { getOrCreateDeviceSecret } from "./zkClient";
import { type ZkKeys, blindSlotId, deriveHlsKey, deriveKeys } from "./zk";

/** Étiquette de clé aveugle inscrite dans le M3U8 (le relais la refuse comme source). */
export const HLS_KEY_URI = `${BLIND_KEY_SCHEME}v1`;

export interface PublishSegment {
  data: Uint8Array;
  dur: number;
}

export type PublishResult =
  | { ok: true; streamSlot: string; playlistUrl: string }
  | { ok: false; reason: "erreur" };

interface DeviceCrypto {
  keys: ZkKeys;
  contentKey: Uint8Array;
}

let cached: Promise<DeviceCrypto | null> | null = null;

function deviceCrypto(): Promise<DeviceCrypto | null> {
  if (!cached) {
    cached = (async () => {
      const secret = getOrCreateDeviceSecret();
      if (!secret) return null;
      const [keys, contentKey] = await Promise.all([deriveKeys(secret), deriveHlsKey(secret)]);
      return { keys, contentKey };
    })();
  }
  return cached;
}

/** La clé de contenu brute (16 octets) à fournir au key loader du lecteur. Ne la transmettez pas. */
export async function resolveContentKey(): Promise<Uint8Array | null> {
  const dc = await deviceCrypto();
  return dc ? dc.contentKey : null;
}

/** slot aveuglé du flux (affichable : ne révèle que la présence). */
export async function streamSlotId(label: string): Promise<string | null> {
  const dc = await deviceCrypto();
  if (!dc) return null;
  return blindSlotId(dc.keys, `hls/${label}`);
}

/** URL relayée de la playlist M3U8 d'un flux. */
export async function playlistUrl(label: string): Promise<string | null> {
  const slot = await streamSlotId(label);
  return slot ? `/api/hls/${slot}` : null;
}

/**
 * Chiffre chaque segment sur l'appareil et publie le flux (chunks opaques +
 * manifeste d'indexation). La clé n'est jamais envoyée.
 */
export async function publishStream(label: string, segments: PublishSegment[]): Promise<PublishResult> {
  try {
    const dc = await deviceCrypto();
    if (!dc || segments.length === 0) return { ok: false, reason: "erreur" };
    const streamSlot = await blindSlotId(dc.keys, `hls/${label}`);

    const indexed: HlsSegment[] = [];
    let target = 1;
    for (let i = 0; i < segments.length; i++) {
      const { data, dur } = segments[i];
      const segSlot = await blindSlotId(dc.keys, `hls/${label}/seg/${i}`);
      const iv = randomIv();
      const ct = await encryptSegment(dc.contentKey, iv, data);
      const res = await fetch(`/api/hls/${streamSlot}/seg/${segSlot}`, {
        method: "PUT",
        headers: { "content-type": "application/octet-stream" },
        body: ct as BodyInit,
      });
      if (!res.ok) return { ok: false, reason: "erreur" };
      indexed.push({ slot: segSlot, dur, iv: ivToHex(iv) });
      target = Math.max(target, Math.ceil(dur));
    }

    const manifest: HlsManifest = {
      v: 1,
      target,
      keyMethod: "AES-128",
      keyUri: HLS_KEY_URI,
      segments: indexed,
    };
    const put = await fetch(`/api/hls/${streamSlot}`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(manifest),
    });
    if (!put.ok) return { ok: false, reason: "erreur" };

    return { ok: true, streamSlot, playlistUrl: `/api/hls/${streamSlot}` };
  } catch {
    return { ok: false, reason: "erreur" };
  }
}

/**
 * Récupère et déchiffre localement un segment donné (index 0-based) d'un flux —
 * utile pour vérifier la chaîne de bout en bout, ou pour un lecteur maison.
 */
export async function fetchSegment(label: string, index: number): Promise<Uint8Array | null> {
  try {
    const dc = await deviceCrypto();
    if (!dc) return null;
    const streamSlot = await blindSlotId(dc.keys, `hls/${label}`);

    const manifestRes = await fetch(`/api/hls/${streamSlot}`);
    if (!manifestRes.ok) return null;
    // Le relais rend du M3U8 ; on reconstruit l'IV via l'étiquette locale.
    const segSlot = await blindSlotId(dc.keys, `hls/${label}/seg/${index}`);
    const playlist = await manifestRes.text();
    const iv = ivForSegment(playlist, `/api/hls/${streamSlot}/seg/${segSlot}`);
    if (!iv) return null;

    const segRes = await fetch(`/api/hls/${streamSlot}/seg/${segSlot}`);
    if (!segRes.ok) return null;
    const ct = new Uint8Array(await segRes.arrayBuffer());
    return decryptSegment(dc.contentKey, iv, ct);
  } catch {
    return null;
  }
}

/** Retrouve l'IV (juste au-dessus de l'URI de segment) dans un M3U8. */
function ivForSegment(playlist: string, segUri: string): Uint8Array | null {
  const lines = playlist.split(/\r?\n/);
  const at = lines.indexOf(segUri);
  if (at < 0) return null;
  for (let i = at - 1; i >= 0 && i >= at - 3; i--) {
    const m = /IV=0x([0-9a-fA-F]{32})/.exec(lines[i]);
    if (m) return ivFromHex(m[1].toLowerCase());
  }
  return null;
}

/** Droit à l'effacement : supprime le manifeste distant (segments compris côté relais). */
export async function eraseStream(label: string): Promise<boolean> {
  try {
    const slot = await streamSlotId(label);
    if (!slot) return false;
    const res = await fetch(`/api/hls/${slot}`, { method: "DELETE" });
    return res.ok;
  } catch {
    return false;
  }
}
