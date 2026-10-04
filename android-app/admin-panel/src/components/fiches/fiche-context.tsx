// Contexte d'ouverture des fiches. Séparé de l'hôte pour éviter
// un import circulaire avec les liens cliquables.
import { createContext, useContext, type ReactNode } from 'react';
import type { FicheCible } from '@/lib/fiches';

const FicheCtx = createContext<(cible: FicheCible) => void>(() => {});

export function FicheProvider({
  open,
  children,
}: {
  open: (cible: FicheCible) => void;
  children: ReactNode;
}) {
  return <FicheCtx.Provider value={open}>{children}</FicheCtx.Provider>;
}

export function useFicheOpener(): (cible: FicheCible) => void {
  return useContext(FicheCtx);
}
