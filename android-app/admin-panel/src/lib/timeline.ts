// =========================================================
//  timeline.ts — Mise en forme de la chronologie et des latences (pur)
// =========================================================
//  Aucun chiffre inventé : un segment sans mesure s'affiche « non mesuré ».

export const EVENT_LABELS: Record<string, string> = {
  ORDER_CREATED: 'Ordre créé (transaction engagée)',
  ORDER_SENT: 'Ordre publié vers la box',
  BOX_RECEIVED: 'Box : ordre reçu',
  BOX_APPLIED: 'Box : ordre appliqué',
  BOX_FAILED: 'Box : échec',
  ORDER_EXPIRED: 'Aucune réponse de la box (expiré)',
  CONFIG_REVISION_PUBLISHED: 'Révision de listes publiée',
  CONFIG_REVISION_ACKNOWLEDGED: 'Révision confirmée par la box',
  CONFIG_REVISION_REJECTED_BY_BOX: 'Révision refusée par la box (ancienne gardée)',
};

export function eventLabel(type: string): string {
  if (EVENT_LABELS[type]) return EVENT_LABELS[type];
  if (type.startsWith('activate.')) return `Panel : ${type === 'activate.renew' ? 'renouvellement' : 'activation'}`;
  if (type.startsWith('source.')) return `Panel : listes (${type.slice(7)})`;
  return type;
}

/// Gravité visuelle d'un événement : erreur, attention, normal.
export function eventTone(type: string): 'bad' | 'warn' | 'ok' {
  if (type === 'BOX_FAILED' || type === 'CONFIG_REVISION_REJECTED_BY_BOX') return 'bad';
  if (type === 'ORDER_EXPIRED') return 'warn';
  return 'ok';
}

export function formatMs(v: number | null | undefined): string {
  if (v == null || !Number.isFinite(v)) return 'non mesuré';
  if (v < 1000) return `${Math.round(v)} ms`;
  return `${(v / 1000).toFixed(v < 10000 ? 2 : 1)} s`;
}

export const SEGMENT_LABELS: Record<string, string> = {
  client_to_api: 'Navigateur → API (horloges différentes)',
  api: 'API → transaction engagée',
  publish: 'Transaction → publication',
  received: 'Publication → box a reçu',
  received_to_applied: 'Box a reçu → appliqué (heures serveur)',
  box_apply: 'Traitement sur la box (horloge de la box)',
  applied: 'Publication → box a appliqué',
  failed: 'Publication → échec box',
  end_to_end: 'API → box a appliqué (bout en bout)',
};

export const OP_LABELS: Record<string, string> = {
  activation: 'Activation',
  renewal: 'Renouvellement',
  source: 'Changement de listes',
  reset: 'Remise à neuf',
};
