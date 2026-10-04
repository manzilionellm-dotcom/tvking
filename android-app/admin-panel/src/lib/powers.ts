// Pouvoirs clients — logique pure du panel (testée dans powers.test.ts).
// Aucune URL de flux, aucun mot de passe ici.

/// Textes par défaut proposés à l'admin (modifiables avant l'envoi).
export const DEFAULT_PAYMENT_MESSAGE =
  'Merci de régler votre abonnement pour continuer à profiter du service.';

/// Libellés FR lisibles des actions du journal (clé technique → texte).
const ACTION_LABELS: Record<string, string> = {
  'client.block': 'Blocage / déblocage',
  'client.payment_request.set': 'Demande de paiement envoyée',
  'client.payment_request.clear': 'Demande de paiement retirée',
  'client.message.send': 'Message envoyé',
  'client.message.clear': 'Message retiré',
  'client.extend': 'Abonnement prolongé',
  'client.suspend': 'Abonnement suspendu',
  'client.resume': 'Abonnement repris',
  'client.refresh': 'Relecture forcée',
  'client.note.add': 'Note ajoutée',
  'client.note.delete': 'Note supprimée',
  'trial.extend': 'Jours d’essai ajoutés',
  'device.block': 'Blocage / déblocage',
  'source.set': 'Liste poussée',
  'source.delete': 'Liste effacée',
};

export function describeAction(action: string): string {
  return ACTION_LABELS[action] ?? action;
}

/// Jours à ajouter : entier de 1 à 365 (même règle que le serveur).
export function parseDays(raw: string): { days: number } | { error: string } {
  const s = raw.trim();
  if (!/^[0-9]+$/.test(s)) return { error: 'Indique un nombre entier de jours.' };
  const n = Number(s);
  if (n < 1) return { error: 'Indique au moins 1 jour.' };
  if (n > 365) return { error: 'Maximum 365 jours à la fois.' };
  return { days: n };
}

/// Durée d'affichage d'un message, en heures (vide = sans limite).
export function parseHours(raw: string): { hours: number | null } | { error: string } {
  const s = raw.trim();
  if (s === '') return { hours: null };
  const n = Number(s.replace(',', '.'));
  if (!Number.isFinite(n) || n <= 0 || n > 2160) {
    return { error: 'Durée invalide (1 à 2160 heures).' };
  }
  return { hours: n };
}

/// Lien de paiement : vide ou https (sans identifiants), comme le serveur.
export function checkPayLink(raw: string): { link: string | null } | { error: string } {
  const s = raw.trim();
  if (!s) return { link: null };
  let u: URL;
  try { u = new URL(s); } catch { return { error: 'Lien de paiement invalide.' }; }
  if (u.protocol !== 'https:' || u.username || u.password) {
    return { error: 'Le lien de paiement doit être en https.' };
  }
  return { link: u.href };
}

export interface PaymentForm {
  message: string;
  amount: string;
  currency: string;
  link: string;
}

/// Corps de PUT /devices/:id/payment-request (ou une erreur lisible).
export function buildPaymentPayload(f: PaymentForm):
  | { payload: { message: string; amount: string; currency: string; link?: string } }
  | { error: string } {
  const link = checkPayLink(f.link);
  if ('error' in link) return { error: link.error };
  const payload: { message: string; amount: string; currency: string; link?: string } = {
    message: f.message.trim() || DEFAULT_PAYMENT_MESSAGE,
    amount: f.amount.trim(),
    currency: f.currency.trim().toUpperCase(),
  };
  if (link.link) payload.link = link.link;
  return { payload };
}
