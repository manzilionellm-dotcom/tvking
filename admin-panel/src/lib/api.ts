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
  download_url: string | null;
  is_active: number;
  created_at: number;
  updated_at: number;
}
export const appsApi = {
  list: () => request<{ items: App[] }>('/api/v1/apps'),
  create: (payload: Partial<App>) =>
    request<{ id: string }>('/api/v1/apps', { method: 'POST', body: payload }),
  update: (id: string, payload: Partial<App>) =>
    request<{ updated: number }>(
      `/api/v1/apps/${encodeURIComponent(id)}`,
      { method: 'PATCH', body: payload },
    ),
};

// =========================================================
//  SERVEURS PAR DÉFAUT (proposés dans l'app cliente)
// =========================================================
//  Le client ne saisit jamais d'URL : il choisit « Serveur 1 / 2 / 3… »
//  et tape son code Xtream. On gère ici les URLs (cachées côté app).
export interface DefaultServer {
  id: string;
  label: string;
  url: string;
  position: number;
  enabled: number;
  created_at: number;
  updated_at: number;
}
export const serversApi = {
  list: () => request<{ items: DefaultServer[] }>('/api/v1/servers'),
  create: (payload: {
    label: string;
    url: string;
    position?: number;
    enabled?: boolean;
  }) =>
    request<{ id: string }>('/api/v1/servers', { method: 'POST', body: payload }),
  update: (
    id: string,
    payload: Partial<{
      label: string;
      url: string;
      position: number;
      enabled: boolean;
    }>,
  ) =>
    request<{ updated: number }>(`/api/v1/servers/${id}`, {
      method: 'PATCH',
      body: payload,
    }),
  remove: (id: string) =>
    request<{ deleted: number }>(`/api/v1/servers/${id}`, { method: 'DELETE' }),
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
// Source IPTV assignée à un appareil par sa MAC (poussée à l'app).
export interface DeviceSourceInput {
  type: 'xtream' | 'm3u';
  label?: string | null;
  server_url?: string | null;
  username?: string | null;
  password?: string | null;
  m3u_url?: string | null;
  epg_url?: string | null;
}
export interface DeviceSource extends DeviceSourceInput {
  mac?: string;
  updated_at?: number;
}

export const activateApi = {
  // Active une MAC (owner ou revendeur). Cree/renouvelle la licence et
  // debite les credits du revendeur selon le cout du plan. Si `source`
  // est fourni, on l'assigne a la MAC (l'app la chargera automatiquement).
  activate: (payload: {
    mac: string;
    plan: string;
    app_id?: string;
    label?: string;
    customer_name?: string;
    customer_email?: string;
    custom_days?: number;
    reseller_id?: string;
    source?: DeviceSourceInput;
  }) =>
    request<ActivateResult>('/api/v1/activate', { method: 'POST', body: payload }),
};

// Source assignée par MAC (gérée indépendamment de l'activation).
export const sourcesApi = {
  get: (mac: string) =>
    request<{ mac: string; source: DeviceSource | null }>(
      `/api/v1/sources/${encodeURIComponent(mac)}`,
    ),
  set: (mac: string, source: DeviceSourceInput) =>
    request<{ ok: boolean; mac: string }>(
      `/api/v1/sources/${encodeURIComponent(mac)}`,
      { method: 'PUT', body: { source } },
    ),
  clear: (mac: string) =>
    request<{ ok: boolean; mac: string }>(
      `/api/v1/sources/${encodeURIComponent(mac)}`,
      { method: 'DELETE' },
    ),
};

// =========================================================
//  ANNONCES (notifications broadcast — owner uniquement)
// =========================================================
//  L'owner écrit un message → toutes les apps l'affichent comme une
//  notification douce à leur prochaine ouverture. Réservé super_admin.
/** Catégories d'annonce (pilotent icône + couleur dans l'app). */
export type AnnouncementKind = 'nouveaute' | 'promo' | 'info' | 'maintenance';

export interface Announcement {
  id: number;
  title: string;
  body: string;
  url: string;
  kind?: string;
  cta?: string;
  country?: string;
  expires_at?: number;
  created_at: number;
}
export const announcementsApi = {
  list: () => request<{ items: Announcement[] }>('/api/v1/announcements'),
  create: (payload: {
    title: string;
    body: string;
    url?: string;
    kind?: string;
    cta?: string;
    country?: string;
    durationMin?: number;
  }) =>
    request<{ ok: boolean; id: number | null }>('/api/v1/announcements', {
      method: 'POST',
      body: payload,
    }),
  clear: () =>
    request<{ ok: boolean }>('/api/v1/announcements', { method: 'DELETE' }),
  remove: (id: number) =>
    request<{ ok: boolean }>(`/api/v1/announcements/${id}`, {
      method: 'DELETE',
    }),
};

// =========================================================
//  ACCUEIL DYNAMIQUE (Centre de contrôle, Module 1/8)
// =========================================================
//  Pilote l'ordre / visibilité / ruban / vedette des sections de
//  l'accueil de l'app, en temps réel et sans mise à jour de store.
export interface HomeSection {
  key: string;
  position: number;
  enabled: number;
  ribbon: string;
  featured: number;
  updated_at?: number;
}
export interface HomeLayoutSnapshot {
  id: number;
  label: string;
  created_at: number;
}
/** Rubans disponibles ('' = aucun). Aligné avec HOME_RIBBONS (worker). */
export const HOME_RIBBONS: string[] = [
  '', 'NOUVEAU', 'POPULAIRE', 'EXCLUSIF', 'EN DIRECT', 'VIP',
  'COUPE DU MONDE', 'EURO 2028', 'UFC', 'CHAMPIONS LEAGUE',
];
/** Libellés lisibles des sections connues (clé → nom affiché). */
export const HOME_SECTION_LABELS: Record<string, string> = {
  recent: 'Récemment regardé',
  favorites: 'Favoris',
  sport: 'Sport',
  entertainment: 'Divertissement',
  info: 'Info',
  kids: 'Enfants',
  general: 'Général',
  cinema: 'Cinéma & Séries (verrouillé)',
};
export const homeLayoutApi = {
  get: () =>
    request<{ items: HomeSection[]; version: number }>('/api/v1/home-layout'),
  save: (items: HomeSection[], label?: string) =>
    request<{ ok: boolean; items: HomeSection[]; version: number }>(
      '/api/v1/home-layout',
      { method: 'PUT', body: { items, label } },
    ),
  history: () =>
    request<{ items: HomeLayoutSnapshot[] }>('/api/v1/home-layout/history'),
  restore: (id: number) =>
    request<{ ok: boolean }>('/api/v1/home-layout/restore', {
      method: 'POST',
      body: { id },
    }),
};

// =========================================================
//  MISE À JOUR FORCÉE (bouton du panel)
// =========================================================
//  « Forcer » bloque toutes les apps PLUS ANCIENNES que le dernier
//  build connu, jusqu'à ce qu'elles se mettent à jour. minBuildTs en
//  secondes ; 0 = désactivé.
export const forceUpdateApi = {
  get: () =>
    request<{ minBuildTs: number; latestBuildTs: number }>('/api/v1/force-update'),
  force: () =>
    request<{ ok: boolean; minBuildTs: number }>('/api/v1/force-update', {
      method: 'POST',
      body: { action: 'force' },
    }),
  disable: () =>
    request<{ ok: boolean; minBuildTs: number }>('/api/v1/force-update', {
      method: 'POST',
      body: { action: 'disable' },
    }),
};

// =========================================================
//  FAVORI DU JOUR (chaîne mise en avant)
// =========================================================
export const featuredApi = {
  get: () => request<{ name: string; note: string }>('/api/v1/featured'),
  set: (name: string, note: string) =>
    request<{ ok: boolean; name: string; note: string }>('/api/v1/featured', {
      method: 'POST',
      body: { name, note },
    }),
};

// =========================================================
//  THÈME DE L'APP (nom affiché + couleur d'accent + fond)
// =========================================================
//  L'owner personnalise l'app à distance : son NOM (ex. « WorldCup2026 »)
//  et sa COULEUR d'accent. L'app lit /api/theme au démarrage et s'adapte
//  sans mise à jour de store. Valeurs vides = défauts (BLACK7 ROYAL, braise).
export interface ThemeConfig {
  appName: string;
  accent: string; // '#RRGGBB' ou '' (défaut braise)
  bg: string;     // 'dark' | 'light' | '' (défaut sombre)
}
export const themeApi = {
  get: () => request<ThemeConfig>('/api/v1/theme'),
  save: (cfg: { appName: string; accent: string; bg: string }) =>
    request<{ ok: boolean } & ThemeConfig>('/api/v1/theme', {
      method: 'PUT',
      body: cfg,
    }),
};

// =========================================================
//  APPS EN LIGNE (présence : IP + pays via Cloudflare)
// =========================================================
export interface OnlineDevice {
  mac: string;
  ip: string;
  country: string;
  lastSeen: number;
}
export interface OnlineSnapshot {
  onlineCount: number;
  todayCount: number;
  byCountry: Record<string, number>;
  items: OnlineDevice[];
}
export const onlineApi = {
  get: () => request<OnlineSnapshot>('/api/v1/online'),
};

// Liste de pays (ISO2 → nom FR) pour le ciblage des annonces. Drapeau
// dérivé du code ISO via flagEmoji(). Liste volontairement large mais
// non exhaustive ; '' = tout le monde.
export const COUNTRIES: { code: string; name: string }[] = [
  { code: 'SE', name: 'Suède' }, { code: 'NO', name: 'Norvège' },
  { code: 'DK', name: 'Danemark' }, { code: 'FI', name: 'Finlande' },
  { code: 'FR', name: 'France' }, { code: 'BE', name: 'Belgique' },
  { code: 'CH', name: 'Suisse' }, { code: 'DE', name: 'Allemagne' },
  { code: 'NL', name: 'Pays-Bas' }, { code: 'GB', name: 'Royaume-Uni' },
  { code: 'ES', name: 'Espagne' }, { code: 'IT', name: 'Italie' },
  { code: 'PT', name: 'Portugal' }, { code: 'IE', name: 'Irlande' },
  { code: 'US', name: 'États-Unis' }, { code: 'CA', name: 'Canada' },
  { code: 'MA', name: 'Maroc' }, { code: 'DZ', name: 'Algérie' },
  { code: 'TN', name: 'Tunisie' }, { code: 'SN', name: 'Sénégal' },
  { code: 'CI', name: "Côte d'Ivoire" }, { code: 'TR', name: 'Turquie' },
  { code: 'SA', name: 'Arabie saoudite' }, { code: 'AE', name: 'Émirats' },
  { code: 'QA', name: 'Qatar' }, { code: 'EG', name: 'Égypte' },
  { code: 'AU', name: 'Australie' }, { code: 'BR', name: 'Brésil' },
];

/** Drapeau emoji à partir d'un code ISO2 (ex. 'SE' → 🇸🇪). */
export function flagEmoji(code: string): string {
  if (!code || code.length !== 2) return '🏳️';
  const A = 0x1f1e6;
  const up = code.toUpperCase();
  return String.fromCodePoint(
    A + (up.charCodeAt(0) - 65),
    A + (up.charCodeAt(1) - 65),
  );
}

export interface PlanCost { plan: string; credits: number; }
export const planCostsApi = {
  list: () => request<{ items: PlanCost[] }>('/api/v1/plan-costs'),
  update: (costs: Record<string, number>) =>
    request<{ updated: number }>('/api/v1/plan-costs', {
      method: 'PUT',
      body: { costs },
    }),
};
