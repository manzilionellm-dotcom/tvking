// =========================================================
//  api.ts — Client HTTP du Worker API v1
// =========================================================
//  Wrapper minimal autour de fetch() avec :
//    - injection automatique du JWT (Authorization: Bearer …)
//    - JSON encode/decode
//    - gestion d'erreurs typee
//
//  Le JWT est stocke en localStorage sous la cle 'auth_token'.
//  Pas de cookies httpOnly pour la Phase 1 (l'app et l'API sont
//  cross-origin, on resterait coince sur SameSite). On passera
//  a un cookie cross-domain seulement quand le panel et le Worker
//  partageront le meme domaine racine (Phase 2).
// =========================================================

const TOKEN_KEY = 'auth_token';

/// URL de base de l'API. En production le panel est servi par
/// Cloudflare Pages sur un sous-domaine (ex: admin.7themotion.com)
/// et l'API tourne sur seven-motion-backend.workers.dev. On garde
/// la config configurable via VITE_API_BASE.
const API_BASE: string =
  (import.meta.env.VITE_API_BASE as string | undefined) ||
  // Defaut prod : meme origin (si le Worker sert aussi le panel)
  // ou un domaine connu. En dev le proxy Vite redirige /api → :8787.
  '';

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}
export function setToken(t: string | null) {
  if (t) localStorage.setItem(TOKEN_KEY, t);
  else localStorage.removeItem(TOKEN_KEY);
}

export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

interface RequestOpts {
  method?: 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE';
  body?: unknown;
  /// Si true, n'attache pas le token (utilise par /auth/login).
  noAuth?: boolean;
}

async function request<T = unknown>(
  path: string,
  opts: RequestOpts = {},
): Promise<T> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };
  if (!opts.noAuth) {
    const token = getToken();
    if (token) headers.Authorization = `Bearer ${token}`;
  }
  const resp = await fetch(`${API_BASE}${path}`, {
    method: opts.method || 'GET',
    headers,
    body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
  });

  const text = await resp.text();
  let json: any = null;
  try { json = text ? JSON.parse(text) : null; } catch { /* non-JSON */ }

  if (!resp.ok) {
    const code = (json && json.error) || 'http_error';
    const msg = (json && json.message) || `HTTP ${resp.status}`;
    if (resp.status === 401) {
      // Token expire ou invalide → on flush et on reload login
      setToken(null);
    }
    throw new ApiError(resp.status, code, msg);
  }
  return json as T;
}

// =========================================================
//  Endpoints typees
// =========================================================

export interface MeUser {
  id: string;
  email: string;
  name: string | null;
  role: string; // 'super_admin' | 'admin' | 'support' | 'reseller'
  credit_balance?: number;
  commission_rate?: number;
  status?: string;
}
export interface AuthLoginResponse {
  token: string;
  user: MeUser;
}

/// Cache module de l'utilisateur courant (rempli au bootstrap / login).
/// Permet a la Sidebar et aux pages de connaitre le role sans contexte
/// React : la valeur est stable pour la duree de la session.
let _currentUser: MeUser | null = null;
export function getCurrentUser(): MeUser | null { return _currentUser; }
export function setCurrentUser(u: MeUser | null) { _currentUser = u; }
export function isOwnerRole(role?: string | null): boolean {
  return role === 'super_admin' || role === 'admin' || role === 'support';
}

export const authApi = {
  login: (email: string, password: string) =>
    request<AuthLoginResponse>('/api/v1/auth/login', {
      method: 'POST',
      body: { email, password },
      noAuth: true,
    }),
  // Login d'un compte revendeur (table resellers, role 'reseller').
  resellerLogin: (email: string, password: string) =>
    request<AuthLoginResponse>('/api/v1/auth/reseller/login', {
      method: 'POST',
      body: { email, password },
      noAuth: true,
    }),
  me: () => request<{ user: MeUser }>('/api/v1/auth/me'),
};

export interface StatsOverview {
  customers: number;
  devices: number;
  licenses: number;
  active_licenses: number;
  expired_licenses: number;
  apps: number;
  revenue_30d_cents?: number;
  resellers?: number;       // present pour l'owner
  credit_balance?: number;  // present pour un revendeur
}
export const statsApi = {
  overview: () => request<StatsOverview>('/api/v1/stats/overview'),
};

export interface App {
  id: string;
  name: string;
  package_name: string;
  primary_color: string | null;
  tagline: string | null;
  default_iptv_server: string | null;
  default_playlist_type: string;
  pricing_json: string | null;
  is_active: number;
  created_at: number;
  updated_at: number;
}
export const appsApi = {
  list: () => request<{ items: App[] }>('/api/v1/apps'),
  create: (payload: Partial<App>) =>
    request<{ id: string }>('/api/v1/apps', { method: 'POST', body: payload }),
};

export interface Customer {
  id: string;
  email: string | null;
  name: string | null;
  phone: string | null;
  reseller_id: string | null;
  created_at: number;
}
export const customersApi = {
  list: (q?: string) =>
    request<{ items: Customer[] }>(
      `/api/v1/customers${q ? `?q=${encodeURIComponent(q)}` : ''}`,
    ),
  create: (payload: Partial<Customer>) =>
    request<{ id: string }>('/api/v1/customers', { method: 'POST', body: payload }),
};

