// =========================================================
//  robust.ts — gardes pures du panel (testées sans navigateur)
// =========================================================
//  Le Worker et le navigateur ne parlent pas toujours la même langue :
//  corps vide, liste énorme, date en secondes, fuseau du portable.
//  Tout ce qui peut planter ou mentir est ramené ici, pour qu'un test
//  Node puisse le casser puis le vérifier.
// =========================================================

/// Heure civile affichée à tout le monde : Paris, pas le fuseau du
/// portable de l'admin (sinon deux personnes ne lisent pas la même
/// heure d'expiration).
export const PANEL_TIME_ZONE = 'Europe/Paris';

/// Taille de page demandée par le panel. Le Worker refuse au-delà.
export const LIST_PAGE_SIZE = 100;

/// Plafond de lignes dessinées. Au-delà, le navigateur rame : on coupe
/// et on signale que la liste est tronquée.
export const MAX_LIST_RENDER = 200;

export interface ListPage<T> {
  items: T[];
  total: number;
  limit: number;
  offset: number;
  truncated: boolean;
  dropped: number;
}

/// Millisecondes, ou null si vide / 0 / illisible.
/// < 1e11 → secondes Unix (vieilles lignes).
export function toEpochMs(value: unknown): number | null {
  if (value == null || value === '') return null;
  const n = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(n) || n <= 0) return null;
  if (n < 1e11) return Math.round(n * 1000);
  return n;
}

/// "15 juin 2026, 14:00" en heure de Paris. Vide → « — ».
export function formatDateTime(value: unknown): string {
  const ms = toEpochMs(value);
  if (ms == null) return '—';
  const d = new Date(ms);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleString('fr-FR', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: PANEL_TIME_ZONE,
  });
}

