// Une recherche reste du texte libre. Le masque MAC est seulement un
// affichage : le texte original (casse comprise) reste la requête API.
import {
  applyMacEdit, caretForUsefulCount, formatMacAddress, macMatches,
  macUsefulChars, usefulCountBefore, type MacDeleteDirection, type MacEditResult,
} from './mac';

/** Garde volontairement les noms ambigus (« cafe », « deadbeef »), IP et emails. */
export function isMacSearchQuery(query: string): boolean {
  const raw = query.trim();
  if (!raw || !/^[a-z0-9:.\- ]+$/i.test(raw)) return false;
  const useful = macUsefulChars(raw);
  if (useful.length > 12) return false;
  if (/^MK/i.test(useful)) {
    return useful.length >= 2 && (/^MK[0-9A-F]*$/.test(useful) || /\d/.test(useful));
  }
  if (!useful || !/^[0-9A-F]+$/.test(useful)) return false;
  // Une IPv4, même encore partielle, et les formes IPv6 restent littérales.
  if (/^\d{1,3}(?:\.\d{0,3}){1,3}$/.test(raw) || raw.includes('::')) return false;
  if (raw.includes(':') && raw.split(':').some((part) => part.length > 2)) return false;
  return /\d/.test(useful) || /[:.\- ]/.test(raw)
    || useful.length === 12 || /^(AA|BB|CC|DD|EE|FF)/.test(useful);
}

export function macSearchDisplay(query: string): string {
  return isMacSearchQuery(query) ? formatMacAddress(query) : query;
}

/** Complément du filtre textuel, uniquement sur les écrans qui acceptent une MAC. */
export function macSearchMatches(mac: string | null | undefined, query: string): boolean {
  return isMacSearchQuery(query) && macMatches(mac, query);
}

function rawPosition(query: string, shown: string, position: number): number {
  const usefulCount = usefulCountBefore(shown, position);
  if (usefulCount <= 0) return 0;
  let count = 0;
  for (let i = 0; i < query.length; i++) {
    if (/[a-z0-9]/i.test(query[i]) && ++count === usefulCount) {
      let boundary = i + 1;
      // Le curseur après un « : » affiché doit aussi rester après le
      // séparateur original (point, tiret, espace), s'il en existe un.
      if (shown[position - 1] === ':') {
        while (boundary < query.length && !/[a-z0-9]/i.test(query[boundary])) boundary++;
      }
      return boundary;
    }
  }
  return query.length;
}

/**
 * Transpose l'édition de l'affichage sur le texte original. Les « : »
 * ajoutés par le masque ne deviennent jamais des caractères du nom si
 * l'utilisateur poursuit avec du texte, un email ou plus de 12 caractères.
 */
export function applyMacSearchEdit(
  raw: string, rawCaret: number | null, previous: string, direction: MacDeleteDirection,
): MacEditResult {
  const caret = rawCaret ?? raw.length;
  const shown = macSearchDisplay(previous);
  if (!isMacSearchQuery(previous)) {
    return {
      value: raw,
      caret: isMacSearchQuery(raw) ? caretForUsefulCount(usefulCountBefore(raw, caret)) : caret,
    };
  }

  // Même geste de suppression que le champ MAC strict : effacer un « : »
  // supprime son voisin utile. On conserve sa casse dans la requête brute.
  if (raw.length < shown.length && macUsefulChars(raw) === macUsefulChars(shown)) {
    const edited = applyMacEdit(raw, caret, shown, direction);
    const before = usefulCountBefore(raw, caret);
    const removed = direction === 'forward' ? before : before - 1;
    const positions = Array.from(previous.matchAll(/[a-z0-9]/gi), (match) => match.index!);
    const index = positions[removed];
    if (index !== undefined) {
      const value = previous.slice(0, index) + previous.slice(index + 1);
      return { value, caret: isMacSearchQuery(value) ? edited.caret : Math.min(index, value.length) };
    }
  }

  // Le préfixe/suffixe inchangé provient de l'ancien texte (pas de sa
  // version forcée en majuscules). Seule la zone saisie est remplacée.
  let start = 0;
  while (start < shown.length && start < raw.length && shown[start] === raw[start]) start++;
  let oldEnd = shown.length;
  let newEnd = raw.length;
  while (oldEnd > start && newEnd > start && shown[oldEnd - 1] === raw[newEnd - 1]) { oldEnd--; newEnd--; }
  // En fin d'affichage, le brut peut aussi contenir un espace, point ou
  // tiret saisi juste avant. L'ajout suivant se place APRÈS ce caractère,
  // sans le remplacer sous prétexte qu'il est masqué dans la vue MAC.
  const from = start === shown.length ? previous.length : rawPosition(previous, shown, start);
  const to = oldEnd === start ? from
    : oldEnd === shown.length ? previous.length : rawPosition(previous, shown, oldEnd);
  const inserted = raw.slice(start, newEnd);
  const value = previous.slice(0, from) + inserted + previous.slice(to);
  return {
    value,
    caret: isMacSearchQuery(value)
      ? caretForUsefulCount(usefulCountBefore(raw, caret))
      : Math.min(value.length, from + inserted.length + Math.max(0, caret - newEnd)),
  };
}
