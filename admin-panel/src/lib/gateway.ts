// =========================================================
//  gateway.ts — Client du panel vers la passerelle « maison mère »
// =========================================================
//  La passerelle est un service séparé (sur TON VPS), pas le Worker. Le
//  panel l'appelle directement (CORS activé côté passerelle). L'URL et le
//  jeton admin sont stockés localement dans le navigateur (panel admin).
// =========================================================

const LS_BASE = 'gw_base';
const LS_TOKEN = 'gw_token';

export function getGatewayConfig(): { base: string; token: string } {
  return {
    base: (localStorage.getItem(LS_BASE) || '').replace(/\/+$/, ''),
    token: localStorage.getItem(LS_TOKEN) || '',
  };
}
export function setGatewayConfig(base: string, token: string) {
  localStorage.setItem(LS_BASE, base.trim().replace(/\/+$/, ''));
  localStorage.setItem(LS_TOKEN, token.trim());
}
export function hasGatewayConfig(): boolean {
  const c = getGatewayConfig();
  return !!c.base && !!c.token;
}

export interface GwSession {
  key: string;
  state: string;
  subscribers: number;
  upstreamStatus: number;
  bytesIn: number;
  sinceMs: number;
}
export interface GwStatus {
  hub: {
    upstreamActive: number;
    liveSessions: number;
    vodSessions: number;
    providerMax: number;
    sessions: GwSession[];
  };
  sessions: { byUser: Record<string, number>; byFamily: Record<string, number> };
  users: { username: string; familyId: string; maxStreams: number }[];
  metrics: { counters: Record<string, number>; gauges: Record<string, number> };
  uptimeSec: number;
}
export interface GwUser { username: string; password: string; maxStreams: number }
export interface GwFamily { id: string; maxStreams: number; users: GwUser[] }

export class GatewayError extends Error {
  status: number;
  constructor(message: string, status: number) { super(message); this.status = status; }
}

async function call<T>(path: string, init?: RequestInit): Promise<T> {
  const { base, token } = getGatewayConfig();
  if (!base || !token) throw new GatewayError('Passerelle non configurée.', 0);
  let resp: Response;
  try {
    resp = await fetch(base + path, {
      ...init,
      headers: {
        authorization: `Bearer ${token}`,
        ...(init?.body ? { 'content-type': 'application/json' } : {}),
        ...(init?.headers || {}),
      },
    });
  } catch {
    // Réseau / CORS / mixed-content (passerelle en http derrière panel https).
    throw new GatewayError('Passerelle injoignable (URL, HTTPS ou CORS ?).', 0);
  }
  if (resp.status === 404) throw new GatewayError('Refusé (jeton admin invalide ?).', 404);
  if (!resp.ok) {
    let msg = `Erreur ${resp.status}.`;
    try { const j = await resp.json(); if (j && j.code) msg = j.code; } catch { /* */ }
    throw new GatewayError(msg, resp.status);
  }
  if (resp.status === 204) return undefined as T;
  return (await resp.json()) as T;
}

export const gatewayApi = {
  status: () => call<GwStatus>('/admin/status'),
  families: () => call<{ families: GwFamily[] }>('/admin/families'),
  createFamily: (id: string, maxStreams: number) =>
    call<{ ok: boolean; code?: string }>('/admin/families', {
      method: 'POST', body: JSON.stringify({ id, maxStreams }),
    }),
  deleteFamily: (id: string) =>
    call<{ ok: boolean }>(`/admin/families/${encodeURIComponent(id)}`, { method: 'DELETE' }),
  addUser: (familyId: string, username: string, password: string, maxStreams: number) =>
    call<{ ok: boolean; code?: string }>(
      `/admin/families/${encodeURIComponent(familyId)}/users`,
      { method: 'POST', body: JSON.stringify({ username, password, maxStreams }) },
    ),
  deleteUser: (familyId: string, username: string) =>
    call<{ ok: boolean }>(
      `/admin/families/${encodeURIComponent(familyId)}/users/${encodeURIComponent(username)}`,
      { method: 'DELETE' },
    ),
};

/** Génère un mot de passe court, lisible, pour un clone. */
export function genPassword(): string {
  const chars = 'abcdefghijkmnpqrstuvwxyz23456789';
  let s = '';
  for (let i = 0; i < 8; i++) s += chars[Math.floor(Math.random() * chars.length)];
  return s;
}

/** Formate des octets en unité lisible. */
export function fmtBytes(n: number): string {
  if (!n || n < 1024) return `${n || 0} o`;
  const units = ['Ko', 'Mo', 'Go', 'To'];
  let v = n / 1024, i = 0;
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
  return `${v.toFixed(1)} ${units[i]}`;
}
