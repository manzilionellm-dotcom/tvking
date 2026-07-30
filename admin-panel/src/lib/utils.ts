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

/// Normalise un timestamp « au format inconnu » en millisecondes Unix.
/// Le worker (déployé en parallèle du panel) peut renvoyer des secondes,
/// des millisecondes ou une chaîne ISO selon les versions — on accepte
/// tout, défensivement, et on renvoie null si c'est illisible.
export function toMillis(v: number | string | null | undefined): number | null {
  if (v == null) return null;
  if (typeof v === 'number' && Number.isFinite(v) && v > 0) {
    // Heuristique : < 10^12 ⇒ secondes (10^12 ms ≈ année 2001+ en ms).
    return v < 1e12 ? v * 1000 : v;
  }
  if (typeof v === 'string' && v.trim()) {
    const iso = Date.parse(v);
    if (!Number.isNaN(iso)) return iso;
    const n = Number(v);
    if (Number.isFinite(n) && n > 0) return n < 1e12 ? n * 1000 : n;
  }
  return null;
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
