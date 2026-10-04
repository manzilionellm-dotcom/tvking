import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

/// Helper standard shadcn pour merger des classes Tailwind sans
/// duplications. `cn('p-2', condition && 'p-4')` resout les conflits.
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/// MAC d'appareil : « AD:A6:98:70:6A » (sans MK:, avec tirets, espaces
/// ou rien) devient MK:AD:A6:98:70:6A. Logique pure dans mac.ts.
export { normalizeMac, isValidMac, displayMac } from './mac';

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
