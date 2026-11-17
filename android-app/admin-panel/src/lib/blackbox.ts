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

// Cette édition TV omet la chaîne dans sa présence, mais ses diagnostics
// audio et vidéo contiennent le nom connu au moment de la lecture.
export const NOVATUBE_TV_VERSION = '1.0.0+1794878682';
export const JOURNAL_REFRESH_MS = 45_000;
// La colonne indique explicitement l'heure de la dernière lecture. Après
// quinze minutes sans nouveau journal, l'information disparaît comme la présence.
export const JOURNAL_FRESH_MS = 15 * 60_000;

export interface PlaybackObservation {
  name: string;
  time: string; // Heure locale affichée par la TV, sans conversion de fuseau.
}

export function lastTvPlayback(text: string): PlaybackObservation | null {
  const lines = text.split('\n');
  for (let i = lines.length - 1; i >= 0; i--) {
    // Un nouveau démarrage sépare deux sessions sur le même appareil.
    const entry = /^(\d{2}\/\d{2} \d{2}:\d{2}:\d{2}) [A-Z] \[([A-Z]+)\] (.+)$/.exec(lines[i].trim());
    if (!entry) continue;
    const [, time, tag, message] = entry;
    if (tag === 'BOOT') break;
    if (tag !== 'SON' && tag !== 'IMAGE') continue;
    const title = tag === 'SON'
      ? /^\[(.{1,180})\] Seconde \d+\s*:/u.exec(message)
      : /^\[((?:[^\[\]]|\[[^\[\]]*\])+)\] \S/u.exec(message.slice(0, 184));
    const name = title?.[1].trim();
    if (!name || name.length > 180 || /^son témoin$/iu.test(name) ||
        /https?:|:\/\/|password=|username=|\[(?:masqué|identifiants|url)\]|[\u0000-\u001f\u007f]/iu.test(name)) continue;
    return { name, time };
  }
  return null;
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
