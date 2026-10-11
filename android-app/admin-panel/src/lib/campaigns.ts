export interface CampaignContent {
  type: 'advertisement' | 'event';
  title: string;
  body: string;
  url: string;
  cta: string;
  country: string;
  starts_at: number;
  ends_at: number;
  timezone: string;
}
export interface Campaign extends CampaignContent {
  id: string;
  status: 'draft' | 'scheduled' | 'paused' | 'archived';
  version: number;
  broadcast_id: number | null;
  delivery_active?: number | null;
  created_at: number;
  updated_at: number;
}

// « Disponible » ne signifie pas « vue » : aucune impression n'est inventée.
export function campaignState(item: Campaign, now: number) {
  if (item.status === 'draft' || item.status === 'archived') return item.status;
  if (item.ends_at <= now) return 'ended';
  if (item.broadcast_id && item.delivery_active === null) return 'removed';
  if (item.status === 'paused') return 'paused';
  if (item.broadcast_id) {
    if (item.delivery_active === 0) return 'paused';
    return 'available';
  }
  return item.starts_at > now ? 'scheduled' : 'ready';
}

export function toLocalInput(at: number): string {
  const date = new Date(at);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function parseLocalDate(input: string): number {
  const at = new Date(input).getTime();
  // Refuse aussi le 31 février et les heures inexistantes au changement
  // d'heure, que Date normaliserait silencieusement.
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(input) ||
      !Number.isFinite(at) || toLocalInput(at) !== input) {
    throw new Error('Date ou heure locale invalide.');
  }
  return at;
}
