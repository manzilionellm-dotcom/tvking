// Lecture / écriture des interrupteurs de repli (localStorage).
// Coupé si la clé n'est pas exactement « 1 ».
import { useEffect, useState } from 'react';
import { flagOn, writeFlag, type FlagStore } from '@/lib/flags';

const EVENT = 'panel-flags';

function store(): FlagStore | null {
  try {
    if (typeof localStorage === 'undefined') return null;
    return localStorage;
  } catch {
    return null;
  }
}

export function usePanelFlag(key: string): [boolean, (on: boolean) => void] {
  const [on, setOn] = useState(() => flagOn(store(), key));
  useEffect(() => {
    const sync = () => setOn(flagOn(store(), key));
    window.addEventListener(EVENT, sync);
    window.addEventListener('storage', sync);
    return () => {
      window.removeEventListener(EVENT, sync);
      window.removeEventListener('storage', sync);
    };
  }, [key]);
  const write = (value: boolean) => {
    const s = store();
    if (!s) return;
    writeFlag(s, key, value);
    setOn(value);
    window.dispatchEvent(new Event(EVENT));
  };
  return [on, write];
}
