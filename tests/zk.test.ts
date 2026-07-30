import { describe, expect, it } from "vitest";
import {
  BUCKET_BYTES,
  CIPHERTEXT_BYTES,
  IV_BYTES,
  MAX_PAYLOAD_BYTES,
  ZK_VERSION,
  blindSlotId,
  deriveKeys,
  fromBase64,
  isSlotId,
  open,
  padToBucket,
  parseEnvelope,
  presenceOf,
  seal,
  timingSafeEqual,
  toBase64,
  unpadBucket,
} from "../app/lib/zk";

const secret = new Uint8Array(32).fill(7);
const otherSecret = new Uint8Array(32).fill(8);

describe("presenceOf (data masking)", () => {
  it("réduit toute grandeur à présent/absent — jamais un compte", () => {
    expect(presenceOf(0)).toBe("absent");
    expect(presenceOf(1)).toBe("present");
    expect(presenceOf(9999)).toBe("present");
    expect(presenceOf(true)).toBe("present");
    expect(presenceOf(false)).toBe("absent");
    expect(presenceOf(null)).toBe("absent");
    expect(presenceOf(undefined)).toBe("absent");
    expect(presenceOf([])).toBe("absent");
    expect(presenceOf([1, 2, 3])).toBe("present");
    expect(presenceOf(new Map())).toBe("absent");
    expect(presenceOf(new Map([["a", 1]]))).toBe("present");
  });
});

describe("padToBucket / unpadBucket", () => {
  it("rembourre toujours à la même taille fixe, quel que soit le payload", () => {
    for (const n of [0, 1, 100, MAX_PAYLOAD_BYTES]) {
      const block = padToBucket(new Uint8Array(n).fill(0xab));
      expect(block).not.toBeNull();
      expect(block!.length).toBe(BUCKET_BYTES);
    }
  });

  it("refuse un payload plus grand que le bloc (pas de bloc extensible)", () => {
    expect(padToBucket(new Uint8Array(MAX_PAYLOAD_BYTES + 1))).toBeNull();
  });

  it("round-trip exact", () => {
    const payload = new TextEncoder().encode('{"v":1,"entries":{"a":{"pos":10,"dur":40,"at":5}}}');
    const back = unpadBucket(padToBucket(payload)!);
    expect(back).toEqual(payload);
  });

  it("rejette un bloc de mauvaise taille ou à longueur incohérente", () => {
    expect(unpadBucket(new Uint8Array(BUCKET_BYTES - 1))).toBeNull();
    const lying = new Uint8Array(BUCKET_BYTES);
    new DataView(lying.buffer).setUint32(0, MAX_PAYLOAD_BYTES + 1, false);
    expect(unpadBucket(lying)).toBeNull();
  });
});

describe("parseEnvelope", () => {
  it("rejette tout écart de forme ou de taille", async () => {
    const keys = await deriveKeys(secret);
    const good = (await seal(keys, new Uint8Array(10)))!;
    expect(parseEnvelope(good)).not.toBeNull();

    expect(parseEnvelope(null)).toBeNull();
    expect(parseEnvelope("x")).toBeNull();
    expect(parseEnvelope({})).toBeNull();
    expect(parseEnvelope({ ...good, v: 2 })).toBeNull();
    expect(parseEnvelope({ ...good, extra: "champ caché" })).toBeNull();
    expect(parseEnvelope({ ...good, iv: "$$$" })).toBeNull();
    // Chiffré plus court ou plus long que la taille FIXE → rejet (canal taille fermé).
    expect(parseEnvelope({ ...good, ct: toBase64(new Uint8Array(CIPHERTEXT_BYTES - 1)) })).toBeNull();
    expect(parseEnvelope({ ...good, ct: toBase64(new Uint8Array(CIPHERTEXT_BYTES + 1)) })).toBeNull();
    expect(parseEnvelope({ ...good, iv: toBase64(new Uint8Array(IV_BYTES + 1)) })).toBeNull();
  });
});

describe("seal / open", () => {
  it("round-trip et taille de chiffré UNIFORME quel que soit le contenu", async () => {
    const keys = await deriveKeys(secret);
    const small = new TextEncoder().encode("a");
    const large = new Uint8Array(9000).fill(0x5a);

    const envSmall = (await seal(keys, small))!;
    const envLarge = (await seal(keys, large))!;
    expect(envSmall.v).toBe(ZK_VERSION);
    // 1 octet ou 9000 octets : exactement la même empreinte réseau.
    expect(fromBase64(envSmall.ct)!.length).toBe(CIPHERTEXT_BYTES);
    expect(fromBase64(envLarge.ct)!.length).toBe(CIPHERTEXT_BYTES);

    expect(await open(keys, envSmall)).toEqual(small);
    expect(await open(keys, envLarge)).toEqual(large);
  });

  it("refuse une charge au-delà du bloc fixe", async () => {
    const keys = await deriveKeys(secret);
    expect(await seal(keys, new Uint8Array(MAX_PAYLOAD_BYTES + 1))).toBeNull();
  });

  it("échoue proprement sur clé étrangère ou chiffré altéré", async () => {
    const keys = await deriveKeys(secret);
    const other = await deriveKeys(otherSecret);
    const env = (await seal(keys, new TextEncoder().encode("secret")))!;

    expect(await open(other, env)).toBeNull();

    const ct = fromBase64(env.ct)!;
    ct[0] ^= 0xff;
    expect(await open(keys, { ...env, ct: toBase64(ct) })).toBeNull();
  });
});

describe("blindSlotId", () => {
  it("est déterministe par appareil et au format attendu", async () => {
    const keys = await deriveKeys(secret);
    const a = await blindSlotId(keys, "resume/v1");
    expect(a).toMatch(/^[0-9a-f]{64}$/);
    expect(isSlotId(a)).toBe(true);
    expect(await blindSlotId(keys, "resume/v1")).toBe(a);
  });

  it("diffère entre appareils et entre étiquettes (non corrélable)", async () => {
    const keys = await deriveKeys(secret);
    const other = await deriveKeys(otherSecret);
    const a = await blindSlotId(keys, "resume/v1");
    expect(await blindSlotId(other, "resume/v1")).not.toBe(a);
    expect(await blindSlotId(keys, "liste/v1")).not.toBe(a);
  });
});

describe("isSlotId", () => {
  it("n'accepte que 64 hex minuscules", () => {
    expect(isSlotId("a".repeat(64))).toBe(true);
    expect(isSlotId("A".repeat(64))).toBe(false);
    expect(isSlotId("a".repeat(63))).toBe(false);
    expect(isSlotId("g".repeat(64))).toBe(false);
    expect(isSlotId(42)).toBe(false);
  });
});

describe("timingSafeEqual", () => {
  it("compare correctement", async () => {
    expect(await timingSafeEqual("motdepasse", "motdepasse")).toBe(true);
    expect(await timingSafeEqual("motdepasse", "motdepassé")).toBe(false);
    expect(await timingSafeEqual("", "x")).toBe(false);
  });
});

describe("deriveKeys", () => {
  it("refuse un secret trop court", async () => {
    await expect(deriveKeys(new Uint8Array(8))).rejects.toThrow();
  });
});
