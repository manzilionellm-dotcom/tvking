// =========================================================
//  spatial.ts — Logique PURE de navigation spatiale (testable)
// =========================================================
//  Extraite de SpatialNav pour être testable sans DOM. Modèle Android TV
//  « élément le plus proche dans la direction » : depuis le centre de
//  l'élément courant, on score chaque candidat = distance le long de
//  l'axe + distance hors-axe × 2.5 (on pénalise le décalage latéral pour
//  garder un déplacement droit et prévisible). Le plus petit score gagne.
// =========================================================

export type Dir = "up" | "down" | "left" | "right";

/// Rectangle minimal (compatible avec DOMRect).
export interface Rectish {
  left: number;
  top: number;
  width: number;
  height: number;
}

/// Pénalité appliquée au décalage hors-axe (un candidat « tout droit »
/// est préféré à un candidat décalé, même un peu plus proche en absolu).
export const OFF_AXIS_PENALTY = 2.5;

/// Tolérance (px) pour ignorer le bruit d'alignement : un candidat doit
/// être franchement dans la direction pour être éligible.
export const DIRECTION_MARGIN = 8;

export function centerOf(r: Rectish): { x: number; y: number } {
  return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
}

/// Score d'un candidat dans une direction. Retourne `null` si le candidat
/// n'est PAS dans la direction demandée (donc inéligible). Plus le score
/// est petit, meilleur est le candidat.
export function directionScore(
  cur: Rectish,
  cand: Rectish,
  dir: Dir,
): number | null {
  const c = centerOf(cur);
  const t = centerOf(cand);
  const dx = t.x - c.x;
  const dy = t.y - c.y;

  let along: number;
  let off: number;
  switch (dir) {
    case "left":
      if (dx >= -DIRECTION_MARGIN) return null;
      along = -dx;
      off = Math.abs(dy);
      break;
    case "right":
      if (dx <= DIRECTION_MARGIN) return null;
      along = dx;
      off = Math.abs(dy);
      break;
    case "up":
      if (dy >= -DIRECTION_MARGIN) return null;
      along = -dy;
      off = Math.abs(dx);
      break;
    case "down":
      if (dy <= DIRECTION_MARGIN) return null;
      along = dy;
      off = Math.abs(dx);
      break;
  }
  return along + off * OFF_AXIS_PENALTY;
}

/// Indice du meilleur candidat dans `cands` pour la direction donnée,
/// ou -1 s'il n'y a aucun candidat éligible. (Le rectangle courant ne
/// doit PAS figurer dans `cands`.)
export function bestCandidateIndex(
  cur: Rectish,
  cands: Rectish[],
  dir: Dir,
): number {
  let best = -1;
  let bestScore = Number.POSITIVE_INFINITY;
  for (let i = 0; i < cands.length; i++) {
    const s = directionScore(cur, cands[i], dir);
    if (s !== null && s < bestScore) {
      bestScore = s;
      best = i;
    }
  }
  return best;
}
