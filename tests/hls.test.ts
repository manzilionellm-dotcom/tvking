import { describe, expect, it } from "vitest";
import {
  BLIND_KEY_SCHEME,
  buildMediaPlaylist,
  decryptSegment,
  encryptSegment,
  type HlsManifest,
  isBlindKeyUri,
  isIv,
  ivFromHex,
  ivToHex,
  parseManifest,
  randomIv,
} from "../app/lib/hls";
import {
  MAX_SEGMENT_BYTES,
  MAX_STREAMS,
  emptyRelay,
  getManifest,
  getSegment,
  putManifest,
  putSegment,
  streamPresence,
} from "../app/lib/hlsStore";
import { deriveHlsKey } from "../app/lib/zk";

const sid = (n: number) => n.toString(16).padStart(64, "0");
const KEY_URI = `${BLIND_KEY_SCHEME}v1`;

function manifest(segCount = 2): HlsManifest {
  return {
    v: 1,
    target: 6,
    keyMethod: "AES-128",
    keyUri: KEY_URI,
    segments: Array.from({ length: segCount }, (_, i) => ({
      slot: sid(i + 1),
      dur: 6,
      iv: "0".repeat(32),
    })),
  };
}

describe("isBlindKeyUri (verrou anti-oracle de clé)", () => {
  it("accepte le schéma aveugle, refuse tout schéma réseau", () => {
    expect(isBlindKeyUri(`${BLIND_KEY_SCHEME}v1`)).toBe(true);
    expect(isBlindKeyUri("tvking-key:resume/abc")).toBe(true);
    // Un relais ne doit JAMAIS pouvoir servir la clé :
    expect(isBlindKeyUri("http://evil/key.bin")).toBe(false);
    expect(isBlindKeyUri("https://relay/key.bin")).toBe(false);
    expect(isBlindKeyUri("//relay/key.bin")).toBe(false);
    expect(isBlindKeyUri("key.bin")).toBe(false);
    expect(isBlindKeyUri("")).toBe(false);
    expect(isBlindKeyUri(42)).toBe(false);
  });
});

describe("isIv / ivToHex / ivFromHex", () => {
  it("round-trip et validation", () => {
    const iv = randomIv();
    const hex = ivToHex(iv);
    expect(isIv(hex)).toBe(true);
    expect(ivFromHex(hex)).toEqual(iv);
    expect(ivFromHex("xyz")).toBeNull();
    expect(isIv("0".repeat(31))).toBe(false);
    expect(isIv("A".repeat(32))).toBe(false);
  });
});

describe("parseManifest", () => {
  it("accepte un manifeste conforme", () => {
    expect(parseManifest(manifest())).not.toBeNull();
  });

  it("REJETTE un manifeste dont l'URI de clé n'est pas aveugle", () => {
    expect(parseManifest({ ...manifest(), keyUri: "https://relay/key.bin" })).toBeNull();
    expect(parseManifest({ ...manifest(), keyUri: "key.bin" })).toBeNull();
  });

  it("rejette écarts de forme, segments vides, champs en trop", () => {
    expect(parseManifest(null)).toBeNull();
    expect(parseManifest({ ...manifest(), v: 2 })).toBeNull();
    expect(parseManifest({ ...manifest(), extra: "x" })).toBeNull();
    expect(parseManifest({ ...manifest(), target: 0 })).toBeNull();
    expect(parseManifest({ ...manifest(), keyMethod: "PLAIN" })).toBeNull();
    expect(parseManifest({ ...manifest(0) })).toBeNull();
    expect(parseManifest({ ...manifest(), segments: [{ slot: "court", dur: 6, iv: "0".repeat(32) }] })).toBeNull();
    expect(parseManifest({ ...manifest(), segments: [{ slot: sid(1), dur: 6, iv: "bad" }] })).toBeNull();
    expect(parseManifest({ ...manifest(), segments: [{ slot: sid(1), dur: 6, iv: "0".repeat(32), extra: 1 }] })).toBeNull();
  });
});