/// Minuit UTC du jour civil à Paris, pour compter des jours calendaires
/// (le quotient par 86 400 000 s se trompe d'un jour autour de minuit
/// et des changements d'heure).
export function parisDayIndex(ms: number): number {
  const ymd = new Intl.DateTimeFormat('en-CA', {
    timeZone: PANEL_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(ms);
  return Math.round(Date.parse(`${ymd}T00:00:00Z`) / 86400000);
}

/// Jours calendaires Paris entre maintenant et l'expiration.
/// null si pas de date (à vie). Négatif si le jour est passé.
export function calendarDaysUntil(expires: unknown, now: number): number | null {
  const ms = toEpochMs(expires);
  if (ms == null) return null;
  return parisDayIndex(ms) - parisDayIndex(now);
}

/// Phrase lue dans la fiche appareil et la colonne « expire le ».
export function expiryPhrase(expires: unknown, now = Date.now()): string {
  const ms = toEpochMs(expires);
  if (ms == null) return 'À vie';
  const when = formatDateTime(ms);
  const days = calendarDaysUntil(ms, now) ?? 0;
  if (ms <= now) {
    return days < 0 ? `Expiré le ${when} · depuis ${-days} j` : `Expiré le ${when}`;
  }
  if (days <= 0) return `Expire aujourd'hui · ${when}`;
  return `${days} j restant${days > 1 ? 's' : ''} · ${when}`;
}

/// Drapeau uniquement pour un vrai code ISO2. « ?? » ou « 12 » ne doit
/// pas produire un caractère illisible, ni lever d'exception.
export function flagEmoji(code: string | null | undefined): string {
  if (!code || !/^[a-zA-Z]{2}$/.test(code)) return '🏳️';
  const up = code.toUpperCase();
  const A = 0x1f1e6;
  return String.fromCodePoint(A + (up.charCodeAt(0) - 65), A + (up.charCodeAt(1) - 65));
}

/// « il y a 3 min ». Accepte les secondes comme les millisecondes.
export function agoLabel(value: unknown, now = Date.now()): string {
  const ts = toEpochMs(value);
  if (ts == null) return '—';
  const s = Math.floor((now - ts) / 1000);
  if (s < 5) return 'à l\'instant';
  if (s < 60) return `il y a ${s}s`;
  if (s < 3600) return `il y a ${Math.floor(s / 60)} min`;
  if (s < 86400) return `il y a ${Math.floor(s / 3600)} h`;
  return `il y a ${Math.floor(s / 86400)} j`;
}

export function readListPage<T>(raw: unknown): ListPage<T> {
  const o = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  const all = Array.isArray(o.items) ? (o.items as T[]) : [];
  const dropped = all.length > MAX_LIST_RENDER ? all.length - MAX_LIST_RENDER : 0;
  const items = dropped > 0 ? all.slice(0, MAX_LIST_RENDER) : all;
  const totalNum = Number(o.total);
  const total = Number.isFinite(totalNum) ? totalNum : all.length;
  const limitNum = Number(o.limit);
  const limit = Number.isFinite(limitNum) ? limitNum : items.length;
  const offsetNum = Number(o.offset);
  const offset = Number.isFinite(offsetNum) && offsetNum > 0 ? offsetNum : 0;
  const serverTruncated = o.truncated === true || offset + all.length < total;
  return {
    items,
    total,
    limit,
    offset,
    truncated: serverTruncated || dropped > 0,
    dropped,
  };
}

export interface OnlineItem {
  mac: string;
  ip: string;
  country: string;
  lastSeen: number;
  channel: string;
}

export interface OnlineView {
  onlineCount: number;
  todayCount: number;
  byCountry: [string, number][];
  items: OnlineItem[];
}

/// La page « En ligne » plantait si `byCountry` ou `items` manquait
/// (Object.entries(undefined), ou items.length sur undefined).
export function onlineView(raw: unknown): OnlineView {
  const o = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  const src = o.byCountry && typeof o.byCountry === 'object' && !Array.isArray(o.byCountry)
    ? (o.byCountry as Record<string, unknown>)
    : {};
  const byCountry: [string, number][] = [];
  for (const [k, v] of Object.entries(src)) {
    if (!/^[a-zA-Z]{2}$/.test(k)) continue;
    byCountry.push([k.toUpperCase(), Number(v) || 0]);
  }
  byCountry.sort((a, b) => b[1] - a[1]);
  const itemsIn = Array.isArray(o.items) ? o.items : [];
  const items = itemsIn.slice(0, MAX_LIST_RENDER).map((d) => {
    const row = d && typeof d === 'object' ? (d as Record<string, unknown>) : {};
    const country = typeof row.country === 'string' && /^[a-zA-Z]{2}$/.test(row.country)
      ? row.country.toUpperCase()
      : '';
    return {
      mac: row.mac == null ? '' : String(row.mac),
      ip: row.ip == null ? '' : String(row.ip),
      country,
      lastSeen: toEpochMs(row.lastSeen) || 0,
      channel: row.channel == null ? '' : String(row.channel),
    };
  });
  return {
    onlineCount: Number(o.onlineCount) || 0,
    todayCount: Number(o.todayCount) || 0,
    byCountry,
    items,
  };
}

/// Recherche du carnet. Une ligne sans `usernames` ne doit pas faire
/// tomber toute la page (it.usernames.some sur undefined).
export function referenceMatches(it: unknown, q: string): boolean {
  const t = q.trim().toLowerCase();
  if (!t) return true;
  const row = it && typeof it === 'object' ? (it as Record<string, unknown>) : {};
  const mac = String(row.mac || '').toLowerCase();
  const name = String(row.customer_name || '').toLowerCase();
  const users = Array.isArray(row.usernames) ? row.usernames : [];
  const servers = Array.isArray(row.servers) ? row.servers : [];
  return mac.includes(t)
    || name.includes(t)
    || users.some((u) => String(u || '').toLowerCase().includes(t))
    || servers.some((s) => String(s || '').toLowerCase().includes(t));
}

export interface HttpRead {
  ok: boolean;
  status: number;
  code: string;
  message: string;
  clearToken: boolean;
  json: unknown;
}

/// Traduit le corps HTTP du Worker. Un 200 vide ou du HTML ne doit
/// pas devenir `null` puis `null.items` dans la page.
export function interpretHttpResult(status: number, text: string): HttpRead {
  let json: unknown = null;
  let parsed = false;
  const trimmed = text.trim();
  if (!trimmed) {
    parsed = true;
    json = null;
  } else {
    try {
      json = JSON.parse(trimmed);
      parsed = true;
    } catch {
      parsed = false;
    }
  }
  const obj = json && typeof json === 'object' ? (json as Record<string, unknown>) : null;
  if (status < 200 || status >= 300) {
    const message = obj && typeof obj.message === 'string' && obj.message
      ? obj.message
      : `HTTP ${status}`;
    const code = obj && typeof obj.error === 'string' && obj.error ? obj.error : 'http_error';
    return { ok: false, status, code, message, clearToken: status === 401, json };
  }
  if (!parsed || json === null || typeof json !== 'object') {
    return {
      ok: false,
      status,
      code: 'bad_response',
      message: 'Réponse du serveur illisible.',
      clearToken: false,
      json: null,
    };
  }
  return { ok: true, status, code: '', message: '', clearToken: false, json };
}

export function networkFailureMessage(): string {
  return 'Connexion impossible. Vérifiez le réseau, puis réessayez.';
}

export function isAbortError(e: unknown): boolean {
  return !!e && typeof e === 'object' && (e as { name?: string }).name === 'AbortError';
}

/// Ignore une réponse arrivée après une recherche plus récente.
export function createGeneration() {
  let current = 0;
  return {
    next(): number {
      current += 1;
      return current;
    },
    isCurrent(id: number): boolean {
      return id === current;
    },
  };
}

/// Un seul appel à la fois. Le deuxième clic pendant que le premier
/// n'a pas fini ne part pas (double débit de crédits, double transfert).
export function createSingleFlight() {
  let running = false;
  return {
    get pending(): boolean {
      return running;
    },
    async run<T>(fn: () => Promise<T>): Promise<T | undefined> {
      if (running) return undefined;
      running = true;
      try {
        return await fn();
      } finally {
        running = false;
      }
    },
  };
}

/// Annule la requête précédente quand l'utilisateur retape.
export function createAbortBag() {
  let ctrl: AbortController | null = null;
  return {
    next(): AbortSignal {
      ctrl?.abort();
      ctrl = new AbortController();
      return ctrl.signal;
    },
    abort(): void {
      ctrl?.abort();
    },
  };
}

export function listQuery(
  path: string,
  q?: string,
  page?: { limit?: number; offset?: number },
): string {
  const p = new URLSearchParams();
  if (q) p.set('q', q);
  if (page?.limit) p.set('limit', String(page.limit));
  if (page?.offset) p.set('offset', String(page.offset));
  const s = p.toString();
  return s ? `${path}?${s}` : path;
}

/// Sauvegarde JSON compacte. L'indentation doublait la mémoire sur
/// un dump de plusieurs milliers de lignes et figeait l'onglet.
export function serializeBackup(dump: unknown): string {
  return JSON.stringify(dump);
}
