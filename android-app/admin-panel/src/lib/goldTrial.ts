// Une lecture à la fois ; quitter la page annule la requête et le prochain tick.
export function pollTrials(load: (signal: AbortSignal) => Promise<void>, interval = 1500) {
  let stopped = false;
  let timer: ReturnType<typeof setTimeout>;
  let controller: AbortController;
  async function tick() {
    controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);
    try { await load(controller.signal); }
    catch { /* Le prochain tick retente ; l'appelant affiche l'erreur métier. */ }
    finally {
      clearTimeout(timeout);
      if (!stopped) timer = setTimeout(tick, interval);
    }
  }
  void tick();
  return () => { stopped = true; clearTimeout(timer); controller?.abort(); };
}

export function trialMac(value: string): string | null {
  const mac = value.trim().replaceAll('-', ':').toUpperCase();
  return /^(?:MK|[0-9A-F]{2})(?::[0-9A-F]{2}){5}$/.test(mac) ? mac : null;
}

export function trialDate(value: unknown): string {
  if (value === null || value === undefined || value === '') return '—';
  const numeric = typeof value === 'number' ? value : Number(value);
  const date = Number.isFinite(numeric)
    ? new Date(numeric < 100000000000 ? numeric * 1000 : numeric)
    : new Date(String(value));
  return Number.isFinite(date.getTime()) ? date.toLocaleString('fr-FR') : '—';
}

export type HistoryRow = { key: string; date: unknown; event: string; expire: unknown; line: string; ip: string; version: string };

// Projection explicite : jamais de JSON brut qui pourrait afficher des accès IPTV.
export function historyRows(values: unknown[], prefix: string): HistoryRow[] {
  return values.flatMap((value, index) => {
    if (!value || typeof value !== 'object') return [];
    const row = value as Record<string, unknown>;
    const text = (v: unknown) => typeof v === 'string' || typeof v === 'number' ? String(v) : '—';
    return [{ key: `${prefix}-${text(row.id)}-${index}`, date: row.created_at ?? row.date,
      event: text(row.reason ?? row.event ?? row.action ?? row.state ?? (row.kind ? `${row.kind}.${row.status ?? ''}` : row.type)),
      expire: row.expire ?? row.expires_at, line: text(row.line_id ?? row.gold_line_id ?? row.gold_user_id),
      ip: text(row.ip), version: text(row.app_version) }];
  });
}
