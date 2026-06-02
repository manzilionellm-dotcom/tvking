import { describe, expect, it } from "vitest";
import {
  bestCandidateIndex,
  directionScore,
  type Rectish,
} from "../app/lib/spatial";

// Helper : construit un rectangle.
const rect = (left: number, top: number, w = 50, h = 50): Rectish => ({
  left,
  top,
  width: w,
  height: h,
});

describe("directionScore", () => {
  const cur = rect(100, 100); // centre (125, 125)

  it("retourne null si le candidat n'est PAS dans la direction", () => {
    // Un candidat à droite n'est pas « à gauche ».
    expect(directionScore(cur, rect(300, 100), "left")).toBeNull();
    // Un candidat en bas n'est pas « en haut ».
    expect(directionScore(cur, rect(100, 300), "up")).toBeNull();
  });

  it("retourne un score fini quand le candidat est dans la direction", () => {
    const s = directionScore(cur, rect(300, 100), "right");
    expect(s).not.toBeNull();
    expect(Number.isFinite(s as number)).toBe(true);
  });

  it("pénalise le décalage hors-axe (un candidat aligné score mieux)", () => {
    const aligned = directionScore(cur, rect(300, 100), "right")!; // même ligne
    const offset = directionScore(cur, rect(300, 400), "right")!; // décalé bas
    expect(aligned).toBeLessThan(offset);
  });
});

describe("bestCandidateIndex", () => {
  const cur = rect(100, 100); // centre (125, 125)

  it("choisit le voisin le plus proche dans la direction", () => {
    const cands = [
      rect(100, 400), // bas (hors sujet pour 'right')
      rect(220, 105), // droite, presque aligné  ← attendu
      rect(600, 110), // droite mais plus loin
    ];
    expect(bestCandidateIndex(cur, cands, "right")).toBe(1);
  });

  it("préfère l'aligné à un candidat plus proche mais très décalé", () => {
    const cands = [
      rect(180, 600), // un peu à droite mais TRÈS bas
      rect(320, 120), // plus loin à droite mais aligné  ← attendu
    ];
    expect(bestCandidateIndex(cur, cands, "right")).toBe(1);
  });

  it("retourne -1 si aucun candidat n'est dans la direction", () => {
    const cands = [rect(100, 400), rect(100, 600)]; // tous en bas
    expect(bestCandidateIndex(cur, cands, "up")).toBe(-1);
  });

  it("navigue correctement vers le haut", () => {
    const cands = [
      rect(100, 20), // au-dessus, aligné  ← attendu
      rect(400, 30), // au-dessus mais décalé
    ];
    expect(bestCandidateIndex(cur, cands, "up")).toBe(0);
  });
});
