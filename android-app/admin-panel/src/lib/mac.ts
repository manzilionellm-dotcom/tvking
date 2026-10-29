// =========================================================
//  Adresses MAC — formatage automatique pendant la saisie
// =========================================================
//  « MKFB88052B68 » → « MK:FB:88:05:2B:68 ». Majuscules, « : » toutes les
//  2 positions, séparateurs : - . espace acceptés (saisie ou collage).
//  Caractères utiles : A-Z et 0-9 (PAS de validation hexadécimale stricte :
//  les MAC personnalisées commencent par « MK »). 12 utiles / 17 affichés.
//  Aucune MAC stockée n'est modifiée : ce module ne sert qu'à l'affichage,
//  à la saisie et aux comparaisons.
// =========================================================

export const MAC_USEFUL_LENGTH = 12;
export const MAC_DISPLAY_LENGTH = 17;

/** Garde uniquement les caractères utiles (A-Z, 0-9), en majuscules. */
export function macUsefulChars(input: string | null | undefined): string {
  return String(input ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
}

/** Forme canonique pour comparer deux MAC (sans séparateur, majuscules, 12 max). */
export function normalizeMac(input: string | null | undefined): string {
  return macUsefulChars(input).slice(0, MAC_USEFUL_LENGTH);
}

/** « aabbccddeeff », « aa-bb-cc-dd-ee-ff »… → « AA:BB:CC:DD:EE:FF ». */
export function formatMacAddress(input: string | null | undefined): string {
  const useful = normalizeMac(input);
  return (useful.match(/.{1,2}/g) || []).join(':');
}

/** Vrai si les deux valeurs désignent la même MAC, quel que soit leur format. */
export function sameMac(a: string | null | undefined, b: string | null | undefined): boolean {
  const na = normalizeMac(a);
  return na.length > 0 && na === normalizeMac(b);
}

/** Recherche tolérante : « mkfb88 », « FB:88:05 », « fb-88 » trouvent « MK:FB:88:05:2B:68 ». */
export function macMatches(stored: string | null | undefined, query: string | null | undefined): boolean {
  const q = macUsefulChars(query);
  return q.length > 0 && macUsefulChars(stored).includes(q);
}

/** La saisie ressemble-t-elle à un morceau de MAC (et pas à un label/nom) ? */
export function looksLikeMac(query: string | null | undefined): boolean {
  const raw = String(query ?? '').trim();
  if (!raw || !/^[0-9A-Za-z:.\- ]+$/.test(raw)) return false;
  const u = macUsefulChars(raw);
  if (u.length < 4 || u.length > MAC_USEFUL_LENGTH) return false;
  // Un séparateur, un préfixe MK ou une suite hexadécimale = MAC probable.
  return /[:.\-]/.test(raw) || u.startsWith('MK') || /^[0-9A-F]+$/.test(u);
}

/** Position du curseur dans la valeur formatée juste après `useful` caractères utiles. */
export function caretForUsefulCount(useful: number): number {
  const n = Math.max(0, Math.min(useful, MAC_USEFUL_LENGTH));
  return n === 0 ? 0 : n + Math.floor((n - 1) / 2);
}

/** Nombre de caractères utiles situés avant `caret` dans `value`. */
export function usefulCountBefore(value: string, caret: number): number {
  return macUsefulChars(value.slice(0, Math.max(0, caret))).length;
}

export interface MacEditResult {
  value: string;
  caret: number;
}

export type MacDeleteDirection = 'backward' | 'forward';

/**
 * Applique une modification brute (frappe, collage, suppression) et renvoie
 * la valeur formatée + la position du curseur à restaurer.
 *
 * - `raw` / `rawCaret` : valeur et curseur de l'input APRÈS la modification.
 * - `previous` : valeur formatée AVANT la modification.
 * - `direction` : sens de la suppression si c'en est une (Retour arrière par défaut).
 */
export function applyMacEdit(
  raw: string,
  rawCaret: number | null | undefined,
  previous = '',
  direction: MacDeleteDirection = 'backward',
): MacEditResult {
  const caret = rawCaret ?? raw.length;
  let useful = macUsefulChars(raw);
  let before = usefulCountBefore(raw, caret);
  const prevUseful = macUsefulChars(previous);

  // Seul un « : » a été effacé (Retour arrière/Suppr juste à côté d'un
  // séparateur) : on efface le caractère utile voisin, sinon le formatage
  // remettrait le « : » et la touche semblerait bloquée.
  if (raw.length < formatMacAddress(previous).length && useful === prevUseful && useful.length > 0) {
    if (direction === 'forward') {
      if (before < useful.length) useful = useful.slice(0, before) + useful.slice(before + 1);
    } else if (before > 0) {
      useful = useful.slice(0, before - 1) + useful.slice(before);
      before -= 1;
    }
  }

  // MAC déjà complète : on refuse l'ajout au lieu de pousser la fin dehors.
  if (useful.length > MAC_USEFUL_LENGTH && prevUseful.length >= MAC_USEFUL_LENGTH) {
    const keep = formatMacAddress(previous);
    const added = useful.length - prevUseful.length;
    const prevCaret = caretForUsefulCount(Math.max(0, before - added));
    return { value: keep, caret: Math.min(prevCaret, keep.length) };
  }

  const value = formatMacAddress(useful);
  const n = Math.min(before, normalizeMac(useful).length);
  return { value, caret: Math.min(caretForUsefulCount(n), value.length) };
}
