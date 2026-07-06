import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

/// Helper standard shadcn pour merger des classes Tailwind sans
/// duplications. `cn('p-2', condition && 'p-4')` resout les conflits.
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/// Convertit des millisecondes Unix en string locale "12 mai 2026, 14:32".
export function formatDateTime(ms: number | null | undefined): string {
  if (!ms) return '—';
  try {
    return new Date(ms).toLocaleString('fr-FR', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch {
    return '—';
  }
}

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

/// Formate une saisie de MAC EN DIRECT au format attendu par le serveur :
/// MK:XX:XX:XX:XX:XX (5 paires hexadécimales, cf. MAC_RX côté worker).
/// L'admin tape juste les chiffres/lettres à la suite — le préfixe « MK: »
/// et les « : » entre chaque paire s'ajoutent tout seuls, impossible de se
/// tromper de format (demande : « j'écris des chiffres, les deux points
/// partent tout seuls, sinon rechercher/corriger prend du temps »).
/// À utiliser UNIQUEMENT sur un champ qui n'attend QUE la MAC — jamais sur
/// une barre de recherche libre (MAC OU nom OU serveur), où elle casserait
/// la saisie d'un nom de client.
export function formatMacInput(raw: string): string {
  const hexOnly = raw.toUpperCase().replace(/^MK:?/, '').replace(/[^0-9A-F]/g, '');
  const pairs = hexOnly.slice(0, 10).match(/.{1,2}/g) || [];
  return 'MK:' + pairs.join(':');
}
