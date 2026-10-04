// =========================================================
//  flags.ts — Interrupteurs de repli du panel
// =========================================================
//  Tout changement de comportement reste coupé tant que la valeur
//  stockée n'est pas exactement « 1 ». Aucune valeur par défaut
//  n'allume un interrupteur.
//
//  Fichier pur : testé par fiches.test.ts. Le stockage réel
//  (localStorage) est branché dans l'interface, pas ici.
// =========================================================

/// Lignes et adresses ouvrent une fiche. Coupé : le panel reste comme avant.
export const FLAG_FICHES = 'panel.fiches-cliquables';

/// Bouton « masquer / réafficher une liste » sur la box.
/// Coupé : aucun envoi, le Worker ne connaît pas le drapeau hidden.
export const FLAG_LISTE_MASQUEE = 'panel.liste-masquee';

export interface FlagStore {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

/// Vrai seulement si la clé vaut « 1 ». Tout le reste (absent, vide, « 0 ») est coupé.
export function flagOn(store: FlagStore | null | undefined, key: string): boolean {
  if (!store) return false;
  try {
    return store.getItem(key) === '1';
  } catch {
    return false;
  }
}

/// « 1 » allume, « 0 » coupe. On n'écrit jamais une autre valeur.
export function writeFlag(store: FlagStore, key: string, on: boolean): void {
  store.setItem(key, on ? '1' : '0');
}
