// Sondage du panel vers le Worker.
// Un événement déjà écrit (présence, inventaire, listes) doit apparaître
// en au plus 2 secondes. Les réponses qui se croisent ne doivent pas
// réafficher un état plus vieux.

export const PANEL_POLL_MS = 2000;

export function shouldApplyPollResult(resultSeq: number, appliedSeq: number): boolean {
  return resultSeq >= appliedSeq;
}
