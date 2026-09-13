// =========================================================
//  MacLink — une MAC cliquable PARTOUT → même fiche 360°
// =========================================================
//  Vague A : plus de tiroir maison. On ouvre DeviceSheet (le même
//  composant que la ligne Devices / le Cmd+K). Fallback local si le
//  Provider n'est pas monté (ne devrait plus arriver hors login).
// =========================================================

import { useState } from 'react';
import { cn } from '@/lib/utils';
import { DeviceSheet, useDeviceSheet } from '@/components/DeviceSheet';

export function MacLink({
  mac,
  className,
}: {
  mac: string | null | undefined;
  className?: string;
}) {
  const sheet = useDeviceSheet();
  const [local, setLocal] = useState(false);
  if (!mac) return <span className="text-ink-tertiary">—</span>;

  return (
    <>
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation();
          // open() no-op hors provider → on ouvre alors une fiche locale.
          try {
            sheet.open(mac);
          } catch {
            setLocal(true);
          }
        }}
        title="Voir la fiche complète"
        className={cn(
          'font-mono text-xs text-accent underline-offset-2 hover:underline',
          className,
        )}
      >
        {mac}
      </button>
      {local && <DeviceSheet mac={mac} onClose={() => setLocal(false)} />}
    </>
  );
}