export interface Device {
  id: string;
  customer_id: string;
  mac: string;
  label: string | null;
  reseller_id?: string | null;
  block_status?: string | null; // null/'active' | 'frozen' | 'banned'
  first_seen_at: number;
  last_seen_at: number;
  customer_name?: string | null;
  customer_email?: string | null;
}
export const devicesApi = {
  list: (q?: string) =>
    request<{ items: Device[] }>(
      `/api/v1/devices${q ? `?q=${encodeURIComponent(q)}` : ''}`,
    ),
  // Geler ('frozen'), bannir ('banned') ou reactiver ('active') une MAC.
  setBlock: (id: string, block_status: 'active' | 'frozen' | 'banned') =>
    request<{ updated: number; block_status: string | null }>(
      `/api/v1/devices/${id}`,
      { method: 'PATCH', body: { block_status } },
    ),
  remove: (id: string) =>
    request<{ deleted: number }>(`/api/v1/devices/${id}`, { method: 'DELETE' }),
};

export interface License {
  id: string;
  customer_id: string;
  device_id: string;
  app_id: string;
  status: string;
  plan: string;
  started_at: number;
  expires_at: number | null;
  auto_renew: number;
  customer_name?: string | null;
  customer_email?: string | null;
  device_mac?: string;
  device_label?: string | null;
  app_name?: string;
}
export const licensesApi = {
  list: () => request<{ items: License[] }>('/api/v1/licenses'),
  create: (payload: {
    customer_id: string;
    device_id: string;
    app_id: string;
    plan: string;
    custom_days?: number;
    auto_renew?: boolean;
  }) =>
    request<{ id: string; expires_at: number | null }>(
      '/api/v1/licenses',
      { method: 'POST', body: payload },
    ),
  renew: (id: string, plan = '1y', customDays?: number) =>
    request<{ updated: number; expires_at: number | null }>(
      `/api/v1/licenses/${id}/renew`,
      { method: 'POST', body: { plan, custom_days: customDays } },
    ),
};

// =========================================================
//  RESELLERS · CREDITS · ACTIVATION (panel revendeurs)
// =========================================================

/// Profil de l'acteur courant (avec solde de credits si revendeur).
export const meApi = {
  get: () => request<{ user: MeUser }>('/api/v1/me'),
  // Changer SON propre mot de passe (admin ou revendeur).
  changePassword: (current_password: string, new_password: string) =>
    request<{ ok: boolean }>('/api/v1/me/password', {
      method: 'POST',
      body: { current_password, new_password },
    }),
};

export interface Reseller {
  id: string;
  email: string;
  name: string | null;
  status: string;            // 'active' | 'suspended'
  credit_balance: number;
  commission_rate: number;
  created_at: number;
  devices?: number;
  licenses?: number;
  parent_reseller_id?: string | null;
  sub_resellers?: number;
}
export const resellersApi = {
  list: () => request<{ items: Reseller[] }>('/api/v1/resellers'),
  get: (id: string) => request<Reseller>(`/api/v1/resellers/${id}`),
  create: (payload: {
    email: string;
    password: string;
    name?: string;
    credit_balance?: number;
    commission_rate?: number;
  }) =>
    request<{ id: string; credit_balance: number }>('/api/v1/resellers', {
      method: 'POST',
      body: payload,
    }),
  update: (id: string, payload: Partial<{
    name: string; status: string; commission_rate: number; password: string;
  }>) =>
    request<{ updated: number }>(`/api/v1/resellers/${id}`, {
      method: 'PATCH',
      body: payload,
    }),
};

export interface CreditEntry {
  id: string;
  delta: number;
  reason: string;            // 'issue'|'activation'|'renew'|'adjust'|'refund'
  balance_after: number;
  ref_device_mac: string | null;
  ref_license_id: string | null;
  note: string | null;
  created_at: number;
}
export const creditsApi = {
  // Emettre (montant positif) ou retirer (negatif) des credits a un revendeur.
  issue: (resellerId: string, amount: number, note?: string) =>
    request<{ credit_balance: number; delta: number }>(
      `/api/v1/resellers/${resellerId}/credits`,
      { method: 'POST', body: { amount, note } },
    ),
  history: (resellerId: string) =>
    request<{ items: CreditEntry[] }>(`/api/v1/resellers/${resellerId}/credits`),
};

export interface ActivateResult {
  ok: boolean;
  license_id: string;
  device_id: string;
  customer_id: string;
  mac: string;
  plan: string;
  expires_at: number | null;
  credits_charged: number;
  credit_balance: number | null;
  renewed: boolean;
}
export const activateApi = {
  // Active une MAC (owner ou revendeur). Cree/renouvelle la licence et
  // debite les credits du revendeur selon le cout du plan.
  activate: (payload: {
    mac: string;
    plan: string;
    app_id?: string;
    label?: string;
    customer_name?: string;
    customer_email?: string;
    custom_days?: number;
    reseller_id?: string;
  }) =>
    request<ActivateResult>('/api/v1/activate', { method: 'POST', body: payload }),
};

export interface PlanCost { plan: string; credits: number; }
export const planCostsApi = {
  list: () => request<{ items: PlanCost[] }>('/api/v1/plan-costs'),
  update: (costs: Record<string, number>) =>
    request<{ updated: number }>('/api/v1/plan-costs', {
      method: 'PUT',
      body: { costs },
    }),
};
