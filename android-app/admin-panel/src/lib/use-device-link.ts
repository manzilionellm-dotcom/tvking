import { useEffect, useRef, useState } from 'react';
import { ApiError, devicesApi, isAbortError, type Device } from './api';

/** La MAC du lien n'est pas une fiche. Seul l'objet exact renvoyé par la liste
 * authentifiée peut ouvrir le centre de contrôle ; les autres résultats sont ignorés.
 */
export function useDeviceLink(mac: string | null, open: (device: Device | null) => void, logout: () => void) {
  const [error, setError] = useState<string | null>(null);
  const generation = useRef(0);
  useEffect(() => {
    const owner = ++generation.current;
    setError(null);
    if (!mac) return;
    const abort = new AbortController();
    open(null);
    devicesApi.list(mac, { limit: 100, offset: 0 }, abort.signal).then((result) => {
      if (abort.signal.aborted || owner !== generation.current) return;
      const exact = Array.isArray(result.items) ? result.items.filter((device) => device
        && typeof device.id === 'string' && device.id.length > 0 && device.mac === mac) : [];
      if (exact.length === 1) open(exact[0]);
      else setError('Cette fiche est introuvable ou n’est pas accessible avec ce compte.');
    }).catch((failure: unknown) => {
      if (abort.signal.aborted || owner !== generation.current || isAbortError(failure)) return;
      if (failure instanceof ApiError && failure.status === 401) logout();
      else setError('Cette fiche n’a pas pu être ouverte. Vérifie ton accès et réessaie.');
    });
    return () => { generation.current++; abort.abort(); };
  }, [mac, open, logout]);
  return error;
}
