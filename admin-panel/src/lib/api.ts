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

/// Lien de TÉLÉCHARGEMENT de l'app à donner au client. Domaine propre
/// dédié (app.7themotion.com → route /vip du Worker, proxy du dernier
/// APK). On NE lit JAMAIS le `download_url` stocké en base (qui pouvait
/// pointer sur un vieux domaine mort). Surchargeable via VITE_DOWNLOAD_URL.
export const DOWNLOAD_URL: string =
  (import.meta.env.VITE_DOWNLOAD_URL as string | undefined) ||
  'https://app.7themotion.com/vip';

/// Code OFFICIEL Downloader (aftv.news) qui pointe sur DOWNLOAD_URL.
/// Le client tape ce numéro dans l'app Downloader (TV / Fire TV) →
/// l'app se télécharge. Permanent. Surchargeable via VITE_DOWNLOADER_CODE.
export const DOWNLOADER_CODE: string =
  (import.meta.env.VITE_DOWNLOADER_CODE as string | undefined) || '7988141';

/// Lien + code Downloader de la version TV (DeFew TV).
export const DOWNLOAD_URL_TV = 'https://app.7themotion.com/tv';
export const DOWNLOADER_CODE_TV = '6248618';

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
  level?: string;          // legacy
  permissions?: string[];  // revendeur : droits cochés par l'admin
  credit_balance?: number;
  commission_rate?: number;
  status?: string;
}

