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

/// Vrai si la saisie ressemble à un début de MAC, pas à un nom de client.
///
/// Pourquoi : Lionel tape `80` puis `7860074F` dans la recherche Devices.
/// On veut poser les `:` tout seuls (`80:78:60:07:4F`) SANS transformer
/// « Jean » ou « Ada » en hex. Un nom fait de seules lettres A–F
/// (rare) reste un nom tant qu'il n'y a ni chiffre, ni `:`, ni préfixe
/// `MK:`.
///
/// Aligné sur `cloudflare/mac_identity.js` — si tu changes l'un, change
/// l'autre, sinon le panel formate et le Worker ne retrouve plus la ligne.
export function looksLikeMacTyping(raw: string): boolean {
  const t = raw.trim();
  if (!t) return false;
  const mk = /^MK:?/i.test(t);
  const rest = mk ? t.replace(/^MK:?/i, '') : t;
  // Séparateurs classiques au collage : : - . espace
  if (/[^0-9A-Fa-f:.\-\s]/.test(rest)) return false;
  const hex = rest.replace(/[^0-9A-Fa-f]/g, '');
  if (mk) return true;
  if (!hex) return false;
  if (/[0-9]/.test(hex)) return true;
  if (/[:.\-]/.test(rest)) return true;
  return false;
}

/// Formate une saisie MAC AU FIL DE L'EAU (recherche + collage).
///
/// Règles (demande Lionel, 13/09/2026 — champ recherche `/devices`) :
///  - on ne garde que l'hex (les `:` déjà là, tirets, points, espaces
///    sont juste des séparateurs, on les réécrit) ;
///  - un `:` tous les 2 caractères hex ;
///  - max 6 octets (12 hex) — MAC IEEE classique ; nos MAC internes
///    font 5 octets après `MK:`, 12 laisse de la marge si on colle
///    une adresse « vraie » ;
///  - le préfixe `MK:` déjà tapé / collé est CONSERVÉ, jamais inventé
///    (sinon la barre de recherche écrirait `MK:` dès la première
///    lettre et casserait « Martin ») ;
///  - si ça ne ressemble pas à une MAC → on rend `raw` tel quel
///    (recherche par nom, note, téléphone).
///
/// Exemples :
///   `807860074F`     → `80:78:60:07:4F`
///   `80:78:60:07:4F` → `80:78:60:07:4F`  (collage déjà ponctué)
///   `MK807860074F`   → `MK:80:78:60:07:4F`
///   `Jean`           → `Jean`
export function formatMacAsYouType(raw: string): string {
  if (!raw) return '';
  if (!looksLikeMacTyping(raw)) return raw;

  const mk = /^MK:?/i.test(raw.trimStart());
  const body = mk ? raw.replace(/^\s*MK:?/i, '') : raw;
  const hex = body.toUpperCase().replace(/[^0-9A-F]/g, '').slice(0, 12);
  const pairs = hex.match(/.{1,2}/g) || [];
  const joined = pairs.join(':');
  if (mk) return joined ? `MK:${joined}` : 'MK:';
  return joined;
}

/// Formate une saisie de MAC EN DIRECT au format attendu par le serveur :
/// MK:XX:XX:XX:XX:XX (5 paires hexadécimales, cf. MAC_RX côté worker).
/// L'admin tape juste les chiffres/lettres à la suite — le préfixe « MK: »
/// et les « : » entre chaque paire s'ajoutent tout seuls, impossible de se
/// tromper de format (demande : « j'écris des chiffres, les deux points
/// partent tout seuls, sinon rechercher/corriger prend du temps »).
///
/// Construit SUR `formatMacAsYouType` (un seul endroit qui pose les `:`)
/// puis force `MK:` + 10 hex — contrat Worker / activate.
/// À utiliser UNIQUEMENT sur un champ qui n'attend QUE la MAC — jamais
/// tout seul sur une barre de recherche libre (utiliser
/// `formatMacAsYouType`, qui refuse de manger un nom de client).
export function formatMacInput(raw: string): string {
  const seeded = /^MK/i.test(raw.trim()) ? raw : `MK:${raw}`;
  const typed = formatMacAsYouType(seeded);
  const hexOnly = typed.toUpperCase().replace(/^MK:?/, '').replace(/[^0-9A-F]/g, '');
  const pairs = hexOnly.slice(0, 10).match(/.{1,2}/g) || [];
  return 'MK:' + pairs.join(':');
}

/// Recherche texte ↔ MAC stockée `MK:80:78:…` : accepte `80:78`,
/// `8078`, `MK:80:78`. Sert les filtres client (En ligne, Références)
/// pour rester alignés sur le LIKE Worker.
export function macTextMatches(mac: string, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  const m = mac.toLowerCase();
  if (m.includes(q)) return true;
  if (!looksLikeMacTyping(query)) return false;
  const qh = q.replace(/[^0-9a-f]/g, '');
  if (qh.length < 2) return false;
  return m.replace(/[^0-9a-f]/g, '').includes(qh);
}
