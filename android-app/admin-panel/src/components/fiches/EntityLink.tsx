// Lien vers une fiche. Interrupteur coupé : le texte reste du texte,
// le clic ne change rien.
import type { ReactNode } from 'react';
import { FLAG_FICHES } from '@/lib/flags';
import { cibleAppareil, cibleListe, type FicheCible, type ListOrigin } from '@/lib/fiches';
import { normalizeMac } from '@/lib/utils';
import { useFicheOpener } from './fiche-context';
import { usePanelFlag } from './usePanelFlag';

export function EntityLink({
  cible,
  className,
  children,
  title,
}: {
  cible: FicheCible | null;
  className?: string;
  children: ReactNode;
  title?: string;
}) {
  const [on] = usePanelFlag(FLAG_FICHES);
  const open = useFicheOpener();
  if (!on || !cible) return <span className={className}>{children}</span>;
  return (
    <button
      type="button"
      className={'text-left underline-offset-2 hover:underline ' + (className || '')}
      title={title || 'Ouvrir la fiche'}
      onClick={(e) => {
        e.stopPropagation();
        open(cible);
      }}
    >
      {children}
    </button>
  );
}

/// N'affiche rien tant que l'interrupteur des fiches est coupé,
/// y compris l'espace autour. Pas de décalage dans la page.
export function ZoneFiche({
  className,
  children,
}: {
  className?: string;
  children: ReactNode;
}) {
  const [on] = usePanelFlag(FLAG_FICHES);
  if (!on) return null;
  return <div className={className}>{children}</div>;
}

/// Lien affiché seulement quand l'interrupteur des fiches est allumé
/// et que la MAC est complète. Sinon rien n'apparaît.
export function OuvrirFicheBox({
  mac,
  index,
  origin,
  children,
}: {
  mac: string;
  index?: number;
  origin?: ListOrigin;
  children: ReactNode;
}) {
  const [on] = usePanelFlag(FLAG_FICHES);
  const open = useFicheOpener();
  if (!on) return null;
  const adresse = normalizeMac(mac);
  const cible = index == null
    ? cibleAppareil({ mac: adresse })
    : cibleListe({ mac: adresse, index, origin });
  if (!cible) return null;
  return (
    <button
      type="button"
      className="text-sm font-medium text-accent-bright underline-offset-2 hover:underline"
      onClick={() => open(cible)}
    >
      {children}
    </button>
  );
}
