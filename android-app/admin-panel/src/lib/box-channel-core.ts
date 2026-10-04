// Forme des messages du canal panel ↔ Worker.
// Aucun mot de passe, aucun identifiant, aucune adresse de flux.
// Voir docs/CANAL-TEMPS-REEL.md.

export interface ChannelEvent {
  v: number;
  seq: number;
  type: string;
  mac: string;
  at: number;
}

const SECRET_KEYS = new Set([
  'password',
  'username',
  'server_url',
  'm3u_url',
  'epg_url',
  'secret',
  'token',
]);

function hasSecretKey(value: unknown): boolean {
  if (!value || typeof value !== 'object') return false;
  for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
    if (SECRET_KEYS.has(key.toLowerCase())) return true;
    if (hasSecretKey(child)) return true;
  }
  return false;
}

/// null si le texte n'est pas un événement du contrat, ou s'il
/// contient une clé interdite.
export function parseChannelEvent(raw: string): ChannelEvent | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== 'object' || hasSecretKey(parsed)) return null;
  const row = parsed as Record<string, unknown>;
  if (row.type === 'hello') return null;
  const seq = typeof row.seq === 'number' ? row.seq : Number(row.seq);
  const type = typeof row.type === 'string' ? row.type : '';
  const mac = typeof row.mac === 'string' ? row.mac : '';
  const at = typeof row.at === 'number' ? row.at : 0;
  if (!Number.isFinite(seq) || seq <= 0 || !type || !mac) return null;
  return { v: 1, seq, type, mac, at };
}