/// Liste canonique des droits attribuables à un revendeur (cases à
/// cocher, miroir du backend) + libellés FR pour l'UI admin.
export const RESELLER_CAPS: { key: string; label: string }[] = [
  { key: 'activate', label: 'Activer appareils' },
  { key: 'sources', label: 'Pousser source' },
  { key: 'resellers', label: 'Sous-revendeurs' },
  { key: 'devices', label: 'Voir appareils' },
  { key: 'activations', label: 'Voir activations' },
];
/// true si l'utilisateur courant a la capacité `cap` (admin = tout ;
/// revendeur = uniquement ce que l'admin lui a coché).
export function userCan(user: MeUser | null, cap: string): boolean {
  if (!user) return false;
  if (user.role !== 'reseller') return true;
  return Array.isArray(user.permissions) && user.permissions.includes(cap);
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
  // `otp` = code 2FA (6 chiffres) — requis seulement si le compte a
  // activé la double authentification (erreur 'otp_required' sinon).
  login: (email: string, password: string, otp?: string) =>
    request<AuthLoginResponse>('/api/v1/auth/login', {
      method: 'POST',
      body: { email, password, ...(otp ? { otp } : {}) },
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
  // Auto-inscription revendeur via le lien unique → compte 'pending'.
  resellerSignup: (email: string, password: string, name?: string) =>
    request<{ ok: boolean; pending: boolean }>('/api/v1/auth/reseller/signup', {
      method: 'POST',
      body: { email, password, name },
      noAuth: true,
    }),
};

export interface StatsOverview {
  customers: number;
  devices: number;
  licenses: number;
  active_licenses: number;
  expired_licenses: number;
  expiring_7d?: number;     // abonnements actifs qui expirent sous 7 jours
  apps: number;
  revenue_30d_cents?: number;
  resellers?: number;       // present pour l'owner
  credit_balance?: number;  // present pour un revendeur
}
export const statsApi = {
  overview: () => request<StatsOverview>('/api/v1/stats/overview'),
};

// =========================================================
//  SAUVEGARDE DE LA BASE (export JSON — owner uniquement)
// =========================================================
//  Filet de sécurité : si la base D1 est perdue, on peut restaurer
//  depuis ce dump. Le panel propose un bouton « Télécharger une
//  sauvegarde » qui récupère ce JSON et le sauvegarde en fichier.
export interface BackupDump {
  generatedAt: number;
  version: number;
  tables: Record<string, unknown[]>;
}
export const backupApi = {
  get: () => request<BackupDump>('/api/v1/backup'),
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
  // Infos appareil remontées par le heartbeat (recensement parc).
  device_model?: string | null;
  android_build?: string | null;
  android_release?: string | null;
  app_build?: number | null;
  platform?: string | null;   // 'tv' (DeFew TV) | 'mobile' (The Few)
}
// Abonnement (licence) d'un appareil, vue panel.
export interface DeviceLicense {
  status: string;          // 'active' | 'expired' | 'frozen' | …
  plan: string | null;
  started_at?: number | null;
  expires_at: number | null;
  auto_renew?: number;
}
// Présence live d'un appareil (dernière trace serveur).
export interface DevicePresence {
  online: boolean;
  ip: string;
  country: string;
  channel: string;         // chaîne en cours de visionnage ('' si rien)
  last_seen: number;
}
// Source réellement présente sur la TV (remontée par le heartbeat de l'app).
// Sans mot de passe : le client ne le transmet jamais.
export interface DeviceLocalSource {
  type: 'xtream' | 'm3u';
  name: string;
  server: string;
  username: string;
  channels: number;
  active: boolean;
}
// Fiche 360° agrégée d'un appareil : abonnement + présence + M-Trio +
// inventaire réel des sources sur l'appareil.
export interface DeviceOverview {
  mac: string;
  license: DeviceLicense | null;
  presence: DevicePresence | null;
  sources: DeviceSource[];
  localSources?: DeviceLocalSource[];
}
export const devicesApi = {
  list: (q?: string) =>
    request<{ items: Device[] }>(
      `/api/v1/devices${q ? `?q=${encodeURIComponent(q)}` : ''}`,
    ),
  // Fiche 360° d'un appareil (abonnement + présence live + M-Trio) en 1 appel.
  overview: (id: string) =>
    request<DeviceOverview>(`/api/v1/devices/${encodeURIComponent(id)}/overview`),
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
  status: string;            // 'pending' | 'active' | 'suspended'
  level?: string;            // legacy
  permissions?: string[];    // droits cochés par l'admin
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
    name: string; status: string; permissions: string[];
    commission_rate: number; password: string;
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
  // Le worker renvoie le TRIO complet (`sources`) + la 1re source (`source`,
  // rétro-compat). On expose les deux : `sources` sert au panel pour montrer
  // « tout ce que le client a dans le ventre » à partir de sa MAC.
  get: (mac: string) =>
    request<{ mac: string; source: DeviceSource | null; sources?: DeviceSource[] }>(
      `/api/v1/sources/${encodeURIComponent(mac)}`,
    ),
  set: (mac: string, source: DeviceSourceInput) =>
    request<{ ok: boolean; mac: string }>(
      `/api/v1/sources/${encodeURIComponent(mac)}`,
      { method: 'PUT', body: { source } },
    ),
  // TRIO : pousse 1 à 3 sources d'un coup sur une même MAC. Le client
  // les charge toutes et bascule entre elles dans l'app.
  setMany: (mac: string, sources: DeviceSourceInput[]) =>
    request<{ ok: boolean; mac: string; count: number }>(
      `/api/v1/sources/${encodeURIComponent(mac)}`,
      { method: 'PUT', body: { sources } },
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
  active?: number; // 1 = active (affichée), 0 = désactivée
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
  // Active / désactive une annonce sans la supprimer.
  setActive: (id: number, active: boolean) =>
    request<{ ok: boolean; active: boolean }>(`/api/v1/announcements/${id}`, {
      method: 'PATCH',
      body: { active },
    }),
  // Interrupteur GLOBAL : coupe / réactive toutes les notifications.
  getSettings: () =>
    request<{ enabled: boolean }>('/api/v1/announcements/settings'),
  setSettings: (enabled: boolean) =>
    request<{ ok: boolean; enabled: boolean }>('/api/v1/announcements/settings', {
      method: 'PUT',
      body: { enabled },
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
  get: (platform?: string) =>
    request<{ minBuildTs: number; latestBuildTs: number }>(`/api/v1/force-update${_plat(platform)}`),
  force: (platform?: string) =>
    request<{ ok: boolean; minBuildTs: number }>(`/api/v1/force-update${_plat(platform)}`, {
      method: 'POST',
      body: { action: 'force' },
    }),
  disable: (platform?: string) =>
    request<{ ok: boolean; minBuildTs: number }>(`/api/v1/force-update${_plat(platform)}`, {
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
export interface ThemeRule {
  enabled: boolean;
  label: string;
  month: number | null;   // 1-12 = tout le mois
  from: string | null;    // 'MMDD'
  to: string | null;      // 'MMDD'
  accent: string;         // '#RRGGBB' ou ''
  bg: 'dark' | 'light' | '';
  appName: string;
}
/// '' (mobile) ou '?platform=tv' (DeFew TV).
const _plat = (p?: string) => (p === 'tv' ? '?platform=tv' : '');
export const themeApi = {
  get: (platform?: string) =>
    request<ThemeConfig>(`/api/v1/theme${_plat(platform)}`),
  save: (cfg: { appName: string; accent: string; bg: string }, platform?: string) =>
    request<{ ok: boolean } & ThemeConfig>(`/api/v1/theme${_plat(platform)}`, {
      method: 'PUT',
      body: cfg,
    }),
  getAutomations: (platform?: string) =>
    request<{ rules: ThemeRule[] }>(`/api/v1/theme/automations${_plat(platform)}`),
  saveAutomations: (rules: ThemeRule[], platform?: string) =>
    request<{ ok: boolean; rules: ThemeRule[] }>(
      `/api/v1/theme/automations${_plat(platform)}`,
      { method: 'PUT', body: { rules } },
    ),
};

// =========================================================
//  HISTORIQUE DES MODIFICATIONS (audit log) — owner
// =========================================================
export interface AuditLog {
  id: string;
  actor_type: string;
  actor_id: string;
  action: string;
  target_type: string | null;
  target_id: string | null;
  before_json: string | null;
  after_json: string | null;
  created_at: number;
}
export const auditApi = {
  list: () => request<{ items: AuditLog[] }>('/api/v1/audit-logs'),
};

// =========================================================
//  CARNET DE RÉFÉRENCES — MAC activées + username(s) Xtream
// =========================================================
export interface ActivationReference {
  mac: string;
  customer_name: string | null;
  usernames: string[];     // username(s) Xtream, SANS mot de passe
  servers: string[];       // serveur(s) Xtream (base url)
  status: string;          // 'active'|'expired'|'frozen'|'banned'|'none'
  label: string | null;
  updated_at: number | null;
}
export const referencesApi = {
  list: () => request<{ items: ActivationReference[] }>('/api/v1/references'),
};

// =========================================================
//  TRANSFERT d'abonnement (changement d'appareil)
// =========================================================
export const transferApi = {
  transfer: (oldMac: string, newMac: string, label?: string) =>
    request<{ ok: boolean; old_mac: string; new_mac: string; moved_licenses: number }>(
      '/api/v1/transfer',
      { method: 'POST', body: { old_mac: oldMac, new_mac: newMac, label } },
    ),
};

// =========================================================
//  Familles — une ligne (source) partagée par plusieurs appareils
// =========================================================
export interface FamilySource {
  type: 'xtream' | 'm3u';
  label?: string | null;
  server_url?: string | null;
  username?: string | null;
  password?: string | null;
  m3u_url?: string | null;
  epg_url?: string | null;
}
export interface Family {
  id: string;
  name: string;
  source: FamilySource | null;
  member_count?: number;
  created_at: number;
}
export interface FamilyMember {
  mac: string;
  label: string | null;
  created_at: number;
}
export interface FamilyLink {
  id: string;
  token: string;
  label: string | null;
  created_at: number;
}

/// URL publique d'un lien M3U de famille (à donner au membre). Le jeton
/// est résolu par le Worker → playlist de la source unique de la famille.
export function m3uLinkUrl(token: string): string {
  return `${API_BASE}/api/m3u/${token}`;
}

export const familiesApi = {
  list: () => request<{ items: Family[] }>('/api/v1/families'),
  create: (name: string, source: FamilySource) =>
    request<{ ok: boolean; family: Family }>('/api/v1/families', {
      method: 'POST',
      body: { name, source },
    }),
  get: (id: string) =>
    request<{ family: Family; members: FamilyMember[]; links: FamilyLink[] }>(
      `/api/v1/families/${id}`,
    ),
  remove: (id: string) =>
    request<{ ok: boolean }>(`/api/v1/families/${id}`, { method: 'DELETE' }),
  addMember: (id: string, mac: string, label?: string, plan?: string) =>
    request<{ ok: boolean; mac: string }>(`/api/v1/families/${id}/members`, {
      method: 'POST',
      body: { mac, label, plan },
    }),
  removeMember: (id: string, mac: string) =>
    request<{ ok: boolean }>(
      `/api/v1/families/${id}/members/${encodeURIComponent(mac)}`,
      { method: 'DELETE' },
    ),
  createLink: (id: string, label?: string) =>
    request<FamilyLink>(`/api/v1/families/${id}/links`, {
      method: 'POST',
      body: { label },
    }),
  deleteLink: (id: string, linkId: string) =>
    request<{ ok: boolean }>(`/api/v1/families/${id}/links/${linkId}`, {
      method: 'DELETE',
    }),
};

// =========================================================
//  PUB VIDÉO AU DÉMARRAGE (jouée quand le client ouvre l'app)
// =========================================================
export interface AdConfig {
  enabled: boolean;
  url: string;
  skip: number;   // secondes avant que « Passer » apparaisse
  freq: string;   // 'always' | 'daily'
}
export const adApi = {
  get: () => request<AdConfig>('/api/v1/ad'),
  save: (cfg: { enabled: boolean; url: string; skip: number; freq: string }) =>
    request<{ ok: boolean } & AdConfig>('/api/v1/ad', { method: 'PUT', body: cfg }),
};

// =========================================================
//  TARIFS (prix affichés dans l'app + essai + promo/bonus)
// =========================================================
//  L'owner fixe les prix EN € (à vie / 1 an), la durée de l'essai gratuit,
//  et un message promo/bonus optionnel (« 1 acheté = 1 offert »). L'app lit
//  /api/pricing au démarrage et affiche le bloc « Nos offres ».
export interface PricingConfig {
  currency: string;     // ex. '€'
  lifetime: string;     // ex. '9,9'
  yearly: string;       // ex. '4,9'
  trialDays: number;    // ex. 7
  promoEnabled: boolean;
  promoMessage: string;
}
export const pricingApi = {
  get: () => request<PricingConfig>('/api/v1/pricing'),
  save: (cfg: PricingConfig) =>
    request<{ ok: boolean } & PricingConfig>('/api/v1/pricing', {
      method: 'PUT',
      body: cfg,
    }),
  // Donne `days` jours (7 par défaut) à TOUS les appareils actifs, puis le
  // paywall revient automatiquement. Action ponctuelle de bascule payante.
  grantTrialAll: (days: number) =>
    request<{ ok: boolean; days: number; updated: number }>(
      '/api/v1/grant-trial-all',
      { method: 'POST', body: { days } },
    ),
};

// =========================================================
//  AVIS CLIENTS (invitation + avis reçus)
// =========================================================
export interface FeedbackPrompt {
  enabled: boolean;
  message: string;
}
export interface FeedbackItem {
  id: number;
  mac: string | null;
  country: string | null;
  rating: number;
  message: string;
  created_at: number;
}
export const feedbackApi = {
  getPrompt: () => request<FeedbackPrompt>('/api/v1/feedback-prompt'),
  savePrompt: (cfg: { enabled: boolean; message: string }) =>
    request<{ ok: boolean } & FeedbackPrompt>('/api/v1/feedback-prompt', {
      method: 'PUT',
      body: cfg,
    }),
  list: () => request<{ items: FeedbackItem[] }>('/api/v1/feedback'),
};

// =========================================================
//  APPS EN LIGNE (présence : IP + pays via Cloudflare)
// =========================================================
export interface OnlineDevice {
  mac: string;
  ip: string;
  country: string;
  lastSeen: number;
  channel?: string;   // chaîne en cours de visionnage (vide si rien)
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

// =========================================================
//  TEST DE SOURCE EN DIRECT (avant de pousser)
// =========================================================
//  Vérifie en quelques secondes qu'une source répond VRAIMENT :
//  identifiants Xtream valides (statut, échéance, connexions) ou
//  playlist M3U qui répond avec des chaînes. Zéro devinette.
export interface SourceCheckResult {
  ok: boolean;
  type: 'xtream' | 'm3u';
  ms: number;
  reachable?: boolean;
  code?: string | null;          // 'bad_credentials' | 'http_404' | 'not_m3u' | 'network'…
  message?: string;
  // Xtream
  status?: string;               // 'Active'…
  expires_at?: number | null;
  max_connections?: number | null;
  active_connections?: number | null;
  // M3U
  sample_channels?: number;
}
export const sourceCheckApi = {
  check: (source: DeviceSourceInput) =>
    request<SourceCheckResult>('/api/v1/source-check', {
      method: 'POST',
      body: { source },
    }),
};

// =========================================================
//  SYNC INSTANTANÉ — révision de synchro d'un appareil
// =========================================================
//  Après un push, le panel peut vérifier que la révision a bien été
//  bumpée (— la TV re-synchronise en < 20 s dès qu'elle la voit).
export const deviceSyncApi = {
  get: (mac: string) =>
    request<{ mac: string; rev: number; updated_at: number | null }>(
      `/api/v1/sync/${encodeURIComponent(mac)}`,
    ),
};

// =========================================================
//  ACCÈS APP — interrupteur global (owner)
// =========================================================
export type AppAccessMode = 'open' | 'maintenance' | 'locked';
export interface AppAccessConfig {
  mode: AppAccessMode;
  message: string;
}
export const appAccessApi = {
  get: (platform?: string) =>
    request<AppAccessConfig>(`/api/v1/app-access${_plat(platform)}`),
  save: (cfg: AppAccessConfig, platform?: string) =>
    request<{ ok: boolean } & AppAccessConfig>(`/api/v1/app-access${_plat(platform)}`, {
      method: 'PUT',
      body: cfg,
    }),
};

// =========================================================
//  PRODUITS — catalogue publiable (owner)
// =========================================================
export interface Product {
  id: string;
  title: string;
  description: string | null;
  image_url: string | null;
  price_label: string | null;
  cta_label: string | null;
  cta_url: string | null;
  badge: string | null;
  position: number;
  active: number;
  created_at: number;
  updated_at: number;
}
export const productsApi = {
  list: () => request<{ items: Product[] }>('/api/v1/products'),
  create: (payload: Partial<Product>) =>
    request<{ ok: boolean; id: string }>('/api/v1/products', {
      method: 'POST',
      body: payload,
    }),
  update: (id: string, payload: Partial<Product>) =>
    request<{ ok: boolean; updated: number }>(`/api/v1/products/${id}`, {
      method: 'PATCH',
      body: payload,
    }),
  remove: (id: string) =>
    request<{ ok: boolean }>(`/api/v1/products/${id}`, { method: 'DELETE' }),
};

// =========================================================
//  INTÉGRATIONS — clés API + webhooks (owner)
// =========================================================
export const API_KEY_SCOPES: { key: string; label: string; hint: string }[] = [
  { key: 'activate', label: 'Activer', hint: 'POST /api/v1/activate' },
  { key: 'sources', label: 'Sources', hint: 'GET/PUT/DELETE /api/v1/sources/:mac + source-check' },
  { key: 'read', label: 'Lecture', hint: 'GET devices / licenses / customers / stats' },
  { key: 'publish', label: 'Publier', hint: 'POST products / announcements' },
];
export const WEBHOOK_EVENTS: { key: string; label: string }[] = [
  { key: 'activation.created', label: 'Activation créée' },
  { key: 'activation.renewed', label: 'Activation renouvelée' },
  { key: 'source.updated', label: 'Source poussée' },
  { key: 'source.cleared', label: 'Source retirée' },
  { key: 'device.blocked', label: 'Appareil gelé/banni' },
];
export interface ApiKey {
  id: string;
  name: string;
  prefix: string;
  scopes: string[];
  created_at: number;
  last_used_at: number | null;
  revoked_at: number | null;
}
export interface Webhook {
  id: string;
  url: string;
  events: string[];
  active: number;
  created_at: number;
  last_fired_at: number | null;
  last_status: string | null;
}
export const integrationsApi = {
  listKeys: () => request<{ items: ApiKey[] }>('/api/v1/integrations/keys'),
  createKey: (name: string, scopes: string[]) =>
    request<{ ok: boolean; id: string; key: string; name: string; scopes: string[] }>(
      '/api/v1/integrations/keys',
      { method: 'POST', body: { name, scopes } },
    ),
  revokeKey: (id: string) =>
    request<{ ok: boolean }>(`/api/v1/integrations/keys/${id}`, { method: 'DELETE' }),
  listWebhooks: () => request<{ items: Webhook[] }>('/api/v1/integrations/webhooks'),
  createWebhook: (url: string, events: string[]) =>
    request<{ ok: boolean; id: string; url: string; events: string[]; secret: string }>(
      '/api/v1/integrations/webhooks',
      { method: 'POST', body: { url, events } },
    ),
  updateWebhook: (id: string, payload: { active?: boolean; events?: string[] }) =>
    request<{ ok: boolean }>(`/api/v1/integrations/webhooks/${id}`, {
      method: 'PATCH',
      body: payload,
    }),
  deleteWebhook: (id: string) =>
    request<{ ok: boolean }>(`/api/v1/integrations/webhooks/${id}`, { method: 'DELETE' }),
  testWebhook: (id: string) =>
    request<{ ok: boolean; sent: boolean }>(`/api/v1/integrations/webhooks/${id}/test`, {
      method: 'POST',
    }),
};

// =========================================================
//  2FA TOTP (comptes admin) + SANTÉ SYSTÈME
// =========================================================
export const twoFaApi = {
  status: () => request<{ enabled: boolean; pending: boolean }>('/api/v1/me/2fa'),
  setup: () =>
    request<{ ok: boolean; secret: string; otpauth: string }>('/api/v1/me/2fa/setup', {
      method: 'POST',
      body: {},
    }),
  enable: (code: string) =>
    request<{ ok: boolean; enabled: boolean }>('/api/v1/me/2fa/enable', {
      method: 'POST',
      body: { code },
    }),
  disable: (password: string, code: string) =>
    request<{ ok: boolean; enabled: boolean }>('/api/v1/me/2fa/disable', {
      method: 'POST',
      body: { password, code },
    }),
};

export interface HealthStatus {
  ok: boolean;
  db_ok: boolean;
  db_ms: number | null;
  time: number;
}
export const healthApi = {
  get: () => request<HealthStatus>('/api/v1/health'),
};

// =========================================================
//  SORTIE RÉSEAU (IP) PAR APPAREIL — « changer l'IP d'un client »
// =========================================================
//  Un fournisseur verrouille le compte sur une IP ; le client voyage,
//  tout casse. L'admin assigne une SORTIE (un proxy qu'il contrôle,
//  situé dans le bon pays) à la MAC : tout le trafic IPTV du client
//  sort par cette IP fixe. Livré instantanément.
export interface NetExit {
  id: string;
  label: string;   // ex. « Suède 🇸🇪 »
  proxy: string;   // 'http://[user:pass@]host:port' ou 'socks5://host:port'
}
export interface DeviceNet {
  mac: string;
  proxy: string;   // '' = direct (aucune sortie)
  label: string;
  updated_at: number | null;
}
export const netExitsApi = {
  list: () => request<{ items: NetExit[] }>('/api/v1/net-exits'),
  save: (items: NetExit[]) =>
    request<{ ok: boolean; items: NetExit[] }>('/api/v1/net-exits', {
      method: 'PUT',
      body: { items },
    }),
};
export const deviceNetApi = {
  get: (mac: string) =>
    request<DeviceNet>(`/api/v1/device-net/${encodeURIComponent(mac)}`),
  // proxy vide = repasse le client en direct (efface la sortie).
  set: (mac: string, proxy: string, label = '') =>
    request<{ ok: boolean; mac: string; assigned: boolean; label: string }>(
      `/api/v1/device-net/${encodeURIComponent(mac)}`,
      { method: 'PUT', body: { proxy, label } },
    ),
  clear: (mac: string) =>
    request<{ ok: boolean; mac: string }>(
      `/api/v1/device-net/${encodeURIComponent(mac)}`,
      { method: 'DELETE' },
    ),
};
