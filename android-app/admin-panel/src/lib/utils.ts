import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

/// Helper standard shadcn pour merger des classes Tailwind sans
/// duplications. `cn('p-2', condition && 'p-4')` resout les conflits.
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/// MAC d'appareil telle que le serveur l'attend : MK:XX:XX:XX:XX:XX.
export function normalizeMac(raw: string): string {
  return raw.trim().toUpperCase();
}

export function isValidMac(raw: string): boolean {
  return /^MK(?::[0-9A-F]{2}){5}$/i.test(normalizeMac(raw));
}

/// Date lisible en heure de Paris (robust.ts : secondes ou ms,
/// fuseau fixe, valeur vide → « — »).
export { formatDateTime } from './robust';

/// Formate un montant en cents → "12,99 €". Devise par defaut EUR.
export function formatMoney(cents: number, currency = 'EUR'): string {
  try {
    return new Intl.NumberFormat('fr-FR', {
      style: 'currency',
      currency,
    }).format(cents / 100);
  } catch {
    return `${(cents / 100).toFixed(2)} ${currency}`;
  }
}
