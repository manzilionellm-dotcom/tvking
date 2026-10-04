// Sondage du panel vers le Worker.
// Un événement déjà écrit (présence, inventaire, listes) doit apparaître
// en au plus 2 secondes. Les réponses qui se croisent ne doivent pas
// réafficher un état plus vieux.

export const PANEL_POLL_MS = 2000;

/// Filet quand le canal est ouvert : on ne sonde plus toutes les 2 s.
/// Un événement du canal déclenche la relecture tout de suite.
export const PANEL_POLL_SLOW_MS = 60_000;

/// Interrupteur de repli. Vrai = on ignore le canal et on sonde
/// toutes les 2 s, comme avant. Défaut faux (repli coupé).
export const REALTIME_POLL_LEGACY = false;

export function shouldApplyPollResult(resultSeq: number, appliedSeq: number): boolean {
  return resultSeq >= appliedSeq;
}

/// Délai avant la prochaine lecture. Canal ouvert et repli coupé :
/// filet lent. Sinon : 2 s.
export function panelPollInterval(channelUp: boolean): number {
  if (REALTIME_POLL_LEGACY || !channelUp) return PANEL_POLL_MS;
  return PANEL_POLL_SLOW_MS;
}
