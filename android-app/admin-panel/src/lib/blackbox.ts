// =========================================================
//  blackbox.ts — Affichage du journal dans le panel
// =========================================================
//  La box envoie son journal au Worker (même MAC que
//  l'activation). Cette page le relit. Le délai de 1,5 s est
//  le temps max entre « le Worker a le texte » et « Lionel le
//  voit », tant que la page est ouverte.
// =========================================================

/// Entre 1 et 2 secondes : la consigne du revendeur.
export const BLACKBOX_POLL_MS = 1500;

const MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/i;

/// `null` si ce n'est pas une MAC de box. Sinon la forme
/// canonique (majuscules), celle que la base utilise.
export function normalizePanelMac(raw: string): string | null {
  const mac = raw.trim().toUpperCase();
  return MAC_RX.test(mac) ? mac : null;
}

/// Heure de la dernière réception. Chaîne vide tant que la
/// box n'a rien envoyé (updated_at = 0).
export function formatBlackBoxUpdated(ms: number): string {
  if (!ms || ms <= 0) return '';
  try {
    return new Date(ms).toLocaleString('fr-FR', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
  } catch {
    return '';
  }
}
