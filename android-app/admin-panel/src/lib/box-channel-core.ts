// Forme des messages du canal panel ↔ Worker.
// Aucun mot de passe, aucun identifiant, aucune adresse de flux.
// Voir docs/CANAL-TEMPS-REEL.md.

export interface ChannelEvent {
  v: number;
  seq?: number;
  type: string;
  mac: string;
  at: number;
  order_id?: string;
  trace_id?: string;
  kind?: string;
  state?: string;
  config_rev?: number | null;
  applied_rev?: number | null;
  online?: boolean;
  last_seen_at?: number;
  elapsed_ms?: number | null;
}

const SECRET_KEYS = new Set([
  'password',
  'username',
  'server_url',
  'm3u_url',
  'epg_url',
  'secret',
  'token',
  'ticket',
  'authorization',
  'device_secret',
]);

function hasSecretKey(value: unknown): boolean {
  if (!value || typeof value !== 'object') return false;
  for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
    if (SECRET_KEYS.has(key.toLowerCase())) return true;
    if (hasSecretKey(child)) return true;
  }
  return false;
}

function readFrame(raw: string): Record<string, unknown> | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed) || hasSecretKey(parsed)) return null;
  const row = parsed as Record<string, unknown>;
  if (row.v !== undefined && row.v !== 1) return null;
  return row;
}

export function isChannelHello(raw: string): boolean {
  const row = readFrame(raw);
  return row?.v === 1 && row.type === 'hello';
}

/// Les reçus et présences du nouveau Worker n'ont pas de séquence.
/// Ils déclenchent une relecture HTTP : seul l'ordre exact relu dans
/// ordersApi peut confirmer une opération à l'utilisateur.
export function parseChannelEvent(raw: string): ChannelEvent | null {
  const row = readFrame(raw);
  if (!row) return null;
  if (row.type === 'hello') return null;
  const type = typeof row.type === 'string' ? row.type : '';
  const mac = typeof row.mac === 'string' ? row.mac : '';
  const at = typeof row.at === 'number' ? row.at : 0;
  if (!type || !mac || !Number.isFinite(at) || at < 0) return null;
  const event: ChannelEvent = { v: 1, type, mac, at };
  if (row.seq !== undefined) {
    const seq = typeof row.seq === 'number' ? row.seq : Number(row.seq);
    if (!Number.isSafeInteger(seq) || seq <= 0) return null;
    event.seq = seq;
  } else if (type === 'receipt') {
    if (typeof row.order_id !== 'string' || !row.order_id.trim() ||
        typeof row.kind !== 'string' || !row.kind.trim() ||
        !['created', 'queued', 'sent', 'received', 'applied', 'failed', 'expired'].includes(String(row.state))) return null;
    event.kind = row.kind;
    event.state = String(row.state);
    for (const key of ['config_rev', 'applied_rev', 'elapsed_ms'] as const) {
      const value = row[key];
      if (value === undefined) continue;
      if (value !== null && (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0)) return null;
      event[key] = value as number | null;
    }
  } else if (type === 'presence') {
    if (typeof row.online !== 'boolean' || typeof row.last_seen_at !== 'number' ||
        !Number.isFinite(row.last_seen_at) || row.last_seen_at < 0) return null;
    event.online = row.online;
    event.last_seen_at = row.last_seen_at;
  } else {
    return null;
  }
  for (const key of ['order_id', 'trace_id'] as const) {
    if (typeof row[key] === 'string' && row[key]) event[key] = row[key];
  }
  return event;
}
