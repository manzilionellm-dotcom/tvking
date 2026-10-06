// =========================================================
//  delivery.ts — « Suivi de l'envoi » : ce que la box a VRAIMENT fait
// =========================================================
//  Avant le 06/10/2026, l'écran Listes affichait « la box est prévenue à
//  l'instant » dès que le serveur répondait, sans aucune nouvelle de la
//  télé. Désormais chaque envoi rend un `order_id` ; le panel relit l'état
//  de CET ordre (GET /api/v1/orders?mac=…), alimenté par les accusés de la
//  box (RECEIVED, puis APPLIED ou FAILED). Le texte dit seulement ce qui
//  est prouvé par le dernier accusé reçu.
//
//  Fichier pur : testé par delivery.test.ts.
// =========================================================

export interface OrderLike {
  order_id: string;
  state?: string | null;
  error_message?: string | null;
  error_code?: string | null;
}

export type DeliveryKind = 'wait' | 'received' | 'ok' | 'failed' | 'late';

/// Intervalle de relecture de l'ordre, et abandon de la relecture (le
/// serveur passe lui-même un ordre sans réponse à « expired » après 10 min).
export const DELIVERY_POLL_MS = 1500;
export const DELIVERY_GIVE_UP_MS = 11 * 60 * 1000;

/// L'ordre [orderId] dans la liste rendue par le serveur (absent = null).
export function findOrder(items: OrderLike[] | null | undefined, orderId: string): OrderLike | null {
  return (items || []).find((o) => o.order_id === orderId) ?? null;
}

/// Texte et nature de l'état. `null` (ordre pas encore listé) = attente.
export function deliveryStatus(order: OrderLike | null, verb: 'load' | 'remove' = 'load'): { kind: DeliveryKind; text: string; done: boolean } {
  const state = String(order?.state ?? 'sent').toLowerCase();
  if (state === 'received') {
    return {
      kind: 'received',
      text: verb === 'remove' ? 'Ordre reçu par la box. Retrait en cours…' : 'Ordre reçu par la box. Chargement en cours…',
      done: false,
    };
  }
  if (state === 'applied') {
    return {
      kind: 'ok',
      text: verb === 'remove' ? 'Retrait confirmé par la box.' : 'Listes confirmées sur la box.',
      done: true,
    };
  }
  if (state === 'failed') {
    const why = String(order?.error_message || order?.error_code || 'raison non transmise').trim().replace(/[.\s]+$/, '');
    return {
      kind: 'failed',
      text: verb === 'remove' ? `La box n’a pas appliqué le retrait : ${why}.` : `La box n’a pas chargé la liste : ${why}.`,
      done: true,
    };
  }
  if (state === 'expired') {
    return {
      kind: 'late',
      text: 'La box n’a pas répondu en 10 minutes (éteinte ou hors ligne). Elle appliquera la liste à sa prochaine connexion.',
      done: true,
    };
  }
  return { kind: 'wait', text: 'Enregistrée sur le serveur. En attente de la box…', done: false };
}
