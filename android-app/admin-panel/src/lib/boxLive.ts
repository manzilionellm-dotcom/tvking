// =========================================================
//  boxLive.ts — Texte « en direct » d'une box, sans recharger
// =========================================================
//  Le panel interroge /api/v1/boxes/live toutes les quelques
//  secondes. Ici, on transforme la réponse en une ligne lisible :
//    en ligne · v1.2.3 · appliqué à 12:03:04 · activation
//    hors ligne · en attente : suspension
//  Aucun secret n'est affiché : l'API n'en envoie pas.

export interface LiveOrder {
  id: number;
  kind: string;
  created_at?: number;
  applied_at?: number;
}

export interface BoxLive {
  id?: string;
  mac: string;
  online: boolean;
  last_seen_at: number;
  app_version?: string;
  app_build?: number;
  pending?: LiveOrder[];
  last_applied?: LiveOrder | null;
  fleet_pending?: LiveOrder[];
  fleet_last_applied?: LiveOrder | null;
}

export const KIND_LABEL: Record<string, string> = {
  activate: 'activation',
  renew: 'renouvellement',
  expire: 'expiration',
  suspend: 'suspension',
  resume: 'réactivation',
  block: 'blocage',
  source: 'changement de liste',
  source_clear: 'effacement de liste',
  transfer: 'transfert',
  device_delete: 'suppression',
  message: 'message',
  theme: 'thème',
  home: 'accueil',
  force_update: 'mise à jour forcée',
  featured: 'favori',
  ad: 'publicité',
  pricing: 'tarifs',
  feedback: 'avis',
  servers: 'serveurs',
  license: 'licence',
};

export function kindLabel(kind: string): string {
  return KIND_LABEL[kind] || kind || 'ordre';
}

/// « appliqué à 12:03:04 ». L'heure est calculée par [clock]
/// pour que le test n'ait pas besoin du fuseau de la machine.
export function appliedPhrase(epochMs: number, clock: (ms: number) => string): string {
  return `appliqué à ${clock(epochMs)}`;
}

export function localClock(epochMs: number): string {
  const d = new Date(epochMs);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

/// Ligne affichée dans le tableau. [now] sert à l'ancienneté.
export function liveSummary(
  row: BoxLive,
  clock: (ms: number) => string = localClock,
): string {
  const parts: string[] = [row.online ? 'en ligne' : 'hors ligne'];
  const version = (row.app_version || '').trim();
  if (version) parts.push(`v${version}`);
  else if (row.app_build) parts.push(`build ${row.app_build}`);

  const pending = row.pending && row.pending.length ? row.pending[0] : null;
  const fleetPending = row.fleet_pending && row.fleet_pending.length
    ? row.fleet_pending[0]
    : null;
  const waiting = pending || fleetPending;
  if (waiting) {
    parts.push(`en attente : ${kindLabel(waiting.kind)}`);
  }

  const applied = newestApplied(row.last_applied, row.fleet_last_applied);
  if (applied && applied.applied_at) {
    parts.push(`${appliedPhrase(applied.applied_at, clock)} · ${kindLabel(applied.kind)}`);
  }
  return parts.join(' · ');
}

function newestApplied(a?: LiveOrder | null, b?: LiveOrder | null): LiveOrder | null {
  if (a && a.applied_at && b && b.applied_at) {
    return a.applied_at >= b.applied_at ? a : b;
  }
  if (a && a.applied_at) return a;
  if (b && b.applied_at) return b;
  return null;
}

export function indexByMac(items: BoxLive[]): Record<string, BoxLive> {
  const out: Record<string, BoxLive> = {};
  for (const item of items) out[item.mac] = item;
  return out;
}