describe("buildMediaPlaylist", () => {
  it("produit un M3U8 valide avec clé aveugle et un IV par segment", () => {
    const m = manifest(2);
    m.segments[0].iv = "1".repeat(32);
    m.segments[1].iv = "2".repeat(32);
    const pl = buildMediaPlaylist(m, (slot) => `/api/hls/S/seg/${slot}`);
    expect(pl).toContain("#EXTM3U");
    expect(pl).toContain("#EXT-X-TARGETDURATION:6");
    expect(pl).toContain(`METHOD=AES-128,URI="${KEY_URI}",IV=0x${"1".repeat(32)}`);
    expect(pl).toContain(`/api/hls/S/seg/${sid(1)}`);
    expect(pl).toContain("#EXT-X-ENDLIST");
    // La clé elle-même n'apparaît JAMAIS dans la playlist — seulement son URI aveugle.
    expect(pl).not.toMatch(/https?:\/\//);
  });
});

describe("encryptSegment / decryptSegment (AES-128 natif HLS)", () => {
  const secret = new Uint8Array(32).fill(3);

  it("round-trip exact", async () => {
    const key = await deriveHlsKey(secret);
    const iv = randomIv();
    const media = new Uint8Array(5000).map((_, i) => i & 0xff);
    const ct = await encryptSegment(key, iv, media);
    expect(ct).not.toEqual(media);
    expect(await decryptSegment(key, iv, ct)).toEqual(media);
  });

  it("échoue proprement avec une clé étrangère (relais ne peut pas déchiffrer)", async () => {
    const key = await deriveHlsKey(secret);
    const foreign = await deriveHlsKey(new Uint8Array(32).fill(9));
    const iv = randomIv();
    const ct = await encryptSegment(key, iv, new Uint8Array(1024).fill(7));
    const out = await decryptSegment(foreign, iv, ct);
    // Soit padding invalide (null), soit octets différents — jamais le clair.
    expect(out === null || !out.every((b) => b === 7)).toBe(true);
  });

  it("la clé de contenu est déterministe par appareil", async () => {
    const a = await deriveHlsKey(secret);
    const b = await deriveHlsKey(secret);
    expect(a).toEqual(b);
    expect(a.length).toBe(16);
  });
});

describe("relais serveur (aveugle)", () => {
  it("stocke/rend un manifeste et des segments opaques", () => {
    const relay = emptyRelay();
    expect(putManifest(relay, sid(100), manifest())).toBe("stored");
    expect(getManifest(relay, sid(100))).not.toBeNull();

    const chunk = new Uint8Array([1, 2, 3, 4]);
    expect(putSegment(relay, sid(1), chunk)).toBe("stored");
    expect(getSegment(relay, sid(1))).toEqual(chunk);
  });

  it("REJETTE un manifeste à URI de clé non aveugle (verrou serveur)", () => {
    const relay = emptyRelay();
    expect(putManifest(relay, sid(1), { ...manifest(), keyUri: "https://relay/k" })).toBe("rejected");
    expect(getManifest(relay, sid(1))).toBeNull();
  });

  it("rejette slot invalide, segment vide ou trop gros", () => {
    const relay = emptyRelay();
    expect(putManifest(relay, "pas-slot", manifest())).toBe("rejected");
    expect(putSegment(relay, sid(1), new Uint8Array(0))).toBe("rejected");
    expect(putSegment(relay, sid(1), new Uint8Array(MAX_SEGMENT_BYTES + 1))).toBe("rejected");
  });

  it("évince les flux en FIFO au plafond", () => {
    const relay = emptyRelay();
    for (let i = 0; i < MAX_STREAMS + 2; i++) putManifest(relay, sid(i), manifest());
    expect(relay.manifests.size).toBe(MAX_STREAMS);
    expect(getManifest(relay, sid(0))).toBeNull();
    expect(getManifest(relay, sid(MAX_STREAMS + 1))).not.toBeNull();
  });

  it("ne sort qu'un état binaire présent/absent pour le panel", () => {
    const relay = emptyRelay();
    expect(streamPresence(relay, sid(1))).toBe("absent");
    putManifest(relay, sid(1), manifest());
    expect(streamPresence(relay, sid(1))).toBe("present");
    expect(streamPresence(relay, "invalide")).toBe("absent");
  });
});
