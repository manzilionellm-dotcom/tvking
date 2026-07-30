import { describe, expect, it } from "vitest";
import {
  MAX_SLOTS,
  deleteSlot,
  emptyVault,
  getSlot,
  putSlot,
  slotPresence,
  vaultPresence,
} from "../app/lib/vault";
import { deriveKeys, seal, type Envelope } from "../app/lib/zk";

async function makeEnvelope(fill = 1): Promise<Envelope> {
  const keys = await deriveKeys(new Uint8Array(32).fill(fill));
  return (await seal(keys, new Uint8Array(64).fill(fill)))!;
}

const sid = (n: number) => n.toString(16).padStart(64, "0");

describe("putSlot / getSlot / deleteSlot", () => {
  it("stocke et restitue une enveloppe conforme", async () => {
    const vault = emptyVault();
    const env = await makeEnvelope();
    expect(putSlot(vault, sid(1), env)).toBe("stored");
    expect(getSlot(vault, sid(1))).toEqual(env);
  });

  it("rejette slot non aveuglé et enveloppe non conforme", async () => {
    const vault = emptyVault();
    const env = await makeEnvelope();
    expect(putSlot(vault, "pas-un-slot", env)).toBe("rejected");
    expect(putSlot(vault, sid(1), { ...env, meta: "interdite" })).toBe("rejected");
    expect(putSlot(vault, sid(1), { v: 1, iv: env.iv, ct: "court" })).toBe("rejected");
    expect(putSlot(vault, sid(1), null)).toBe("rejected");
    // Rien n'est entré dans le coffre.
    expect(vaultPresence(vault)).toBe("absent");
  });

  it("get/delete sur slot invalide ou absent restent inertes", async () => {
    const vault = emptyVault();
    expect(getSlot(vault, "zzz")).toBeNull();
    expect(getSlot(vault, sid(9))).toBeNull();
    deleteSlot(vault, "zzz");
    deleteSlot(vault, sid(9));
    expect(vaultPresence(vault)).toBe("absent");
  });

  it("efface réellement (droit à l'effacement)", async () => {
    const vault = emptyVault();
    putSlot(vault, sid(1), await makeEnvelope());
    deleteSlot(vault, sid(1));
    expect(getSlot(vault, sid(1))).toBeNull();
    expect(vaultPresence(vault)).toBe("absent");
  });

  it("évince en FIFO au-delà du plafond, sans horodatage", async () => {
    const vault = emptyVault();
    const env = await makeEnvelope();
    for (let i = 0; i < MAX_SLOTS + 3; i++) putSlot(vault, sid(i), env);
    expect(vault.slots.size).toBe(MAX_SLOTS);
    // Les 3 plus anciens sont partis, les récents restent.
    expect(getSlot(vault, sid(0))).toBeNull();
    expect(getSlot(vault, sid(2))).toBeNull();
    expect(getSlot(vault, sid(3))).not.toBeNull();
    expect(getSlot(vault, sid(MAX_SLOTS + 2))).not.toBeNull();
  });

  it("re-déposer rafraîchit la position FIFO du slot", async () => {
    const vault = emptyVault();
    const env = await makeEnvelope();
    for (let i = 0; i < MAX_SLOTS; i++) putSlot(vault, sid(i), env);
    putSlot(vault, sid(0), env); // slot 0 repasse en fin de file
    putSlot(vault, sid(MAX_SLOTS), env); // force une éviction → slot 1 sort
    expect(getSlot(vault, sid(0))).not.toBeNull();
    expect(getSlot(vault, sid(1))).toBeNull();
  });

  it("un enregistrement ne contient QUE iv et ct (minimisation)", async () => {
    const vault = emptyVault();
    putSlot(vault, sid(1), await makeEnvelope());
    const stored = vault.slots.get(sid(1))!;
    expect(Object.keys(stored).sort()).toEqual(["ct", "iv", "v"]);
  });
});

describe("vue panel binaire", () => {
  it("ne sort jamais autre chose que present/absent, quel que soit le volume", async () => {
    const vault = emptyVault();
    expect(vaultPresence(vault)).toBe("absent");

    const env = await makeEnvelope();
    putSlot(vault, sid(1), env);
    expect(vaultPresence(vault)).toBe("present");

    // 1 ou 50 dépôts : le panel voit EXACTEMENT le même état.
    for (let i = 2; i <= 50; i++) putSlot(vault, sid(i), env);
    expect(vaultPresence(vault)).toBe("present");

    expect(slotPresence(vault, sid(1))).toBe("present");
    expect(slotPresence(vault, sid(999))).toBe("absent");
    expect(slotPresence(vault, "invalide")).toBe("absent");
  });
});
