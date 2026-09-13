// =========================================================
//  Téléphone → WhatsApp (wa.me)
// =========================================================
//  Pourquoi un parseur dédié : Lionel note souvent « Ahmed 06 12 34 56 78 »
//  ou « +33 7… » dans la note / le fiche client. On extrait les chiffres
//  pour ouvrir WhatsApp RÉEL (pas seulement copier un texte).
//  wa.me veut l'indicatif SANS + ni 00 (ex. 33612345678).
// =========================================================

/// Séquences qui ressemblent à un numéro (FR / intl), avec espaces et tirets.
const PHONE_CANDIDATE = /(?:\+|00)?[\d][\d\s./()-]{6,20}\d/g;

/// Normalise une saisie vers les chiffres wa.me, ou null si trop court.
export function normalizeWaDigits(raw: string): string | null {
  let s = raw.replace(/[^\d+]/g, '');
  if (s.startsWith('+')) s = s.slice(1);
  if (s.startsWith('00')) s = s.slice(2);
  // Mobile / fixe FR à 10 chiffres commençant par 0 → +33.
  if (s.startsWith('0') && s.length === 10) s = `33${s.slice(1)}`;
  if (s.length < 8 || s.length > 15) return null;
  return s;
}

/// Premier numéro trouvé dans les textes (note, tél client, label…).
export function parsePhoneDigits(
  ...blobs: Array<string | null | undefined>
): string | null {
  for (const blob of blobs) {
    if (!blob) continue;
    const matches = blob.match(PHONE_CANDIDATE);
    if (!matches) continue;
    for (const raw of matches) {
      const d = normalizeWaDigits(raw);
      if (d) return d;
    }
  }
  return null;
}

export function waMeUrl(digits: string | null, text: string): string {
  const q = encodeURIComponent(text);
  // Sans numéro : WhatsApp ouvre le sélecteur de contact avec le texte.
  return digits
    ? `https://wa.me/${digits}?text=${q}`
    : `https://wa.me/?text=${q}`;
}

export function openWhatsApp(digits: string | null, text: string): void {
  window.open(waMeUrl(digits, text), '_blank', 'noopener,noreferrer');
}
